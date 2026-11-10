import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/on_screen.dart';

void main() {
  testWidgets('a label under IgnorePointer in a tappable row counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // A translucent handler over an IgnorePointer.
        home: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {},
          child: const IgnorePointer(child: Center(child: Text('Wekker-instellingen'))),
        ),
      ),
    );
    expect(find.text('Wekker-instellingen').hitTestable(), findsNothing);
    expect(OnScreenFinder(find.text('Wekker-instellingen')), findsOneWidget);
  });

  testWidgets('a label on a hidden IndexedStack child does not', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IndexedStack(
          children: [
            Center(child: Text('shown')),
            Center(child: Text('hidden')),
          ],
        ),
      ),
    );
    expect(OnScreenFinder(find.text('shown')), findsOneWidget);
    expect(OnScreenFinder(find.text('hidden')), findsNothing);
  });

  testWidgets('a label behind a dialog barrier does not', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('in dialog')),
              ),
              child: const Text('behind'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('behind'));
    await tester.pumpAndSettle();
    expect(OnScreenFinder(find.text('in dialog')), findsOneWidget);
    expect(OnScreenFinder(find.text('behind')), findsNothing);
  });

  testWidgets('a label under an absorbing AbsorbPointer does not', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AbsorbPointer(child: Center(child: Text('Inloggen'))),
      ),
    );
    expect(OnScreenFinder(find.text('Inloggen')), findsNothing);
  });
}
