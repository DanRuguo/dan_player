import 'app_fonts.dart';
import 'app_input_theme.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/app_motion.dart';

abstract final class DesktopLyricTypography {
  static const String fontFamily = danEmbeddedFontFamily;
  static const List<String> fontFamilyFallback = danFontFamilyFallback;

  static ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );

    return ThemeData(
      inputDecorationTheme: appInputTheme(scheme),
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      colorScheme: scheme,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: AppMotion.quick,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return scheme.primary.withValues(alpha: 0.10);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        ),
      ),
    );
  }
}
