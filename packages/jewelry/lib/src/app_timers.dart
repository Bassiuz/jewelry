import 'dart:async';

import 'jewelry_binding.dart';

/// Runs the app's `Timer`s and `Future.delayed`s on recording time
/// ([JewelryBinding.appClock]) instead of wall time, so a popup that shows
/// 5 s after login lands on the same frame every run, however slow the run.
///
/// Only timers the app makes are moved: one whose caller is
/// `flutter_test`, `integration_test`, jewelry, a gesture recognizer or the
/// scenario's own code (under `integration_test/`) stays on wall time, so
/// pumps, waits and long presses work as before.
///
/// ponytail: the caller is read from the stack trace at creation, about
/// tens of microseconds per timer. When the test does not pump for a second
/// (awaiting something outside the app), due timers fire on wall time
/// instead, so app code that needs a timer to finish cannot hang the test.
class AppTimers {
  AppTimers._();

  static final _pending = <_AppTimer>[];
  static DateTime _lastPump = DateTime.now();

  /// The zone rules; a scenario and every frame run under them.
  static final spec = ZoneSpecification(
    createTimer: (self, parent, zone, duration, f) =>
        duration <= Duration.zero || !fromApp(StackTrace.current)
        ? parent.createTimer(zone, duration, f)
        : _AppTimer(parent, zone, duration, () => f()),
    createPeriodicTimer: (self, parent, zone, period, f) {
      if (period <= Duration.zero || !fromApp(StackTrace.current)) {
        return parent.createPeriodicTimer(zone, period, f);
      }
      late final _AppTimer t;
      return t = _AppTimer(parent, zone, period, () => f(t), periodic: true);
    },
  );

  /// Frames run outside the scenario's zone; this one gives them the rules.
  static final frameZone = Zone.root.fork(specification: spec);

  /// The harness pumped a frame: fire what is due on the app clock.
  static void pumped() {
    _lastPump = DateTime.now();
    fireDue();
  }

  /// Fires every timer whose time on the app clock has come.
  static void fireDue() {
    final now = JewelryBinding.appClock.now();
    for (final t in List.of(_pending)) {
      if (!t.due.isAfter(now)) t._fire();
    }
  }

  /// Drops what a finished scenario left pending.
  static void reset() {
    for (final t in List.of(_pending)) {
      t.cancel();
    }
  }

  static final _frame = RegExp(r'\(([^)\s]+?)(?::\d+)*\)$');
  static const _harness = [
    'package:flutter_test/',
    'package:integration_test/',
    'package:jewelry/',
    'package:jewelry_firebase/',
    'package:test_api/',
    'package:matcher/',
    'package:flutter/src/gestures/',
  ];

  /// Whether the code that asked for a timer in [stack] is the app's: the
  /// first frame outside `dart:` that is not in [AppTimers] itself.
  static bool fromApp(StackTrace stack) {
    for (final line in '$stack'.split('\n')) {
      final uri = _frame.firstMatch(line.trim())?.group(1);
      if (uri == null || uri.startsWith('dart:')) continue;
      if (uri.endsWith('app_timers.dart')) continue;
      return !_harness.any(uri.startsWith) &&
          !uri.contains('/integration_test/');
    }
    return false;
  }
}

class _AppTimer implements Timer {
  _AppTimer(
    this._parent,
    this._zone,
    this._duration,
    this._callback, {
    this.periodic = false,
  }) : due = JewelryBinding.appClock.now().add(_duration) {
    AppTimers._pending.add(this);
    _armFallback(_duration);
  }

  final ZoneDelegate _parent;
  final Zone _zone;
  final Duration _duration;
  final void Function() _callback;
  final bool periodic;
  DateTime due;
  Timer? _fallback;
  var _tick = 0;
  var _active = true;

  // Wall time as a backstop, for when nothing pumps (see AppTimers).
  void _armFallback(Duration after) {
    _fallback?.cancel();
    _fallback = _parent.createTimer(_zone, after, () {
      final idle = DateTime.now().difference(AppTimers._lastPump);
      if (idle > const Duration(seconds: 1)) {
        _fire();
      } else {
        _armFallback(const Duration(milliseconds: 500));
      }
    });
  }

  void _fire() {
    if (!_active) return;
    _tick++;
    if (periodic) {
      due = due.add(_duration);
      _armFallback(_duration);
    } else {
      _active = false;
      _fallback?.cancel();
      AppTimers._pending.remove(this);
    }
    // Asynchronously, like a real timer, in the zone that made it.
    _parent.createTimer(_zone, Duration.zero, _callback);
  }

  @override
  void cancel() {
    _active = false;
    _fallback?.cancel();
    AppTimers._pending.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
