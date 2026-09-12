import 'package:dan_player/component/app_menu_anchor.dart';
import 'dart:math' as math;
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
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
                          : Icons.crop_square),
                      trailingIcon:
                          value.shape == shape ? const Icon(Icons.check) : null,
                      onPressed: () => onChanged(value.copyWith(shape: shape)),
                      child: Text(ui(
                          shape == CategoryCoverShape.circle ? '圆形' : '矩形'))),
                const Divider(),
                MenuItemButton(
                    leadingIcon: const Icon(Icons.title),
                    trailingIcon:
                        value.showTitle ? const Icon(Icons.check) : null,
                    onPressed: () =>
                        onChanged(value.copyWith(showTitle: !value.showTitle)),
                    child: Text(ui('显示封面标题'))),
                MenuItemButton(
                    leadingIcon: const Icon(Icons.info_outline),
                    trailingIcon:
                        value.showDetails ? const Icon(Icons.check) : null,
                    onPressed: () => onChanged(
                        value.copyWith(showDetails: !value.showDetails)),
                    child: Text(ui('显示数量与来源'))),
                SubmenuButton(
                    leadingIcon: const Icon(Icons.sort),
                    menuChildren: [
                      for (final entry in [
                        (CategorySort.standard, '默认顺序'),
                        (CategorySort.name, '名称'),
                        (CategorySort.count, '歌曲数量'),
                        (CategorySort.custom, '自定义')
                      ])
                        MenuItemButton(
                            trailingIcon: value.sort == entry.$1
                                ? const Icon(Icons.check)
                                : null,
                            onPressed: () =>
                                onChanged(value.copyWith(sort: entry.$1)),
                            child: Text(ui(entry.$2))),
                      const Divider(),
                      for (final entry in [(false, '升序'), (true, '降序')])
                        MenuItemButton(
                            trailingIcon: value.descending == entry.$1
                                ? const Icon(Icons.check)
                                : null,
                            onPressed: () =>
                                onChanged(value.copyWith(descending: entry.$1)),
                            child: Text(ui(entry.$2))),
                    ],
                    child: Text(ui('排序'))),
                MenuItemButton(
                    leadingIcon: const Icon(Icons.dashboard_customize_outlined),
                    trailingIcon:
                        value.autoFill ? const Icon(Icons.check) : null,
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
                  icon: const Icon(Icons.tune)))
        ]);
      }

      final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1);
      var segmentWidth = 44.0;
      for (final label in ['圆形', '矩形', '标题', '说明']) {
        painter.text = TextSpan(
            text: ui(label), style: Theme.of(context).textTheme.labelLarge);
        painter.layout();
        segmentWidth =
            math.max(segmentWidth, painter.width.ceilToDouble() + 56);
      }
      painter.dispose();
      final inline = constraints.maxWidth >= segmentWidth * 4 + 360;
      final labels = constraints.maxWidth >= segmentWidth * 4 + 170;
      final width = labels ? segmentWidth : 44.0;
      final height = appToolbarControlHeight(context);
      final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppSegmentedControl<CategoryCoverShape>(
                key: const ValueKey('category-cover-shape'),
                value: value.shape,
                showLabels: labels,
                segmentWidth: width,
                maxWidth: width * 2 + 8,
                semanticLabel: ui('分类封面'),
                onChanged: (shape) => onChanged(value.copyWith(shape: shape)),
                options: [
                  AppSegmentOption(
                      value: CategoryCoverShape.circle,
                      label: ui('圆形'),
                      icon: Icons.circle_outlined),
                  AppSegmentOption(
                      value: CategoryCoverShape.rounded,
                      label: ui('矩形'),
                      icon: Icons.crop_square),
                ]),
            SegmentedButton<String>(
                key: const ValueKey('category-caption-options'),
                emptySelectionAllowed: true,
                multiSelectionEnabled: true,
                showSelectedIcon: false,
                selected: {
                  if (value.showTitle) 'title',
                  if (value.showDetails) 'details'
                },
                onSelectionChanged: (selected) => onChanged(value.copyWith(
                    showTitle: selected.contains('title'),
                    showDetails: selected.contains('details'))),
                style: appToolbarControlStyle(context).copyWith(
                    fixedSize: WidgetStatePropertyAll(Size(width, height)),
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? scheme.onPrimaryContainer
                            : scheme.primary),
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? scheme.primaryContainer
                            : Colors.transparent)),
                segments: [
                  for (final entry in [
                    ('title', '标题', '显示封面标题', Icons.title),
                    ('details', '说明', '显示数量与来源', Icons.info_outline)
                  ])
                    ButtonSegment(
                        value: entry.$1,
                        tooltip: ui(entry.$3),
                        label: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: height - appToolbarPadding.vertical),
                            child: labels
                                ? AppToolbarLabel(
                                    label: ui(entry.$2), icon: entry.$4)
                                : Icon(entry.$4, size: 20)))
                ]),
            AppSortButton<CategorySort>(
                key: const ValueKey('category-sort'),
                value: value.sort,
                maxWidth: labels ? 150 : 44,
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
                      icon: Icons.sort),
                  AppSortOption(
                      value: CategorySort.name,
                      label: ui('名称'),
                      icon: Icons.sort_by_alpha),
                  AppSortOption(
                      value: CategorySort.count,
                      label: ui('歌曲数量'),
                      icon: Icons.library_music_outlined),
                  AppSortOption(
                      value: CategorySort.custom,
                      label: ui('自定义'),
                      icon: Icons.drag_indicator),
                ]),
            IconButton.outlined(
                key: const ValueKey('category-auto-fill'),
                tooltip: ui('自动填充空隙'),
                isSelected: value.autoFill,
                style: appToolbarControlStyle(context, iconOnly: true).copyWith(
                    foregroundColor: WidgetStatePropertyAll(value.autoFill
                        ? scheme.onPrimaryContainer
                        : scheme.primary),
                    backgroundColor: WidgetStatePropertyAll(value.autoFill
                        ? scheme.primaryContainer
                        : Colors.transparent)),
                onPressed: value.shape == CategoryCoverShape.circle
                    ? null
                    : () =>
                        onChanged(value.copyWith(autoFill: !value.autoFill)),
                icon: const Icon(Icons.dashboard_customize_outlined)),
          ]);
      return inline
          ? Row(children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              controls
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 8), controls]);
    });
  }
}
