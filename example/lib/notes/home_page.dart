import 'package:flutter/material.dart';

import 'notes_list.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.email});

  final String email;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final name = widget.email.split('@').first;
    return Scaffold(
      key: const ValueKey('home'),
      appBar: AppBar(title: Text(_tab == 0 ? 'Hi $name' : 'Notes')),
      body: _tab == 0
          ? const Center(child: Text('Nothing due today.'))
          : const NotesList(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            key: ValueKey('notesTab'),
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Notes',
          ),
        ],
      ),
    );
  }
}
