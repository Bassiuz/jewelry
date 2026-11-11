import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dashboard_page.dart';
import 'device/device.dart';
import 'scenario_recording.dart';
import 'scenario_result.dart';
import 'slug.dart';
import 'video.dart';

/// A local web page that follows a `jewelry run` live: every scenario file
/// with its state, every emulator's screen with the step it is at, and the
/// result of what finished (the golden or this run's recording as a video,
/// the diff images).
///
/// The CLI feeds it the same events as the terminal footer; the page polls
/// `state.json` and the screens.
class Dashboard {
  Dashboard({required this.root});

  /// The `.jewelry` folder; results and goldens are served from it.
  final Directory root;

  HttpServer? _server;
  final _clock = Stopwatch()..start();
  final _tests = <String, _Test>{};
  final _workers = <String, _Worker>{};

  /// Where the page is, once [start] has run.
  Uri get url => Uri.parse('http://localhost:${_server!.port}/');

  /// Serves on [port], or on any free port when it is taken.
  Future<void> start({int port = 4848}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server!.listen((r) => unawaited(_handle(r)));
  }

  Future<void> stop() async => _server?.close(force: true);

  static String _key(String profile, String file) => '$profile|$file';
  static String _workerKey(String profile, int worker) => '$profile#$worker';

  /// The files [profile] will run, in the order they will run.
  void queue(String profile, List<String> files) {
    for (final f in files) {
      _tests[_key(profile, f)] = _Test(profile, f);
    }
  }

  /// What emulator [worker] of [profile] is doing between scenarios.
  void status(String profile, int worker, String text) =>
      // The footer's "<profile> <n>: " prefix; the card names the emulator.
      _worker(profile, worker).status = text.replaceFirst(
        RegExp(r'^[^:]*: '),
        '',
      );

  /// The booted device of [worker], for its live screen.
  void attach(String profile, int worker, Device device) =>
      _worker(profile, worker).device = device;

  void started(String profile, String file, int worker) {
    final w = _worker(profile, worker)
      ..test = _key(profile, file)
      ..steps = []
      ..step = null;
    _tests[w.test!]
      ?..state = 'running'
      ..worker = worker;
  }

  /// The scenario [label] on [worker] declared its [steps].
  void planned(String profile, int worker, String label, List<String> steps) {
    final w = _worker(profile, worker)..steps = steps;
    final t = _tests[w.test];
    if (t != null && !t.labels.contains(label)) t.labels.add(label);
  }

  void step(String profile, int worker, String label) =>
      _worker(profile, worker).step = label;

  /// [worker] is free; its last file is being compared on the Mac.
  void judging(String profile, int worker) {
    final w = _worker(profile, worker);
    _tests[w.test]?.state = 'judging';
    w
      ..test = null
      ..steps = []
      ..step = null;
  }

  void finished(String profile, String file, List<ScenarioResult> results) {
    final t = _tests[_key(profile, file)] ??= _Test(profile, file);
    t
      ..results = results
      ..state = results.any((r) => r.failed)
          ? 'failed'
          : results.any((r) => r.outcome == Outcome.recorded)
          ? 'recorded'
          : 'passed';
    for (final r in results) {
      if (!t.labels.contains(r.label)) t.labels.add(r.label);
    }
  }

  _Worker _worker(String profile, int worker) => _workers.putIfAbsent(
    _workerKey(profile, worker),
    () => _Worker(profile, worker),
  );

