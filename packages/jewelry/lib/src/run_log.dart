import 'dart:convert';
import 'dart:io';

import 'scenario_result.dart';

/// The latest result of every scenario, in `.jewelry/last_run.json`.
///
/// A run replaces the results of the files it ran and keeps the rest, so
/// after a full run and a `--failed` rerun the log still covers the suite.
/// It feeds the HTML report, `jewelry accept`, `--failed` and the time
/// estimate of the next run.
class RunLog {
  RunLog(this.dir, this.results);

  factory RunLog.load(Directory dir) {
    final file = File('${dir.path}/last_run.json');
    if (!file.existsSync()) return RunLog(dir, []);
    return RunLog(dir, [
      for (final r in jsonDecode(file.readAsStringSync()) as List)
        ScenarioResult.fromJson(r as Map<String, dynamic>),
    ]);
  }

  /// The `.jewelry` folder.
  final Directory dir;
  final List<ScenarioResult> results;

  /// Replaces what is known about [file] on [profile] with [fresh].
  void replace(String file, String profile, List<ScenarioResult> fresh) {
    results
      ..removeWhere((r) => r.file == file && r.profile == profile)
      ..addAll(fresh);
  }

  /// How long [file] took on [profile] last time, when known.
  Duration? lastDuration(String file, String profile) => results
      .where((r) => r.file == file && r.profile == profile)
      .map((r) => r.duration)
      .firstOrNull;

  /// [files] with the slowest of the last run first, files without a
  /// duration before those: a long scenario that starts last keeps one
  /// emulator busy while the others are done.
  List<String> longestFirst(List<String> files, String profile) {
    int ms(String f) =>
        lastDuration(f, profile)?.inMilliseconds ?? 1 << 40;
    return [...files]..sort((a, b) => ms(b).compareTo(ms(a)));
  }

  void save() => File('${dir.path}/last_run.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(results),
  );
}
