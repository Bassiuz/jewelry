// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:jewelry/src/accept.dart';
import 'package:jewelry/src/compare.dart';
import 'package:jewelry/src/compare_screens.dart';
import 'package:jewelry/src/comparison_result.dart';
import 'package:jewelry/src/device/android_device.dart';
import 'package:jewelry/src/device/device.dart';
import 'package:jewelry/src/device/device_for_profile.dart';
import 'package:jewelry/src/device_profile.dart';
import 'package:jewelry/src/firebase_emulators.dart';
import 'package:jewelry/src/html_report.dart';
import 'package:jewelry/src/jewelry_config.dart';
import 'package:jewelry/src/match_mode.dart';
import 'package:jewelry/src/report.dart';
import 'package:jewelry/src/run_log.dart';
import 'package:jewelry/src/run_progress.dart';
import 'package:jewelry/src/scenario_recording.dart';
import 'package:jewelry/src/scenario_result.dart';
import 'package:jewelry/src/dashboard.dart';
import 'package:jewelry/src/scenario_suite.dart';
import 'package:jewelry/src/video.dart';
import 'package:jewelry/src/slug.dart';
import 'package:jewelry/src/snapshots.dart';

const usage = """
jewelry run [--record] [--failed] [--profile <name>] [--match frames|screens]
            [--drift <n>] [--rest <n>] [--tolerance <pct>] [--parallel <n>]
            [--window] [--verbose]
            [files...]
jewelry accept [scenario...]
jewelry devices

run      Runs every integration_test/scenarios/*_test.dart on each profile in
         jewelry.yaml and compares against the goldens. --failed runs only
         what failed last time. --verbose prints the flutter test output.
         Android emulators run without a window and, with --parallel or
         `parallel:` in jewelry.yaml, several at once; --window shows them.
         Without --profile it runs `default_profile:`, or every profile.
accept   Makes the recordings of the last run the goldens, without running
         anything. Names a scenario by label or file to accept only that one.

Goldens live in .jewelry/goldens, failures in .jewelry/failures, the report
of the last run in .jewelry/report.html.""";

