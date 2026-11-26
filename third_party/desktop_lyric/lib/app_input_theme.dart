import 'package:flutter/material.dart';

/// Shared by the main player and auxiliary lyric windows.
InputDecorationThemeData appInputTheme(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  final restOutline =
      scheme.outlineVariant.withValues(alpha: isDark ? .42 : .52);
  return InputDecorationThemeData(
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    hoverColor:
        scheme.secondaryContainer.withValues(alpha: isDark ? .22 : .28),
    hintStyle: TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: .76),
      fontWeight: FontWeight.w400,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border(restOutline),
    enabledBorder: border(restOutline),
    focusedBorder: border(scheme.primary, 1.8),
    disabledBorder: border(scheme.outlineVariant.withValues(alpha: .26)),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 1.8),
    prefixIconColor: scheme.primary,
    suffixIconColor: scheme.primary,
  );
}
