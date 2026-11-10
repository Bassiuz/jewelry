import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/captured_frame.dart';
import 'package:jewelry/src/scenario_recording.dart';
import 'package:jewelry/src/snapshots.dart';

import 'test_png.dart';

void main() {
  CapturedFrame shot(String name, int r) =>
      CapturedFrame(step: 's', png: pixel(r, 0, 0).png, snapshot: name);

  test('snapshot names survive the steps sidecar', () {
    final recording = ScenarioRecording([pixel(1, 1, 1), shot('Schema', 2), pixel(3, 3, 3)]);
    final back = ScenarioRecording.decode(recording.toApng(), recording.toStepsJson());
    expect(back.snapshots.keys, ['Schema']);
    expect(back.frames.map((f) => f.snapshot), [null, 'Schema', null]);
  });

  test('recorded snapshots compare clean, a changed one does not', () {
    final dir = Directory.systemTemp.createTempSync('jewelry_snapshots');
    addTearDown(() => dir.deleteSync(recursive: true));
    final goldens = SnapshotGoldens(Directory('${dir.path}/p'));
    goldens.record(ScenarioRecording([shot('Taken on Schema', 10)]));
    expect(File('${dir.path}/p/taken_on_schema.png').existsSync(), isTrue);

    expect(goldens.compare(ScenarioRecording([shot('Taken on Schema', 10)]), 0), isEmpty);

    final changed = goldens.compare(ScenarioRecording([shot('Taken on Schema', 99)]), 0);
    expect(changed.single.reason, contains('differ'));

    final renamed = goldens.compare(ScenarioRecording([shot('Other', 10)]), 0);
    expect(renamed.map((m) => m.reason), [
      contains('no image golden'),
      contains('took no such snapshot'),
    ]);
  });
}