/// `fvm dart` when the CLI itself runs through fvm, for commands to paste.
final _dart = Platform.resolvedExecutable.contains('/fvm/')
    ? 'fvm dart'
    : 'dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addFlag(
      'record',
      negatable: false,
      help: 'Write goldens instead of comparing',
    )
    ..addFlag('failed', negatable: false, help: 'Only what failed last time')
    ..addFlag(
      'verbose',
      negatable: false,
      help: 'Print the flutter test output',
    )
    ..addFlag('window', negatable: false, help: 'Show the emulator window')
    ..addFlag(
      'dashboard',
      defaultsTo: true,
      help: 'Serve a live dashboard of the run on localhost',
    )
    ..addOption('dashboard-port', help: 'Port of the dashboard (4848)')
    ..addOption('parallel', help: 'Emulators at once')
    ..addOption('profile', help: 'Only this profile')
    ..addOption('match', allowed: ['frames', 'screens'])
    ..addOption('drift')
    ..addOption('rest')
    ..addOption('tolerance');
  final args = parser.parse(argv);
  if (args.rest.firstOrNull == 'run' && !File('jewelry.yaml').existsSync()) {
    // First run in this app: write the file the flags default from.
    final avds =
        await Process.run('${AndroidDevice.findSdk()}/emulator/emulator', [
          '-list-avds',
        ]).then(
          (r) => [
            for (final l in (r.stdout as String).split('\n'))
              if (l.trim().isNotEmpty && !l.contains(' ')) l.trim(),
          ],
          onError: (_) => <String>[],
        );
    File('jewelry.yaml').writeAsStringSync(JewelryConfig.starter(avds));
    print(
      'Wrote jewelry.yaml with a profile for '
      '${avds.firstOrNull ?? 'an AVD you still have to create'}. '
      'Check it, then run this again.',
    );
    exit(0);
  }
  final config = JewelryConfig.load(File('jewelry.yaml'));
  final wanted = args['profile'] as String? ?? config.defaultProfile;
  final profiles = wanted == null
      ? config.profiles.values.toList()
      : [
          config.profiles[wanted] ??
              (throw ArgumentError('No profile $wanted in jewelry.yaml')),
        ];
  final log = RunLog.load(Directory('.jewelry')..createSync());

  switch (args.rest.firstOrNull) {
    case 'devices':
      for (final p in profiles) {
        final found = await deviceForProfile(p).exists();
        print('${found ? 'ok     ' : 'missing'}  ${p.name}  (${p.platform})');
      }
    case 'accept':
      final (:accepted, :refused) = acceptLastRun(
        log,
        only: args.rest.sublist(1),
      );
      writeHtmlReport(log, dart: _dart);
      for (final r in accepted) {
        print(
          'accepted "${r.label}" on ${r.profile}: '
          '${r.frames} frames, ${r.snapshots} snapshots are the golden now',
        );
      }
      for (final r in refused) {
        print(
          'not accepted "${r.label}" on ${r.profile}: the run did not '
          'finish (${r.reason}). Fix it and run it again.',
        );
      }
      if (accepted.isEmpty && refused.isEmpty) {
        print(
          'Nothing to accept: the last run left no failed comparison'
          '${args.rest.length > 1 ? ' by that name' : ''}.',
        );
      }
      exit(refused.isEmpty ? 0 : 1);
    case 'dashboard':
      // The last runs' results, without running anything.
      if (log.results.isEmpty) {
        print('Nothing to show yet: run jewelry run first.');
        exit(2);
      }
      final dashboard = Dashboard(root: Directory('.jewelry'))..showLog(log);
      await dashboard.start(
        port: int.tryParse(args['dashboard-port'] ?? '') ?? 4848,
      );
      print(
        'jewelry: dashboard of the last run at ${dashboard.url} '
        '(${log.results.length} scenarios). Ctrl-C stops it.',
      );
      if (Platform.isMacOS) await Process.run('open', ['${dashboard.url}']);
      await ProcessSignal.sigint.watch().first;
      await dashboard.stop();
      exit(0);
    case 'video':
      // jewelry video <scenario>...: the golden of each, as an MP4 to share.
      final wantedNames = args.rest.sublist(1);
      if (wantedNames.isEmpty) {
        print(
          'Usage: jewelry video <scenario>... (a name under .jewelry/goldens)',
        );
        exit(64);
      }
      final goldens = Directory('.jewelry/goldens');
      final known = goldens.existsSync()
          ? [
              for (final d in goldens.listSync().whereType<Directory>())
                d.path.split('/').last,
            ]
          : <String>[];
      var failed = false;
      for (final want in wantedNames) {
        // An exact name, or a part of one that names a single scenario.
        final hits = known.contains(want)
            ? [want]
            : known.where((k) => k.contains(slug(want))).toList();
        if (hits.length != 1) {
          print(
            hits.isEmpty
                ? 'No golden matches "$want".'
                : '"$want" matches ${hits.length}: ${hits.join(', ')}',
          );
          failed = true;
          continue;
        }
        for (final p in profiles) {
          final base = '.jewelry/goldens/${hits.single}/${p.name}';
          if (!File('$base.apng').existsSync()) continue;
          final out = File('.jewelry/videos/${hits.single}.${p.name}.mp4');
          await writeVideo(ScenarioRecording.read(base), out);
          print(
            '${out.path}  ${(out.lengthSync() / 1e6).toStringAsFixed(1)} MB',
          );
        }
      }
      exit(failed ? 1 : 0);
    case 'run':
      final names = {for (final p in profiles) p.name};
      final files =
          args['failed'] as bool
                ? {
                    for (final r in log.results)
                      if (r.failed && names.contains(r.profile)) r.file,
                  }.toList()
                : args.rest.length > 1
                ? args.rest.sublist(1)
                : _scenarioFiles()
            ..sort();
      if (files.isEmpty) {
        stderr.writeln(
          args['failed'] as bool
              ? 'Nothing failed in the last run.'
              : 'No scenarios in integration_test/scenarios',
        );
        exit(args['failed'] as bool ? 0 : 2);
      }
      if (args['dashboard'] as bool) {
        _dashboard = Dashboard(root: Directory('.jewelry'));
        await _dashboard!.start(
          port: int.tryParse(args['dashboard-port'] ?? '') ?? 4848,
        );
        print('jewelry: live dashboard at ${_dashboard!.url}');
      }
      final failed = await _run(
        config: config,
        profiles: profiles,
        files: files,
        log: log,
        record: args['record'] as bool,
        verbose: args['verbose'] as bool,
        window: args['window'] as bool || !config.headless,
        parallel: int.tryParse(args['parallel'] ?? '') ?? config.parallel,
        match: args['match'] == null
            ? config.match
            : MatchMode.values.byName(args['match'] as String),
        drift: int.tryParse(args['drift'] ?? '') ?? config.drift,
        rest: int.tryParse(args['rest'] ?? '') ?? config.rest,
        tolerance: double.tryParse(args['tolerance'] ?? '') ?? config.tolerance,
      );
      await _dashboard?.stop();
      exit(failed ? 1 : 0);
    default:
      print(usage);
      exit(2);
  }
}

