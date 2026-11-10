import 'package:flutter_test/flutter_test.dart';

import 'finder_target.dart';
import 'key_target.dart';

/// Something a step can act on. A bare [String] means a widget key.
abstract class Target {
  const Target();

  Finder get finder;

  /// Accepts a [Target], a [String] key or a raw [Finder].
  static Target of(Object target) => switch (target) {
    Target t => t,
    String key => KeyTarget(key),
    Finder f => FinderTarget(f),
    _ => throw ArgumentError.value(
      target,
      'target',
      'Expected a String key, a Finder or a Target',
    ),
  };
}
