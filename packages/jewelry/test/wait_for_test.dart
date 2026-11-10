import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

const label = 'waitFor survives a .first on an empty match';

void main() {
  scenario(
    label,
    launch: (ctx) => ctx.tester.pumpWidget(const MaterialApp(home: _Late())),
    steps: [
      step('Wait for a widget that appears later, via .first', (t) async {
        await t.waitFor(find.text('ready').first, timeout: const Duration(seconds: 2));
        await t.expectText('ready');
      }),
    ],
  );
}

class _Late extends StatefulWidget {
  const _Late();

  @override
  State<_Late> createState() => _LateState();
}

class _LateState extends State<_Late> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Center(child: Text(_c.isCompleted ? 'ready' : 'loading')),
  );
}
