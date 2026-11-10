import 'package:flutter/material.dart';

import 'login_page.dart';

/// A small notes app for the README scenario: log in, open the notes tab.
/// Everything is in memory, so every run draws the same frames.
class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB8860B)),
      ),
      home: const LoginPage(),
    );
  }
}
