import 'package:flutter/material.dart';

const _notes = [
  ('Groceries', 'Eggs, coffee, two lemons'),
  ('Birthday ideas', 'Record player for Sam'),
  ('Book club', 'Chapter 4 by Thursday'),
];

class NotesList extends StatelessWidget {
  const NotesList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('notesList'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final (title, body) in _notes)
          Card(
            child: ListTile(title: Text(title), subtitle: Text(body)),
          ),
      ],
    );
  }
}
