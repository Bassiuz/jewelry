import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_timers.dart';

/// Puts the integration test binding on a harness-driven clock.
///
/// The stock live binding renders only on pump but stamps frames with real
/// time, so animations would advance by wall time. `flutter test` on a
/// device creates the binding before `main` runs, so it cannot be
/// subclassed; instead the engine's begin-frame callback is wrapped and
/// every frame is stamped with [now], which [advance] moves by exactly the
/// pumped duration. A 300 ms animation is always the same frames.
class JewelryBinding {
  JewelryBinding._();

  static IntegrationTestWidgetsFlutterBinding? _binding;

  /// True on a device run; false in plain widget tests.
  static bool get isActive => _binding != null;

  /// The harness clock: total pumped time since start.
  static Duration now = Duration.zero;

  /// Call first in `main` of every scenario file.
  static IntegrationTestWidgetsFlutterBinding ensureInitialized() {
    if (_binding != null) return _binding!;
    final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    b.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    // Registered lazily on the first scheduled frame; force it so there is
    // a callback to wrap.
    // ignore: invalid_use_of_protected_member
    b.ensureFrameCallbacksRegistered();
    final engineBeginFrame = b.platformDispatcher.onBeginFrame!;
    final engineDrawFrame = b.platformDispatcher.onDrawFrame!;
    // Builds and layout read [appClock] too, not only the test's own code.
    // So are timers a build or a frame callback makes (see AppTimers).
    Zone frameZone() => timersOnAppClock ? AppTimers.frameZone : Zone.root;
    b.platformDispatcher.onBeginFrame = (_) =>
        frameZone().run(() => withClock(appClock, () => engineBeginFrame(now)));
    b.platformDispatcher.onDrawFrame = () =>
        frameZone().run(() => withClock(appClock, engineDrawFrame));
    return _binding = b;
  }

  /// Moves the clock; [ScenarioTester] calls this before every pump.
  ///
  /// ponytail: pumps still wait the real duration (the live binding uses a
  /// Timer), so a scenario runs at real-time pace. The app's own timers run
  /// on [appClock] during a scenario ([AppTimers]).
  static void advance(Duration d) {
    now += d;
    if (timersOnAppClock) AppTimers.pumped();
  }

  /// True while a scenario runs on a device: the app's timers follow
  /// [appClock].
  static bool timersOnAppClock = false;

  /// What `clock.now()` returns in the app during a scenario: the minute the
  /// scenario started (the CLI sets the device clock just before) plus the
  /// pumped time and the real time spent in `t.wait`. So a note saved 15 s
  /// into the recording says 09:00 however slow the login was that run.
  ///
  /// ponytail: only `package:clock` sees it; `DateTime.now()`, Firestore
  /// server timestamps and other isolates (notification actions) keep the
  /// device clock.
  static final appClock = Clock(
    () =>
        _startMinute?.add(
          now -
              _nowAtStart +
              waited +
              (waitingSince == null
                  ? Duration.zero
                  : DateTime.now().difference(waitingSince!)),
        ) ??
        DateTime.now(),
  );

  /// When the `t.wait` in progress started; its time counts as it passes.
  static DateTime? waitingSince;
  static DateTime? _startMinute;
  static Duration _nowAtStart = Duration.zero;

  /// Real time spent waiting, which [appClock] counts as passed.
  static Duration waited = Duration.zero;

  /// Starts [appClock] at the current device minute.
  static void startAppClock() {
    final n = DateTime.now();
    _startMinute = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    _nowAtStart = now;
    waited = Duration.zero;
  }
}
