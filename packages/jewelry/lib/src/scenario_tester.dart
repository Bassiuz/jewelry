import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_actions.dart';
import 'frame_capture.dart';
import 'host_channel.dart';
import 'jewelry_binding.dart';
import 'on_screen.dart';
import 'target.dart';

/// The `t` handed to every step. Every pump is one engine frame on the
/// harness clock, and every frame is captured.
class ScenarioTester {
  ScenarioTester(
    this._tester,
    this._capture, {
    this._channel,
    this._ignoreErrors = const [],
  });

  final List<Pattern> _ignoreErrors;

  /// One frame at 60 Hz.
  static const frame = Duration(microseconds: 16667);

  final WidgetTester _tester;
  final FrameCapture _capture;

  /// The underlying tester, for widget lookups the actions do not cover.
  /// Pump through [pump] or [settle], never through this, or frames go
  /// uncaptured.
  WidgetTester get tester => _tester;
  final HostChannel? _channel;
  var _backgrounded = false;

  /// Whether the app is in the background (or behind the lock screen).
  bool get backgrounded => _backgrounded;

  /// Host-performed device actions. Only available on a device run.
  DeviceActions get device {
    final channel = _channel;
    if (channel == null) {
      throw StateError('t.device needs a device run under the jewelry CLI');
    }
    return DeviceActions(
      channel,
      (b) => _backgrounded = b,
      _capture.captureDevice,
    );
  }

  /// Waits in real time without pumping. The only way to let time pass while
  /// the app is in the background; app timers and alarms run meanwhile.
  ///
  /// While backgrounded on a device run, the device screen is recorded as
  /// device frames every [every], so the recording shows what the user
  /// sees meanwhile: the home screen, a heads-up notification, an alarm.
  Future<void> wait(
    Duration duration, {
    Duration every = const Duration(seconds: 1),
  }) async {
    final end = DateTime.now().add(duration);
    if (!_backgrounded || _channel == null) {
      if (duration > Duration.zero) await Future<void>.delayed(duration);
      return;
    }
    while (DateTime.now().isBefore(end)) {
      final next = DateTime.now().add(every);
      await _capture.captureDevice(await device.rawScreenshot());
      final left = next.difference(DateTime.now());
      final remaining = end.difference(DateTime.now());
      final pause = left < remaining ? left : remaining;
      if (pause > Duration.zero) await Future<void>.delayed(pause);
    }
  }

  /// Keeps the current screen up for [duration] of recording time, so a
  /// person watching the recording can see what happened. Pumps frames;
  /// in the background it records device frames instead.
  Future<void> hold([Duration duration = const Duration(seconds: 1)]) async {
    if (_backgrounded) return wait(duration);
    await pump(duration.inMicroseconds ~/ frame.inMicroseconds);
  }

  /// Settles, then records one frame named [name] as an image golden: the
  /// CLI writes it as `<name>.png` next to the video golden and compares it
  /// on its own. Use it for the screens a scenario is about.
  Future<void> snapshot(String name) async {
    if (_backgrounded) {
      throw StateError('snapshot("$name") needs the app in the foreground');
    }
    await settle();
    keepErrorsVisible();
    JewelryBinding.advance(frame);
    await _tester.pump(frame);
    await _capture.capture(snapshot: name);
  }

  /// Pumps [count] frames, capturing each.
  Future<void> pump([int count = 1]) async {
    if (_backgrounded) {
      throw StateError(
        'Cannot pump while the app is in the background; use t.wait',
      );
    }
    for (var i = 0; i < count; i++) {
      keepErrorsVisible();
      JewelryBinding.advance(frame);
      await _tester.pump(frame);
      await _capture.capture();
    }
  }

  FlutterExceptionHandler? _printing;

  /// Apps point `FlutterError.onError` at their crash reporter, sometimes
  /// again in the middle of a scenario (an app that rebuilds after a re-login). The test
  /// still fails on the error but prints nothing. Before every frame, wrap
  /// whatever handler is installed so the error is printed first.
  /// Called by the scenario runner before launch and before every frame.
  void keepErrorsVisible() {
    final current = FlutterError.onError;
    if (current == _printing) return;
    _printing = (details) {
      final text = details.exceptionAsString();
      if (_ignoreErrors.any(text.contains)) {
        debugPrint('jewelry: ignored flutter error: ${text.split('\n').first}');
        return;
      }
      debugPrint('jewelry: flutter error: $text\n${details.stack}');
      current?.call(details);
    };
    FlutterError.onError = _printing;
  }

