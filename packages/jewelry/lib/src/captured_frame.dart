import 'dart:typed_data';

import 'ignored_region.dart';

/// One frame as lossless PNG, tagged with the step that produced it.
class CapturedFrame {
  const CapturedFrame({
    required this.step,
    required this.png,
    this.device = false,
    this.snapshot,
    this.wait = false,
    this.ignored = const [],
  });

  CapturedFrame asWait() => CapturedFrame(
    step: step,
    png: png,
    device: device,
    snapshot: snapshot,
    wait: true,
    ignored: ignored,
  );

  final String step;
  final Uint8List png;

  /// A device screenshot (status bar, home screen, notifications) taken
  /// while the app was in the background, not an engine frame. Shown in
  /// the recording, never compared: the clock in the status bar alone
  /// differs every run.
  final bool device;

  /// Set when the scenario took a snapshot here (`t.snapshot(name)`): the
  /// frame is also written and compared as a PNG image golden.
  final String? snapshot;

  /// Recorded while the scenario waited on something outside the app's
  /// control: app start, a `waitFor` that had not matched yet, a settle that
  /// ran into its cap (a spinner). How many such frames there are depends
  /// on I/O timing, so they are shown but not compared.
  final bool wait;

  /// Regions the comparison skips (`t.ignore`): widgets that animate on
  /// their own clock.
  final List<IgnoredRegion> ignored;
}
