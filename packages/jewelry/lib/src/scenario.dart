import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show ViewPadding;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_timers.dart';
import 'captured_frame.dart';
import 'frame_capture.dart';
import 'host_channel.dart';
import 'jewelry_binding.dart';
import 'scenario_context.dart';
import 'scenario_recording.dart';
import 'scenario_tester.dart';
import 'slug.dart';
import 'step.dart';

/// Seeds state before the app launches.
typedef Given = FutureOr<void> Function(ScenarioContext ctx);

/// The app's own bootstrap, with fakes injected. It pumps the root widget.
typedef Launch = Future<void> Function(ScenarioContext ctx);

/// Frames of every scenario that ran in this process, by label.
final capturedScenarios = <String, List<CapturedFrame>>{};

/// Registers a scenario as a widget test and runs it with frame capture.
///
/// [ignoreErrors] lists substrings of errors the scenario tolerates: uncaught
/// async errors (`'firebase_functions/unavailable'` when Cloud Functions do
/// not run) and framework errors (a known layout overflow). They are still
/// printed.
///
/// [pauseAfterStep] is recorded after every step so a person can follow
/// the recording; `Duration.zero` turns it off.
void scenario(
  String label, {
  Given? given,
  required Launch launch,
  required List<Step> steps,
  List<Pattern> ignoreErrors = const [],
  List<Object> ignore = const [],
  Duration pauseAfterStep = const Duration(seconds: 1),
}) {
  testWidgets(label, (tester) {
    JewelryBinding.startAppClock();
    // On a device the app's timers follow the app clock too (AppTimers).
    final timers = JewelryBinding.isActive;
    JewelryBinding.timersOnAppClock = timers;
    addTearDown(() {
      JewelryBinding.timersOnAppClock = false;
      AppTimers.reset();
    });
    return runZoned(
      zoneSpecification: timers ? AppTimers.spec : null,
      () => withClock(
        JewelryBinding.appClock,
        () => _guarded(label, ignoreErrors, () async {
          // Started from the launcher, the test can begin before Android has
          // given the app a surface; there is nothing to capture until it has.
          while (JewelryBinding.isActive && tester.view.physicalSize.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          if (JewelryBinding.isActive && Platform.isAndroid) {
            _pinTopInset(tester);
          }
          final ctx = ScenarioContext(tester);
          await given?.call(ctx);

          // The cursor blinks on a wall-clock timer; keep it solid.
          EditableText.debugDeterministicCursor = true;
          addTearDown(() => EditableText.debugDeterministicCursor = false);
          // Typing goes straight to the fields instead of through the platform
          // keyboard, which slides in and resizes the app on the system clock.
          if (!tester.testTextInput.isRegistered) {
            tester.testTextInput.register();
            addTearDown(tester.testTextInput.unregister);
          }
          final capture = FrameCapture(tester);
          // Left out of every comparison in this scenario (see t.ignore); the
          // context's list, so ctx.ignore in launch counts too.
          for (final i in ignore) {
            ctx.ignore(i);
          }
          capture.ignoreAlways = ctx.ignored;
          final channel = JewelryBinding.isActive
              ? await HostChannel.open(label)
              : null;
          final t = ScenarioTester(
            tester,
            capture,
            channel: channel,
            ignoreErrors: ignoreErrors,
          );

          t.keepErrorsVisible();
          capture.currentStep = 'launch';
          // App start depends on I/O (Firebase, network); its frames are shown,
          // not compared.
          capture.waiting = true;
          await launch(ctx);
          await capture.capture();
          await t.settle();
          capture.waiting = false;

          try {
            // The whole plan up front, for the live dashboard.
            debugPrint(
              'jewelry: steps\t$label\t'
              '${jsonEncode([for (final s in steps) s.label])}',
            );
            for (final s in steps) {
              capture.currentStep = s.label;
              // Lands in the flutter test output and the device log, so a run that
              // dies mid-scenario shows which step it was in.
              debugPrint('jewelry: step "${s.label}"');
              try {
                await s.run(t);
                // Leaves each step's result on screen in the recording; the last
                // one is the scenario's final screen.
                await t.hold(pauseAfterStep);
                capture.ignoreThisStep.clear();
              } catch (e, stack) {
                // Printed here because the app may have pointed FlutterError.onError
                // at its crash reporter, which then swallows the test's own report.
                debugPrint('jewelry: step "${s.label}" failed: $e\n$stack');
                rethrow;
              }
            }
          } finally {
            // Written even when a step failed: the CLI keeps a failed run's frames
            // under .jewelry/failures as actual.apng, which shows where it got.
            capturedScenarios[label] = capture.frames;
            if (JewelryBinding.isActive) {
              // ponytail: whole recording held in memory, then one APNG in the
              // app's temp dir. Stream frames to disk if long scenarios run out of
              // RAM.
              final dir = Directory('${Directory.systemTemp.path}/jewelry')
                ..createSync(recursive: true);
              final base = '${dir.path}/${slug(label)}';
              final writing = Stopwatch()..start();
              ScenarioRecording(capture.frames).write(base);
              debugPrint(
                'jewelry: timing ${capture.timing}, '
                'writing ${writing.elapsed.inSeconds} s',
              );
              // ignore: avoid_print
              print('${ScenarioRecording.marker}\t$label\t$base');
              await channel!.close();
            }
          }
          // The scenario is complete once the last step ran; the recording holds
          // every frame. flutter_test then unmounts the whole app, which production
          // never does, and errors raised there (double disposes, for instance)
          // would fail the scenario and lose the recording. Log them instead.
          FlutterError.onError = (details) => debugPrint(
            'jewelry: error after the last step, ignored: '
            '${details.exceptionAsString()}',
          );
        }),
      ),
    );
  });
}

/// Runs a scenario body in its own error zone, so an uncaught async error
/// from the app (a future nobody awaits) is printed and fails the scenario
/// even when the app has pointed `FlutterError.onError` at its crash
/// reporter. Errors containing one of [ignore] are printed and ignored:
/// for what the test environment does not provide, such as Cloud
/// Functions. Errors after the body finished are printed only.
Future<void> _guarded(
  String label,
  List<Pattern> ignore,
  Future<void> Function() body,
) {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
        if (!done.isCompleted) done.complete();
      } catch (e, stack) {
        if (!done.isCompleted) done.completeError(e, stack);
      }
    },
    (e, stack) {
      final text = '$e';
      if (ignore.any(text.contains)) {
        debugPrint('jewelry: ignored uncaught error: $text');
        return;
      }
      if (done.isCompleted) {
        debugPrint('jewelry: uncaught error after "$label" finished: $text');
        return;
      }
      debugPrint('jewelry: uncaught error in "$label": $text\n$stack');
      done.completeError(e, stack);
    },
  );
  return done.future;
}

/// Emulators of one AVD do not agree on the top inset: some add the camera
/// cutout to the status bar (151 px on a Pixel 8 Pro), some do not (72 px),
/// and a golden recorded on one then never matches a run on the other.
/// The app gets the plain status bar, 24 dp, on every emulator.
// ponytail: 24 dp is Android's status bar; a profile setting if a device
// ever needs another.
void _pinTopInset(WidgetTester tester) {
  final view = tester.view;
  final top = 24 * view.devicePixelRatio;
  FakeViewPadding pinned(ViewPadding p) =>
      FakeViewPadding(left: p.left, top: top, right: p.right, bottom: p.bottom);
  view.padding = pinned(view.padding);
  view.viewPadding = pinned(view.viewPadding);
}