  Map<String, Object?> get state => {
    'elapsedMs': _clock.elapsedMilliseconds,
    'tests': [
      for (final t in _tests.values)
        {
          'key': _key(t.profile, t.file),
          'file': t.file,
          'name': t.file.split('/').last,
          'profile': t.profile,
          'state': t.state,
          'worker': t.worker,
          'labels': t.labels,
          'slugs': [for (final l in t.labels) slug(l)],
          'results': [
            for (final r in t.results)
              {
                'label': r.label,
                'slug': slug(r.label),
                'outcome': r.outcome.name,
                'reason': r.reason,
                'detail': r.detail,
                'step': r.step,
                'durationMs': r.duration.inMilliseconds,
                'frames': r.frames,
                'failureDir': r.failed ? r.failureDir : null,
                'log': r.log,
              },
          ],
        },
    ],
    'workers': [
      for (final w in _workers.values)
        {
          'key': _workerKey(w.profile, w.worker),
          'profile': w.profile,
          'worker': w.worker,
          'status': w.status,
          'test': w.test,
          'steps': w.steps,
          'step': w.step,
          'live': w.device != null,
        },
    ],
  };

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    try {
      final path = request.uri.path;
      if (path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(dashboardPage);
      } else if (path == '/state.json') {
        res.headers
          ..contentType = ContentType.json
          ..set('cache-control', 'no-store');
        res.write(jsonEncode(state));
      } else if (path.startsWith('/screen/')) {
        await _screen(Uri.decodeComponent(path.substring(8)), res);
      } else if (path.startsWith('/video/')) {
        await _video(path.substring(7).split('/'), res);
      } else if (path.startsWith('/files/')) {
        await _file(Uri.decodeComponent(path.substring(7)), res);
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write('$e');
    }
    await res.close();
  }

  /// The latest screenshot of an emulator. Shared between viewers and
  /// taken at most every 700 ms, so a page left open costs the run little.
  Future<void> _screen(String key, HttpResponse res) async {
    final w = _workers[key];
    final device = w?.device;
    if (w == null || device == null) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final fresh =
        w.shotAt != null &&
        DateTime.now().difference(w.shotAt!) <
            const Duration(milliseconds: 700);
    if (!fresh) {
      w.shot ??= device.screenshot().then(
        (png) {
          w
            ..last = png
            ..shotAt = DateTime.now()
            ..shot = null;
          return png;
        },
        onError: (Object e) {
          w.shot = null;
          throw e;
        },
      );
      await w.shot;
    }
    res.headers
      ..contentType = ContentType('image', 'png')
      ..set('cache-control', 'no-store');
    res.add(w.last!);
  }

  /// `/video/golden/<slug>/<profile>` or `/video/failure/<slug>/<profile>`:
  /// that recording as an MP4, made once and kept until it changes.
  Future<void> _video(List<String> parts, HttpResponse res) async {
    if (parts.length != 3 || parts.any((p) => p.contains('..'))) {
      res.statusCode = HttpStatus.badRequest;
      return;
    }
    final [kind, name, profile] = parts;
    final base = switch (kind) {
      'golden' => '${root.path}/goldens/$name/$profile',
      'failure' => '${root.path}/failures/$name/$profile/actual',
      _ => null,
    };
    if (base == null || !File('$base.apng').existsSync()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final out = File('${root.path}/videos/dashboard/$kind.$name.$profile.mp4');
    final source = File('$base.apng').lastModifiedSync();
    if (!out.existsSync() || out.lastModifiedSync().isBefore(source)) {
      // Decoding a recording takes seconds of CPU; keep the server free.
      await _videoInIsolate(base, out);
    }
    res.headers.contentType = ContentType('video', 'mp4');
    await res.addStream(out.openRead());
  }

  /// Files under [root] (diff images, logs), for the result view.
  Future<void> _file(String rel, HttpResponse res) async {
    final file = File('${root.path}/$rel');
    if (rel.contains('..') || !file.existsSync()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    res.headers.contentType = switch (rel.split('.').last) {
      'png' => ContentType('image', 'png'),
      'html' => ContentType.html,
      'json' => ContentType.json,
      _ => ContentType.text,
    };
    await res.addStream(file.openRead());
  }
}

/// Top level, so the isolate's closure holds only [base] and [out].
Future<void> _videoInIsolate(String base, File out) =>
    Isolate.run(() => writeVideo(ScenarioRecording.read(base), out));

class _Test {
  _Test(this.profile, this.file);
  final String profile;
  final String file;
  String state = 'queued';
  int? worker;
  final labels = <String>[];
  List<ScenarioResult> results = const [];
}

class _Worker {
  _Worker(this.profile, this.worker);
  final String profile;
  final int worker;
  String status = 'starting';
  Device? device;
  String? test;
  List<String> steps = [];
  String? step;
  Uint8List? last;
  DateTime? shotAt;
  Future<Uint8List>? shot;
}
