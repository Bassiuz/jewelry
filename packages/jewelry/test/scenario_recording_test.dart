import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/captured_frame.dart';
import 'package:jewelry/src/scenario_recording.dart';

import 'test_png.dart';

void main() {
  test('APNG plus steps sidecar round-trips frames and step tags', () {
    final original = ScenarioRecording([
      pixel(255, 0, 0, step: 'launch'),
      pixel(255, 0, 0, step: 'launch'),
      pixel(0, 255, 0, step: 'tap'),
    ]);
    final back = ScenarioRecording.decode(
      original.toApng(),
      original.toStepsJson(),
    );
    expect(back.frames.map((f) => f.step), ['launch', 'launch', 'tap']);
    expect(back.frames[2].png, original.frames[2].png);
    expect(
      original.toStepsJson(),
      '[{"step":"launch","frames":2},{"step":"tap","frames":1}]',
    );
  });

  test('device frames keep their flag through the sidecar', () {
    final frames = [
      pixel(1, 2, 3, step: 'a'),
      CapturedFrame(step: 'a', png: pixel(4, 5, 6).png, device: true),
      pixel(7, 8, 9, step: 'a'),
    ];
    final recording = ScenarioRecording(frames);
    final back = ScenarioRecording.decode(
      recording.toApng(),
      recording.toStepsJson(),
    );
    expect([for (final f in back.frames) f.device], [false, true, false]);
  });
}
