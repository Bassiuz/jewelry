# jewelry_firebase

Firebase Emulator Suite support for jewelry scenarios.

- The jewelry CLI starts the emulators when `jewelry.yaml` has a `firebase:` block, clears them between scenarios, and passes `JEWELRY_FIREBASE_EMULATOR=1` and `JEWELRY_FIREBASE_PROJECT` as dart-defines to the app.
- The app calls `FirebaseEmulator.useIfRequested(auth:, firestore:, functions:)` right after `Firebase.initializeApp()`. Because the switch is a compile-time define, background isolates (notification actions) point at the emulators too.
- Scenarios seed through `ctx.firebase.seed.doc(path, data)` and `ctx.firebase.seed.user(email:, password:)`.

In-process fakes were the original plan; they were dropped because notification actions run in a separate isolate with real Firebase instances, which fakes cannot reach. See the repository `decisions.md`.

## Fake Cloud Functions

Callables are mocked in Dart, per scenario. The fake listens on the Functions emulator port inside the on-device test; the CLI forwards that port from the host to the device on Android (the iOS simulator shares localhost), so the app's `useFunctionsEmulator` call reaches it from every isolate. Keep `functions` out of `only:` in `jewelry.yaml`.

```dart
scenario(
  'Home address is looked up in the Kadaster',
  given: (ctx) async {
    final functions = await ctx.fakeFunctions();
    functions.on('Widgets-callableRelayCallToKadaster', (data) => {...});
    functions.returns('userBsnCheck', {'isValid': true});
    functions.fail('getActivePickupPoints', 'UNAVAILABLE', 'down');
  },
  launch: launchApp,
  steps: [...],
);
```

- The name is the callable name as the app calls it. Every call is logged (`jewelry: callable name({...})`) and kept in `functions.calls` for assertions.
- A callable without a fake answers `NOT_FOUND` and logs which fakes exist, so a missing mock shows up instead of hanging.
- Throw `FunctionsFailure(status, message)` from a fake for any callable error code.
