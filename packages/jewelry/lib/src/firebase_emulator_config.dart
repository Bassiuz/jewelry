import 'dart:convert';

/// The `firebase:` block in `jewelry.yaml`.
///
/// ```yaml
/// firebase:
///   project: my-app-dev
///   dir: .            # where firebase.json lives, relative to the app
///   only: [auth, firestore]
/// ```
class FirebaseEmulatorConfig {
  const FirebaseEmulatorConfig({
    required this.project,
    this.dir = '.',
    this.only = const ['auth', 'firestore'],
    this.authPort = 9099,
    this.firestorePort = 8080,
    this.functionsPort = 5001,
    this.hubPort = 4400,
    this.worker = 0,
  });

  factory FirebaseEmulatorConfig.fromYaml(Map<dynamic, dynamic> yaml) =>
      FirebaseEmulatorConfig(
        project:
            yaml['project'] as String? ??
            (throw const FormatException('firebase: missing project')),
        dir: yaml['dir'] as String? ?? '.',
        only:
            (yaml['only'] as List?)?.cast<String>() ??
            const ['auth', 'firestore'],
        authPort: yaml['auth_port'] as int? ?? 9099,
        firestorePort: yaml['firestore_port'] as int? ?? 8080,
        functionsPort: yaml['functions_port'] as int? ?? 5001,
        hubPort: yaml['hub_port'] as int? ?? 4400,
      );

  /// The emulators of worker [worker] when several devices run at once:
  /// every port moved up by ten per worker, so each device talks to its own
  /// Auth and Firestore and clearing one does not wipe another's data.
  /// Worker 0 keeps the ports of `firebase.json`.
  FirebaseEmulatorConfig forWorker(int worker) => FirebaseEmulatorConfig(
    project: project,
    dir: dir,
    only: only,
    authPort: authPort + 10 * worker,
    firestorePort: firestorePort + 10 * worker,
    functionsPort: functionsPort + 10 * worker,
    hubPort: hubPort + 10 * worker,
    worker: worker,
  );

  /// Every port these emulators listen on, for the check before starting.
  List<int> get ports => [
    authPort,
    firestorePort,
    hubPort,
    9150 + 10 * worker, // Firestore websocket
    4500 + 10 * worker, // logging
    if (only.contains('functions')) functionsPort,
  ];

  /// Which worker this is the config of; 0 without parallel devices.
  final int worker;

  /// `firebase.json` with the ports of this worker, for `--config`.
  /// [source] is the app's own `firebase.json`; everything but the emulator
  /// ports is kept, rules and indexes included.
  String firebaseJson(String source) {
    final json = (jsonDecode(source) as Map).cast<String, dynamic>();
    final emulators = ((json['emulators'] as Map?) ?? {})
        .cast<String, dynamic>();
    Map<String, dynamic> block(String name) =>
        ((emulators[name] as Map?) ?? {}).cast<String, dynamic>();
    json['emulators'] = {
      ...emulators,
      'auth': {...block('auth'), 'port': authPort},
      'firestore': {
        ...block('firestore'),
        'port': firestorePort,
        'websocketPort': 9150 + 10 * worker,
      },
      'hub': {...block('hub'), 'port': hubPort},
      'logging': {...block('logging'), 'port': 4500 + 10 * worker},
      'ui': {'enabled': false},
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  final String project;
  final String dir;
  final List<String> only;
  final int authPort;
  final int firestorePort;
  final int functionsPort;
  final int hubPort;

  /// What the app reads through `FirebaseEmulator.fromDefines`.
  List<String> get dartDefines => [
    '--dart-define=JEWELRY_FIREBASE_EMULATOR=true',
    '--dart-define=JEWELRY_FIREBASE_PROJECT=$project',
    '--dart-define=JEWELRY_FIREBASE_AUTH_PORT=$authPort',
    '--dart-define=JEWELRY_FIREBASE_FIRESTORE_PORT=$firestorePort',
    '--dart-define=JEWELRY_FIREBASE_FUNCTIONS_PORT=$functionsPort',
  ];
}
