import 'dart:io';

import 'run_log.dart';
import 'scenario_recording.dart';
import 'scenario_result.dart';
import 'slug.dart';
import 'snapshots.dart';

/// Makes the recordings of the last run the goldens, without running
/// anything: the failed comparison already left the complete recording in
/// its failure folder.
///
/// [only] narrows it to scenarios by label, slug or file; empty takes every
/// failure that can be accepted. A scenario whose step failed cannot: that
/// run stopped halfway. Returns the accepted and the refused results.
({List<ScenarioResult> accepted, List<ScenarioResult> refused}) acceptLastRun(
  RunLog log, {
  List<String> only = const [],
}) {
  final accepted = <ScenarioResult>[];
  final refused = <ScenarioResult>[];
  for (final r in log.results) {
    if (!r.failed) continue;
    if (only.isNotEmpty &&
        !only.any((o) => o == r.label || slug(o) == slug(r.label) || o == r.file)) {
      continue;
    }
    final failure = Directory('${log.dir.path}/${r.failureDir}');
    if (!r.acceptable || !File('${failure.path}/actual.apng').existsSync()) {
      refused.add(r);
      continue;
    }
    final recording = ScenarioRecording.read('${failure.path}/actual');
    final golden = '${log.dir.path}/${r.goldenBase}';
    Directory(golden).parent.createSync(recursive: true);
    recording.write(golden);
    SnapshotGoldens(Directory(golden)).record(recording);
    failure.deleteSync(recursive: true);
    r
      ..outcome = Outcome.accepted
      ..reason = ''
      ..detail = ''
      ..acceptable = false;
    accepted.add(r);
  }
  log.save();
  return (accepted: accepted, refused: refused);
}