Future<bool> _run({
  required JewelryConfig config,
  required List<DeviceProfile> profiles,
  required List<String> files,
  required RunLog log,
  required bool record,
  required bool verbose,
  required bool window,
  required int parallel,
  required MatchMode match,
  required int drift,
  required int rest,
  required double tolerance,
}) async {
  File('.jewelry/.gitignore').writeAsStringSync('*\n');
  Directory('.jewelry/logs').createSync();
  // Every scenario file of the app goes into the one entry point, not just
  // the ones of this run, so running a single file does not rebuild the app.
  final suite = ScenarioSuite([..._scenarioFiles(), ...files]);
  final entry = File(ScenarioSuite.path);
  // Left alone when nothing changed, so the build sees the same input.
  if (!entry.existsSync() || entry.readAsStringSync() != suite.source) {
    entry.writeAsStringSync(suite.source);
  }

  // ponytail: only Android runs in parallel. Simulators share the host's
  // ports, so the channel and the fakes of two of them would collide.
  int workersFor(DeviceProfile p) =>
      p.platform == 'android' ? parallel.clamp(1, files.length) : 1;
  final workers = profiles.map(workersFor).reduce((a, b) => a > b ? a : b);

  // What the same files took last time; files never run count as average.
  final known = [
    for (final p in profiles)
      for (final f in files) log.lastDuration(f, p.name),
  ];
  final measured = known.nonNulls.toList();
  final average = measured.isEmpty
      ? null
      : measured.reduce((a, b) => a + b) ~/ measured.length;
  final progress = RunProgress(
    total: known.length,
    workers: workers,
    estimate: average == null
        ? null
        : known.fold<Duration>(
                Duration.zero,
                (sum, d) => sum + (d ?? average),
              ) ~/
              workers,
    // The raw output and a redrawn footer do not mix.
    live: verbose ? false : null,
  );
  progress.line(
    'jewelry: ${record ? 'recording' : 'comparing (${match.name})'} '
    '${files.length} scenario files on ${profiles.map((p) => p.name).join(', ')}'
    '${workers > 1 ? ', $workers emulators at once' : ''}',
  );
  final ran = <ScenarioResult>[];
  // Two builds in one project overwrite each other's APK.
  final building = _Turn();
  // The APK of every set of build arguments, built once.
  final builds = <String, Future<String>>{};
  // Instances of one AVD started in the same instant never finish booting:
  // each wipes the data they share while the other reads it.
  final booting = _Turn();

  try {
    for (final profile in profiles) {
      final queue = log.longestFirst(files, profile.name);
      _dashboard?.queue(profile.name, queue);
      final count = workersFor(profile);
      // A worker that dies (its emulator did not boot) leaves its share of
      // the queue to the others; the error is shown once they are done.
      final errors = <Object>[];
      await Future.wait([
        for (var worker = 0; worker < count; worker++)
          _worker(
            worker: worker,
            // One emulator runs the AVD the ordinary way.
            instance: count > 1 ? worker : null,
            config: config,
            profile: profile,
            queue: queue,
            named: profiles.length > 1,
            log: log,
            ran: ran,
            progress: progress,
            building: building,
            builds: builds,
            booting: booting,
            record: record,
            verbose: verbose,
            window: window,
            match: match,
            drift: drift,
            rest: rest,
            tolerance: tolerance,
          ).catchError((Object e) => errors.add(e)),
      ]);
      if (errors.isNotEmpty) {
        progress.close();
        if (errors.whereType<_BuildFailed>().firstOrNull case final failed?) {
          stderr.writeln(failed);
          exit(1);
        }
        throw StateError(
          '${errors.length} of $count emulators stopped early:\n'
          '${errors.join('\n')}',
        );
      }
    }
  } finally {
    progress.close();
  }
  progress.summary(ran, dart: _dart);
  return ran.any((r) => r.failed);
}

