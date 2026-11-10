import 'package:flutter_test/flutter_test.dart';

import 'target.dart';

/// Finds a widget by its visible text, in plain `Text` and in `Text.rich`.
class TextTarget extends Target {
  const TextTarget(this.text);

  final String text;

  @override
  Finder get finder => find.text(text, findRichText: true);

  @override
  String toString() => 'text "$text"';
}

/// Targets a widget by its visible text.
Target text(String text) => TextTarget(text);
