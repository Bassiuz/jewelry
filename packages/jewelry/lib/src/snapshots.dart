import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

import 'compare.dart';
import 'diff_png.dart';
import 'scenario_recording.dart';
import 'slug.dart';

/// One snapshot that did not match its image golden.
class SnapshotMismatch {
  const SnapshotMismatch(this.name, this.reason);

  final String name;
  final String reason;

  @override
  String toString() => 'snapshot "$name": $reason';
}

/// The image goldens of one scenario on one profile:
/// `<dir>/<slug(name)>.png`, one per `t.snapshot(name)`.
class SnapshotGoldens {
  SnapshotGoldens(this.dir);

  final Directory dir;

  File _file(String name) => File('${dir.path}/${slug(name)}.png');

  /// Replaces the image goldens with the snapshots of [recording].
  void record(ScenarioRecording recording) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final shots = recording.snapshots;
    if (shots.isEmpty) return;
    dir.createSync(recursive: true);
    for (final MapEntry(key: name, value: frame) in shots.entries) {
      _file(name).writeAsBytesSync(frame.png);
    }
  }

  /// Compares the snapshots of [actual] against the image goldens, pixel by
  /// pixel within [tolerance] percent. A snapshot without a golden, or a
  /// golden the run no longer took, is a mismatch too.
  List<SnapshotMismatch> compare(ScenarioRecording actual, double tolerance) {
    final shots = actual.snapshots;
    final mismatches = <SnapshotMismatch>[];
    final goldenNames = dir.existsSync()
        ? {
            for (final f in dir.listSync().whereType<File>())
              if (f.path.endsWith('.png'))
                f.uri.pathSegments.last.replaceAll('.png', ''),
          }
        : <String>{};
    for (final MapEntry(key: name, value: frame) in shots.entries) {
      final file = _file(name);
      goldenNames.remove(slug(name));
      if (!file.existsSync()) {
        mismatches.add(SnapshotMismatch(name, 'no image golden, run with --record'));
        continue;
      }
      final diff = snapshotDiffPercent(file.readAsBytesSync(), frame.png);
      if (diff > tolerance) {
        mismatches.add(
          SnapshotMismatch(name, '${diff.toStringAsFixed(2)}% of pixels differ'),
        );
      }
    }
    for (final missing in goldenNames) {
      mismatches.add(SnapshotMismatch(missing, 'golden exists, the run took no such snapshot'));
    }
    return mismatches;
  }

  /// Writes `<name>.expected.png`, `<name>.actual.png` and `<name>.diff.png`
  /// for every pixel mismatch into [into].
  void writeDiffs(ScenarioRecording actual, List<SnapshotMismatch> mismatches, Directory into) {
    final shots = actual.snapshots;
    for (final m in mismatches) {
      final golden = _file(m.name);
      final frame = shots[m.name];
      if (!golden.existsSync() || frame == null) continue;
      into.createSync(recursive: true);
      final base = '${into.path}/${slug(m.name)}';
      File('$base.expected.png').writeAsBytesSync(golden.readAsBytesSync());
      File('$base.actual.png').writeAsBytesSync(frame.png);
      File('$base.diff.png').writeAsBytesSync(
        diffPng(golden.readAsBytesSync(), frame.png),
      );
    }
  }
}

/// Percentage of differing pixels between two PNGs, ignoring
/// [channelNoise]; 100 when the sizes differ.
double snapshotDiffPercent(Uint8List a, Uint8List b) =>
    rgbaDiffPercent(decodePngToRgba(a), decodePngToRgba(b));
