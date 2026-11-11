import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/apng/decoder.dart';
// ignore: implementation_imports
import 'package:flutter_golden_animation/src/apng/encoder.dart';

import 'captured_frame.dart';
import 'ignored_region.dart';

/// The frames of one scenario run: an APNG plus a steps sidecar, because
/// APNG has nowhere to put the step a frame belongs to.
///
/// Files: `<base>.apng` and `<base>.steps.json`
/// (`[{"step": "...", "frames": n}, ...]`, run-length).
class ScenarioRecording {
  const ScenarioRecording(this.frames);

  final List<CapturedFrame> frames;

  /// Frame delay written into the APNG; frames are 60 Hz.
  static const frameDelayMs = 17;

  /// Printed by the on-device run as `marker\t<label>\t<base>`; the CLI
  /// pulls `<base>.apng` and `<base>.steps.json`.
  static const marker = 'jewelry:recorded';

  /// Printed when the on-device host channel is listening:
  /// `channelMarker\t<port>\t<systemTemp>\t<label>`.
  static const channelMarker = 'jewelry:channel';

  Uint8List toApng() => encodeApng(
    frames: [for (final f in frames) f.png],
    frameDelayMs: frameDelayMs,
  );

  String toStepsJson() {
    final runs = <Map<String, Object>>[];
    for (final f in frames) {
      if (runs.isNotEmpty &&
          runs.last['step'] == f.step &&
          (runs.last['device'] == true) == f.device &&
          (runs.last['wait'] == true) == f.wait &&
          runs.last['snapshot'] == null &&
          f.snapshot == null &&
          jsonEncode(runs.last['ignore'] ?? const []) ==
              jsonEncode(f.ignored)) {
        runs.last['frames'] = (runs.last['frames']! as int) + 1;
      } else {
        runs.add({
          'step': f.step,
          'frames': 1,
          if (f.device) 'device': true,
          if (f.wait) 'wait': true,
          if (f.snapshot != null) 'snapshot': f.snapshot!,
          if (f.ignored.isNotEmpty) 'ignore': f.ignored,
        });
      }
    }
    return jsonEncode(runs);
  }

  static ScenarioRecording decode(Uint8List apng, String stepsJson) {
    final pngs = decodeApng(apng).frames;
    final runs = (jsonDecode(stepsJson) as List).cast<Map<String, dynamic>>();
    final steps = [
      for (final r in runs)
        for (var i = 0; i < (r['frames'] as int); i++)
          (
            step: r['step'] as String,
            device: r['device'] == true,
            snapshot: r['snapshot'] as String?,
            wait: r['wait'] == true,
            ignored: [
              for (final j in (r['ignore'] as List?) ?? const [])
                IgnoredRegion.fromJson(j as List),
            ],
          ),
    ];
    if (steps.length != pngs.length) {
      throw FormatException(
        'steps sidecar covers ${steps.length} frames, APNG has ${pngs.length}',
      );
    }
    return ScenarioRecording([
      for (var i = 0; i < pngs.length; i++)
        CapturedFrame(
          step: steps[i].step,
          png: pngs[i],
          device: steps[i].device,
          snapshot: steps[i].snapshot,
          wait: steps[i].wait,
          ignored: steps[i].ignored,
        ),
    ]);
  }

  void write(String base) {
    File('$base.apng').writeAsBytesSync(toApng());
    File('$base.steps.json').writeAsStringSync(toStepsJson());
  }

  /// The snapshot frames by name, in recording order.
  Map<String, CapturedFrame> get snapshots => {
    for (final f in frames)
      if (f.snapshot != null) f.snapshot!: f,
  };

  static ScenarioRecording read(String base) => decode(
    File('$base.apng').readAsBytesSync(),
    File('$base.steps.json').readAsStringSync(),
  );
}
