import 'dart:io';

import 'package:yaml/yaml.dart';

import 'device_profile.dart';
import 'firebase_emulator_config.dart';
import 'match_mode.dart';

/// Parsed `jewelry.yaml`.
class JewelryConfig {
  const JewelryConfig({
    required this.profiles,
    this.drift = 30,
    this.tolerance = 0.0,
    this.match = MatchMode.frames,
    this.rest = 15,
    this.headless = true,
    this.parallel = 1,
    this.defaultProfile,
    this.firebase,
    this.flutterTestArgs = const [],
    this.clock,
  });

  factory JewelryConfig.parse(String source) {
    final yaml = loadYaml(source) as Map;
    final profiles = (yaml['profiles'] as Map? ?? {}).map(
      (name, body) =>
          MapEntry(name as String, DeviceProfile.fromYaml(name, body as Map)),
    );
    return JewelryConfig(
      profiles: profiles,
      drift: yaml['drift'] as int? ?? 30,
      tolerance: (yaml['tolerance'] as num? ?? 0).toDouble(),
      match: MatchMode.values.asNameMap()[yaml['match'] ?? 'frames'] ??
          (throw FormatException(
            'match: expected frames or screens, got ${yaml['match']}',
          )),
      rest: yaml['rest'] as int? ?? 15,
      headless: yaml['headless'] as bool? ?? true,
      parallel: yaml['parallel'] as int? ?? 1,
      defaultProfile: switch (yaml['default_profile']) {
        null => null,
        final String name when profiles.containsKey(name) => name,
        final other => throw FormatException(
          'default_profile: no profile $other under profiles',
        ),
      },
      firebase: yaml['firebase'] == null
          ? null
          : FirebaseEmulatorConfig.fromYaml(yaml['firebase'] as Map),
      flutterTestArgs:
          (yaml['flutter_test_args'] as List?)?.cast<String>() ?? const [],
      clock: switch (yaml['clock']) {
        null => null,
        final String c => DateTime.parse(c),
        final other => throw FormatException('clock: expected an ISO date, got $other'),
      },
    );
  }

  static JewelryConfig load(File file) {
    if (!file.existsSync()) {
      throw FileSystemException('No jewelry.yaml in this directory', file.path);
    }
    return JewelryConfig.parse(file.readAsStringSync());
  }

  final Map<String, DeviceProfile> profiles;
  final int drift;
  final double tolerance;

  /// `match: screens` compares resting screens instead of every frame.
  final MatchMode match;

  /// Screens mode: frames a screen must stay unchanged to count as resting.
  final int rest;

  /// Android emulators run without a window; `--window` shows them.
  final bool headless;

  /// How many emulators of a profile run scenarios at the same time.
  final int parallel;

  /// The profile `run` uses without `--profile`; every profile when null.
  final String? defaultProfile;

  /// What `jewelry run` writes when the app has no `jewelry.yaml` yet.
  /// [avds] are the Android virtual devices on this machine.
  static String starter(List<String> avds) {
    final avd = avds.firstOrNull ?? 'Pixel_8_API_35';
    final name = avd.toLowerCase();
    return '''
# jewelry: video goldens for integration scenarios.
#   dart run jewelry run --record   record goldens
#   dart run jewelry run            compare against them
profiles:
  $name:
    platform: android
    avd: $avd${avds.isEmpty ? '   # no AVD found on this machine, create one first' : ''}
    # ram_mb: 4096   # for a large app that a 2 GB emulator kills
    # internet: true # the emulator is offline by default

# What `jewelry run` does without flags.
default_profile: $name   # --profile <name> picks another
headless: true           # --window shows the emulator
parallel: 5              # emulators at once, --parallel <n>; each takes its RAM

# match: screens         # for apps with wall-clock timers and network
''';
  }

  /// Present when the CLI must run the Firebase Emulator Suite.
  final FirebaseEmulatorConfig? firebase;

  /// Extra arguments for `flutter test`, for example `[--flavor, develop]`.
  final List<String> flutterTestArgs;

  /// The device clock at the start of every scenario file, so dates and
  /// times on screen are the same every run. `clock: 2026-01-05T09:00:00`
  /// in `jewelry.yaml`, read as host local time. Android only.
  final DateTime? clock;
}
