import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Try the real empty space below the unchanged navigation first. Only a short
/// sidebar needs the existing scrollable navigation above a separate footer.
class SidebarResourcePlacement extends MultiChildRenderObjectWidget {
  SidebarResourcePlacement(
      {super.key,
      required Widget navigation,
      required Widget monitor,
      required this.measurementIdentity,
      required this.bottomInset})
      : super(children: [
          _NavigationExtent(child: RepaintBoundary(child: navigation)),
          monitor,
        ]);

  final double bottomInset;
  final Object measurementIdentity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ResourcePlacement(bottomInset, measurementIdentity);

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    final placement = renderObject as _ResourcePlacement;
    placement.bottomInset = bottomInset;
    placement.measurementIdentity = measurementIdentity;
  }
}

class _NavigationExtent extends SingleChildRenderObjectWidget {
  const _NavigationExtent({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _NavigationExtentBox();
}

class _NavigationExtentBox extends RenderProxyBox {
  double? occupiedBottom;
  double fullHeight = 0;
  double fullWidth = 0;
  bool _measureNeeded = true;

  @override
  void performLayout() {
    super.performLayout();
    _measureNeeded = true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_measureNeeded || size.height != fullHeight) return;
    _measureNeeded = false;
    // Descendant transforms and sizes are only valid after the entire layout
    // has completed. Cache the result until navigation itself lays out again;
    // ordinary resource samples never walk this subtree.
    var bottom = 0.0;
    var scrolls = false;
    void visit(RenderObject node) {
      if (node is RenderViewport && node.offset is ScrollPosition) {
        final position = node.offset as ScrollPosition;
        scrolls |=
            position.hasContentDimensions && position.maxScrollExtent > 0;
      }
      if (node is RenderSemanticsAnnotations &&
          (node.properties.button == true || node.properties.onTap != null) &&
          node.hasSize) {
        final bounds = MatrixUtils.transformRect(
            node.getTransformTo(this), Offset.zero & node.size);
        if (bounds.isFinite) bottom = math.max(bottom, bounds.bottom);
      }
      node.visitChildren(visit);
    }

    child?.visitChildren(visit);
    final next = scrolls ? math.max(bottom, fullHeight) : bottom;
    if (next != occupiedBottom) {
      occupiedBottom = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) parent?.markNeedsLayout();
      });
    }
  }
}

class _PlacementData extends ContainerBoxParentData<RenderBox> {}

class _ResourcePlacement extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PlacementData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PlacementData> {
  _ResourcePlacement(this._bottomInset, this._measurementIdentity);
  Object _measurementIdentity;
  set measurementIdentity(Object value) {
    if (_measurementIdentity == value) return;
    _measurementIdentity = value;
    final navigation = firstChild! as _NavigationExtentBox;
    navigation.occupiedBottom = null;
    navigation._measureNeeded = true;
    markNeedsLayout();
  }

  double _bottomInset;
  set bottomInset(double value) {
    if (value == _bottomInset) return;
    _bottomInset = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PlacementData) {
      child.parentData = _PlacementData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final navigation = firstChild! as _NavigationExtentBox;
    final monitor = lastChild!;
    if (navigation.fullHeight != size.height ||
        navigation.fullWidth != size.width) {
      navigation.fullHeight = size.height;
      navigation.fullWidth = size.width;
      navigation.occupiedBottom = null;
    }
    monitor.layout(
        BoxConstraints.tightFor(width: size.width)
            .copyWith(maxHeight: size.height),
        parentUsesSize: true);
    var inset =
        math.min(_bottomInset, math.max(0, size.height - monitor.size.height));
    final occupied = navigation.occupiedBottom;
    final free = size.height - (occupied ?? 0) - monitor.size.height;
    if (monitor.size.height > 0 && free < 0) {
      // The original navigation already needs this area. Keep all destinations
      // reachable by its own scrolling, with the footer outside that viewport.
      navigation.layout(
          BoxConstraints.tight(
              Size(size.width, size.height - monitor.size.height - inset)),
          parentUsesSize: true);
    } else {
      // Preserve navigation coordinates even when the preferred inset must be
      // smaller. Footer samples do not relayout or remeasure unchanged nav.
      inset = math.min(inset, math.max(0, free));
      navigation.layout(BoxConstraints.tight(size), parentUsesSize: true);
    }
    (navigation.parentData! as _PlacementData).offset = Offset.zero;
    (monitor.parentData! as _PlacementData).offset = Offset(
        0,
        occupied == null
            ? size.height
            : size.height - inset - monitor.size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
