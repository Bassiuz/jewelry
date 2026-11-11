import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import '../scenario_suite.dart';
import 'device.dart';
import 'ui_dump.dart';

/// An Android AVD driven through `emulator` and `adb`.
class AndroidDevice implements Device {
  AndroidDevice(
    this.avd, {
    String? sdk,
    this.ramMb,
    this.internet = false,
    this.window = false,
    this.instance,
  }) : sdk = sdk ?? findSdk();

  final String avd;
  final int? ramMb;

  /// See `DeviceProfile.internet`.
  final bool internet;

  /// Shows the emulator window. Off by default: frames come from the app
  /// and device screenshots from adb, so nothing needs the window.
  final bool window;

  /// Set when the run boots several emulators of this AVD at once: 0, 1, 2
  /// and so on. Each is a read-only instance on its own console port, which
  /// is what the emulator requires to run one AVD more than once. Null runs
  /// the AVD the ordinary way.
  final int? instance;

  // ponytail: a fixed range well above the ports a hand-started emulator
  // takes (5554 up). Pick free ports from `adb devices` if this ever clashes.
  int get _port => 5580 + 2 * instance!;
  final String sdk;
  Process? _emulator;
  String? _serial;

  /// The adb serial, once the emulator is up.
  String get serial => _serial!;

  static String findSdk() =>
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      '${Platform.environment['HOME']}/Library/Android/sdk';

  String get _adb => '$sdk/platform-tools/adb';
  String get _emulatorBin => '$sdk/emulator/emulator';

  @override
  Future<bool> exists() async {
    final r = await Process.run(_emulatorBin, ['-list-avds']);
    return (r.stdout as String).split('\n').map((l) => l.trim()).contains(avd);
  }

  @override
  Future<String> boot() async {
    try {
      return await _bootOnce();
    } on _NoInternet {
      // Now and then a fresh emulator never gets internet; the app's own
      // internet checks then fail every scenario on it. A new boot fixes it.
      await shutdown();
      _emulator = null;
      _serial = null;
      try {
        return await _bootOnce();
      } on _NoInternet catch (e) {
        throw StateError('$e, also after a reboot');
      }
    }
  }

