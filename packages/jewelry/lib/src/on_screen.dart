import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the widgets of [parent] that are on screen and reachable by a tap.
///
/// Like [Finder.hitTestable], but a widget also counts when the topmost
/// hit at its centre is one of its ancestors: tappable rows often wrap
/// their label in `IgnorePointer` under a `GestureDetector`, so the label
/// itself is never hit although tapping it works. Only a gesture handler
/// (a pointer listener) counts as such an ancestor, so a page under an
/// `AbsorbPointer` is not on screen yet. A widget on a hidden tab
/// or behind a dialog barrier is still rejected: the topmost hit there is
/// a sibling subtree.
class OnScreenFinder extends ChainedFinder {
  OnScreenFinder(super.parent);

  @override
  String get description => '${parent.describeMatch(Plurality.many)} (on screen)';

  @override
  Iterable<Element> filter(Iterable<Element> parentCandidates) sync* {
    for (final candidate in parentCandidates) {
      final box = candidate.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final view = candidate.findAncestorRenderObjectOfType<RenderView>();
      if (view == null) continue;
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, center, view.flutterView.viewId);
      final top = result.path
          .map((e) => e.target)
          .whereType<RenderObject>()
          .firstOrNull;
      if (top == null || top is RenderView) continue;
      final reachable =
          top == box ||
          _isAncestor(box, top) ||
          // A gesture handler above the label takes the tap; an
          // AbsorbPointer above it (a page still animating in) does not.
          (top is RenderPointerListener && _isAncestor(top, box));
      if (reachable) yield candidate;
    }
  }

  static bool _isAncestor(RenderObject ancestor, RenderObject of) {
    for (RenderObject? r = of.parent; r != null; r = r.parent) {
      if (r == ancestor) return true;
    }
    return false;
  }
}

/// The widgets of [finder] that are on screen and reachable by a tap; see
/// [OnScreenFinder]. What every `t` action waits for.
Finder onScreen(Finder finder) => OnScreenFinder(finder);
