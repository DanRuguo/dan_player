import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sequential scale derived from the current palette rather than fixed chart
/// colors. Larger values approach the full accent; smaller values use a softer
/// tertiary tone so magnitude remains visible in both light and dark themes.
abstract final class StatisticsMagnitudeColor {
  static Color resolve(ColorScheme scheme, double fraction) {
    final strength = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    final accent = Color.lerp(scheme.tertiary, scheme.primary, strength)!;
    return Color.lerp(scheme.surfaceContainerLow, accent, .5 + .5 * strength)!;
  }
}

/// A shared, theme-aware comparison row. Every bar in a group uses one scale.
class StatisticsBarRow extends StatelessWidget {
  const StatisticsBarRow(
      {super.key,
      required this.label,
      required this.detail,
      required this.valueLabel,
      required this.value,
      required this.maximum,
      this.rank,
      this.valueColumnWidth});
  final String label, detail, valueLabel;
  final double value, maximum;
  final int? rank;
  final double? valueColumnWidth;

  static double measureValues(BuildContext context, Iterable<String> values) {
    final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context));
    var width = 0.0;
    for (final value in values) {
      painter.text = TextSpan(
          text: value,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600));
      painter.layout();
      width = math.max(width, painter.width.ceilToDouble());
    }
    painter.dispose();
    return width + 2;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = maximum.isFinite && maximum > 0 && value.isFinite
        ? (value / maximum).clamp(0.0, 1.0)
        : 0.0;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final numberWidth =
        valueColumnWidth ?? measureValues(context, [valueLabel]);
    final title = Tooltip(
        message: '$label\n$detail',
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));
    final amount = Text(valueLabel,
        textAlign: TextAlign.right,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600));
    final bar = ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
            height: 8,
            child: ColoredBox(
                color: scheme.primary.withValues(alpha: .09),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                        widthFactor: fraction,
                        heightFactor: 1,
                        child: ColoredBox(
                            color: StatisticsMagnitudeColor.resolve(
                                scheme, fraction)))))));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final rankWidth = rank == null ? 0.0 : 28 * scale;
          final width = constraints.maxWidth - rankWidth;
          final labelWidth = (width * .24).clamp(90 * scale, 240 * scale);
          final inline = width - labelWidth - numberWidth - 24 >= 90 * scale;
          return Row(children: [
            if (rank != null)
              SizedBox(
                  width: rankWidth,
                  child:
                      Text('$rank', style: TextStyle(color: scheme.primary))),
            Expanded(
                child: inline
                    ? Row(children: [
                        SizedBox(width: labelWidth, child: title),
                        const SizedBox(width: 12),
                        Expanded(child: bar),
                        const SizedBox(width: 12),
                        SizedBox(width: numberWidth, child: amount),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            title,
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(child: bar),
                              const SizedBox(width: 12),
                              Flexible(child: amount)
                            ]),
                          ])),
          ]);
        }));
  }
}
