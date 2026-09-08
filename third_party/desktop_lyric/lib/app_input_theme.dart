import 'package:flutter/material.dart';

/// Shared by the main player and auxiliary lyric windows.
InputDecorationThemeData appInputTheme(ColorScheme scheme) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecorationThemeData(
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border(scheme.outlineVariant),
    enabledBorder: border(scheme.outlineVariant),
    focusedBorder: border(scheme.primary, 2),
    disabledBorder: border(scheme.outlineVariant.withValues(alpha: .45)),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 2),
    prefixIconColor: scheme.primary,
    suffixIconColor: scheme.primary,
  );
}
