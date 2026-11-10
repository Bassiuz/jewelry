import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:jewelry/jewelry.dart';

import 'test_png.dart';

void main() {
  final home = pixel(255, 0, 0, step: 'launch');
  final sheet = pixel(0, 255, 0, step: 'open');
  final done = pixel(0, 0, 255, step: 'save');
  // Animation frames: every one a different picture.
  CapturedFrame mid(int n) => pixel(n, n, n, step: 'open');

  ComparisonResult compare(List<CapturedFrame> golden, List<CapturedFrame> actual) =>
      compareScreens(golden: golden, actual: actual, rest: 3);

  test('other hold lengths and other animation frames still pass', () {
    final result = compare(
      [...List.filled(5, home), mid(10), mid(20), ...List.filled(4, sheet), ...List.filled(3, done)],
      [...List.filled(9, home), mid(15), ...List.filled(3, sheet), mid(99), ...List.filled(20, done)],
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('a golden screen the run never shows fails, naming the step', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(4, sheet), ...List.filled(3, done)],
      [...List.filled(5, home), ...List.filled(3, done)],
    );
    expect(
      result,
      isA<ScreenMismatch>()
          .having((r) => r.missing, 'missing', true)
          .having((r) => r.step, 'step', 'open')
          .having((r) => r.goldenIndex, 'golden frame', 5),
    );
  });

  test('a screen only the run rests on fails', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(3, done)],
      [...List.filled(5, home), ...List.filled(4, sheet), ...List.filled(3, done)],
    );
    expect(
      result,
      isA<ScreenMismatch>()
          .having((r) => r.missing, 'missing', false)
          .having((r) => r.actualIndex, 'actual frame', 5),
    );
  });

  test('a rest in one run that is one frame in the other passes', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(4, sheet), ...List.filled(3, done)],
      [...List.filled(5, home), sheet, ...List.filled(3, done)],
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('the same screens in another order fail', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(4, sheet), ...List.filled(3, done)],
      [...List.filled(5, home), ...List.filled(3, done), ...List.filled(4, sheet)],
    );
    expect(result, isA<ScreenMismatch>());
  });

  test('a screen seen only while waiting does not have to be in the golden', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(3, done)],
      [
        ...List.filled(5, home),
        ...List.filled(4, sheet.asWait()),
        ...List.filled(3, done),
      ],
    );
    expect(result, isA<ComparisonPassed>());
  });

  test('a golden rest that the run shows while waiting passes', () {
    final result = compare(
      [...List.filled(5, home), ...List.filled(4, sheet), ...List.filled(3, done)],
      [...List.filled(5, home), sheet.asWait(), ...List.filled(3, done)],
    );
    expect(result, isA<ComparisonPassed>());
  });
}