  /// Pumps frames until nothing is scheduled any more, the frame stopped
  /// changing, or [maxFrames] (2 s) have passed.
  ///
  /// ponytail: on a live engine `hasScheduledFrame` can stay true (tickers,
  /// ink), so two byte-identical frames in a row also count as settled. A
  /// looping animation (a spinner in a button) never does either, so the cap
  /// is low and not an error; a delayed transition is waited for by the
  /// next action's [waitFor], which keeps pumping.
  Future<void> settle({int maxFrames = 120}) async {
    final start = _capture.frames.length;
    for (var i = 0; i < maxFrames; i++) {
      await pump();
      if (!_tester.binding.hasScheduledFrame) return;
      if (_capture.lastTwoFramesIdentical) return;
    }
    // Still changing after the cap: a spinner or other open-ended
    // animation, usually waiting on I/O. Not a stable sequence to compare.
    _capture.markWaitFrom(start);
  }

  /// Taps [target], first waiting for it to be on screen and hit-testable
  /// (a route still sliding in absorbs pointers).
  Future<void> tap(Object target) async {
    await waitFor(target);
    await _tester.tap(_onScreen(target));
    await settle();
  }

  /// Taps a point on screen, for controls without key or text that sit at
  /// the crossing of two labels (a checkbox in a "Ja" column).
  Future<void> tapAt(Offset position) async {
    await _tester.tapAt(position);
    await settle();
  }

  /// The centre of [target] on screen, after waiting for it.
  Future<Offset> centerOf(Object target) async {
    await waitFor(target);
    return _tester.getCenter(_onScreen(target).first);
  }

  Future<void> longPress(Object target) async {
    await waitFor(target);
    await _tester.longPress(_onScreen(target));
    await settle();
  }

  Future<void> enterText(Object target, String text) async {
    await waitFor(target);
    await _tester.enterText(_onScreen(target), text);
    await settle();
  }

  Future<void> drag(Object target, Offset offset) async {
    await _tester.drag(Target.of(target).finder, offset);
    await settle();
  }

  /// Drags [scrollable] by [delta] until [target] is on screen.
  Future<void> scrollUntilVisible(
    Object target, {
    required Object scrollable,
    Offset delta = const Offset(0, -200),
    int maxDrags = 50,
  }) async {
    final finder = _onScreen(target);
    for (var i = 0; i < maxDrags; i++) {
      if (_present(finder)) return;
      await drag(scrollable, delta);
    }
    throw TestFailure('${Target.of(target)} not visible after $maxDrags drags');
  }

  /// Pumps frames until [target] is on screen and hit-testable, so a widget
  /// behind a transition or a loading overlay does not count yet.
  Future<void> waitFor(
    Object target, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final finder = _onScreen(target);
    final maxFrames = timeout.inMicroseconds ~/ frame.inMicroseconds;
    final wasWaiting = _capture.waiting;
    _capture.waiting = true;
    try {
      for (var i = 0; i < maxFrames; i++) {
        if (_present(finder)) return;
        await pump();
      }
    } finally {
      _capture.waiting = wasWaiting;
    }
    throw TestFailure(
      '${Target.of(target)} did not appear within $timeout.\n'
      'On screen: ${visibleTexts().join(' | ')}',
    );
  }

  /// The texts currently on screen and hit-testable, in tree order. Printed
  /// when a [waitFor] times out, so a wrong string is found at a glance.
  List<String> visibleTexts() {
    final texts = <String>[];
    for (final e in OnScreenFinder(
      find.byWidgetPredicate((w) => w is Text || w is RichText),
    ).evaluate()) {
      final w = e.widget;
      final s = switch (w) {
        Text(:final data?) => data,
        Text(:final textSpan?) => textSpan.toPlainText(),
        RichText(:final text) => text.toPlainText(),
        _ => '',
      };
      if (s.trim().isNotEmpty && !texts.contains(s)) texts.add(s);
    }
    return texts;
  }

  /// Whether [finder] matches now. `.first` and `.at()` throw on an empty
  /// match instead of returning nothing; that counts as not there yet.
  static bool _present(Finder finder) {
    try {
      return finder.evaluate().isNotEmpty;
    } on StateError {
      return false;
    } on RangeError {
      return false;
    }
  }

  /// Only widgets that are on screen and hit-testable count, so a key reused
  /// on a hidden tab or behind an overlay does not make a finder ambiguous.
  Finder _onScreen(Object target) => OnScreenFinder(Target.of(target).finder);

  Future<void> expectVisible(Object target) async {
    expect(Target.of(target).finder, findsWidgets);
  }

  Future<void> expectText(String text) async {
    expect(find.text(text), findsWidgets);
  }
}
