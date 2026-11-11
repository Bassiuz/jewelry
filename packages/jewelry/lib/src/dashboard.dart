import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'accept.dart';
import 'dashboard_page.dart';
import 'device/device.dart';
import 'run_log.dart';
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

  /// The results of the last runs, for the accept button. Without it the
  /// page cannot accept anything.
  RunLog? log;

  /// How long the whole run is expected to take, from the last run's times.
  Duration? estimate;

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

  /// [worker] stopped early: its emulator or its Firebase emulators could
  /// not start. Shown on its card instead of a status.
  void failed(String profile, int worker, Object error) =>
      _worker(profile, worker).error = '$error'.replaceFirst('Bad state: ', '');

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
          : results.any((r) => r.outcome == Outcome.accepted)
          ? 'accepted'
          : 'passed';
    for (final r in results) {
      if (!t.labels.contains(r.label)) t.labels.add(r.label);
    }
  }

  /// Shows what [log] holds, the results of the last runs, as finished
  /// scenarios: for `jewelry dashboard`, which runs nothing. Failed first.
  void showLog(RunLog log) {
    this.log = log;
    final byFile = <String, List<ScenarioResult>>{};
    for (final r in log.results) {
      byFile.putIfAbsent(_key(r.profile, r.file), () => []).add(r);
    }
    final ordered = byFile.values.toList()
      ..sort((a, b) {
        final failed =
            (b.any((r) => r.failed) ? 1 : 0) - (a.any((r) => r.failed) ? 1 : 0);
        return failed != 0 ? failed : a.first.label.compareTo(b.first.label);
      });
    for (final results in ordered) {
      final r = results.first;
      queue(r.profile, [r.file]);
      finished(r.profile, r.file, results);
    }
  }

  _Worker _worker(String profile, int worker) => _workers.putIfAbsent(
    _workerKey(profile, worker),
    () => _Worker(profile, worker),
  );

  Map<String, Object?> get state => {
    'elapsedMs': _clock.elapsedMilliseconds,
    'estimateMs': estimate?.inMilliseconds,
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
                'acceptable': r.failed && r.acceptable && log != null,
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
          'error': w.error,
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
      } else if (path == '/logo.svg') {
        res.headers
          ..contentType = ContentType('image', 'svg+xml')
          ..set('cache-control', 'max-age=86400');
        res.write(jewelryLogo);
      } else if (path.startsWith('/accept/') && request.method == 'POST') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(_accept(Uri.decodeComponent(path.substring(8)))));
      } else if (path == '/state.json') {
        res.headers
          ..contentType = ContentType.json
          ..set('cache-control', 'no-store');
        res.write(jsonEncode(state));
      } else if (path.startsWith('/screen/')) {
        await _screen(Uri.decodeComponent(path.substring(8)), res);
      } else if (path.startsWith('/video/')) {
        await _video(path.substring(7).split('/'), request);
      } else if (path.startsWith('/timeline/')) {
        await _timeline(path.substring(10).split('/'), res);
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

  /// Makes this run's recordings of the scenario file behind [key] its
  /// goldens, as `jewelry accept` does.
  Map<String, Object?> _accept(String key) {
    final t = _tests[key];
    if (t == null || log == null) return {'accepted': 0, 'refused': 0};
    final (:accepted, :refused) = acceptLastRun(
      log!,
      only: [t.file],
      profile: t.profile,
    );
    finished(t.profile, t.file, t.results);
    return {'accepted': accepted.length, 'refused': refused.length};
  }

  /// The recording behind `<kind>/<slug>/<profile>`: `golden` or `failure`
  /// (this run's recording of a failed scenario). Null for a bad request.
  String? _recording(List<String> parts) {
    if (parts.length != 3 || parts.any((p) => p.contains('..'))) return null;
    final [kind, name, profile] = parts;
    return switch (kind) {
      'golden' => '${root.path}/goldens/$name/$profile',
      'failure' => '${root.path}/failures/$name/$profile/actual',
      _ => null,
    };
  }

  /// `/video/<kind>/<slug>/<profile>`: that recording as an MP4, made once
  /// and kept until the recording changes. Answers range requests, which a
  /// browser needs to seek.
  Future<void> _video(List<String> parts, HttpRequest request) async {
    final res = request.response;
    final base = _recording(parts);
    if (base == null || !File('$base.apng').existsSync()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final out = File('${root.path}/videos/dashboard/${parts.join('.')}.mp4');
    final source = File('$base.apng').lastModifiedSync();
    if (!out.existsSync() || out.lastModifiedSync().isBefore(source)) {
      // Decoding a recording takes seconds of CPU; keep the server free.
      await _videoInIsolate(base, out);
    }
    await _send(out, request, ContentType('video', 'mp4'));
  }

  /// `/timeline/<kind>/<slug>/<profile>`: where each step sits in that
  /// recording's video ([videoTimeline]).
  Future<void> _timeline(List<String> parts, HttpResponse res) async {
    final base = _recording(parts);
    final steps = File('$base.steps.json');
    if (base == null || !steps.existsSync()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(videoTimeline(steps.readAsStringSync())));
  }

  /// [file], or the byte range the request asks for.
  static Future<void> _send(
    File file,
    HttpRequest request,
    ContentType type,
  ) async {
    final res = request.response;
    final length = file.lengthSync();
    res.headers
      ..contentType = type
      ..set('accept-ranges', 'bytes');
    final range = RegExp(r'bytes=(\d*)-(\d*)')
        .firstMatch(request.headers.value('range') ?? '');
    if (range == null) {
      res.contentLength = length;
      await res.addStream(file.openRead());
      return;
    }
    final start = int.tryParse(range.group(1)!) ?? 0;
    final end = int.tryParse(range.group(2)!) ?? length - 1;
    if (start >= length || end < start) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      return;
    }
    final last = end < length ? end : length - 1;
    res
      ..statusCode = HttpStatus.partialContent
      ..contentLength = last - start + 1;
    res.headers.set('content-range', 'bytes $start-$last/$length');
    await res.addStream(file.openRead(start, last + 1));
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
  String? error;
  Device? device;
  String? test;
  List<String> steps = [];
  String? step;
  Uint8List? last;
  DateTime? shotAt;
  Future<Uint8List>? shot;
}
