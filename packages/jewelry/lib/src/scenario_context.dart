import 'package:flutter_test/flutter_test.dart';

/// Handed to `given` and `launch`. Extension packages hang their state on it.
class ScenarioContext {
  ScenarioContext(this.tester);

  final WidgetTester tester;

  final Map<Type, Object> _attachments = {};

  /// Returns the attachment of type [T], creating it on first use.
  ///
  /// `jewelry_firebase` uses this for `ctx.firebase`.
  T attachment<T extends Object>(T Function() create) =>
      _attachments.putIfAbsent(T, create) as T;
}
