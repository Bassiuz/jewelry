import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'target.dart';

/// Finds a widget by the icon it shows, for icon buttons without keys.
class IconTarget extends Target {
  const IconTarget(this.icon);

  final IconData icon;

  @override
  Finder get finder => find.byIcon(icon);

  @override
  String toString() => 'icon $icon';
}

/// Targets a widget by the icon it shows, such as `icon(Icons.close)`.
Target icon(IconData icon) => IconTarget(icon);
