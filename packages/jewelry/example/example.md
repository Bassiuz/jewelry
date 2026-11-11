# Example

A scenario in `integration_test/scenarios/notes_test.dart` of a Flutter app. The full example app is in the [repository](https://github.com/Bassiuz/jewelry/tree/main/example).

```dart
import 'package:jewelry/jewelry.dart';

void main() {
  JewelryBinding.ensureInitialized();

  scenario(
    'User logs in and sees their notes',
    launch: (ctx) => ctx.tester.pumpWidget(const NotesApp()),
    steps: [
      step('Log in', (t) async {
        await t.enterText('emailField', 'anna@example.com');
        await t.enterText('passwordField', 'secret');
        await t.tap('loginButton');
        await t.waitFor('home');
      }),
      step('Open the notes list', (t) async {
        await t.tap('notesTab');
        await t.waitFor('notesList');
        await t.expectText('Groceries');
        await t.snapshot('Notes list');
      }),
    ],
  );
}
```

```
dart run jewelry run --record   # record the golden
dart run jewelry run            # compare against it
dart run jewelry dashboard      # look at the last run
```
