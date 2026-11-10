import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'on_screen.dart';
import 'target.dart';

/// Finds a [TextField] by its label, for forms without keys.
///
/// First a field whose own decoration shows [label] (label, hint or helper
/// text inside it). Failing that, a form that puts the label above the
/// field: the nearest text field below the label text.
class FieldTarget extends Target {
  const FieldTarget(this.label);

  final String label;

  @override
  Finder get finder => _FieldFinder(label);

  @override
  String toString() => 'field "$label"';
}

class _FieldFinder extends Finder {
  _FieldFinder(this.label);

  final String label;

  @override
  String get description => 'field "$label"';

  /// Recomputed on every evaluation: [ScenarioTester.waitFor] evaluates the
  /// same finder once per pumped frame.
  @override
  Iterable<Element> findInCandidates(Iterable<Element> candidates) {
    final fields = candidates.where((e) => e.widget is TextField).toList();
    final inside = find
        .ancestor(of: find.text(label), matching: find.byType(TextField))
        .evaluate()
        .toSet();
    final matched = fields.where(inside.contains).toList();
    if (matched.isNotEmpty) return matched;
    final below = _nearestBelowLabel(fields);
    return below == null ? const [] : [below];
  }

  Element? _nearestBelowLabel(List<Element> fields) {
    final labels = OnScreenFinder(find.text(label)).evaluate();
    if (labels.isEmpty) return null;
    final labelBox = labels.first.renderObject! as RenderBox;
    final labelBottom = labelBox
        .localToGlobal(Offset(0, labelBox.size.height))
        .dy;
    Element? best;
    var bestGap = double.infinity;
    for (final e in fields) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final gap = box.localToGlobal(Offset.zero).dy - labelBottom;
      if (gap >= -1 && gap < bestGap) {
        best = e;
        bestGap = gap;
      }
    }
    return best;
  }
}

/// Targets a text field by its visible label.
Target field(String label) => FieldTarget(label);
