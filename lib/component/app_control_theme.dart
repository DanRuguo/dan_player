import 'package:flutter/material.dart';

/// Complete text styles for overlay controls. Tooltip uses its supplied style
/// directly, so a color-only style would lose the application's chosen font
/// family/fallbacks even though ordinary Text widgets inherit them correctly.
ThemeData applyAppControlTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  final label = theme.textTheme.labelLarge ?? const TextStyle();
  final segmentStyle = theme.segmentedButtonTheme.style ?? const ButtonStyle();
  return theme.copyWith(
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        color: scheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: segmentStyle.copyWith(
        textStyle: WidgetStatePropertyAll(label),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: .38);
          }
          return states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.primary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          return states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent;
        }),
      ),
    ),
  );
}
