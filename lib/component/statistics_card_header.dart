import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the title and controls on one row when their natural widths fit.
/// Otherwise the title stays above the controls, aligned to opposite edges.
/// Titles must support intrinsic sizing; controls may contain a LayoutBuilder.
class StatisticsCardHeader extends StatelessWidget {
  const StatisticsCardHeader(
      {super.key, required this.title, required this.controls});

  final Widget title;
  final Widget controls;

  @override
  Widget build(BuildContext context) => _HeaderLayout(
      direction: Directionality.of(context),
      children: [IntrinsicWidth(child: title), controls]);
}

class _HeaderLayout extends MultiChildRenderObjectWidget {
  const _HeaderLayout({required this.direction, required super.children});
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HeaderRenderBox(direction);

  @override
  void updateRenderObject(BuildContext context, _HeaderRenderBox renderObject) {
    renderObject.direction = direction;
  }
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _HeaderRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _HeaderRenderBox(this._direction);
  TextDirection _direction;
  set direction(TextDirection value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth);
    final title = firstChild!;
    final controls = lastChild!;
    final loose = constraints.loosen();
    title.layout(loose, parentUsesSize: true);
    controls.layout(loose, parentUsesSize: true);
    const gap = 12.0;
    final inline =
        title.size.width + gap + controls.size.width <= constraints.maxWidth;
    size = constraints.constrain(Size(
        constraints.maxWidth,
        inline
            ? math.max(title.size.height, controls.size.height)
            : title.size.height + gap + controls.size.height));
    final titleData = title.parentData! as _HeaderParentData;
    final controlsData = controls.parentData! as _HeaderParentData;
    titleData.offset = Offset(
        _direction == TextDirection.ltr ? 0 : size.width - title.size.width,
        inline ? (size.height - title.size.height) / 2 : 0);
    controlsData.offset = Offset(
        _direction == TextDirection.ltr ? size.width - controls.size.width : 0,
        inline
            ? (size.height - controls.size.height) / 2
            : title.size.height + gap);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
