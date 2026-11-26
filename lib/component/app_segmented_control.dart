import 'dart:math' as math;

import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_motion.dart';
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

/// Displays the alternatives inside a Material 3 Expressive tonal capsule track
/// when their actual font metrics fit. Narrow hosts use a menu of the same
/// choices, not an ambiguous cycle button.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.maxWidth,
    this.compact = false,
    this.showLabels = true,
    this.wrapCompactLabel = false,
    this.semanticLabel,
    this.segmentWidth,
  }) : assert(options.length >= 2);

  final T value;
  final List<AppSegmentOption<T>> options;
  final ValueChanged<T>? onChanged;
  final double? maxWidth;
  final bool compact;

  /// Icon-only segments retain translated tooltips and accessibility labels.
  final bool showLabels;

  /// Keep the selected label readable in a narrow menu button, growing its
  /// height to fit rather than switching to the default icon-only fallback.
  final bool wrapCompactLabel;
  final String? semanticLabel;

  /// Align related groups using the same measured segment width.
  final double? segmentWidth;

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
    final isDark = scheme.brightness == Brightness.dark;
    final textStyle = DefaultTextStyle.of(context)
        .style
        .merge(theme.textTheme.labelLarge)
        .copyWith(fontWeight: FontWeight.w600);
    final measureStyle = textStyle.copyWith(fontWeight: FontWeight.w700);
    final selected = options.firstWhere((option) => option.value == value,
        orElse: () => options.first);
    final reduced = appToolbarReduceMotion(context);
    // Measure each option's natural width in the active language and font so
    // labels never get squeezed into an underestimated uniform box.
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    final optionWidths = <double>[
      for (final option in options)
        if (segmentWidth != null)
          segmentWidth!
        else if (!showLabels)
          42.0
        else
          () {
            painter.text = TextSpan(text: option.label, style: measureStyle);
            painter.layout();
            // 14px * 2 horizontal padding + 20px icon + 8px gap + 4px cushion.
            return math.max(44.0, painter.width.ceilToDouble() + 60.0);
          }(),
    ];
    painter.dispose();
    // Outer 3px padding on both sides + 1px border on both sides + 2px gaps.
    final expandedWidth = optionWidths.fold<double>(0, (a, b) => a + b) +
        (options.length - 1) * 2 +
        8;
    final baseStyle = appToolbarControlStyle(context, reduced: reduced);
    final controlHeight = baseStyle.minimumSize!.resolve({})!.height;

    return LayoutBuilder(builder: (context, constraints) {
      final available = math.max(
          0.0,
          math.min(
              maxWidth ?? double.infinity,
              constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : math.max(44.0, MediaQuery.sizeOf(context).width - 48)));
      if (!compact && expandedWidth <= available) {
        final totalHeight = math.max(controlHeight, constraints.minHeight);
        final innerHeight = math.max(36.0, totalHeight - 8);
        final duration = reduced ? Duration.zero : AppMotion.quick;
        final stretchTrack = constraints.hasBoundedWidth &&
            maxWidth == null &&
            constraints.minWidth > expandedWidth;
        return Semantics(
          container: true,
          label: semanticLabel,
          child: DecoratedBox(
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
                mainAxisSize:
                    stretchTrack ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  for (var index = 0; index < options.length; index++) ...[
                    if (index > 0) const SizedBox(width: 2),
                    if (stretchTrack)
                      Expanded(
                        flex: math.max(1, optionWidths[index].round()),
                        child: _ExpressiveSegmentPill(
                          key: options[index].key,
                          label: options[index].label,
                          icon: options[index].icon,
                          selected: options[index].value == selected.value,
                          enabled: onChanged != null,
                          showLabel: showLabels,
                          width: null,
                          minWidth: null,
                          constrainText: true,
                          height: innerHeight,
                          duration: duration,
                          textStyle: textStyle,
                          onTap: onChanged == null
                              ? null
                              : () => _select(options[index].value),
                        ),
                      )
                    else
                      _ExpressiveSegmentPill(
                        key: options[index].key,
                        label: options[index].label,
                        icon: options[index].icon,
                        selected: options[index].value == selected.value,
                        enabled: onChanged != null,
                        showLabel: showLabels,
                        width: segmentWidth ?? (showLabels ? null : 42.0),
                        minWidth: segmentWidth == null && showLabels
                            ? optionWidths[index]
                            : null,
                        constrainText: segmentWidth != null,
                        height: innerHeight,
                        duration: duration,
                        textStyle: textStyle,
                        onTap: onChanged == null
                            ? null
                            : () => _select(options[index].value),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      final popupWidth = math.max(
          44.0, math.min(360.0, MediaQuery.sizeOf(context).width - 32));
      return AppMenuAnchor(
        style: MenuStyle(
          shape: const WidgetStatePropertyAll(AppShape.surface),
          maximumSize:
              WidgetStatePropertyAll(Size(popupWidth, double.infinity)),
        ),
        menuChildren: [
          for (final option in options)
            MenuItemButton(
              key: option.key,
              leadingIcon: Icon(
                option.icon,
                color: option.value == selected.value
                    ? scheme.onSecondaryContainer
                    : scheme.primary,
              ),
              trailingIcon: option.value == selected.value
                  ? Icon(Icons.check_rounded,
                      size: 18, color: scheme.onSecondaryContainer)
                  : null,
              onPressed: onChanged == null ? null : () => _select(option.value),
              style: ButtonStyle(
                backgroundColor: option.value == selected.value
                    ? WidgetStatePropertyAll(
                        scheme.secondaryContainer.withValues(alpha: .72))
                    : null,
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return scheme.onSurface.withValues(alpha: .38);
                  }
                  return option.value == selected.value
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface;
                }),
                textStyle: WidgetStatePropertyAll(
                  textStyle.copyWith(
                    fontWeight: option.value == selected.value
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              child: wrapCompactLabel
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.max(1.0, popupWidth - 96)),
                      child: Text(option.label, softWrap: true))
                  : Text(option.label,
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
            child: canShowLabel || wrapCompactLabel
                ? Tooltip(
                    message: tooltip,
                    child: OutlinedButton(
                      style: baseStyle.copyWith(
                        maximumSize: wrapCompactLabel
                            ? const WidgetStatePropertyAll<Size?>(
                                Size(double.infinity, double.infinity))
                            : baseStyle.maximumSize,
                        fixedSize: const WidgetStatePropertyAll<Size?>(null),
                      ),
                      onPressed: onChanged == null ? null : toggle,
                      child: wrapCompactLabel
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(selected.icon, size: appToolbarIconSize),
                                const SizedBox(width: appToolbarLabelGap),
                                Flexible(
                                  child: Text(
                                    selected.label,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                  ),
                                ),
                                const SizedBox(width: appToolbarTrailingGap),
                                const Icon(Icons.expand_more_rounded, size: 18),
                              ],
                            )
                          : AppToolbarLabel(
                              label: selected.label,
                              icon: selected.icon,
                              trailing: const Icon(Icons.expand_more_rounded,
                                  size: 18)),
                    ),
                  )
                : IconButton.outlined(
                    tooltip: tooltip,
                    style: appToolbarControlStyle(context,
                        reduced: reduced, iconOnly: true),
                    onPressed: onChanged == null ? null : toggle,
                    icon: Icon(selected.icon),
                  ),
          );
        },
      );
    });
  }
}