/// One emulator with its own Firebase emulators, running scenario files
/// from [queue] until it is empty.
Future<void> _worker({
  required int worker,
  required int? instance,
  required JewelryConfig config,
  required DeviceProfile profile,
  required List<String> queue,
  required bool named,
  required RunLog log,
  required List<ScenarioResult> ran,
  required RunProgress progress,
  required _Turn building,
  required Map<String, Future<String>> builds,
  required _Turn booting,
  required bool record,
  required bool verbose,
  required bool window,
  required MatchMode match,
  required int drift,
  required int rest,
  required double tolerance,
}) async {
  final fb = config.firebase?.forWorker(worker);
  final emulators = fb == null ? null : FirebaseEmulators(fb);
  final device = deviceForProfile(profile, window: window, instance: instance);
  final who = instance == null ? profile.name : '${profile.name} ${worker + 1}';
  final testArgs = [
    ...config.flutterTestArgs,
    // Android: every worker's build gets the ports of `firebase.json` on
    // the device's own loopback, and `adb reverse` sends them to this
    // worker's emulators, so all workers share one build. 127.0.0.2, not
    // localhost: FlutterFire rewrites localhost and 127.0.0.1 to 10.0.2.2.
    if (device is AndroidDevice) ...[
      ...?config.firebase?.dartDefines,
      if (fb != null) '--dart-define=JEWELRY_FIREBASE_HOST=127.0.0.2',
    ] else
      ...?fb?.dartDefines,
    // Lets the app make its rendering deterministic for the recording, for
    // example a fixed ink sparkle seed: bool.fromEnvironment('JEWELRY').
    '--dart-define=JEWELRY=true',
  ];
  // Android: one build per set of arguments, shared by every worker that
  // has the same. Started now, so it runs while the emulator boots.
  final apk = device is AndroidDevice
      ? builds.putIfAbsent(testArgs.join(' '), () async {
          final name = 'app-${builds.length}.apk';
          final done = await building.take();
          try {
            _say(
              progress,
              profile.name,
              worker,
              '$who: building the app, once for this run',
            );
            return await _buildApk(testArgs, name);
          } finally {
            done();
          }
        })
      : null;
  // Its error is reported where it is awaited, after the boot.
  apk?.ignore();
  var booted = false;
  final judging = <Future<void>>[];
  try {
    if (emulators != null) {
      _say(
        progress,
        profile.name,
        worker,
        '$who: firebase emulators starting (${fb!.only.join(', ')})',
      );
      await emulators.start();
    }
    final bootedTurn = await booting.take();
    _say(progress, profile.name, worker, '$who: booting');
    final String id;
    try {
      id = await device.boot();
    } finally {
      bootedTurn();
    }
    booted = true;
    _say(progress, profile.name, worker, '$who: booted as $id');
    _dashboard?.attach(profile.name, worker, device);
    if (fb != null && device is AndroidDevice) {
      final base = config.firebase!;
      await device.reverse(base.authPort, fb.authPort);
      await device.reverse(base.firestorePort, fb.firestorePort);
      // Fake Cloud Functions listen on the device itself.
      if (fb.only.contains('functions')) {
        await device.reverse(base.functionsPort, fb.functionsPort);
      }
    }
    if (fb != null && !fb.only.contains('functions')) {
      // The app calls the Functions emulator port on the host
      // (10.0.2.2); fake Cloud Functions listen on the device.
      await device.forwardToDevice(fb.functionsPort);
    }
    await device.startLog(
      File(
        '.jewelry/logs/${profile.name}${worker == 0 ? '' : '.${worker + 1}'}.log',
      ),
    );
    // Before the first scenario, so its time does not include the build.
    final built = await apk;
    while (queue.isNotEmpty) {
      final file = queue.removeAt(0);
      final name = file.split('/').last;
      progress.start(named ? '$name on ${profile.name}' : name, worker: worker);
      _dashboard?.started(profile.name, file, worker);
      final watch = Stopwatch()..start();
      await emulators?.clear();
      if (config.clock != null) await device.setClock(config.clock!);
      final run = device is AndroidDevice
          ? await _runBuilt(
              file,
              device,
              built!,
              profile.name,
              progress,
              worker: worker,
              verbose: verbose,
            )
          : await _flutterTest(
              file,
              id,
              device,
              profile.name,
              testArgs,
              progress,
              worker: worker,
              building: building,
              verbose: verbose,
            );
      // Pulled now and judged off the emulator: comparing takes seconds of
      // CPU on the Mac, and the emulator can run the next scenario meanwhile.
      final pulled = <String, (Uint8List, String)>{};
      for (final MapEntry(key: label, value: base) in run.recorded.entries) {
        final apng = await device.pull('$base.apng');
        if (apng.length < 8 || apng[0] != 0x89 || apng[1] != 0x50) {
          throw StateError(
            'Pulling $base.apng did not return a PNG. Got '
            '${apng.length} bytes: '
            '${utf8.decode(apng.take(200).toList(), allowMalformed: true)}',
          );
        }
        pulled[label] = (
          apng,
          utf8.decode(await device.pull('$base.steps.json')),
        );
      }
      // Remove what the run left behind (alarms, notifications) before
      // the next scenario, also when nothing was recorded.
      final appPath = run.recorded.values.firstOrNull ?? run.appPath;
      if (appPath != null) await device.clearApp(appPath);

      final judge = _Judge(
        file: file,
        name: name,
        profile: profile.name,
        duration: watch.elapsed,
        record: record,
        match: match,
        drift: drift,
        rest: rest,
        tolerance: tolerance,
        exitCode: run.exitCode,
        reason: run.reason,
        detail: run.detail,
        step: run.step,
        log: run.log,
        pulled: pulled,
      );
      progress.release(worker: worker);
      _dashboard?.judging(profile.name, worker);
      judging.add(
        _judgeInIsolate(judge).then((results) {
          ran.addAll(results);
          // After every file, so a run that is stopped halfway still leaves
          // a report and `--failed` knows what to rerun.
          log
            ..replace(file, profile.name, results)
            ..save();
          writeHtmlReport(log, dart: _dart);
          progress.finish(results);
          _dashboard?.finished(profile.name, file, results);
        }),
      );
    }
  } finally {
    await Future.wait(judging);
    _say(progress, profile.name, worker, '$who: shutting down');
    if (booted) await device.stopLog();
    // A device that never booted may have nothing to shut down; its boot
    // error is the one to report.
    await device.shutdown().catchError((Object _) {}, test: (_) => !booted);
    await emulators?.stop();
  }
}

