import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// All scrolling ancestors can reveal or clip a mounted surface.
/// Listening only to the nearest one misses movement of an outer viewport.
/// Register each scope on the original dependent so replaced outer positions
/// are rebound even when an inner scrollable preserves the same child subtree.
Set<ScrollPosition> scrollPositionsOf(BuildContext context) {
  final positions = <ScrollPosition>{};
  var lookup = context;
  while (true) {
    final scrollable =
        Scrollable.maybeOf(_AncestorScrollLookup(lookup, context));
    if (scrollable == null) break;
    positions.add(scrollable.position);
    lookup = scrollable.context;
  }
  return positions;
}

/// Scrollable's public lookup normally subscribes the lookup context itself.
/// This narrow adapter separates lookup from subscription without depending
/// on Flutter's private scroll-scope type or its widget tree arrangement.
/// It is only passed to [Scrollable.maybeOf], never mounted as a widget context.
class _AncestorScrollLookup implements BuildContext {
  _AncestorScrollLookup(this.lookup, this.dependent);
  final BuildContext lookup, dependent;

  @override
  InheritedElement?
      getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
          lookup.getElementForInheritedWidgetOfExactType<T>();

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor,
          {Object? aspect}) =>
      dependent.dependOnInheritedElement(ancestor, aspect: aspect);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Check actual paint geometry once after a layout/scroll/paint notification.
/// Clips are intersected in screen coordinates, including nested viewports and
/// transformed surfaces. Approximate clips conservatively retain partial views.
bool intersectsPaintViewport(RenderObject? render, Size screen) {
  if (render is! RenderBox || !render.attached || !render.hasSize) return false;
  var visible = MatrixUtils.transformRect(
      render.getTransformTo(null), Offset.zero & render.size);
  if (!visible.isFinite || visible.isEmpty) return false;
  visible = visible.intersect(Offset.zero & screen);
  if (visible.isEmpty) return false;

  RenderObject child = render;
  var parent = child.parent;
  while (parent != null) {
    if (parent is RenderOffstage && parent.offstage) return false;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      final globalClip =
          MatrixUtils.transformRect(parent.getTransformTo(null), clip);
      if (!globalClip.isFinite) return false;
      visible = visible.intersect(globalClip);
      if (visible.isEmpty) return false;
    }
    child = parent;
    parent = child.parent;
  }
  return true;
}
