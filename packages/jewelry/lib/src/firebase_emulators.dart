import 'dart:convert';
import 'dart:io';

import 'firebase_emulator_config.dart';

/// Host side: runs `firebase emulators:start` for one CLI run.
class FirebaseEmulators {
  FirebaseEmulators(this.config);

  final FirebaseEmulatorConfig config;
  Process? _process;
  File? _config;

  Future<void> start() async {
    // A previous run that was killed can leave an emulator behind (the
    // Java Firestore emulator outlives a killed firebase CLI). Starting
    // next to it fails halfway or talks to stale state: say who holds what.
    final taken = <String>[
      for (final port in config.ports)
        if (!await _free(port)) await _holder(port),
    ];
    if (taken.isNotEmpty) {
      throw StateError(
        'Firebase emulator ports are taken, from an earlier run that did not '
        'stop cleanly?\n  ${taken.join('\n  ')}',
      );
    }
    // Workers past the first get their own ports through a firebase.json
    // written next to the app's, so paths to rules in it keep resolving.
    if (config.worker > 0) {
      _config = File('${config.dir}/firebase.jewelry-${config.worker}.json')
        ..writeAsStringSync(
          config.firebaseJson(
            File('${config.dir}/firebase.json').readAsStringSync(),
          ),
        );
    }
    _process = await Process.start('firebase', [
      'emulators:start',
      '--only',
      config.only.join(','),
      '--project',
      config.project,
      if (_config != null) ...['--config', _config!.uri.pathSegments.last],
    ], workingDirectory: config.dir);
    final log = File(
      '${Directory.systemTemp.path}/jewelry_firebase_emulators'
      '${config.worker == 0 ? '' : '_${config.worker}'}.log',
    )..writeAsStringSync('');
    _process!.stdout.listen(
      (b) => log.writeAsBytesSync(b, mode: FileMode.append),
    );
    _process!.stderr.listen(
      (b) => log.writeAsBytesSync(b, mode: FileMode.append),
    );
    _process!.exitCode.then((_) => _exited = true);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (await _hubUp()) return;
      if (_exited) {
        throw StateError(
          'firebase emulators exited early, see ${log.path}:\n${log.readAsStringSync()}',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('firebase emulators did not come up, see ${log.path}');
  }

  var _exited = false;

  Future<bool> _hubUp() async {
    final client = HttpClient();
    try {
      final r = await client
          .getUrl(Uri.parse('http://localhost:${config.hubPort}/emulators'))
          .then((req) => req.close());
      await r.drain<void>();
      return r.statusCode == 200;
    } on SocketException {
      return false;
    } finally {
      client.close();
    }
  }

  /// Wipes Firestore documents and Auth accounts.
  Future<void> clear() async {
    if (config.only.contains('firestore')) {
      await _delete(
        'http://localhost:${config.firestorePort}/emulator/v1/projects/'
        '${config.project}/databases/(default)/documents',
      );
    }
    if (config.only.contains('auth')) {
      await _delete(
        'http://localhost:${config.authPort}/emulator/v1/projects/'
        '${config.project}/accounts',
      );
    }
  }

  Future<void> _delete(String url) async {
    final client = HttpClient();
    try {
      final r = await client
          .deleteUrl(Uri.parse(url))
          .then((req) => req.close());
      final body = await r.transform(utf8.decoder).join();
      if (r.statusCode >= 300) {
        throw HttpException('DELETE $url: ${r.statusCode} $body');
      }
    } finally {
      client.close();
    }
  }

  Future<void> stop() async {
    if (_config?.existsSync() ?? false) _config!.deleteSync();
    final p = _process;
    if (p == null) return;
    // The emulators run as children of the firebase CLI (a Java Firestore
    // emulator); killed alone, the CLI leaves them holding their ports.
    final children = await _descendants(p.pid);
    p.kill(ProcessSignal.sigint);
    await p.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    for (final pid in children) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
  }

  static Future<bool> _free(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// `port 8110: java (PID 57919, started Wed Nov 11 10:11:04 2026)`.
  static Future<String> _holder(int port) async {
    final r = await Process.run('lsof', [
      '-nP',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-Fpc',
    ]);
    final lines = (r.stdout as String).split('\n');
    final pid = lines
        .firstWhere((l) => l.startsWith('p'), orElse: () => '')
        .replaceFirst('p', '');
    if (pid.isEmpty) return 'port $port: in use';
    final name = lines
        .firstWhere((l) => l.startsWith('c'), orElse: () => 'c?')
        .substring(1);
    final ps = await Process.run('ps', ['-o', 'lstart=,command=', '-p', pid]);
    final started = (ps.stdout as String).trim();
    final what = started.contains('cloud-firestore-emulator')
        ? 'a Firestore emulator'
        : started.contains('firebase')
        ? 'a Firebase emulator'
        : name;
    return 'port $port: $what (PID $pid, started '
        '${started.length >= 24 ? started.substring(0, 24) : started}) '
        '- stop it with: kill $pid';
  }

  /// The PIDs under [pid], children first-level and deeper.
  static Future<List<int>> _descendants(int pid) async {
    final r = await Process.run('pgrep', ['-P', '$pid']);
    final children = [
      for (final l in (r.stdout as String).split('\n')) ?int.tryParse(l.trim()),
    ];
    return [
      for (final c in children) ...[c, ...await _descendants(c)],
    ];
  }
}