/// Lets one caller at a time through: [take] completes when it is the
/// caller's turn and returns what to call when done.
class _Turn {
  Future<void> _last = Future.value();

  Future<void Function()> take() async {
    final before = _last;
    final done = Completer<void>();
    _last = done.future;
    await before;
    return () {
      if (!done.isCompleted) done.complete();
    };
  }
}

/// What one run of a scenario file produced.
typedef _TestRun = ({
  /// Label to on-device base path of every scenario that reported frames.
  Map<String, String> recorded,
  int exitCode,
  String? appPath,

  /// Why it failed, in one line; empty when [exitCode] is 0.
  String reason,
  String detail,
  String? step,

  /// The run's output, relative to `.jewelry`.
  String log,
});

/// A device that loses its network leaves the app waiting on the emulators
/// forever, and the run with it. Silence this long is a hang, not a wait.
// ponytail: fixed limit, make it a jewelry.yaml option when a scenario
// legitimately stays silent longer.
const _stall = Duration(minutes: 10);

/// Reads what one scenario file's run prints, whether `flutter test` or the
/// device log carries it: the markers, the steps for [progress], and the
/// first failure. Everything else goes to the log file.
class _Output {
  _Output(
    String file,
    this.profile,
    this.device,
    this.progress, {
    required this.worker,
    required this.verbose,
    this.onRunning,
  }) : logPath =
           'logs/${file.split('/').last.replaceAll('.dart', '')}.$profile.log' {
    log = File('.jewelry/$logPath').openWrite();
  }

  final String profile;
  final Device device;
  final RunProgress progress;
  final int worker;
  final bool verbose;

  /// Called at every sign that the app is installed and running.
  final void Function()? onRunning;
  final String logPath;
  late final IOSink log;

  final recorded = <String, String>{};
  String? appPath;
  String? step;
  String? reason;
  final detail = <String>[];
  final tail = <String>[];
  var _inDetail = false;

  static final _stepFailed = RegExp(r'jewelry: step "(.*)" failed: (.*)$');
  static final _stepStarted = RegExp(r'jewelry: step "(.*)"$');
  static final _stepsPlanned = RegExp(r'jewelry: steps\t(.*)\t(\[.*\])$');
  static final _uncaught = RegExp(r'jewelry: uncaught error in ".*": (.*)$');

  void add(String line) {
    final at = line.indexOf('${ScenarioRecording.marker}\t');
    final channelAt = line.indexOf('${ScenarioRecording.channelMarker}\t');
    if (at >= 0) {
      final parts = line.substring(at).split('\t');
      recorded[parts[1]] = parts[2];
      onRunning?.call();
      return;
    }
    if (channelAt >= 0) {
      final parts = line.substring(channelAt).split('\t');
      appPath = parts[2];
      onRunning?.call();
      final shots = Directory('.jewelry/shots/${slug(parts[3])}/$profile');
      unawaited(
        _serveChannel(device, int.parse(parts[1]), parts[2], shots, log),
      );
      return;
    }
    log.writeln(line);
    if (verbose) stdout.writeln(line);
    if (line.trim().isNotEmpty) {
      tail.add(line);
      if (tail.length > 15) tail.removeAt(0);
    }
    final failure = _stepFailed.firstMatch(line) ?? _uncaught.firstMatch(line);
    if (failure != null) {
      // The first one is the cause; flutter_test repeats it afterwards.
      if (reason == null) {
        final inStep = failure.groupCount == 2;
        if (inStep) step = failure.group(1);
        reason = inStep ? 'Step "$step" failed' : 'Uncaught error';
        detail.add(_short(failure.group(failure.groupCount)!));
        _inDetail = true;
      }
    } else if (_inDetail) {
      // The message runs on (what was on screen) until the stack trace.
      _inDetail = line.trim().isNotEmpty && !line.startsWith('#');
      if (_inDetail) detail.add(_short(line));
    } else {
      final started = _stepStarted.firstMatch(line);
      final planned = _stepsPlanned.firstMatch(line);
      if (started != null) {
        step = started.group(1);
        onRunning?.call();
        progress.step(step!, worker: worker);
        _dashboard?.step(profile, worker, step!);
      } else if (planned != null) {
        _dashboard?.planned(
          profile,
          worker,
          planned.group(1)!,
          (jsonDecode(planned.group(2)!) as List).cast<String>(),
        );
      }
    }
  }

