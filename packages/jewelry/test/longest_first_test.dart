import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/run_log.dart';
import 'package:jewelry/src/scenario_result.dart';

void main() {
  test('the queue starts with files never run, then the slowest', () {
    ScenarioResult took(String file, int seconds) => ScenarioResult(
      label: file,
      file: file,
      profile: 'pixel',
      outcome: Outcome.passed,
      duration: Duration(seconds: seconds),
      ranAt: DateTime(2026, 11, 11),
      frames: 1,
    );
    final log = RunLog(Directory.systemTemp, [
      took('diary.dart', 60),
      took('subscribe.dart', 300),
      took('alarm.dart', 120),
    ]);
    expect(
      log.longestFirst(['alarm.dart', 'diary.dart', 'new.dart', 'subscribe.dart'], 'pixel'),
      ['new.dart', 'subscribe.dart', 'alarm.dart', 'diary.dart'],
    );
  });
}
