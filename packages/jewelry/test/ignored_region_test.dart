import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/captured_frame.dart';
import 'package:jewelry/src/compare.dart';
import 'package:jewelry/src/ignored_region.dart';
import 'package:jewelry/src/scenario_recording.dart';

import 'test_png.dart';

CapturedFrame withRegion(CapturedFrame f, List<IgnoredRegion> r, {String step = 's'}) =>
    CapturedFrame(step: step, png: f.png, ignored: r);

void main() {
  const all = IgnoredRegion(0, 0, 1, 1);

  test('pixels inside an ignored region do not count', () {
    final red = withRegion(pixel(255, 0, 0), [all]);
    final green = withRegion(pixel(0, 255, 0), [all]);
    expect(rgbaMatches(frameRgba(red), frameRgba(green), 0), isTrue);
    expect(
      rgbaMatches(frameRgba(pixel(255, 0, 0)), frameRgba(pixel(0, 255, 0)), 0),
      isFalse,
    );
  });

  test('ignored regions survive the steps file', () {
    final rec = ScenarioRecording([
      withRegion(pixel(1, 1, 1), [const IgnoredRegion(1, 2, 3, 4, mustAnimate: true)]),
      pixel(2, 2, 2),
    ]);
    final back = ScenarioRecording.decode(rec.toApng(), rec.toStepsJson());
    expect(back.frames.first.ignored, [
      const IgnoredRegion(1, 2, 3, 4, mustAnimate: true),
    ]);
    expect(back.frames.last.ignored, isEmpty);
  });

  test('a must-animate region that never changes is reported', () {
    const moving = IgnoredRegion(0, 0, 1, 1, mustAnimate: true);
    final still = ScenarioRecording([
      for (var i = 0; i < 3; i++) withRegion(pixel(9, 9, 9), [moving], step: 'Spin'),
    ]);
    expect(stillAnimations(still).single.step, 'Spin');
    final animated = ScenarioRecording([
      withRegion(pixel(9, 9, 9), [moving], step: 'Spin'),
      withRegion(pixel(90, 9, 9), [moving], step: 'Spin'),
    ]);
    expect(stillAnimations(animated), isEmpty);
  });
}
