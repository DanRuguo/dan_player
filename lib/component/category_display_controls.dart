import 'dart:math' as math;
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
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
      final compact =
          MediaQuery.sizeOf(context).height < 650 && constraints.maxWidth < 840;
      final inline = compact ||
          constraints.maxWidth >= 840 &&
              MediaQuery.textScalerOf(context).scale(14) < 20;
      final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppSegmentedControl<CategoryCoverShape>(
              key: const ValueKey('category-cover-shape'),
              value: value.shape,
              compact: compact,
              maxWidth: compact
                  ? 44
                  : inline
                      ? math.min(360, constraints.maxWidth * .36)
                      : math.min(260, constraints.maxWidth),
              semanticLabel: ui('分类封面'),
              onChanged: (shape) => onChanged(value.copyWith(shape: shape)),
              options: [
                AppSegmentOption(
                    value: CategoryCoverShape.circle,
                    label: ui('圆形'),
                    icon: Icons.circle_outlined),
                AppSegmentOption(
                    value: CategoryCoverShape.rounded,
                    label: ui('圆角矩形'),
                    icon: Icons.crop_square),
              ],
            ),
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
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? scheme.onPrimaryContainer
                        : scheme.primary),
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? scheme.primaryContainer
                        : Colors.transparent),
              ),
              segments: [
                ButtonSegment(
                    value: 'title',
                    tooltip: ui('显示封面标题'),
                    label: compact
                        ? const Icon(Icons.title, size: 20)
                        : AppToolbarLabel(label: ui('标题'), icon: Icons.title)),
                ButtonSegment(
                    value: 'details',
                    tooltip: ui('显示数量与来源'),
                    label: compact
                        ? const Icon(Icons.info_outline, size: 20)
                        : AppToolbarLabel(
                            label: ui('说明'), icon: Icons.info_outline)),
              ],
            ),
          ]);
      return inline
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              controls
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 8), controls]);
    });
  }
}
