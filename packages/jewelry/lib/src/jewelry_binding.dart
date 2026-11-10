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
    b.platformDispatcher.onBeginFrame = (_) => engineBeginFrame(now);
    return _binding = b;
  }

  /// Moves the clock; [ScenarioTester] calls this before every pump.
  ///
  /// ponytail: pumps still wait the real duration (the live binding uses a
  /// Timer), so a scenario runs at real-time pace. Timer and Future.delayed
  /// in the app also run on wall time. Only animation timestamps are
  /// harness-driven.
  static void advance(Duration d) => now += d;
}
