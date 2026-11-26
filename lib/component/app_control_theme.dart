import 'package:desktop_lyric/app_input_theme.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';

/// Complete Material 3 Expressive control styles and overlay typography.
/// Tooltip uses its supplied style directly, so a color-only style would lose
/// the application's chosen font family/fallbacks even though ordinary Text
/// widgets inherit them correctly.
ThemeData applyAppControlTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  final label = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w600,
  );
  final menuLabel = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w500,
  );
  final segmentStyle = theme.segmentedButtonTheme.style ?? const ButtonStyle();
  final inputTheme = appInputTheme(scheme);
  return theme.copyWith(
    inputDecorationTheme: inputTheme,
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: inputTheme,
      textStyle: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      menuStyle: MenuStyle(
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(
          scheme.shadow.withValues(alpha: .22),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: .52)),
        ),
        shape: const WidgetStatePropertyAll(AppShape.surface),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest.withValues(alpha: .48),
      borderRadius: AppShape.pillRadius,
      linearMinHeight: 6,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: (theme.menuButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        textStyle: WidgetStatePropertyAll(menuLabel),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.primary),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.pressed)) {
            return scheme.secondaryContainer.withValues(alpha: .78);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return scheme.secondaryContainer
                .withValues(alpha: isDark ? .48 : .62);
          }
          return Colors.transparent;
        }),
        animationDuration: AppMotion.quick,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        textStyle: WidgetStatePropertyAll(label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        animationDuration: AppMotion.quick,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        textStyle: WidgetStatePropertyAll(label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .26),
            );
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: scheme.primary.withValues(alpha: .40));
          }
          return BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? .40 : .48),
          );
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.surfaceContainerLow.withValues(alpha: .36);
          }
          if (states.contains(WidgetState.pressed)) {
            return scheme.secondaryContainer.withValues(alpha: .68);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.secondaryContainer
                .withValues(alpha: isDark ? .38 : .48);
          }
          return scheme.surfaceContainerLow.withValues(alpha: .72);
        }),
        animationDuration: AppMotion.quick,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        textStyle: WidgetStatePropertyAll(label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        elevation: const WidgetStatePropertyAll(0),
        animationDuration: AppMotion.quick,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        textStyle: WidgetStatePropertyAll(label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .12)
                : scheme.secondaryContainer),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.onSecondaryContainer),
        animationDuration: AppMotion.quick,
      ),
    ),
    // Match ordinary icon actions to TextButton actions (A–B, playback rate).
    // Filled controls supply their paired foreground locally for contrast.
    iconButtonTheme: IconButtonThemeData(
      style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        animationDuration: AppMotion.quick,
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.primary),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Icon(
            Icons.check_rounded,
            size: 16,
            color: states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.primary,
          );
        }
        return null;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: .12);
        }
        return scheme.outline.withValues(alpha: .52);
      }),
      trackOutlineWidth: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? 0.0 : 1.5,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: scheme.outline.withValues(alpha: .72), width: 1.6),
    ),
    chipTheme: theme.chipTheme.copyWith(
      shape: AppShape.pill,
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
      secondarySelectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      side: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: isDark ? .38 : .46),
      ),
      labelStyle: menuLabel.copyWith(color: scheme.onSurface),
      secondaryLabelStyle: label.copyWith(color: scheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      trackHeight: 6,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 8,
        pressedElevation: 3,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        color: scheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: segmentStyle.copyWith(
        shape: const WidgetStatePropertyAll(AppShape.pill),
        animationDuration: AppMotion.quick,
        textStyle: WidgetStatePropertyAll(label),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? scheme.outlineVariant.withValues(alpha: .24)
                  : scheme.outlineVariant.withValues(alpha: .44),
            )),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: .38);
          }
          return states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          return states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow;
        }),
      ),
    ),
  );
}