  Future<String> _bootOnce() async {
    final online = await _onlineSerials();
    if (instance != null && online.contains('emulator-$_port')) {
      throw StateError(
        'emulator-$_port is already running: another jewelry run, or a '
        'leftover emulator. Stop it first.',
      );
    }
    // A second emulator on the same AVD fails to start, and this run would
    // then adopt the first one: two runs on one device break each other.
    for (final s in instance == null ? online : const <String>[]) {
      final r = await Process.run(_adb, ['-s', s, 'emu', 'avd', 'name']);
      if ((r.stdout as String).split('\n').first.trim() == avd) {
        throw StateError(
          '$avd is already running as $s: another jewelry run, or a leftover '
          'emulator. Stop it first.',
        );
      }
    }
    final emulator = _emulator = await Process.start(_emulatorBin, [
      '-avd',
      avd,
      '-wipe-data',
      '-no-snapshot',
      '-no-boot-anim',
      '-no-audio',
      // Left to itself a windowless emulator renders in software
      // (swangle_indirect) and a windowed one on the host GPU: slower, and
      // edges come out a few levels different, so goldens would depend on
      // the window. Same renderer either way.
      '-gpu',
      'host',
      if (!window) '-no-window',
      if (instance != null) ...['-read-only', '-port', '$_port'],
      if (ramMb != null) ...['-memory', '$ramMb'],
    ]);
    // Kept, because an emulator that refuses to start says why and exits:
    // waiting three minutes for it to appear would hide that.
    final said = File(
      '${Directory.systemTemp.path}/jewelry_emulator_$avd'
      '${instance == null ? '' : '_$instance'}.log',
    );
    final sink = said.openWrite();
    int? exited;
    unawaited(
      Future.wait([
        emulator.stdout.forEach(sink.add),
        emulator.stderr.forEach(sink.add),
      ]).whenComplete(sink.close),
    );
    unawaited(emulator.exitCode.then((code) => exited = code));
    // Known up front for an instance, so shutdown can reach an emulator
    // that never came online.
    if (instance != null) _serial = 'emulator-$_port';
    _serial = await _poll(
      'emulator running $avd to appear (${said.path})',
      () async {
        if (exited != null) {
          throw StateError(
            'The emulator for $avd exited with $exited, see ${said.path}',
          );
        }
        final serials = await _onlineSerials();
        if (instance != null) {
          return serials.contains('emulator-$_port') ? 'emulator-$_port' : null;
        }
        for (final s in serials) {
          final r = await Process.run(_adb, ['-s', s, 'emu', 'avd', 'name']);
          if ((r.stdout as String).split('\n').first.trim() == avd) return s;
        }
        return null;
      },
    );
    await _poll('boot to complete', () async {
      final r = await _run(['shell', 'getprop', 'sys.boot_completed']);
      return (r.stdout as String).trim() == '1' ? true : null;
    });
    // A wiped Play Store image starts updating Play Services a minute or two
    // after boot and kills every app bound to it, the app under test
    // included (ActivityManager: "stop com.google.android.gms due to
    // installPackageLI"). No Play Store, no update. Images without the store
    // have nothing to disable, hence no exit check.
    if (internet) {
      // A wiped emulator can report boot_completed before its network is up;
      // the app then cannot reach the Firebase emulators on the host.
      await _poll('the network to reach the host (10.0.2.2)', () async {
        final r = await _run([
          'shell',
          'ping',
          '-c',
          '1',
          '-W',
          '1',
          '10.0.2.2',
        ]);
        return r.exitCode == 0 ? true : null;
      }, timeout: const Duration(minutes: 2));
      // Firebase goes through adb, but apps check for real internet (DNS and
      // all) before they let the user do things.
      try {
        await _poll('the internet (dns.google)', () async {
          final r = await _run([
            'shell',
            'ping',
            '-c',
            '1',
            '-W',
            '2',
            'dns.google',
          ]);
          return r.exitCode == 0 ? true : null;
        }, timeout: const Duration(minutes: 1));
      } on TimeoutException {
        throw _NoInternet('$avd ($serial) has no internet');
      }
    } else {
      // Offline: Firebase and the fakes are reached through adb, so the
      // emulator's internet (now and then missing) cannot matter.
      await _run(['shell', 'svc', 'wifi', 'disable']);
      await _run(['shell', 'svc', 'data', 'disable']);
    }
    await _run([
      'shell',
      'pm',
      'disable-user',
      '--user',
      '0',
      'com.android.vending',
    ]);
    // The lock screen turns the screen off after a few seconds, and a
    // screenshot of an off screen is black: scenarios that film the lock
    // screen would record nothing. KEYCODE_SLEEP still turns it off.
    await _run(['shell', 'svc', 'power', 'stayon', 'true']);
    // A wiped emulator has the lock screen switched off: sleep and wake go
    // straight back to the app. Swipe to unlock, no PIN.
    await _run(['shell', 'locksettings', 'set-disabled', 'false']);
    await _run([
      'shell',
      'settings',
      'put',
      'system',
      'screen_off_timeout',
      '1800000',
    ]);
    // Doze cuts an app's network once the screen is off, which drops the
    // test's own connection. Scenarios lock the phone; they do not test doze.
    await _run(['shell', 'dumpsys', 'deviceidle', 'disable']);
    // The soft keyboard slides in on the system clock, not the harness
    // clock, so every run lays out differently while it moves. With the
    // emulator's hardware keyboard attached Android can leave it hidden.
    await _run([
      'shell',
      'settings',
      'put',
      'secure',
      'show_ime_with_hard_keyboard',
      '0',
    ]);
    return serial;
  }

  @override
  Future<Uint8List> pull(String path) async {
    final args = [
      '-s',
      serial,
      'exec-out',
      'run-as',
      _package(path),
      'cat',
      path,
    ];
    final r = await Process.run(_adb, args, stdoutEncoding: null);
    final bytes = Uint8List.fromList(r.stdout as List<int>);
    // run-as reports its own errors on stdout with exit code 0.
    final head = String.fromCharCodes(bytes.take(80));
    if (r.exitCode != 0 ||
        head.startsWith('run-as:') ||
        head.startsWith('cat:')) {
      throw ProcessException(
        _adb,
        args,
        'stderr: ${r.stderr}\nstdout: $head',
        r.exitCode,
      );
    }
    return bytes;
  }

  @override
  Future<void> clearApp(String anyAppPath) async {
    // Uninstall, not `pm clear`: cleared data keeps scheduled alarms and
    // posted notifications, which then fire in the next scenario. The next
    // scenario installs the app again.
    await _run(['uninstall', _package(anyAppPath)]);
  }

