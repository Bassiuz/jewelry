import 'dart:io';

import 'comparison_result.dart';
import 'diff_png.dart';
import 'scenario_recording.dart';
import 'snapshots.dart';

/// Writes `expected.apng`, `actual.apng`, the failing frame of both with
/// their `diff.png`, and `report.md` into [dir]. The HTML report shows them.
void writeFailureReport({
  required Directory dir,
  required String scenario,
  required String profile,
  required ScenarioRecording golden,
  required ScenarioRecording actual,
  required ComparisonResult result,
  List<SnapshotMismatch> snapshots = const [],
}) {
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  golden.write('${dir.path}/expected');
  actual.write('${dir.path}/actual');

  final (goldenIndex, actualIndex) = switch (result) {
    PixelMismatch r => (r.goldenIndex, r.actualIndex),
    TimingFailure r => (r.goldenIndex, r.actualIndex),
    ScreenMismatch r => (r.goldenIndex, r.actualIndex),
    ComparisonPassed() => (-1, -1),
  };
  // The comparison counts compared frames only: no device or wait frames.
  final goldenEngine = [
    for (final f in golden.frames)
      if (!f.device && !f.wait) f,
  ];
  final actualEngine = [
    for (final f in actual.frames)
      if (!f.device && !f.wait) f,
  ];
  // ponytail: one diff frame at the failure, not a diff APNG. Enough to see
  // what broke; the full pair plays in viewer.html.
  if (goldenIndex >= 0 &&
      goldenIndex < goldenEngine.length &&
      actualIndex >= 0 &&
      actualIndex < actualEngine.length) {
    File('${dir.path}/expected_frame.png')
        .writeAsBytesSync(goldenEngine[goldenIndex].png);
    File('${dir.path}/actual_frame.png')
        .writeAsBytesSync(actualEngine[actualIndex].png);
    File('${dir.path}/diff.png').writeAsBytesSync(
      diffPng(goldenEngine[goldenIndex].png, actualEngine[actualIndex].png),
    );
  }

  File('${dir.path}/report.md').writeAsStringSync('''
# $scenario on $profile

**$result**

- Golden: ${golden.frames.length} frames (`expected.apng`)
- Actual: ${actual.frames.length} frames (`actual.apng`)
- `expected_frame.png`, `actual_frame.png`, `diff.png`: golden frame $goldenIndex against actual frame $actualIndex, differing pixels in red
- `../../../report.html` shows all of it
${snapshots.isEmpty ? '' : '\n## Snapshots\n\n${snapshots.map((s) => '- $s').join('\n')}\n\nExpected, actual and diff PNGs are in `snapshots/`.\n'}
## Golden steps

${_runs(golden)}
## Actual steps

${_runs(actual)}''');
}

String _runs(ScenarioRecording r) {
  final buffer = StringBuffer();
  var start = 0;
  final frames = r.frames;
  for (var i = 0; i <= frames.length; i++) {
    if (i == frames.length || frames[i].step != frames[start].step) {
      buffer.writeln('- ${frames[start].step}: frames $start to ${i - 1}');
      start = i;
    }
  }
  return buffer.toString();
}
