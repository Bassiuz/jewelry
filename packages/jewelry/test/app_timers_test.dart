import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/app_timers.dart';
import 'package:jewelry/src/jewelry_binding.dart';

void main() {
  test('an app timer fires when the app clock reaches it, not before', () async {
    JewelryBinding.startAppClock();
    addTearDown(AppTimers.reset);
    var fired = false;
    runZoned(
      zoneSpecification: AppTimers.spec,
      () => Timer(const Duration(seconds: 5), () => fired = true),
    );
    JewelryBinding.now += const Duration(milliseconds: 4900);
    AppTimers.pumped();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fired, isFalse);

    JewelryBinding.now += const Duration(milliseconds: 200);
    AppTimers.pumped();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fired, isTrue);
  });

  test('timers from the harness and the scenario stay on wall time', () {
    StackTrace from(String uri) => StackTrace.fromString(
      '#0      Timer.new (dart:async/timer.dart:1:1)\n'
      '#1      AppTimers.spec (package:jewelry/src/app_timers.dart:2:3)\n'
      '#2      caller ($uri:12:3)\n',
    );
    expect(AppTimers.fromApp(from('package:my_app/promo.dart')), isTrue);
    expect(AppTimers.fromApp(from('package:flutter/src/widgets/scrollbar.dart')), isTrue);
    expect(AppTimers.fromApp(from('package:flutter_test/src/binding.dart')), isFalse);
    expect(AppTimers.fromApp(from('package:jewelry/src/scenario_tester.dart')), isFalse);
    expect(AppTimers.fromApp(from('package:flutter/src/gestures/long_press.dart')), isFalse);
    expect(AppTimers.fromApp(from('file:///app/integration_test/steps/a.dart')), isFalse);
  });
}
