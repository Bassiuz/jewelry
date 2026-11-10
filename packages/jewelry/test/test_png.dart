import 'dart:typed_data';
import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/apng/chunks.dart';
import 'package:jewelry/jewelry.dart';

/// A 1x1 RGBA PNG of one colour, tagged with [step].
CapturedFrame pixel(int r, int g, int b, {String step = 's'}) {
  final ihdr = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final raw = Uint8List.fromList([0, r, g, b, 255]);
  final idat = Uint8List.fromList(ZLibCodec().encode(raw));
  final png = buildPng([
    PngChunk('IHDR', ihdr.buffer.asUint8List()),
    PngChunk('IDAT', idat),
    PngChunk('IEND', Uint8List(0)),
  ]);
  return CapturedFrame(step: step, png: png);
}
