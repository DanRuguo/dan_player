import 'dart:math' as math;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// A short, explicit set of alternatives. Values remain domain identifiers;
/// callers supply translated labels, never translated persistence keys.
class AppSegmentOption<T> {
  const AppSegmentOption({
    required this.value,
    required this.label,
    required this.icon,
    this.key,
  });

  final T value;
  final String label;
  final IconData icon;
  final Key? key;
}

/// Displays the alternatives directly when their actual font metrics fit.
/// Narrow hosts use a menu of the same choices, not an ambiguous cycle button.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.maxWidth,
    this.compact = false,
    this.semanticLabel,
  }) : assert(options.length >= 2);

  final T value;
  final List<AppSegmentOption<T>> options;
  final ValueChanged<T>? onChanged;
  final double? maxWidth;
  final bool compact;
  final String? semanticLabel;

  void _select(T next) {
    if (next != value && options.any((option) => option.value == next)) {
      onChanged?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.labelLarge!;
    final selected = options.firstWhere((option) => option.value == value,
        orElse: () => options.first);
    final reduced = appToolbarReduceMotion(context);
    // Measure once per build (2–3 short strings), not on every animation tick.
    // Leave room for the outline, horizontal padding and icon/label spacing.
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widestSegment = 44.0;
    for (final option in options) {
      painter.text = TextSpan(text: option.label, style: textStyle);
      painter.layout();
      widestSegment =
          math.max(widestSegment, painter.width.ceilToDouble() + 56);
    }
    painter.dispose();
    // Material gives each segment the widest child's intrinsic width.
    // Summing unlike labels would underestimate e.g. "List / Circular covers".
    final expandedWidth = widestSegment * options.length + 4;
    final baseStyle = appToolbarControlStyle(context, reduced: reduced);
    final controlHeight = baseStyle.minimumSize!.resolve({})!.height;
    final style = baseStyle.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.primary),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          !states.contains(WidgetState.disabled) &&
                  states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final available = math.max(
          0.0,
          math.min(
              maxWidth ?? double.infinity,
              constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : math.max(44.0, MediaQuery.sizeOf(context).width - 48)));
      if (!compact && expandedWidth <= available) {
        // SegmentedButton lays out the inner TextButtons at their intrinsic
        // height, independently of a taller outer minHeight. Put the minimum
        // in the label instead, so fill, hit area and contents grow together.
        final minimumLabelHeight =
            math.max(controlHeight, constraints.minHeight) -
                appToolbarPadding.vertical;
        return Semantics(
          label: semanticLabel,
          child: SegmentedButton<T>(
            style: style,
            showSelectedIcon: false,
            segments: [
              for (final option in options)
                ButtonSegment<T>(
                  value: option.value,
                  // The built-in icon path replaces our symmetric padding
                  // with TextButton.icon's asymmetric, scale-dependent one.
                  // A single label group retains the intended center/spacing.
                  label: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minimumLabelHeight),
                    child: AppToolbarLabel(
                        label: option.label,
                        icon: option.icon,
                        labelKey: option.key),
                  ),
                ),
            ],
            selected: {selected.value},
            onSelectionChanged:
                onChanged == null ? null : (values) => _select(values.single),
          ),
        );
      }
      final popupWidth = math.max(
          44.0, math.min(360.0, MediaQuery.sizeOf(context).width - 32));
      return MenuAnchor(
        style: MenuStyle(
          shape: const WidgetStatePropertyAll(AppShape.control),
          maximumSize:
              WidgetStatePropertyAll(Size(popupWidth, double.infinity)),
        ),
        menuChildren: [
          for (final option in options)
            MenuItemButton(
              key: option.key,
              leadingIcon: Icon(option.icon),
              trailingIcon: option.value == selected.value
                  ? const Icon(Icons.check)
                  : null,
              onPressed: onChanged == null ? null : () => _select(option.value),
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(textStyle),
                foregroundColor: style.foregroundColor,
              ),
              child: Text(option.label,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
        builder: (context, controller, child) {
          void toggle() =>
              controller.isOpen ? controller.close() : controller.open();
          final canShowLabel = available >=
              180 *
                  math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);
          final tooltip = semanticLabel == null
              ? selected.label
              : '$semanticLabel · ${selected.label}';
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: available),
            child: canShowLabel
                ? Tooltip(
                    message: tooltip,
                    child: OutlinedButton(
                      style: baseStyle.copyWith(
                          foregroundColor: style.foregroundColor),
                      onPressed: onChanged == null ? null : toggle,
                      child: AppToolbarLabel(
                          label: selected.label,
                          icon: selected.icon,
                          trailing: const Icon(Icons.expand_more, size: 18)),
                    ),
                  )
                : IconButton.outlined(
                    tooltip: tooltip,
                    style: appToolbarControlStyle(context,
                            reduced: reduced, iconOnly: true)
                        .copyWith(foregroundColor: style.foregroundColor),
                    onPressed: onChanged == null ? null : toggle,
                    icon: Icon(selected.icon),
                  ),
          );
        },
      );
    });
  }
}