  /// The application id of [apk].
  Future<String> packageOf(String apk) async {
    // ponytail: the build-tools that sort last; any aapt2 reads any APK.
    final tools = [
      for (final d in Directory('$sdk/build-tools').listSync()) d.path,
    ]..sort();
    final r = await Process.run('${tools.last}/aapt2', [
      'dump',
      'packagename',
      apk,
    ]);
    final package = (r.stdout as String).trim();
    if (r.exitCode != 0 || package.isEmpty) {
      throw ProcessException(
        'aapt2',
        ['dump', 'packagename', apk],
        '${r.stderr}',
        r.exitCode,
      );
    }
    return package;
  }

  /// Installs [apk] and starts it with [scenario] as the file to run (see
  /// [suiteProperty]). Returns the process that prints what the app prints,
  /// one line per message; kill it when done.
  Future<Process> startScenario(
    String apk,
    String package,
    String scenario,
  ) async {
    final installed = await _run(['install', '-r', apk]);
    if (installed.exitCode != 0) {
      throw ProcessException(
        _adb,
        ['install', apk],
        '${installed.stdout}${installed.stderr}',
        installed.exitCode,
      );
    }
    await _run(['shell', 'setprop', suiteProperty, scenario]);
    // What the previous scenario printed must not be read as this one's.
    await _run(['logcat', '-c']);
    final resolved = await _run([
      'shell',
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '-c',
      'android.intent.category.LAUNCHER',
      package,
    ]);
    final activity = (resolved.stdout as String).trim().split('\n').last.trim();
    final log = await Process.start(_adb, [
      '-s',
      serial,
      'logcat',
      '-v',
      'raw',
      '-s',
      'flutter:V',
      'AndroidRuntime:E',
    ]);
    final started = await _run(['shell', 'am', 'start', '-n', activity]);
    if (started.exitCode != 0 ||
        '${started.stdout}${started.stderr}'.contains('Error')) {
      log.kill();
      throw ProcessException(
        _adb,
        ['shell', 'am', 'start', '-n', activity],
        '${started.stdout}${started.stderr}',
        started.exitCode,
      );
    }
    return log;
  }

  /// Whether a process of [package] is alive.
  Future<bool> isRunning(String package) async =>
      ((await _run(['shell', 'pidof', package])).stdout as String)
          .trim()
          .isNotEmpty;

  @override
  Future<Socket> connectChannel(int port) async {
    // Any free host port: the device port is the same on every emulator, so
    // a fixed host port would let a second emulator take over the first
    // one's channel.
    final r = await _run(['forward', 'tcp:0', 'tcp:$port']);
    final hostPort = int.tryParse((r.stdout as String).trim());
    if (hostPort == null) {
      throw ProcessException(
        _adb,
        ['forward', 'tcp:0', 'tcp:$port'],
        '${r.stderr}',
        r.exitCode,
      );
    }
    return Socket.connect(InternetAddress.loopbackIPv4, hostPort);
  }