  /// [exitCode] is non-zero when the run did not pass; [fallback] names why
  /// when no step or error did.
  Future<_TestRun> finish(int exitCode, {required String fallback}) async {
    await log.close();
    if (exitCode != 0 && reason == null) {
      reason = fallback;
      detail.addAll(tail.map(_short));
    }
    return (
      recorded: recorded,
      // A stalled run was stopped; whatever it reports, it did not pass.
      exitCode: reason != null && exitCode == 0 ? 1 : exitCode,
      appPath: appPath,
      reason: reason ?? '',
      detail: detail.join('\n'),
      step: step,
      log: logPath,
    );
  }
}

/// Runs the scenarios of one file on [deviceId] with `flutter test`, which
/// builds the app every time. For devices the CLI cannot start a built app
/// on itself (simulators); Android goes through [_runBuilt].
///
/// Serves the on-device host channel while the test runs: device actions
/// arrive as JSON lines and are performed on [device]. The output goes to a
/// log file; the step lines in it drive [progress] and name the failure.
Future<_TestRun> _flutterTest(
  String file,
  String deviceId,
  Device device,
  String profile,
  List<String> extraArgs,
  RunProgress progress, {
  required int worker,
  required _Turn building,
  required bool verbose,
}) async {
  // Held until the app is installed and running: `flutter test` builds into
  // the project's one build folder, and another device's build would
  // replace the app before this one is installed.
  final built = await building.take();
  final out = _Output(
    file,
    profile,
    device,
    progress,
    worker: worker,
    verbose: verbose,
    onRunning: built,
  );
  final p = await Process.start('${_flutterRoot()}/bin/flutter', [
    'test',
    ScenarioSuite.path,
    '--name',
    ScenarioSuite.nameOf(file),
    '-d',
    deviceId,
    // The app's temp dir holds the recording; keep it until it is pulled.
    '--no-uninstall',
    ...extraArgs,
  ]);
  final stderrDone = p.stderr.transform(utf8.decoder).forEach((chunk) {
    out.log.write(chunk);
    if (verbose) stderr.write(chunk);
  });
  await p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .timeout(
        _stall,
        onTimeout: (sink) {
          out.reason =
              'No output for ${_stall.inMinutes} minutes, stopped '
              '(is the device network down?)';
          p.kill();
          sink.close();
        },
      )
      .forEach(out.add);
  final exitCode = await p.exitCode;
  built();
  await stderrDone;
  return out.finish(exitCode, fallback: 'flutter test exited $exitCode');
}

/// Runs the scenarios of one file on [device] out of the built [apk]:
/// installs it, tells it which file to run, starts it and follows what it
/// prints until it says it is done. No build and no Flutter tool involved.
Future<_TestRun> _runBuilt(
  String file,
  AndroidDevice device,
  String apk,
  String profile,
  RunProgress progress, {
  required int worker,
  required bool verbose,
}) async {
  final out = _Output(
    file,
    profile,
    device,
    progress,
    worker: worker,
    verbose: verbose,
  );
  final package = await device.packageOf(apk);
  final app = await device.startScenario(
    apk,
    package,
    ScenarioSuite.keyOf(file),
  );
  // Nothing on the host is attached to the app, so an app that dies (a
  // crash, the emulator out of memory) only shows as a process that is gone.
  var gone = 0;
  final alive = Timer.periodic(const Duration(seconds: 5), (_) async {
    gone = await device.isRunning(package) ? 0 : gone + 1;
    if (gone < 2) return;
    out.reason ??= 'The app stopped before the scenario was over';
    app.kill();
  });
  int? failed;
  await app.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .timeout(
        _stall,
        onTimeout: (sink) {
          out.reason ??=
              'No output for ${_stall.inMinutes} minutes, stopped '
              '(is the device network down?)';
          app.kill();
          sink.close();
        },
      )
      .forEach((line) {
        if (line.startsWith('$suiteDoneMarker\t')) {
          failed = int.parse(line.split('\t')[2]);
          app.kill();
        } else {
          out.add(line);
        }
      });
  alive.cancel();
  final run = await out.finish(
    failed == 0 ? 0 : 1,
    fallback: failed == null
        ? 'The app stopped before the scenario was over'
        : 'The scenario failed',
  );
  // Names the app for the uninstall when it never got to say where it is.
  return (
    recorded: run.recorded,
    exitCode: run.exitCode,
    appPath: run.appPath ?? '/data/data/$package/',
    reason: run.reason,
    detail: run.detail,
    step: run.step,
    log: run.log,
  );
}

/// The app did not build; [errors] is what the build said about it.
class _BuildFailed implements Exception {
  const _BuildFailed(this.errors);
  final String errors;

