import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'target.dart';

/// Finds a widget by its string [ValueKey].
class KeyTarget extends Target {
  const KeyTarget(this.key);

  final String key;

  @override
  Finder get finder => find.byKey(ValueKey<String>(key));

  @override
  String toString() => 'key "$key"';
}
