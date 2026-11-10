/// Firebase Emulator Suite support for jewelry scenarios.
///
/// The CLI starts the emulators when `jewelry.yaml` has a `firebase:` block
/// and passes `JEWELRY_FIREBASE_EMULATOR` dart-defines to the app. The app
/// calls [FirebaseEmulator.useIfRequested] right after `Firebase.initializeApp`
/// in every isolate that touches Firebase. Scenarios seed through
/// `ctx.firebase.seed`. Cloud Functions are faked in Dart with
/// `ctx.fakeFunctions()`.
library;

export 'src/context_extension.dart';
export 'src/fake_functions.dart';
export 'src/firebase_emulator.dart';
export 'src/seed.dart';
