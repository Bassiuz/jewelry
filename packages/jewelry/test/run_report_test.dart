import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';
// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';
import 'package:jewelry/src/accept.dart';
import 'package:jewelry/src/diff_png.dart';
import 'package:jewelry/src/html_report.dart';
import 'package:jewelry/src/report.dart';
import 'package:jewelry/src/run_log.dart';
import 'package:jewelry/src/run_progress.dart';
import 'package:jewelry/src/scenario_result.dart';

import 'test_png.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('jewelry_report'));
  tearDown(() => dir.deleteSync(recursive: true));

  ScenarioResult result(
    String label,
    Outcome outcome, {
    String reason = '',
    bool acceptable = false,
  }) => ScenarioResult(
    label: label,
    file: 'integration_test/scenarios/${label.toLowerCase()}_test.dart',
    profile: 'pixel',
    outcome: outcome,
    duration: const Duration(seconds: 75),
    ranAt: DateTime(2026, 11, 5, 14),
    reason: reason,
    acceptable: acceptable,
    frames: 3,
  );

  /// A failed comparison of "Login" as the CLI leaves it on disk.
  RunLog failedLogin() {
    final golden = ScenarioRecording([pixel(255, 0, 0), pixel(0, 255, 0)]);
    final actual = ScenarioRecording([
      pixel(255, 0, 0),
      CapturedFrame(step: 's', png: pixel(0, 0, 255).png, snapshot: 'Home'),
    ]);
    Directory('${dir.path}/goldens/login').createSync(recursive: true);
    golden.write('${dir.path}/goldens/login/pixel');
    final failed = result('Login', Outcome.failed, reason: 'Pixel mismatch', acceptable: true);
    writeFailureReport(
      dir: Directory('${dir.path}/${failed.failureDir}'),
      scenario: 'Login',
      profile: 'pixel',
      golden: golden,
      actual: actual,
      result: compareFrameSequences(golden: golden.frames, actual: actual.frames),
    );
    return RunLog(dir, [failed, result('Diary', Outcome.passed)])..save();
  }

  test('the diff image marks a changed pixel red and leaves noise alone', () {
    final grey = pixel(100, 100, 100).png;
    expect(decodePngToRgba(diffPng(grey, pixel(102, 100, 100).png)), [100, 100, 100, 77]);
    expect(decodePngToRgba(diffPng(grey, pixel(110, 100, 100).png)), [255, 0, 0, 255]);
  });

  test('the log survives a round trip and a rerun replaces only its file', () {
    failedLogin();
    final log = RunLog.load(dir);
    expect(log.results.map((r) => r.label), ['Login', 'Diary']);
    expect(log.results.first.acceptable, isTrue);
    expect(
      log.lastDuration(log.results.first.file, 'pixel'),
      const Duration(seconds: 75),
    );

    log.replace(log.results.first.file, 'pixel', [result('Login', Outcome.passed)]);
    expect(log.results.map((r) => r.outcome), [Outcome.passed, Outcome.passed]);
  });

  test('the HTML report shows the failing frames of a failure', () {
    final log = failedLogin();
    writeHtmlReport(log, dart: 'dart');
    final html = File('${dir.path}/report.html').readAsStringSync();

    expect(html, contains('1 failed'));
    expect(html, contains('Pixel mismatch'));
    for (final image in ['expected_frame.png', 'actual_frame.png', 'diff.png']) {
      expect(html, contains('failures/login/pixel/$image'));
      expect(File('${dir.path}/failures/login/pixel/$image').existsSync(), isTrue);
    }
    expect(html, contains('dart run jewelry accept "Login"'));
    expect(html, contains('goldens/diary/pixel.apng'));
  });

  test('accept makes the failed recording the golden without a run', () {
    final log = failedLogin();
    final (:accepted, :refused) = acceptLastRun(log);

    expect(accepted.map((r) => r.label), ['Login']);
    expect(refused, isEmpty);
    final golden = ScenarioRecording.read('${dir.path}/goldens/login/pixel');
    expect(golden.frames.last.png, pixel(0, 0, 255).png);
    expect(File('${dir.path}/goldens/login/pixel/home.png').existsSync(), isTrue);
    expect(Directory('${dir.path}/failures/login/pixel').existsSync(), isFalse);
    expect(RunLog.load(dir).results.first.outcome, Outcome.accepted);
  });

  test('accept refuses a run that stopped in a step', () {
    final log = RunLog(dir, [result('Login', Outcome.failed, reason: 'Step "x" failed')]);
    final (:accepted, :refused) = acceptLastRun(log);

    expect(accepted, isEmpty);
    expect(refused.single.label, 'Login');
  });

  test('piped output names the scenario, the step and the failure', () {
    final out = StringBuffer();
    final progress = RunProgress(total: 2, sink: out, live: false)
      ..start('login_test.dart')
      ..step('Log in as Anna');
    final results = [result('Login', Outcome.failed, reason: 'Pixel mismatch')];
    progress
      ..finish(results)
      ..close()
      ..summary(results, dart: 'fvm dart');

    final text = out.toString();
    expect(text, contains('== [1/2] login_test.dart'));
    expect(text, contains('step: Log in as Anna'));
    expect(text, contains('✗ Login  01:15  Pixel mismatch'));
    expect(text, contains('0 passed, 1 failed, Total: 1'));
    expect(text, contains('fvm dart run jewelry run integration_test/scenarios/login_test.dart'));
    expect(text, contains('fvm dart run jewelry run --failed'));
  });

  test('with two emulators the footer has a line for each', () {
    final out = StringBuffer();
    RunProgress(total: 4, workers: 2, sink: out, live: true, columns: 100)
      ..start('login_test.dart')
      ..start('diary_test.dart', worker: 1)
      ..step('Write a note', worker: 1)
      ..close();

    expect(
      out.toString(),
      contains(
        '▶ [1] login_test.dart · 00:00\n'
        '▶ [2] diary_test.dart · 00:00 · Write a note',
      ),
    );
  });

  test('the footer on a terminal shows progress, counts and the step', () {
    final out = StringBuffer();
    final progress = RunProgress(
      total: 4,
      sink: out,
      live: true,
      columns: 100,
      estimate: const Duration(minutes: 90),
    )
      ..start('login_test.dart')
      ..step('Log in as Anna')
      ..close();

    expect(out.toString(), contains('0/4 · 0 passed · 0 failed · 00:00 / ~1:30:00'));
    expect(out.toString(), contains('▶ login_test.dart · 00:00 · Log in as Anna'));
    expect(progress.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
