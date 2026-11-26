import 'dart:math' as math;
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/foundation.dart';
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
      this.wrapLabel = false,
      this.valueColumnWidth,
      this.progress,
      this.showTooltip = true,
      this.showDetailSubtitle = false,
      this.animateBar = false});
  final bool wrapLabel;
  final String label, detail, valueLabel;
  final double value, maximum;
  final int? rank;
  final double? valueColumnWidth;

  /// An optional shared, finite reveal. Only the bar rebuilds on its ticks;
  /// text measurement and row layout keep their existing static path.
  final ValueListenable<double>? progress;

  /// Disabled for nonpainted layout templates, which need no pointer routes.
  final bool showTooltip;

  /// Displays [detail] as a secondary single-line caption below [label].
  final bool showDetailSubtitle;

  /// Smoothly interpolates bar width changes when switching ranking groups.
  final bool animateBar;

  static double measureValues(BuildContext context, Iterable<String> values) {
    final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context));
    var width = 0.0;
    for (final value in values) {
      painter.text = TextSpan(
          text: value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()]));
      painter.layout();
      width = math.max(width, painter.width.ceilToDouble());
    }
    painter.dispose();
    return width + 2;
  }

  Widget _buildRankBadge(BuildContext context, int rank, double scale) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, Color border) = switch (rank) {
      1 => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          scheme.primary.withValues(alpha: 0.55),
        ),
      2 => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          scheme.secondary.withValues(alpha: 0.45),
        ),
      3 => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          scheme.tertiary.withValues(alpha: 0.45),
        ),
      _ => (
          scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          scheme.onSurfaceVariant,
          Colors.transparent,
        ),
    };
    final badgeSize = (24.0 * scale).clamp(22.0, 34.0);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        width: badgeSize,
        height: badgeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: border == Colors.transparent ? null : Border.all(color: border),
        ),
        child: Text(
          '$rank',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = maximum.isFinite && maximum > 0 && value.isFinite
        ? (value / maximum).clamp(0.0, 1.0)
        : 0.0;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final numberWidth =
        valueColumnWidth ?? measureValues(context, [valueLabel]);
    final primaryTitleStyle = rank != null && rank! <= 3
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : null;
    final labelText = showTooltip
        ? Text(label,
            style: primaryTitleStyle,
            maxLines: wrapLabel ? null : 1,
            overflow: wrapLabel ? TextOverflow.visible : TextOverflow.ellipsis)
        : RichText(
            text: TextSpan(
                text: label,
                style: DefaultTextStyle.of(context)
                    .style
                    .merge(primaryTitleStyle)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: wrapLabel ? null : 1,
            overflow: wrapLabel ? TextOverflow.visible : TextOverflow.ellipsis);
    final labelBlock = showDetailSubtitle && detail.trim().isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              labelText,
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            ],
          )
        : labelText;
    final title = showTooltip
        ? Tooltip(message: '$label\n$detail', child: labelBlock)
        : labelBlock;
    final amountStyle = theme.textTheme.labelLarge?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()]);
    final amount = showTooltip
        ? Text(valueLabel, textAlign: TextAlign.right, style: amountStyle)
        : RichText(
            text: TextSpan(
                text: valueLabel,
                style: DefaultTextStyle.of(context).style.merge(amountStyle)),
            textAlign: TextAlign.right,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context));
    Widget paintBar(double currentFraction) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
            height: 8,
            child: ColoredBox(
                color: scheme.primary.withValues(alpha: .09),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                        widthFactor: currentFraction.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(
                            color: StatisticsMagnitudeColor.resolve(
                                scheme, fraction)))))));
    final Widget bar;
    if (progress != null) {
      bar = ValueListenableBuilder<double>(
        valueListenable: progress!,
        builder: (context, p, child) => paintBar(fraction * p.clamp(0.0, 1.0)),
      );
    } else if (animateBar) {
      final duration = AppMotion.duration(
        context,
        MotionKind.layout,
        AppMotion.standard,
      );
      bar = TweenAnimationBuilder<double>(
        tween: Tween<double>(end: fraction),
        duration: duration,
        curve: AppMotion.standardCurve,
        builder: (context, animatedFraction, _) => paintBar(animatedFraction),
      );
    } else {
      bar = paintBar(fraction);
    }
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final rankWidth =
              rank == null ? 0.0 : (24.0 * scale).clamp(22.0, 34.0) + 10.0;
          final width = constraints.maxWidth - rankWidth;
          final labelWidth = (width * .30).clamp(96 * scale, 250 * scale);
          final inline = width - labelWidth - numberWidth - 24 >= 90 * scale &&
              (!wrapLabel || width / scale >= 600);
          return Row(children: [
            if (rank != null) _buildRankBadge(context, rank!, scale),
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
