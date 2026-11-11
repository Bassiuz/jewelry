import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
    b.platformDispatcher.onBeginFrame = (_) =>
        withClock(appClock, () => engineBeginFrame(now));
    b.platformDispatcher.onDrawFrame = () =>
        withClock(appClock, engineDrawFrame);
    return _binding = b;
  }

  /// Moves the clock; [ScenarioTester] calls this before every pump.
  ///
  /// ponytail: pumps still wait the real duration (the live binding uses a
  /// Timer), so a scenario runs at real-time pace. Timer and Future.delayed
  /// in the app also run on wall time. Only animation timestamps are
  /// harness-driven.
  static void advance(Duration d) => now += d;

  /// What `clock.now()` returns in the app during a scenario: the minute the
  /// scenario started (the CLI sets the device clock just before) plus the
  /// pumped time and the real time spent in `t.wait`. So a note saved 15 s
  /// into the recording says 09:00 however slow the login was that run.
  ///
  /// ponytail: only `package:clock` sees it; `DateTime.now()`, Firestore
  /// server timestamps and other isolates (notification actions) keep the
  /// device clock.
  static final appClock = Clock(
    () => _startMinute?.add(now - _nowAtStart + waited) ?? DateTime.now(),
  );
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
