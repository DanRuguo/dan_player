import 'dart:math' as math;

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

const _distributionColors = [
  Color(0xff168c83),
  Color(0xff4482d6),
  Color(0xff9c6ade),
  Color(0xffd68b35),
  Color(0xff89949e),
  Color(0xffc96788),
  Color(0xff668644),
  Color(0xff5c7f99),
];

Color statisticsDistributionColor(BuildContext context, int index) =>
    Color.lerp(
      _distributionColors[index % _distributionColors.length],
      Theme.of(context).colorScheme.primary,
      .4,
    )!;

double _statisticsTextScale(BuildContext context) =>
    math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);

/// Only the bounded metric/distribution cards use intrinsic row sizing.
/// Natural text/legend height determines the row height; there is no clipping
/// or fixed-height scroll area when accessibility text sizes grow.
class StatisticsEqualHeightRows extends StatefulWidget {
  const StatisticsEqualHeightRows({
    super.key,
    required this.children,
    required this.columns,
    this.spacing = 16,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  State<StatisticsEqualHeightRows> createState() =>
      _StatisticsEqualHeightRowsState();
}

class _StatisticsEqualHeightRowsState extends State<StatisticsEqualHeightRows> {
  final _slots = <GlobalKey>[];

  Widget _child(int index) =>
      KeyedSubtree(key: _slots[index], child: widget.children[index]);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    // Only these bounded card/legend slots survive a responsive column change;
    // original child keys still determine identity within each slot.
    while (_slots.length < widget.children.length) {
      _slots.add(GlobalKey());
    }
    if (_slots.length > widget.children.length) {
      _slots.removeRange(widget.children.length, _slots.length);
    }
    final columns = widget.columns;
    final spacing = widget.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0;
            start < widget.children.length;
            start += columns) ...[
          if (start != 0) SizedBox(height: spacing),
          if (columns == 1)
            _child(start)
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column != 0) SizedBox(width: spacing),
                    Expanded(
                      child: start + column < widget.children.length
                          ? _child(start + column)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class StatisticsDistributionSlice {
  const StatisticsDistributionSlice({
    required this.label,
    required this.value,
    required this.amount,
    required this.detail,
    required this.color,
    this.tooltip,
    this.percentage,
    this.comparisonValue,
  });

  final String label;
  final int value;
  final String amount;
  final String detail;
  final Color color;
  final String? tooltip;
  final double? percentage;
  final double? comparisonValue;
}

class StatisticsDistributionView extends StatelessWidget {
  const StatisticsDistributionView({
    super.key,
    required this.chartId,
    required this.availableWidth,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
  });

  final String chartId;
  final double availableWidth;
  final List<StatisticsDistributionSlice> slices;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final total = slices.fold(0, (sum, item) => sum + item.value);
    final textScale = _statisticsTextScale(context);
    final side = math.min(
      (slices.length <= 2 ? 132.0 : 176.0) * textScale,
      math.max(1.0, availableWidth),
    );
    final horizontal = availableWidth / textScale >= 510;
    final legendWidth =
        horizontal ? availableWidth - side - 24 : availableWidth;
    final legendColumns =
        slices.length > 4 && legendWidth / textScale >= 720 ? 2 : 1;
    final rowWidth = (legendWidth - (legendColumns - 1) * 16) / legendColumns;
    final compactLegend = rowWidth / textScale < 340;
    final chart = Semantics(
      label:
          '${centerLabel.isEmpty ? '' : '$centerLabel '}$centerValue。${slices.map((item) => '${item.label} ${item.amount}').join('，')}',
      excludeSemantics: true,
      child: SizedBox.square(
        key: ValueKey('statistics-chart-$chartId'),
        dimension: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DonutChartPainter(
                  slices: slices,
                  background:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: math.max(1.0, side - 64),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerValue,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      if (centerLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          centerLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final legend = KeyedSubtree(
      key: ValueKey('statistics-legend-$chartId'),
      child: StatisticsEqualHeightRows(
        columns: legendColumns,
        spacing: legendColumns == 1 ? 0 : 16,
        children: [
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(ui("暂无分类数据"), textAlign: TextAlign.center),
            ),
          for (var index = 0; index < slices.length; index++)
            _DistributionComparisonRow(
              key: ValueKey('statistics-comparison-$chartId-$index'),
              slice: slices[index],
              fraction: (slices[index].percentage ??
                      (total == 0 ? 0.0 : 100 * slices[index].value / total)) /
                  100,
              compact: compactLegend,
            ),
        ],
      ),
    );
    return horizontal
        ? Row(
            children: [
              chart,
              const SizedBox(width: 24),
              Expanded(child: legend),
            ],
          )
        : Column(
            children: [
              chart,
              const SizedBox(height: 16),
              legend,
            ],
          );
  }
}

/// The ring and each comparison bar share the same denominator and colour.
/// Long folder names keep a full-path tooltip; counts and percentages have
/// their own line when text scaling leaves insufficient room beside the name.
class _DistributionComparisonRow extends StatelessWidget {
  const _DistributionComparisonRow({
    super.key,
    required this.slice,
    required this.fraction,
    required this.compact,
  });

  final StatisticsDistributionSlice slice;
  final double fraction;
  final bool compact;

  Widget _bar(BuildContext context, double value, {bool secondary = false}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: secondary ? 5 : 8,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(
                  color: secondary
                      ? slice.color.withValues(alpha: .58)
                      : slice.color,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = '${(fraction * 100).toStringAsFixed(1)}%';
    final label = Tooltip(
      message: slice.tooltip ?? slice.label,
      child: Text(slice.label, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
    final amount = Wrap(
      spacing: 12,
      runSpacing: 2,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(slice.amount,
            style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        Text(percentage, style: theme.textTheme.bodySmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: slice.color, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 10),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(child: label),
            if (!compact) ...[
              const SizedBox(width: 16),
              Expanded(child: amount),
            ],
          ]),
          if (compact) ...[
            const SizedBox(height: 4),
            amount,
          ],
          const SizedBox(height: 7),
          Semantics(
            label: '${slice.label} ${slice.amount} $percentage',
            child: _bar(context, fraction),
          ),
          if (slice.detail.isNotEmpty || slice.comparisonValue != null) ...[
            const SizedBox(height: 5),
            if (slice.comparisonValue == null)
              Text(slice.detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Tooltip(
                message: ui("源文件数量"),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        if (slice.detail.isNotEmpty)
                          Text(slice.detail, style: theme.textTheme.bodySmall),
                        Text(
                            '${(slice.comparisonValue! * 100).toStringAsFixed(1)}%',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      label: '${ui("源文件数量")} ${slice.detail}',
                      child: _bar(context, slice.comparisonValue!,
                          secondary: true),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({required this.slices, required this.background});
  final List<StatisticsDistributionSlice> slices;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 22.0;
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, size.shortestSide / 2 - strokeWidth / 2 - 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = background;
    canvas.drawCircle(center, radius, paint);
    final total = slices.fold(0, (sum, item) => sum + item.value);
    if (total == 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = 2 * math.pi * slice.value / total;
      canvas.drawArc(rect, start, sweep, false, paint..color = slice.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.background != background;
}
