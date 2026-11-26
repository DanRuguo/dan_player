import 'dart:math' as math;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class CategoryDisplayControls extends StatelessWidget {
  const CategoryDisplayControls(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.search});
  final CategoryPresentation value;
  final ValueChanged<CategoryPresentation> onChanged;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return AppEntrance(
      identity: 'category-display-controls',
      child: LayoutBuilder(builder: (context, constraints) {
        if (MediaQuery.sizeOf(context).height < 650 &&
            constraints.maxWidth < 840) {
          return Row(children: [
            Expanded(child: search),
            const SizedBox(width: 8),
            AppMenuAnchor(
                useRootOverlay: true,
                consumeOutsideTap: true,
                style: MenuStyle(
                    maximumSize: WidgetStatePropertyAll(Size(
                        math.min(360, constraints.maxWidth), double.infinity))),
                menuChildren: [
                  for (final shape in CategoryCoverShape.values)
                    MenuItemButton(
                        leadingIcon: Icon(shape == CategoryCoverShape.circle
                            ? Icons.circle_outlined
                            : Icons.crop_square_rounded),
                        trailingIcon: value.shape == shape
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onPressed: () =>
                            onChanged(value.copyWith(shape: shape)),
                        child: Text(ui(
                            shape == CategoryCoverShape.circle ? '圆形' : '矩形'))),
                  const Divider(),
                  MenuItemButton(
                      leadingIcon: const Icon(Icons.title_rounded),
                      trailingIcon: value.showTitle
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onPressed: () => onChanged(
                          value.copyWith(showTitle: !value.showTitle)),
                      child: Text(ui('显示封面标题'))),
                  MenuItemButton(
                      leadingIcon: const Icon(Icons.info_outline_rounded),
                      trailingIcon: value.showDetails
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onPressed: () => onChanged(
                          value.copyWith(showDetails: !value.showDetails)),
                      child: Text(ui('显示数量与来源'))),
                  AppSubmenuButton(
                      leadingIcon: const Icon(Icons.sort_rounded),
                      menuStyle: const MenuStyle(
                          maximumSize: WidgetStatePropertyAll(
                              Size(appSortMenuMaxWidth, double.infinity))),
                      menuChildren: [
                        for (final entry in [
                          (CategorySort.standard, '默认顺序'),
                          (CategorySort.name, '名称'),
                          (CategorySort.count, '歌曲数量'),
                          (CategorySort.custom, '自定义')
                        ])
                          MenuItemButton(
                              trailingIcon: value.sort == entry.$1
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              onPressed: () =>
                                  onChanged(value.copyWith(sort: entry.$1)),
                              child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: appSortMenuLabelMaxWidth),
                                  child: Text(ui(entry.$2)))),
                        const Divider(),
                        for (final entry in [(false, '升序'), (true, '降序')])
                          MenuItemButton(
                              trailingIcon: value.descending == entry.$1
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              onPressed: () => onChanged(
                                  value.copyWith(descending: entry.$1)),
                              child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: appSortMenuLabelMaxWidth),
                                  child: Text(ui(entry.$2)))),
                      ],
                      child: Text(ui('排序'))),
                  MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.dashboard_customize_outlined),
                      trailingIcon: value.autoFill
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onPressed: value.shape == CategoryCoverShape.circle
                          ? null
                          : () => onChanged(
                              value.copyWith(autoFill: !value.autoFill)),
                      child: Text(ui('自动填充空隙'))),
                ],
                builder: (context, controller, _) => IconButton.outlined(
                    tooltip: ui('分类显示选项'),
                    style: appToolbarControlStyle(context, iconOnly: true),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    icon: const Icon(Icons.tune_rounded)))
          ]);
        }

        final labelStyle = DefaultTextStyle.of(context)
            .style
            .merge(theme.textTheme.labelLarge)
            .copyWith(fontWeight: FontWeight.w600);
        final measureStyle = labelStyle.copyWith(fontWeight: FontWeight.w700);
        final painter = TextPainter(
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1);
        double measurePill(String text) {
          painter.text = TextSpan(text: text, style: measureStyle);
          painter.layout();
          return math.max(44.0, painter.width.ceilToDouble() + 60.0);
        }

        final circleLabel = ui('圆形');
        final rectLabel = ui('矩形');
        final titleLabel = ui('标题');
        final detailsLabel = ui('说明');
        final circleWidth = measurePill(circleLabel);
        final rectWidth = measurePill(rectLabel);
        final titleWidth = measurePill(titleLabel);
        final detailsWidth = measurePill(detailsLabel);
        final sortMethodLabel = ui(switch (value.sort) {
          CategorySort.standard => '默认顺序',
          CategorySort.name => '名称',
          CategorySort.count => '歌曲数量',
          CategorySort.custom => '自定义',
        });
        final sortFullLabel =
            value.sort == CategorySort.name || value.sort == CategorySort.count
                ? '$sortMethodLabel · ${ui(value.descending ? '降序' : '升序')}'
                : sortMethodLabel;
        painter.text = TextSpan(text: sortFullLabel, style: labelStyle);
        painter.layout();
        final sortNaturalWidth =
            (painter.width.ceilToDouble() + 78.0).clamp(96.0, 280.0);
        painter.dispose();

        final shapeGroupWidth = circleWidth + rectWidth + 10.0;
        final captionGroupWidth = titleWidth + detailsWidth + 10.0;
        final controlsLabeledWidth = shapeGroupWidth +
            8.0 +
            captionGroupWidth +
            8.0 +
            sortNaturalWidth +
            8.0 +
            44.0;
        final labels = constraints.maxWidth >= controlsLabeledWidth;
        final inline = constraints.maxWidth >= controlsLabeledWidth + 220.0;
        final height = appToolbarControlHeight(context);
        final innerHeight = math.max(36.0, height - 8);
        final reduced = appToolbarReduceMotion(context);
        final duration = reduced ? Duration.zero : AppMotion.quick;
        final autoFillEnabled = value.shape != CategoryCoverShape.circle;
        final autoFillActive = autoFillEnabled && value.autoFill;

        final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSegmentedControl<CategoryCoverShape>(
                  key: const ValueKey('category-cover-shape'),
                  value: value.shape,
                  showLabels: labels,
                  segmentWidth: labels ? null : 42.0,
                  semanticLabel: ui('分类封面'),
                  onChanged: (shape) => onChanged(value.copyWith(shape: shape)),
                  options: [
                    AppSegmentOption(
                        value: CategoryCoverShape.circle,
                        label: circleLabel,
                        icon: Icons.circle_outlined),
                    AppSegmentOption(
                        value: CategoryCoverShape.rounded,
                        label: rectLabel,
                        icon: Icons.crop_square_rounded),
                  ]),
              DecoratedBox(
                key: const ValueKey('category-caption-options'),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppShape.pillRadius,
                  border: Border.all(
                    color: scheme.outlineVariant
                        .withValues(alpha: isDark ? .38 : .46),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CaptionTogglePill(
                        label: titleLabel,
                        tooltip: ui('显示封面标题'),
                        icon: Icons.title_rounded,
                        selected: value.showTitle,
                        showLabel: labels,
                        width: labels ? null : 42.0,
                        minWidth: labels ? titleWidth : null,
                        height: innerHeight,
                        duration: duration,
                        textStyle: labelStyle,
                        onTap: () => onChanged(
                            value.copyWith(showTitle: !value.showTitle)),
                      ),
                      const SizedBox(width: 2),
                      _CaptionTogglePill(
                        label: detailsLabel,
                        tooltip: ui('显示数量与来源'),
                        icon: Icons.info_outline_rounded,
                        selected: value.showDetails,
                        showLabel: labels,
                        width: labels ? null : 42.0,
                        minWidth: labels ? detailsWidth : null,
                        height: innerHeight,
                        duration: duration,
                        textStyle: labelStyle,
                        onTap: () => onChanged(
                            value.copyWith(showDetails: !value.showDetails)),
                      ),
                    ],
                  ),
                ),
              ),
              AppSortButton<CategorySort>(
                  key: const ValueKey('category-sort'),
                  value: value.sort,
                  maxWidth: labels ? 280 : 44,
                  direction: value.sort == CategorySort.name ||
                          value.sort == CategorySort.count
                      ? (value.descending
                          ? SortDirection.descending
                          : SortDirection.ascending)
                      : null,
                  onDirectionChanged: (direction) => onChanged(value.copyWith(
                      descending: direction == SortDirection.descending)),
                  onChanged: (sort) => onChanged(value.copyWith(sort: sort)),
                  options: [
                    AppSortOption(
                        value: CategorySort.standard,
                        label: ui('默认顺序'),
                        icon: Icons.sort_rounded),
                    AppSortOption(
                        value: CategorySort.name,
                        label: ui('名称'),
                        icon: Icons.sort_by_alpha_rounded),
                    AppSortOption(
                        value: CategorySort.count,
                        label: ui('歌曲数量'),
                        icon: Icons.library_music_outlined),
                    AppSortOption(
                        value: CategorySort.custom,
                        label: ui('自定义'),
                        icon: Icons.drag_indicator_rounded),
                  ]),
              IconButton.outlined(
                  key: const ValueKey('category-auto-fill'),
                  tooltip: ui('自动填充空隙'),
                  isSelected: autoFillActive,
                  style: appToolbarControlStyle(context, iconOnly: true)
                      .copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: .24),
                        );
                      }
                      if (autoFillActive) {
                        return BorderSide(
                          color: scheme.primary.withValues(alpha: .28),
                        );
                      }
                      return BorderSide(
                        color: scheme.outlineVariant
                            .withValues(alpha: isDark ? .38 : .46),
                      );
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return scheme.onSurface.withValues(alpha: .38);
                      }
                      return autoFillActive
                          ? scheme.onPrimaryContainer
                          : scheme.primary;
                    }),
                    iconColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return scheme.onSurface.withValues(alpha: .38);
                      }
                      return autoFillActive
                          ? scheme.onPrimaryContainer
                          : scheme.primary;
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return scheme.surfaceContainerLow
                            .withValues(alpha: .42);
                      }
                      if (autoFillActive) return scheme.primaryContainer;
                      if (states.contains(WidgetState.hovered)) {
                        return scheme.secondaryContainer
                            .withValues(alpha: isDark ? .42 : .55);
                      }
                      return scheme.surfaceContainerLow;
                    }),
                  ),
                  onPressed: !autoFillEnabled
                      ? null
                      : () =>
                          onChanged(value.copyWith(autoFill: !value.autoFill)),
                  icon: const Icon(Icons.dashboard_customize_outlined)),
            ]);
        return inline
            ? Row(children: [
                Expanded(child: search),
                const SizedBox(width: 10),
                controls
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [search, const SizedBox(height: 8), controls]);
      }),
    );
  }
}

