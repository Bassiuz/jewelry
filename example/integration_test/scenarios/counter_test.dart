import 'package:jewelry/jewelry.dart';
import 'package:jewelry_example/main.dart';

void main() {
  JewelryBinding.ensureInitialized();

  scenario(
    'Counter increments on tap',
    launch: (ctx) => ctx.tester.pumpWidget(const MyApp()),
    steps: [
      step('Tap the button twice', (t) async {
        await t.tap('increment');
        await t.tap('increment');
        await t.expectText('2');
        await t.snapshot('Counter at 2');
      }),
    ],
  );
}
