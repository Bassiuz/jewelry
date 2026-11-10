import 'package:jewelry/jewelry.dart';
import 'package:jewelry_example/notes/notes_app.dart';

import '../steps/auth_steps.dart';

void main() {
  JewelryBinding.ensureInitialized();

  scenario(
    'User logs in and sees their notes',
    launch: (ctx) => ctx.tester.pumpWidget(const NotesApp()),
    steps: [
      logInAs('anna@example.com', 'secret'),
      step('Open the notes list', (t) async {
        await t.tap('notesTab');
        await t.waitFor('notesList');
        await t.expectText('Groceries');
      }),
    ],
  );
}
