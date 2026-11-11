import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

import 'captured_frame.dart';
import 'scenario_recording.dart';

/// A part of a frame that comparisons skip: where a widget the scenario
/// marked with `t.ignore` was drawn, in frame pixels (logical pixels).
class IgnoredRegion {
  const IgnoredRegion(
    this.left,
    this.top,
    this.width,
    this.height, {
    this.mustAnimate = false,
  });

  factory IgnoredRegion.fromJson(List<dynamic> j) => IgnoredRegion(
    j[0] as int,
    j[1] as int,
    j[2] as int,
    j[3] as int,
    mustAnimate: j.length > 4 && j[4] == 1,
  );

  final int left;
  final int top;
  final int width;
  final int height;

  /// The scenario expects these pixels to change during the step: an
  /// animation that should be running.
  final bool mustAnimate;

  List<int> toJson() => [left, top, width, height, if (mustAnimate) 1];

  @override
  bool operator ==(Object other) =>
      other is IgnoredRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.mustAnimate == mustAnimate;

  @override
  int get hashCode => Object.hash(left, top, width, height, mustAnimate);
}

/// The frame's RGBA pixels with its ignored regions painted one flat
/// colour, so they compare equal whatever was drawn there.
///
/// ponytail: each frame blanks its own regions. That is the same area in
/// golden and run while the widget stays put (a progress bar, a hint
/// arrow); a widget that moves between the two would leave a difference at
/// its edges. Blank the union of both frames' regions if that ever matters.
Uint8List frameRgba(CapturedFrame f) {
  final rgba = decodePngToRgba(f.png);
  if (f.ignored.isEmpty) return rgba;
  final width = _pngWidth(f.png);
  final height = rgba.length ~/ 4 ~/ width;
  for (final r in f.ignored) {
    final x1 = (r.left + r.width).clamp(0, width);
    final y1 = (r.top + r.height).clamp(0, height);
    for (var y = r.top.clamp(0, height); y < y1; y++) {
      for (var x = r.left.clamp(0, width); x < x1; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = 255;
        rgba[i + 1] = 0;
        rgba[i + 2] = 255;
        rgba[i + 3] = 255;
      }
    }
  }
  return rgba;
}

int _pngWidth(Uint8List png) => ByteData.sublistView(png, 16, 20).getUint32(0);

/// Every step with a `mustAnimate` region whose pixels never changed, and
/// what to say about it.
List<({String step, String message})> stillAnimations(
  ScenarioRecording recording,
) {
  final problems = <({String step, String message})>[];
  final byStep = <String, List<CapturedFrame>>{};
  for (final f in recording.frames) {
    if (!f.device && f.ignored.any((r) => r.mustAnimate)) {
      byStep.putIfAbsent(f.step, () => []).add(f);
    }
  }
  for (final MapEntry(key: step, value: frames) in byStep.entries) {
    final region = frames.first.ignored.firstWhere((r) => r.mustAnimate);
    final first = _crop(frames.first, region);
    final moved = frames.skip(1).any((f) {
      final c = _crop(f, region);
      if (c.length != first.length) return true;
      for (var i = 0; i < c.length; i++) {
        if (c[i] != first[i]) return true;
      }
      return false;
    });
    if (!moved) {
      problems.add((
        step: step,
        message:
            '$step: the ignored widget at ${region.left},${region.top} '
            '(${region.width}x${region.height}) did not animate',
      ));
    }
  }
  return problems;
}

Uint8List _crop(CapturedFrame f, IgnoredRegion r) {
  final rgba = decodePngToRgba(f.png);
  final width = _pngWidth(f.png);
  final height = rgba.length ~/ 4 ~/ width;
  final out = BytesBuilder();
  for (
    var y = r.top.clamp(0, height);
    y < (r.top + r.height).clamp(0, height);
    y++
  ) {
    final from = (y * width + r.left.clamp(0, width)) * 4;
    final to = (y * width + (r.left + r.width).clamp(0, width)) * 4;
    out.add(Uint8List.sublistView(rgba, from, to));
  }
  return out.takeBytes();
}
