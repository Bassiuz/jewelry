import 'slug.dart';

/// How one scenario ended on one profile.
enum Outcome { passed, recorded, accepted, failed }

/// The result of one scenario on one profile, as kept in
/// `.jewelry/last_run.json` and shown in the summary and the HTML report.
class ScenarioResult {
  ScenarioResult({
    required this.label,
    required this.file,
    required this.profile,
    required this.outcome,
    required this.duration,
    required this.ranAt,
    this.reason = '',
    this.step,
    this.detail = '',
    this.acceptable = false,
    this.frames = 0,
    this.snapshots = 0,
    this.log,
  });

  factory ScenarioResult.fromJson(Map<String, dynamic> json) => ScenarioResult(
    label: json['label'] as String,
    file: json['file'] as String,
    profile: json['profile'] as String,
    outcome: Outcome.values.byName(json['outcome'] as String),
    duration: Duration(milliseconds: json['durationMs'] as int),
    ranAt: DateTime.parse(json['ranAt'] as String),
    reason: json['reason'] as String? ?? '',
    step: json['step'] as String?,
    detail: json['detail'] as String? ?? '',
    acceptable: json['acceptable'] == true,
    frames: json['frames'] as int? ?? 0,
    snapshots: json['snapshots'] as int? ?? 0,
    log: json['log'] as String?,
  );

  /// The scenario label, or the file name when the run never got as far as
  /// reporting a scenario.
  final String label;
  final String file;
  final String profile;
  Outcome outcome;

  /// Time spent on the scenario file, build and install included.
  final Duration duration;
  final DateTime ranAt;

  /// One line: what failed. Empty unless [outcome] is failed.
  String reason;

  /// The step it failed in, when known.
  final String? step;

  /// The rest: the error text, what was on screen, the snapshot mismatches.
  String detail;

  /// The failure folder holds a complete recording that `jewelry accept`
  /// can make the golden. False when a step failed: that run never finished.
  bool acceptable;
  final int frames;
  final int snapshots;

  /// The `flutter test` output of the scenario file, relative to `.jewelry`.
  final String? log;

  bool get failed => outcome == Outcome.failed;

  /// `.jewelry/failures/<slug>/<profile>`, relative to `.jewelry`.
  String get failureDir => 'failures/${slug(label)}/$profile';

  /// `.jewelry/goldens/<slug>/<profile>`, relative to `.jewelry`: the base
  /// of the `.apng` and `.steps.json`, and the folder of the image goldens.
  String get goldenBase => 'goldens/${slug(label)}/$profile';

  Map<String, Object?> toJson() => {
    'label': label,
    'file': file,
    'profile': profile,
    'outcome': outcome.name,
    'durationMs': duration.inMilliseconds,
    'ranAt': ranAt.toIso8601String(),
    if (reason.isNotEmpty) 'reason': reason,
    if (step != null) 'step': step,
    if (detail.isNotEmpty) 'detail': detail,
    if (acceptable) 'acceptable': true,
    'frames': frames,
    'snapshots': snapshots,
    if (log != null) 'log': log,
  };
}
