import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

const label = 'every step ends with a pause, snapshots are tagged';

void main() {
  scenario(
    label,
    pauseAfterStep: const Duration(milliseconds: 500),
    launch: (ctx) => ctx.tester.pumpWidget(const MaterialApp(home: Text('x'))),
    steps: [
      step('Snapshot the screen', (t) => t.snapshot('Start screen')),
      step('Hold a second', (t) => t.hold()),
    ],
  );

  test('the pause and the hold are in the recording', () {
    final frames = capturedScenarios[label]!;
    int count(String step) => frames.where((f) => f.step == step).length;
    // 500 ms pause = 29 frames at 60 Hz (16.667 ms each, rounded down).
    expect(count('Hold a second'), 59 + 29);
    expect(frames.where((f) => f.snapshot == 'Start screen'), hasLength(1));
  });
}
