# Example

`jewelry.yaml` asks the CLI to start the Firebase emulators:

```yaml
firebase:
  project: demo-myapp
```

The app points at them right after `Firebase.initializeApp()`:

```dart
await Firebase.initializeApp();
await FirebaseEmulator.useIfRequested(
  auth: FirebaseAuth.instance,
  firestore: FirebaseFirestore.instance,
  functions: FirebaseFunctions.instance,
);
```

A scenario seeds data and fakes a callable before the app starts:

```dart
scenario(
  'Home address is looked up',
  given: (ctx) async {
    await ctx.firebase.seed.user(email: 'anna@example.com', password: 'secret');
    await ctx.firebase.seed.doc('users/anna', {'name': 'Anna'});
    final functions = await ctx.fakeFunctions();
    functions.returns('lookupAddress', {'street': 'Oudegracht', 'city': 'Utrecht'});
  },
  launch: (ctx) => ctx.tester.pumpWidget(const MyApp()),
  steps: [...],
);
```
