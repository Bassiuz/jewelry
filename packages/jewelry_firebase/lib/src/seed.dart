import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes test data into the emulators through the app's own plugin
/// instances, so paths and shapes are exactly what the app reads.
class Seed {
  const Seed({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Creates or overwrites the document at [path].
  Future<void> doc(String path, Map<String, Object?> data) =>
      firestore.doc(path).set(data);

  /// Creates an Auth emulator account and leaves the app signed out.
  /// Returns the uid.
  Future<String> user({required String email, required String password}) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await auth.signOut();
    return credential.user!.uid;
  }

  /// Signs the app in as [email]; for scenarios that start past the login.
  Future<String> signedInAs({required String email, required String password}) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user!.uid;
  }
}
