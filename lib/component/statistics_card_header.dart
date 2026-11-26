import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef StatisticsPillOption<T> = ({
  T value,
  String label,
  IconData icon,
  Key? key,
});

/// Unified pill-bar segmented selector shared across statistics cards. Keeps
/// every option key directly reachable on narrow viewports while animating
/// selection chrome smoothly without unmounting children.
class StatisticsPillSegmented<T> extends StatelessWidget {
  const StatisticsPillSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<StatisticsPillOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in options)
            Semantics(
              key: item.key,
              button: true,
              selected: item.value == value,
              child: AnimatedContainer(
                duration: duration,
                curve: AppMotion.standardCurve,
                decoration: BoxDecoration(
                  color: item.value == value
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      if (item.value != value) onChanged(item.value);
                    },
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.icon,
                            size: 16,
                            color: item.value == value
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: item.value == value
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                                fontWeight: item.value == value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