class _CaptionTogglePill extends StatefulWidget {
  const _CaptionTogglePill({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.showLabel,
    required this.width,
    required this.minWidth,
    required this.height,
    required this.duration,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final bool showLabel;
  final double? width;
  final double? minWidth;
  final double height;
  final Duration duration;
  final TextStyle textStyle;
  final VoidCallback onTap;

  @override
  State<_CaptionTogglePill> createState() => _CaptionTogglePillState();
}

class _CaptionTogglePillState extends State<_CaptionTogglePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final Color bgColor;
    final Color fgColor;
    final Color iconColor;
    if (widget.selected) {
      bgColor = scheme.primaryContainer;
      fgColor = scheme.onPrimaryContainer;
      iconColor = scheme.onPrimaryContainer;
    } else if (_hovered) {
      bgColor =
          scheme.secondaryContainer.withValues(alpha: isDark ? .40 : .52);
      fgColor = scheme.onSurface;
      iconColor = scheme.primary;
    } else {
      bgColor = Colors.transparent;
      fgColor = scheme.onSurfaceVariant;
      iconColor = scheme.primary;
    }

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.tooltip,
        child: AnimatedContainer(
          duration: widget.duration,
          curve: AppMotion.standardCurve,
          decoration: ShapeDecoration(
            color: bgColor,
            shape: AppShape.pill,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: AppShape.pill,
              onTap: widget.onTap,
              onHover: (hovering) {
                if (_hovered != hovering) {
                  setState(() => _hovered = hovering);
                }
              },
              splashColor: scheme.primary.withValues(alpha: .10),
              highlightColor: scheme.primary.withValues(alpha: .06),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: widget.width ?? widget.minWidth ?? 0.0,
                  maxWidth: widget.width ?? double.infinity,
                  minHeight: widget.height,
                  maxHeight: widget.height,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: widget.showLabel ? 14 : 0),
                  child: widget.showLabel
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(widget.icon,
                                size: appToolbarIconSize, color: iconColor),
                            const SizedBox(width: appToolbarLabelGap),
                            Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              style: widget.textStyle.copyWith(
                                color: fgColor,
                                fontWeight: widget.selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Icon(widget.icon,
                              size: appToolbarIconSize, color: iconColor),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
