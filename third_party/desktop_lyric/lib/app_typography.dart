import 'package:flutter/material.dart';

abstract final class DesktopLyricTypography {
  static const String fontFamily = "DanPingFangSC";
  static const List<String> fontFamilyFallback = [
    fontFamily,
    ".PingFang SC Regular",
    "PingFang SC Regular",
    "PingFang SC",
    "Noto Sans SC",
    "Noto Sans CJK SC",
    "Microsoft YaHei UI",
    "Microsoft YaHei",
    "SimHei",
  ];

  static ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      colorScheme: scheme,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
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
