import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

const label = 'Counter increments on tap';

void main() {
  scenario(
    label,
    launch: (ctx) => ctx.tester.pumpWidget(const _Counter()),
    steps: [
      step('Tap the button', (t) async {
        await t.tap('inc');
        await t.expectText('xx');
      }),
      step('Wait for the label', (t) async {
        await t.waitFor(text('xx'));
        await t.expectVisible('count');
      }),
      step('Type into the labelled field', (t) async {
        await t.enterText(field('Naam'), 'Anna');
        await t.expectText('Anna');
      }),
    ],
  );

  test('every frame was captured and tagged with its step', () {
    final frames = capturedScenarios[label]!;
    expect(frames, isNotEmpty);
    expect(frames.first.step, 'launch');
    expect(frames.map((f) => f.step).toSet(), contains('Tap the button'));
    // PNG signature.
    expect(frames.first.png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // Logical size of the test view (800x600), not physical.
    final ihdr = ByteData.sublistView(frames.first.png, 16, 24);
    expect((ihdr.getUint32(0), ihdr.getUint32(4)), (800, 600));
    // The label grew from x to xx, so the last frame differs from the first.
    expect(frames.last.png, isNot(equals(frames.first.png)));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          // The test font draws every glyph as the same box, so change the
          // length, not the digit, to get a visible difference.
          Text('x' * (_count + 1), key: const ValueKey('count')),
          const TextField(decoration: InputDecoration(labelText: 'Naam')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('inc'),
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    ),
  );
}
