import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

void main() {
  scenario(
    'an ignored uncaught error does not fail the scenario',
    ignoreErrors: ['unavailable'],
    launch: (ctx) => ctx.tester.pumpWidget(const MaterialApp(home: Text('x'))),
    steps: [
      step('Throw from a future nobody awaits', (t) async {
        Future<void>.delayed(Duration.zero, () => throw StateError('functions unavailable'));
        await t.pump(5);
        await t.expectText('x');
      }),
    ],
  );

  scenario(
    'an ignored framework error (layout overflow) does not fail the scenario',
    ignoreErrors: ['A RenderFlex overflowed'],
    launch: (ctx) => ctx.tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 10,
            child: Row(children: [SizedBox(width: 100, height: 10)]),
          ),
        ),
      ),
    ),
    steps: [step('Pump the overflowing row', (t) => t.pump(2))],
  );
}