  @override
  String toString() =>
      'The app did not build:\n$errors\n'
      'Full output: .jewelry/logs/build.log';
}

/// Builds the app with every scenario in it and returns the APK, kept
/// under [name] because the next build replaces the one in `build/`.
Future<String> _buildApk(List<String> args, String name) async {
  final r = await Process.run('${_flutterRoot()}/bin/flutter', [
    'build',
    'apk',
    '--debug',
    '--target',
    ScenarioSuite.path,
    ...args,
  ]);
  final said = '${r.stdout}\n${r.stderr}';
  File('.jewelry/logs/build.log').writeAsStringSync(said);
  final built = RegExp(r'Built (\S+\.apk)').firstMatch(said);
  if (r.exitCode != 0 || built == null) throw _BuildFailed(_buildErrors(said));
  Directory('.jewelry/build').createSync();
  return File(built.group(1)!).copySync('.jewelry/build/$name').path;
}

/// The lines of a failed build that say why: Dart and Kotlin compile errors
/// and what Gradle puts under "What went wrong", else its last lines.
String _buildErrors(String output) {
  final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
  final why = <String>[];
  var wentWrong = 0;
  for (final line in lines) {
    if (line.startsWith('* What went wrong:')) {
      wentWrong = 3;
    } else if (wentWrong > 0 ||
        line.startsWith('e: ') ||
        line.contains(': Error: ')) {
      if (wentWrong > 0) wentWrong--;
      why.add(_short(line));
    }
  }
  return (why.isEmpty
          ? lines.skip(lines.length > 15 ? lines.length - 15 : 0)
          : why.take(12))
      .join('\n');
}

/// Every scenario file of the app in the working directory.
List<String> _scenarioFiles() {
  final dir = Directory('integration_test/scenarios');
  if (!dir.existsSync()) return [];
  return [
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('_test.dart')) f.path,
  ];
}

/// One line of an error, cut where it stops being readable in a summary.
String _short(String line) =>
    line.length > 500 ? '${line.substring(0, 500)}…' : line;

/// `dart` lives at `<flutter>/bin/cache/dart-sdk/bin/dart`, so this follows
/// whatever SDK ran the CLI (fvm included).
String _flutterRoot() =>
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;

/// Answers device action requests from the on-device test until it hangs up.
Future<void> _serveChannel(
  Device device,
  int port,
  String appPath,
  Directory shots,
  IOSink log,
) async {
  final socket = await device.connectChannel(port);
  var shotCount = 0;
  await for (final line
      in socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map<String, dynamic>;
    final args = (request['args'] as Map?)?.cast<String, Object?>() ?? {};
    Object? result;
    try {
      switch (request['action']) {
        case 'background':
          await device.background(appPath);
        case 'foreground':
          await device.foreground(appPath);
        case 'screenshot':
          final png = await device.screenshot(shade: args['shade'] == true);
          final label = args['label'] as String?;
          if (label != null) {
            shots.createSync(recursive: true);
            final name = '${shotCount++}_${slug(label)}.png';
            File('${shots.path}/$name').writeAsBytesSync(png);
            log.writeln('jewelry: screenshot ${shots.path}/$name');
          }
          result = base64Encode(png);
        case 'tapNotificationAction':
          await device.tapNotificationAction(args['text'] as String);
        case 'back':
          await device.back();
        case 'screenOff':
          await device.screenOff();
        case 'screenOn':
          await device.screenOn();
        case 'lockScreen':
          await device.lockScreen();
        case 'setAppOp':
          await device.setAppOp(
            appPath,
            args['op'] as String,
            args['mode'] as String,
          );
        case 'grantPermission':
          await device.grantPermission(appPath, args['permission'] as String);
        default:
          throw UnsupportedError('Unknown device action ${request['action']}');
      }
      socket.writeln(
        jsonEncode({'id': request['id'], 'ok': true, 'result': result}),
      );
    } catch (e) {
      socket.writeln(
        jsonEncode({'id': request['id'], 'ok': false, 'error': '$e'}),
      );
    }
  }
  await socket.close();
}

/// Top level, so the isolate's closure captures [j] and nothing of the
/// worker (its device and processes cannot be sent).
Future<List<ScenarioResult>> _judgeInIsolate(_Judge j) =>
    Isolate.run(() => _judgeRun(j));

/// What [_judgeRun] needs, all sendable to an isolate.
class _Judge {
  _Judge({
    required this.file,
    required this.name,
    required this.profile,
    required this.duration,
    required this.record,
    required this.match,
    required this.drift,
    required this.rest,
    required this.tolerance,
    required this.exitCode,
    required this.reason,
    required this.detail,
    required this.step,
    required this.log,
    required this.pulled,
  });

