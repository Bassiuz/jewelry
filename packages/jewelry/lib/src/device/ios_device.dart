import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'device.dart';

/// An iOS simulator driven through `xcrun simctl`.
class IosDevice implements Device {
  IosDevice(this.simulator, this.runtime);

  final String simulator;

  /// As listed by `simctl list runtimes`, for example `iOS 18.2`.
  final String runtime;
  late String udid;

  @override
  Future<bool> exists() async => await _lookup() != null;

  @override
  Future<String> boot() async {
    udid =
        await _lookup() ??
        (throw StateError('No simulator "$simulator" with runtime $runtime'));
    await _simctl(['shutdown', udid], ok: false);
    await _simctl(['erase', udid]);
    await _simctl(['boot', udid]);
    await _simctl(['bootstatus', udid, '-b']);
    return udid;
  }

  /// Simulator files live on the host filesystem.
  @override
  Future<Uint8List> pull(String path) => File(path).readAsBytes();

  @override
  Future<void> clearApp(String anyAppPath) async {
    await _simctl(['uninstall', udid, await _bundleId(anyAppPath)]);
  }

  /// Bundle id of the installed app whose data container holds [anyAppPath].
  Future<String> _bundleId(String anyAppPath) async {
    final apps = (await _simctl(['listapps', udid])).stdout as String;
    // Blocks look like: "bundle.id" = { ... DataContainer = "file:///..."; }
    final bundle = RegExp(
      r'"([\w.-]+)"\s*=\s*\{[^}]*?DataContainer = "file://([^"]+)"',
      dotAll: true,
    ).allMatches(apps).where((m) => anyAppPath.startsWith(m.group(2)!));
    if (bundle.isEmpty) {
      throw StateError('No installed app owns $anyAppPath');
    }
    return bundle.first.group(1)!;
  }

  /// The simulator shares localhost with the host.
  @override
  Future<Socket> connectChannel(int port) =>
      Socket.connect(InternetAddress.loopbackIPv4, port);

  /// No home button in simctl; launching another app backgrounds ours.
  @override
  Future<void> background(String anyAppPath) async {
    await _simctl(['launch', udid, 'com.apple.Preferences']);
  }

  @override
  Future<void> foreground(String anyAppPath) async {
    await _simctl(['launch', udid, await _bundleId(anyAppPath)]);
  }

  @override
  Future<Uint8List> screenshot({bool shade = false}) async {
    final file = File('${Directory.systemTemp.path}/jewelry_shot_$udid.png');
    await _simctl(['io', udid, 'screenshot', file.path]);
    return file.readAsBytes();
  }

  @override
  Future<void> back() => throw UnsupportedError('iOS has no back button');

  @override
  Future<void> screenOff() =>
      throw UnsupportedError('simctl cannot lock the simulator');

  /// The simulator shares localhost with the host; nothing to forward.
  @override
  Future<void> forwardToDevice(int port) async {}

  /// simctl cannot set the simulator clock; it follows the host.
  @override
  Future<void> setClock(DateTime time) async {}

  @override
  Future<void> screenOn() async {}

  @override
  Future<void> lockScreen() =>
      throw UnsupportedError('simctl cannot lock the simulator');

  @override
  Future<void> setAppOp(String anyAppPath, String op, String mode) async {}

  /// No runtime permission grants through simctl; nothing to do.
  @override
  Future<void> grantPermission(String anyAppPath, String permission) async {}

  @override
  Future<void> tapNotificationAction(String text) =>
      throw UnsupportedError('simctl cannot tap notifications');

  Process? _log;

  @override
  Future<void> startLog(File to) async {
    to.parent.createSync(recursive: true);
    final sink = to.openWrite();
    _log = await Process.start('xcrun', [
      'simctl',
      'spawn',
      udid,
      'log',
      'stream',
      '--style',
      'compact',
      '--predicate',
      'processImagePath contains "Runner"',
    ]);
    _log!.stdout.listen(sink.add, onDone: sink.close);
    _log!.stderr.drain<void>();
  }

  @override
  Future<void> stopLog() async {
    _log?.kill();
    await _log?.exitCode;
  }

  @override
  Future<void> shutdown() => _simctl(['shutdown', udid]);

  Future<String?> _lookup() async {
    final r = await _simctl(['list', 'devices', '--json']);
    final devices = (jsonDecode(r.stdout as String)['devices'] as Map)
        .cast<String, List<dynamic>>();
    final wanted = runtime.replaceAll(RegExp(r'[ .]'), '-');
    for (final MapEntry(key: id, value: list) in devices.entries) {
      if (!id.endsWith('.SimRuntime.$wanted')) continue;
      for (final d in list.cast<Map<String, dynamic>>()) {
        if (d['name'] == simulator && d['isAvailable'] == true) {
          return d['udid'] as String;
        }
      }
    }
    return null;
  }

  Future<ProcessResult> _simctl(List<String> args, {bool ok = true}) async {
    final r = await Process.run('xcrun', ['simctl', ...args]);
    if (ok && r.exitCode != 0) {
      throw ProcessException(
        'xcrun',
        ['simctl', ...args],
        r.stderr as String,
        r.exitCode,
      );
    }
    return r;
  }
}
