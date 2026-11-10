import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

import 'test_png.dart';

void main() {
  final red = pixel(255, 0, 0, step: 'launch');
  final green = pixel(0, 255, 0, step: 'tap');
  final blue = pixel(0, 0, 255, step: 'done');

  test('identical sequences pass with no drift', () {
    final frames = [red, red, green, blue];
    final result = compareFrameSequences(golden: frames, actual: frames);
    expect(
      result,
      isA<ComparisonPassed>().having((r) => r.maxDrift, 'drift', 0),
    );
  });

  test('a frame arriving late within the window passes and reports drift', () {
    final result = compareFrameSequences(
      golden: [red, green, blue],
      actual: [red, red, red, green, blue],
      drift: 2,
    );
    expect(
      result,
      isA<ComparisonPassed>().having((r) => r.maxDrift, 'drift', 2),
    );
  });

  test('a frame later than the window is a timing failure naming the step', () {
    final result = compareFrameSequences(
      golden: [red, green, blue],
      actual: [red, red, red, red, green, blue],
      drift: 2,
    );
    expect(
      result,
      isA<TimingFailure>()
          .having((r) => r.step, 'step', 'tap')
          .having((r) => r.goldenIndex, 'golden', 1)
          .having((r) => r.drift, 'drift', 3),
    );
  });

  test('a frame that never appears is a pixel mismatch at the cursor', () {
    final result = compareFrameSequences(
      golden: [red, green, blue],
      actual: [red, blue, blue],
    );
    expect(
      result,
      isA<PixelMismatch>()
          .having((r) => r.step, 'step', 'tap')
          .having((r) => r.actualIndex, 'actual', 1)
          .having((r) => r.diffPercent, 'diff', 100),
    );
  });

  test('extra trailing frames beyond the window are a timing failure', () {
    final result = compareFrameSequences(
      golden: [red, green],
      actual: [red, green, blue, blue, blue],
      drift: 2,
    );
    expect(result, isA<TimingFailure>().having((r) => r.step, 'step', 'done'));
  });

  test('tolerance lets a small difference through', () {
    final result = compareFrameSequences(
      golden: [red],
      actual: [pixel(254, 0, 0)],
      tolerance: 100,
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('device frames are shown but never compared', () {
    CapturedFrame device(CapturedFrame f) =>
        CapturedFrame(step: f.step, png: f.png, device: true);
    final result = compareFrameSequences(
      golden: [red, device(blue), green],
      actual: [red, device(red), device(green), green],
      drift: 0,
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('wait frames of different length on each side are not compared', () {
    CapturedFrame wait(CapturedFrame f) => f.asWait();
    final spinner = pixel(9, 9, 9, step: 'tap');
    final result = compareFrameSequences(
      golden: [red, wait(spinner), wait(blue), green],
      actual: [red, for (var i = 0; i < 40; i++) wait(spinner), green],
      drift: 0,
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('drift is measured from the previous match, not from the start', () {
    // Two separate 2-frame delays: each within drift 2, 4 frames in total.
    final result = compareFrameSequences(
      golden: [red, green, blue],
      actual: [red, red, red, green, green, green, blue],
      drift: 2,
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('a channel off by one or two is noise, by three is a change', () {
    final result = compareFrameSequences(
      golden: [pixel(100, 100, 100)],
      actual: [pixel(102, 99, 100)],
      drift: 0,
    );
    expect(result, isA<ComparisonPassed>());
    expect(
      compareFrameSequences(golden: [pixel(100, 100, 100)], actual: [pixel(103, 100, 100)], drift: 0),
      isA<PixelMismatch>(),
    );
  });
}
