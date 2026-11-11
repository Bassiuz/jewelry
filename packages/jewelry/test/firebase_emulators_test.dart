import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/firebase_emulator_config.dart';
import 'package:jewelry/src/firebase_emulators.dart';

void main() {
  final hasFirebase = Process.runSync('which', ['firebase']).exitCode == 0;
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('jewelry_fb');
    File('${dir.path}/firebase.json').writeAsStringSync(
      '{"emulators":{"auth":{"port":9099},"firestore":{"port":8080}}}',
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // Worker 7: ports far from the ones a real run uses.
  FirebaseEmulatorConfig config() =>
      FirebaseEmulatorConfig(project: 'demo-jewelry', dir: dir.path).forWorker(7);

  test('a taken port is named before anything starts', () async {
    final squatter = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      config().firestorePort,
    );
    addTearDown(squatter.close);
    expect(
      FirebaseEmulators(config()).start,
      throwsA(
        predicate(
          (e) => '$e'.contains('port ${config().firestorePort}: ') &&
              '$e'.contains('PID $pid'),
        ),
      ),
    );
  });

  test(
    'stopping leaves no emulator holding its ports',
    () async {
      final emulators = FirebaseEmulators(config());
      await emulators.start();
      await emulators.stop();
      for (final port in config().ports) {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await s.close();
      }
    },
    skip: hasFirebase ? false : 'no firebase CLI',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
