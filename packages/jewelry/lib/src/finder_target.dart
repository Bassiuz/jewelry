import 'package:flutter_test/flutter_test.dart';

import 'target.dart';

/// Any flutter_test [Finder] as a target, for widgets without key or text.
class FinderTarget extends Target {
  const FinderTarget(this.finder);

  @override
  final Finder finder;

  @override
  String toString() => finder.describeMatch(Plurality.one);
}
