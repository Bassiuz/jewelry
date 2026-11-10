import 'package:jewelry/jewelry.dart';
import 'package:jewelry_example/main.dart';

// A second scenario file, so `parallel: 2` has something for each emulator.
void main() {
  JewelryBinding.ensureInitialized();

  scenario(
    'Counter reaches three',
    launch: (ctx) => ctx.tester.pumpWidget(const MyApp()),
    steps: [
      step('Tap the button three times', (t) async {
        await t.tap('increment');
        await t.tap('increment');
        await t.tap('increment');
        await t.expectText('3');
        await t.snapshot('Counter at 3');
      }),
    ],
  );
}
