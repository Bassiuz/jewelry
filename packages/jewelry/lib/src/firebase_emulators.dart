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
    if (await _hubUp()) {
      // A previous run that was killed leaves its emulators behind; a new
      // suite then fails to bind and the stale one answers with old state.
      throw StateError(
        'Firebase emulators are already running (hub on port '
        '${config.hubPort}). Stop them first: '
        'lsof -ti :${config.hubPort},:${config.firestorePort},:${config.authPort} | xargs kill',
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
    p.kill(ProcessSignal.sigint);
    await p.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}