  final String file;
  final String name;
  final String profile;
  final Duration duration;
  final bool record;
  final MatchMode match;
  final int drift;
  final int rest;
  final double tolerance;
  final int exitCode;
  final String reason;
  final String detail;
  final String? step;
  final String? log;

  /// Per scenario label: the pulled APNG and its steps JSON.
  final Map<String, (Uint8List, String)> pulled;
}

/// Records, or compares against the goldens, what one scenario file
/// recorded, and writes failure evidence. Runs in its own isolate.
List<ScenarioResult> _judgeRun(_Judge j) {
  final results = <ScenarioResult>[];
  ScenarioResult result(
    String label,
    Outcome outcome, {
    String reason = '',
    String detail = '',
    String? step,
    bool acceptable = false,
    ScenarioRecording? recording,
  }) => ScenarioResult(
    label: label,
    file: j.file,
    profile: j.profile,
    outcome: outcome,
    duration: j.duration,
    ranAt: DateTime.now(),
    reason: reason,
    detail: detail,
    step: step,
    acceptable: acceptable,
    frames: recording?.frames.length ?? 0,
    snapshots: recording?.snapshots.length ?? 0,
    log: j.log,
  );
  if (j.pulled.isEmpty) {
    // No scenario got as far as reporting frames: a build failure, a
    // crash at start or a stall. The file name stands in for it.
    return [
      result(
        j.name,
        Outcome.failed,
        reason: j.reason,
        detail: j.detail,
        step: j.step,
      ),
    ];
  }
  final record = j.record;
  final match = j.match;
  final drift = j.drift;
  final rest = j.rest;
  final tolerance = j.tolerance;
  for (final MapEntry(key: label, value: (apng, steps)) in j.pulled.entries) {
    final actual = ScenarioRecording.decode(apng, steps);
    final goldenBase = '.jewelry/goldens/${slug(label)}/${j.profile}';
    final images = SnapshotGoldens(Directory(goldenBase));
    // Whatever an earlier run left here is about another recording.
    final dir = Directory('.jewelry/failures/${slug(label)}/${j.profile}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);

    if (j.exitCode != 0) {
      // A step failed; keep the frames up to the failure as evidence.
      dir.createSync(recursive: true);
      actual.write('${dir.path}/actual');
      if (actual.frames.isNotEmpty) {
        File('${dir.path}/actual_frame.png')
            .writeAsBytesSync(actual.frames.last.png);
      }
      results.add(
        result(
          label,
          Outcome.failed,
          reason: j.reason,
          detail: j.detail,
          step: j.step,
          recording: actual,
        ),
      );
    } else if (record) {
      Directory(goldenBase).parent.createSync(recursive: true);
      actual.write(goldenBase);
      images.record(actual);
      results.add(result(label, Outcome.recorded, recording: actual));
    } else if (!File('$goldenBase.apng').existsSync()) {
      // Kept, so `jewelry accept` can make it the golden.
      dir.createSync(recursive: true);
      actual.write('${dir.path}/actual');
      results.add(
        result(
          label,
          Outcome.failed,
          reason: 'No golden yet',
          detail: 'Run with --record, or accept this recording.',
          acceptable: true,
          recording: actual,
        ),
      );
    } else {
      final golden = ScenarioRecording.read(goldenBase);
      final compared = match == MatchMode.screens
          ? compareScreens(
              golden: golden.frames,
              actual: actual.frames,
              rest: rest,
              tolerance: tolerance,
            )
          : compareFrameSequences(
              golden: golden.frames,
              actual: actual.frames,
              drift: drift,
              tolerance: tolerance,
            );
      final shots = images.compare(actual, tolerance);
      if (compared is ComparisonPassed && shots.isEmpty) {
        results.add(result(label, Outcome.passed, recording: actual));
        continue;
      }
      writeFailureReport(
        dir: dir,
        scenario: label,
        profile: j.profile,
        golden: golden,
        actual: actual,
        result: compared,
        snapshots: shots,
      );
      images.writeDiffs(actual, shots, Directory('${dir.path}/snapshots'));
      results.add(
        result(
          label,
          Outcome.failed,
          reason: compared is ComparisonPassed
              ? '${shots.length} of ${actual.snapshots.length} '
                    'snapshots differ, the video matches'
              : '$compared',
          detail: shots.join('\n'),
          step: switch (compared) {
            PixelMismatch r => r.step,
            TimingFailure r => r.step,
            ScreenMismatch r => r.step,
            ComparisonPassed() => null,
          },
          acceptable: true,
          recording: actual,
        ),
      );
    }
  }
  return results;
}

/// The live dashboard of this run, when it serves one.
// ponytail: one run per process, so a global beats threading it through
// every worker and output parser.
Dashboard? _dashboard;

/// A status line for the footer and the dashboard.
void _say(RunProgress progress, String profile, int worker, String text) {
  progress.status(text);
  _dashboard?.status(profile, worker, text);
}
