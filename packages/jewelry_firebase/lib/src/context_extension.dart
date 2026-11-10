import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

import 'fake_functions.dart';
import 'firebase_emulator.dart';
import 'seed.dart';

/// `ctx.firebase` on the jewelry scenario context.
class FirebaseContext {
  FirebaseContext({required this.emulator, required this.seed});

  final FirebaseEmulator emulator;
  final Seed seed;
}

extension JewelryFirebase on ScenarioContext {
  /// The emulator handle and seeding API. Requires the app to have called
  /// `Firebase.initializeApp()` and [FirebaseEmulator.useIfRequested] first,
  /// so use it in `launch` after the app's bootstrap, or in a step.
  FirebaseContext get firebase => attachment(
    () => FirebaseContext(
      emulator: FirebaseEmulator.fromDefines,
      seed: Seed(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
      ),
    ),
  );

  /// Fake Cloud Functions for this scenario, started on first use on the
  /// Functions emulator port and closed when the scenario ends. Call it in
  /// `given` or at the top of `launch`, before the app calls a function.
  Future<FakeFunctions> fakeFunctions() => attachment<_FakeFunctionsSlot>(
    _FakeFunctionsSlot.new,
  ).start(FirebaseEmulator.fromDefines.functionsPort);
}

class _FakeFunctionsSlot {
  Future<FakeFunctions>? _started;

  Future<FakeFunctions> start(int port) => _started ??= () async {
    final functions = await FakeFunctions.start(port: port);
    addTearDown(functions.close);
    return functions;
  }();
}
