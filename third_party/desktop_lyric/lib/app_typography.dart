import 'package:flutter/material.dart';
import 'package:desktop_lyric/app_motion.dart';

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
    "Yu Gothic UI",
    "Malgun Gothic",
    "Segoe UI Symbol",
    "Segoe UI Emoji",
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
