import 'package:flutter_test/flutter_test.dart';

import 'target.dart';

/// Handed to `given` and `launch`. Extension packages hang their state on it.
class ScenarioContext {
  ScenarioContext(this.tester);

  final WidgetTester tester;

  final Map<Type, Object> _attachments = {};

  /// Widgets left out of every comparison in this scenario.
  final ignored = <({Finder finder, bool mustAnimate})>[];

  /// Leaves [target] out of the comparison for the whole scenario (see
  /// `t.ignore` for one step). An app's launch helper can register the
  /// widgets that animate on their own clock once for all its scenarios.
  void ignore(Object target) =>
      ignored.add((finder: Target.of(target).finder, mustAnimate: false));

  /// Returns the attachment of type [T], creating it on first use.
  ///
  /// `jewelry_firebase` uses this for `ctx.firebase`.
  T attachment<T extends Object>(T Function() create) =>
      _attachments.putIfAbsent(T, create) as T;
}
