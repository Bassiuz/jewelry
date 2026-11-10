import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

import 'captured_frame.dart';
import 'compare.dart';
import 'comparison_result.dart';

/// Timing-tolerant matching: compares the screens a run rests on instead of
/// every frame.
///
/// A screen is a run of identical consecutive frames; it rests when it stays
/// for at least [rest] compared frames. Every resting screen of the golden
/// must show up in the actual run, in order, for at least one frame (a wait
/// frame will do), and the other way round. So a changed text, a missing dialog or an extra screen fails, while
/// a screen that stays longer or shorter, or data that lands a few frames
/// earlier in an animation, does not.
///
/// For apps whose timers and network run on the wall clock, where no two
/// runs produce the same frames. Animation frames in between are not
/// compared, and neither is how long a screen rests.
///
/// Device frames are left out. Indices in the result count compared frames
/// only, as in [compareFrameSequences].
ComparisonResult compareScreens({
  required List<CapturedFrame> golden,
  required List<CapturedFrame> actual,
  int rest = 15,
  double tolerance = 0.0,
}) {
  final g = _screens(golden, tolerance);
  final a = _screens(actual, tolerance);
  return _firstAbsent(g, a, rest, tolerance, missing: true) ??
      _firstAbsent(a, g, rest, tolerance, missing: false) ??
      const ComparisonPassed(maxDrift: 0);
}

class _Screen {
  _Screen(this.step, this.rgba);

  final String step;
  final Uint8List rgba;

  /// Index of its first compared frame, counting compared frames; -1 while
  /// it has none.
  var first = -1;

  /// Compared frames it stays for. Wait frames do not count: a screen seen
  /// only while waiting is there, but says nothing about resting.
  var frames = 0;
}

/// The runs of identical frames, wait frames included: a popup on a
/// wall-clock timer lands in a step's closing pause in one run and in the
/// next step's `waitFor` in another, and it was on screen both times.
List<_Screen> _screens(List<CapturedFrame> frames, double tolerance) {
  final screens = <_Screen>[];
  var compared = 0;
  for (final f in frames) {
    if (f.device) continue;
    final rgba = decodePngToRgba(f.png);
    // Against the first frame of the run, not the previous one, so a slow
    // fade cannot creep through as one screen.
    if (screens.isEmpty || !rgbaMatches(screens.last.rgba, rgba, tolerance)) {
      screens.add(_Screen(f.step, rgba));
    }
    if (f.wait) continue;
    if (screens.last.first < 0) screens.last.first = compared;
    screens.last.frames++;
    compared++;
  }
  return screens;
}

/// The first resting screen of [from] that [into] does not show in order.
ScreenMismatch? _firstAbsent(
  List<_Screen> from,
  List<_Screen> into,
  int rest,
  double tolerance, {
  required bool missing,
}) {
  var cursor = 0;
  for (final screen in from) {
    if (screen.frames < rest) continue;
    var found = -1;
    for (var j = cursor; j < into.length; j++) {
      if (rgbaMatches(screen.rgba, into[j].rgba, tolerance)) {
        found = j;
        break;
      }
    }
    if (found >= 0) {
      // Not past it: two golden rests on the same picture with only a flicker
      // in between may be one long rest in the other run.
      cursor = found;
      continue;
    }
    // What to show next to it: the most similar resting screen still ahead.
    _Screen? closest;
    var closestDiff = 100.0;
    for (final other in into.skip(cursor)) {
      if (other.frames < rest) continue;
      final diff = rgbaDiffPercent(screen.rgba, other.rgba);
      if (closest == null || diff < closestDiff) {
        closest = other;
        closestDiff = diff;
      }
    }
    final otherIndex = closest?.first ?? 0;
    return ScreenMismatch(
      goldenIndex: missing ? screen.first : otherIndex,
      actualIndex: missing ? otherIndex : screen.first,
      step: screen.step,
      diffPercent: closest == null
          ? 100
          : rgbaDiffPercent(screen.rgba, closest.rgba),
      missing: missing,
      frames: screen.frames,
    );
  }
  return null;
}
