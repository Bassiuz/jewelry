import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'captured_frame.dart';

/// Grabs the root view after a pumped frame and tags it with the current step.
class FrameCapture {
  FrameCapture(this._tester);

  final WidgetTester _tester;
  final List<CapturedFrame> frames = [];

  /// Label stamped on every frame captured from now on.
  String currentStep = 'given';

  Uint8List? _previousRaw;
  var _reused = 0;

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    // Compared as 64-bit words: a frame is a few megabytes.
    final wa = a.buffer.asUint64List(a.offsetInBytes, a.length ~/ 8);
    final wb = b.buffer.asUint64List(b.offsetInBytes, b.length ~/ 8);
    for (var i = 0; i < wa.length; i++) {
      if (wa[i] != wb[i]) return false;
    }
    for (var i = wa.length * 8; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  final _render = Stopwatch();
  final _encode = Stopwatch();
  final _total = Stopwatch()..start();

  /// Where the scenario's time went, for the log.
  String get timing =>
      '${frames.length} frames in ${_total.elapsed.inSeconds} s: '
      'drawing ${_render.elapsed.inSeconds} s, encoding ${_encode.elapsed.inSeconds} s '
      '($_reused frames repeated the one before)';

  /// While true, captured frames are wait frames ([CapturedFrame.wait]).
  bool waiting = false;

  /// Marks the frames from [start] on as wait frames.
  void markWaitFrom(int start) {
    for (var i = start; i < frames.length; i++) {
      frames[i] = frames[i].asWait();
    }
  }

  /// Whether the last two captured frames have identical pixels.
  bool get lastTwoFramesIdentical {
    if (frames.length < 2) return false;
    final a = frames[frames.length - 1].png;
    final b = frames[frames.length - 2].png;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Adds a device screenshot as a [CapturedFrame.device] frame, scaled to
  /// the size of the engine frames so the APNG stays one size.
  Future<void> captureDevice(Uint8List screenshot) async {
    final view = _tester.binding.renderViews.first;
    final size = view.size;
    final png = await _tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        screenshot,
        targetWidth: size.width.round(),
        targetHeight: size.height.round(),
      );
      final image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    });
    frames.add(CapturedFrame(step: currentStep, png: png!, device: true));
    _previousRaw = null; // the next app frame must not reuse this one
    // Device frames are never compared; no wait flag needed.
  }

  Future<void> capture({String? snapshot}) async {
    final view = _tester.binding.renderViews.first;
    // Same as flutter_test goldens: debugLayer, so capture needs a debug build.
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer applies the device pixel ratio and paintBounds is
    // physical, so 1/dpr yields a full frame at logical size.
    // ponytail: logical size keeps goldens small; the profile pins the device,
    // so the ratio is constant anyway. Make it configurable if goldens need it.
    final dpr = view.configuration.devicePixelRatio;
    // Whole logical pixels only: 2992 physical rows at 3x are 997.33
    // logical ones, and the partial last row anti-aliases differently every
    // run.
    final bounds = view.paintBounds;
    final whole = Rect.fromLTWH(
      0,
      0,
      (bounds.width / dpr).floorToDouble() * dpr,
      (bounds.height / dpr).floorToDouble() * dpr,
    );
    _render.start();
    final image = await _tester.runAsync(
      () => layer.toImage(whole, pixelRatio: 1 / dpr),
    );
    _render.stop();
    _encode.start();
    // Most frames repeat the one before (pauses, settles): reading raw
    // pixels is cheap, encoding a PNG is not, so encode only what changed.
    final raw = (await _tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!.buffer.asUint8List();
    final Uint8List png;
    final previous = _previousRaw;
    if (previous != null && frames.isNotEmpty && _same(previous, raw)) {
      png = frames.last.png;
      _reused++;
    } else {
      final bytes = await _tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      png = bytes!.buffer.asUint8List();
    }
    _previousRaw = raw;
    _encode.stop();
    image!.dispose();
    frames.add(
      CapturedFrame(
        step: currentStep,
        png: png,
        snapshot: snapshot,
        wait: waiting && snapshot == null,
      ),
    );
  }
}