  @override
  Future<void> background(String anyAppPath) async {
    await _run(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
  }

  @override
  Future<void> foreground(String anyAppPath) async {
    await _run([
      'shell',
      'monkey',
      '-p',
      _package(anyAppPath),
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
  }

  @override
  Future<Uint8List> screenshot({bool shade = false}) async {
    if (shade) await _expandShade();
    final r = await Process.run(_adb, [
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (shade) await _run(['shell', 'cmd', 'statusbar', 'collapse']);
    return Uint8List.fromList(r.stdout as List<int>);
  }

  Future<void> _expandShade() async {
    await _run(['shell', 'cmd', 'statusbar', 'expand-notifications']);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  @override
  Future<void> tapNotificationAction(String text) async {
    await _expandShade();
    var at = findNodeCenter(await _dump(), text);
    // A notification below an expanded one is collapsed and hides its
    // action buttons. Expand the notifications one by one until it shows.
    final chevrons = findNodeCentersById(await _dump(), ':id/expand_button');
    for (var i = 0; at == null && i < chevrons.length; i++) {
      final current = findNodeCentersById(await _dump(), ':id/expand_button');
      if (i >= current.length) break;
      await _run([
        'shell',
        'input',
        'tap',
        '${current[i].x}',
        '${current[i].y}',
      ]);
      await Future<void>.delayed(const Duration(seconds: 1));
      at = findNodeCenter(await _dump(), text);
    }
    if (at == null) {
      await _run(['shell', 'cmd', 'statusbar', 'collapse']);
      throw StateError('No notification element with text "$text" on screen');
    }
    await _run(['shell', 'input', 'tap', '${at.x}', '${at.y}']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _run(['shell', 'cmd', 'statusbar', 'collapse']);
  }

  /// `cmd alarm set-time` needs no root, unlike `date -s`.
  @override
  Future<void> setClock(DateTime time) async {
    await _run(['shell', 'settings', 'put', 'global', 'auto_time', '0']);
    await _run([
      'shell',
      'cmd',
      'alarm',
      'set-time',
      '${time.millisecondsSinceEpoch}',
    ]);
    // The clock just went back. flutter finds the app's VM service by
    // reading logcat from "now"; the previous scenario's "listening on"
    // line now looks newer than that and sends it to a dead port. Clear it.
    await _run(['logcat', '-c']);
  }

  /// Makes the device's `localhost:[devicePort]` reach the host's
  /// [hostPort].
  Future<void> reverse(int devicePort, int hostPort) async {
    final r = await _run(['reverse', 'tcp:$devicePort', 'tcp:$hostPort']);
    if (r.exitCode != 0) {
      throw ProcessException(
        _adb,
        ['reverse', 'tcp:$devicePort', 'tcp:$hostPort'],
        '${r.stderr}',
        r.exitCode,
      );
    }
  }

  @override
  Future<void> forwardToDevice(int port) async {
    final r = await _run(['forward', 'tcp:$port', 'tcp:$port']);
    if (r.exitCode != 0) {
      throw ProcessException(
        _adb,
        ['forward', 'tcp:$port'],
        '${r.stderr}',
        r.exitCode,
      );
    }
  }

  @override
  Future<void> back() => _run(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);

  @override
  Future<void> screenOff() =>
      _run(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);

  /// Shows the lock screen with the screen on: sleep, then wake without
  /// dismissing the keyguard.
  @override
  Future<void> lockScreen() async {
    await _run(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _run(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
  }

  /// Wakes the screen and swipes the (insecure) keyguard away.
  @override
  Future<void> screenOn() async {
    await _run(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
    await _run(['shell', 'wm', 'dismiss-keyguard']);
  }

  @override
  Future<void> setAppOp(String anyAppPath, String op, String mode) =>
      _run(['shell', 'appops', 'set', _package(anyAppPath), op, mode]);

  Future<String> _dump() async =>
      (await _run(['exec-out', 'uiautomator', 'dump', '/dev/tty'])).stdout
          as String;

  @override
  Future<void> grantPermission(String anyAppPath, String permission) async {
    await _run(['shell', 'pm', 'grant', _package(anyAppPath), permission]);
  }

  Process? _logcat;

  @override
  Future<void> startLog(File to) async {
    await _run(['logcat', '-c']);
    to.parent.createSync(recursive: true);
    final sink = to.openWrite();
    _logcat = await Process.start(_adb, ['-s', serial, 'logcat', '-v', 'time']);
    _logcat!.stdout.listen(sink.add, onDone: sink.close);
    _logcat!.stderr.drain<void>();
  }

  @override
  Future<void> stopLog() async {
    _logcat?.kill();
    await _logcat?.exitCode;
  }

  @override
  Future<void> shutdown() async {
    final emulator = _emulator;
    if (emulator == null) return;
    // Also when it never booted: left alone it keeps its port and its RAM.
    if (_serial != null) await _run(['emu', 'kill']);
    await emulator.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        emulator.kill(ProcessSignal.sigkill);
        return emulator.exitCode;
      },
    );
  }

  /// `/data/user/0/<package>/cache/...` names the package.
  static String _package(String path) {
    final m = RegExp(r'^/data/(?:user/\d+|data)/([^/]+)/').firstMatch(path);
    if (m == null) throw ArgumentError('Not an app path: $path');
    return m.group(1)!;
  }

  Future<ProcessResult> _run(List<String> args) =>
      Process.run(_adb, ['-s', serial, ...args]);

  /// Serials of emulators adb reports as online. A killed emulator can
  /// linger as `offline` and the new one may reuse its port, so only online
  /// ones count.
  Future<List<String>> _onlineSerials() async {
    final r = await Process.run(_adb, ['devices']);
    return [
      for (final line in (r.stdout as String).split('\n'))
        if (line.startsWith('emulator-') && line.trim().endsWith('device'))
          line.split('\t').first,
    ];
  }

  Future<T> _poll<T>(
    String what,
    Future<T?> Function() probe, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final v = await probe();
      if (v != null) return v;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw TimeoutException('Waited $timeout for $what', timeout);
  }
}

class TimeoutException implements Exception {
  const TimeoutException(this.message, this.duration);
  final String message;
  final Duration duration;
  @override
  String toString() => message;
}

class _NoInternet implements Exception {
  const _NoInternet(this.message);
  final String message;
  @override
  String toString() => message;
}
