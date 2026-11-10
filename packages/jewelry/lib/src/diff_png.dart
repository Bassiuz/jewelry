import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/apng/chunks.dart';
// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

import 'compare.dart';

/// A PNG of [expectedPng] dimmed, with every pixel that differs from
/// [actualPng] in red.
///
/// A pixel differs by the same rule the comparison uses, so rendering noise
/// within [channelNoise] stays out of it; flutter_golden_animation's diff
/// image paints a whole fading page red. Frames of another size are all red.
Uint8List diffPng(Uint8List expectedPng, Uint8List actualPng) {
  final header = ByteData.sublistView(
    parsePngChunks(expectedPng).firstWhere((c) => c.type == 'IHDR').data,
  );
  final width = header.getUint32(0);
  final height = header.getUint32(4);
  final expected = decodePngToRgba(expectedPng);
  final actual = decodePngToRgba(actualPng);
  final sameSize = expected.length == actual.length;

  // One filter byte (0, none) in front of every row of RGBA.
  final stride = width * 4 + 1;
  final rows = Uint8List(height * stride);
  for (var p = 0; p < width * height; p++) {
    final i = p * 4;
    final o = i + p ~/ width + 1;
    final differs =
        !sameSize ||
        (expected[i] - actual[i]).abs() > channelNoise ||
        (expected[i + 1] - actual[i + 1]).abs() > channelNoise ||
        (expected[i + 2] - actual[i + 2]).abs() > channelNoise ||
        (expected[i + 3] - actual[i + 3]).abs() > channelNoise;
    if (differs) {
      rows[o] = 255;
      rows[o + 3] = 255;
    } else {
      rows.setRange(o, o + 3, expected, i);
      rows[o + 3] = (expected[i + 3] * 0.3).round();
    }
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  return buildPng([
    PngChunk('IHDR', ihdr.buffer.asUint8List()),
    PngChunk('IDAT', Uint8List.fromList(ZLibCodec().encode(rows))),
    PngChunk('IEND', Uint8List(0)),
  ]);
}
