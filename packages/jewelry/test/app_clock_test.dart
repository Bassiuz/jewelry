import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/jewelry_binding.dart';

void main() {
  test('the app clock starts at the minute and moves with harness time and waits', () {
    final before = DateTime.now();
    JewelryBinding.startAppClock();
    final start = JewelryBinding.appClock.now();
    expect(start.second, 0);
    expect(start.millisecond, 0);
    expect(before.difference(start) < const Duration(minutes: 1), isTrue);

    JewelryBinding.advance(const Duration(seconds: 15));
    JewelryBinding.waited += const Duration(minutes: 2);
    expect(
      JewelryBinding.appClock.now(),
      start.add(const Duration(minutes: 2, seconds: 15)),
    );
  });
}
