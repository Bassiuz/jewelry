/// One entry under `profiles:` in `jewelry.yaml`.
class DeviceProfile {
  const DeviceProfile({
    required this.name,
    required this.platform,
    this.avd,
    this.simulator,
    this.runtime,
    this.ramMb,
    this.internet = false,
  });

  factory DeviceProfile.fromYaml(String name, Map<dynamic, dynamic> yaml) {
    final platform = yaml['platform'] as String?;
    return switch (platform) {
      'android' => DeviceProfile(
        name: name,
        platform: platform!,
        avd: _required(yaml, 'avd', name),
        ramMb: yaml['ram_mb'] as int?,
        internet: yaml['internet'] as bool? ?? false,
      ),
      'ios' => DeviceProfile(
        name: name,
        platform: platform!,
        simulator: _required(yaml, 'simulator', name),
        runtime: _required(yaml, 'runtime', name),
      ),
      _ => throw FormatException(
        'profile "$name": platform must be android or ios, got $platform',
      ),
    };
  }

  final String name;
  final String platform;
  final String? avd;
  final String? simulator;
  final String? runtime;

  /// Android only: overrides the AVD's RAM (`emulator -memory`). A stock
  /// 2 GB Play Store AVD thrashes under a large app and kills it.
  final int? ramMb;

  /// Android: leave the emulator's network on. Off by default, so a
  /// scenario only reaches what it fakes (Firebase and fakes go through
  /// adb) and a run never depends on the emulator's flaky internet.
  final bool internet;

  static String _required(
    Map<dynamic, dynamic> yaml,
    String key,
    String name,
  ) =>
      yaml[key] as String? ??
      (throw FormatException('profile "$name": missing $key'));
}
