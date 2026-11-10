import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Where the Firebase Emulator Suite is, seen from the device.
///
/// Read from dart-defines the jewelry CLI passes to `flutter test`:
/// `JEWELRY_FIREBASE_EMULATOR=1`, `JEWELRY_FIREBASE_PROJECT=<id>` and
/// optional `JEWELRY_FIREBASE_AUTH_PORT`, `JEWELRY_FIREBASE_FIRESTORE_PORT`,
/// `JEWELRY_FIREBASE_FUNCTIONS_PORT`.
class FirebaseEmulator {
  const FirebaseEmulator({
    required this.projectId,
    this.authPort = 9099,
    this.firestorePort = 8080,
    this.functionsPort = 5001,
  });

  /// Whether the CLI asked for the emulators. Compile-time, so it holds in
  /// background isolates too.
  static const requested = bool.fromEnvironment('JEWELRY_FIREBASE_EMULATOR');

  static const fromDefines = FirebaseEmulator(
    projectId: String.fromEnvironment('JEWELRY_FIREBASE_PROJECT'),
    authPort: int.fromEnvironment('JEWELRY_FIREBASE_AUTH_PORT', defaultValue: 9099),
    firestorePort: int.fromEnvironment('JEWELRY_FIREBASE_FIRESTORE_PORT', defaultValue: 8080),
    functionsPort: int.fromEnvironment('JEWELRY_FIREBASE_FUNCTIONS_PORT', defaultValue: 5001),
  );

  final String projectId;
  final int authPort;
  final int firestorePort;
  final int functionsPort;

  /// The host as the device sees it: `JEWELRY_FIREBASE_HOST` when the CLI
  /// set it (127.0.0.2 on Android, reversed to the Mac by adb), else
  /// 10.0.2.2 on the Android emulator and localhost on the iOS simulator.
  static String get host => _host.isNotEmpty
      ? _host
      : Platform.isAndroid
      ? '10.0.2.2'
      : 'localhost';
  static const _host = String.fromEnvironment('JEWELRY_FIREBASE_HOST');

  /// Points the given instances at the emulators. Call right after
  /// `Firebase.initializeApp()` and before any use, in every isolate.
  Future<void> use({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) async {
    await auth?.useAuthEmulator(host, authPort);
    firestore?.useFirestoreEmulator(host, firestorePort);
    functions?.useFunctionsEmulator(host, functionsPort);
  }

  /// The one line an app needs after `Firebase.initializeApp()`:
  /// does nothing unless the jewelry CLI requested the emulators.
  static Future<void> useIfRequested({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) async {
    if (!requested) return;
    await fromDefines.use(auth: auth, firestore: firestore, functions: functions);
  }

  /// Deletes every Firestore document in the emulator.
  Future<void> clearFirestore() => _delete(
    'http://$host:$firestorePort/emulator/v1/projects/$projectId/databases/(default)/documents',
  );

  /// Deletes every Auth emulator account.
  Future<void> clearAuth() => _delete(
    'http://$host:$authPort/emulator/v1/projects/$projectId/accounts',
  );

  Future<void> _delete(String url) async {
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 300) {
        throw HttpException('DELETE $url: ${response.statusCode} $body');
      }
    } finally {
      client.close();
    }
  }
}