class _ExpressiveSegmentPill extends StatefulWidget {
  const _ExpressiveSegmentPill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.showLabel,
    required this.width,
    required this.minWidth,
    required this.constrainText,
    required this.height,
    required this.duration,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final bool showLabel;
  final double? width;
  final double? minWidth;
  final bool constrainText;
  final double height;
  final Duration duration;
  final TextStyle textStyle;
  final VoidCallback? onTap;

  @override
  State<_ExpressiveSegmentPill> createState() => _ExpressiveSegmentPillState();
}

class _ExpressiveSegmentPillState extends State<_ExpressiveSegmentPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final Color bgColor;
    final Color fgColor;
    final Color iconColor;
    if (!widget.enabled) {
      bgColor = widget.selected
          ? scheme.onSurface.withValues(alpha: .10)
          : Colors.transparent;
      fgColor = scheme.onSurface.withValues(alpha: .38);
      iconColor = fgColor;
    } else if (widget.selected) {
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

    final labelWidget = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      overflow:
          widget.constrainText ? TextOverflow.ellipsis : TextOverflow.visible,
      style: widget.textStyle.copyWith(
        color: fgColor,
        fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.width ?? widget.minWidth ?? 0.0,
        maxWidth: widget.width ?? double.infinity,
        minHeight: widget.height,
        maxHeight: widget.height,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 14 : 0),
        child: widget.showLabel
            ? Row(
                mainAxisSize:
                    widget.constrainText ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: appToolbarIconSize, color: iconColor),
                  const SizedBox(width: appToolbarLabelGap),
                  if (widget.constrainText)
                    Flexible(child: labelWidget)
                  else
                    labelWidget,
                ],
              )
            : Center(
                child: Icon(
                  widget.icon,
                  size: appToolbarIconSize,
                  color: iconColor,
                  semanticLabel: widget.label,
                ),
              ),
      ),
    );

    if (!widget.showLabel) {
      content = Tooltip(message: widget.label, child: content);
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
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
            child: content,
          ),
        ),
      ),
    );
  }
}
