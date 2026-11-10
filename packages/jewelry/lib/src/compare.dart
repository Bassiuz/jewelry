import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

import 'captured_frame.dart';
import 'comparison_result.dart';

/// Ordered drift-window matching.
///
/// Golden frame `i` must appear in actual frames `cursor..cursor+drift`,
/// where `cursor` is just past the previous match. Found: advance. Found
/// later than that: timing failure. Not found at all: pixel mismatch
/// against the frame at the cursor.
///
/// Device frames (screenshots taken while backgrounded) and wait frames
/// (I/O-paced, see [CapturedFrame.wait]) are left out on both sides;
/// indices in the result count compared frames only.
ComparisonResult compareFrameSequences({
  required List<CapturedFrame> golden,
  required List<CapturedFrame> actual,
  int drift = 30,
  double tolerance = 0.0,
}) {
  golden = [for (final f in golden) if (!f.device && !f.wait) f];
  actual = [for (final f in actual) if (!f.device && !f.wait) f];
  final decoded = _Decoded(actual);
  var cursor = 0;
  var maxDrift = 0;

  for (var i = 0; i < golden.length; i++) {
    final expected = decodePngToRgba(golden[i].png);
    var found = -1;
    // ponytail: linear scan from the cursor; the success path matches at the
    // cursor, so only failures walk the list.
    for (var j = cursor; j < actual.length; j++) {
      if (rgbaMatches(expected, decoded[j], tolerance)) {
        found = j;
        break;
      }
    }
    final step = golden[i].step;
    if (found == -1) {
      final at = cursor < actual.length ? cursor : actual.length - 1;
      final diff = at < 0 ? 100.0 : _diffPercent(expected, decoded[at]);
      return PixelMismatch(
        goldenIndex: i,
        actualIndex: at,
        step: step,
        diffPercent: diff,
      );
    }
    // Frames skipped since the previous match. Relative, so one slow load
    // early on does not make every later frame late.
    final late = found - cursor;
    if (late > drift) {
      return TimingFailure(
        goldenIndex: i,
        actualIndex: found,
        step: step,
        drift: late,
      );
    }
    if (late > maxDrift) maxDrift = late;
    cursor = found + 1;
  }

  final trailing = actual.length - cursor;
  if (trailing > drift) {
    return TimingFailure(
      goldenIndex: golden.length,
      actualIndex: cursor,
      step: actual[cursor].step,
      drift: trailing,
    );
  }
  return ComparisonPassed(maxDrift: maxDrift);
}

/// Whether two decoded frames show the same picture: within [channelNoise]
/// when [tolerance] is 0, otherwise at most [tolerance] percent differing.
bool rgbaMatches(Uint8List a, Uint8List b, double tolerance) {
  if (a.length != b.length) return false;
  if (tolerance == 0) {
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > channelNoise) return false;
    }
    return true;
  }
  return _diffPercent(a, b) <= tolerance;
}

/// Channel differences up to this many levels (of 255) are rendering noise:
/// the GPU downscale to logical pixels can round a few pixels one level
/// differently between runs. Nobody can see that; a changed digit or colour
/// differs by far more.
const channelNoise = 2;

/// Percentage of pixels whose channels differ by more than [channelNoise].
double rgbaDiffPercent(Uint8List a, Uint8List b) => _diffPercent(a, b);

double _diffPercent(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 100;
  var differing = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > channelNoise ||
        (a[i + 1] - b[i + 1]).abs() > channelNoise ||
        (a[i + 2] - b[i + 2]).abs() > channelNoise ||
        (a[i + 3] - b[i + 3]).abs() > channelNoise) {
      differing++;
    }
  }
  return differing / (a.length ~/ 4) * 100;
}

/// Lazily decoded RGBA of the actual frames.
class _Decoded {
  _Decoded(this._frames) : _cache = List.filled(_frames.length, null);

  final List<CapturedFrame> _frames;
  final List<Uint8List?> _cache;

  Uint8List operator [](int i) => _cache[i] ??= decodePngToRgba(_frames[i].png);
}
