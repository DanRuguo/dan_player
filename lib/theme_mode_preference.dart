import 'package:flutter/material.dart';

/// One persisted choice, with compatibility for the old independent startup
/// switch and bool/int dark-mode fields. System brightness is never persisted
/// as the user's explicit choice.
abstract final class ThemeModePreference {
  static ThemeMode decode(Map settings) {
    final explicit = settings['AppearanceThemeMode'];
    for (final mode in ThemeMode.values) {
      if (explicit == mode.name) return mode;
    }
    final follow = settings['UseSystemThemeMode'];
    if (follow != false && follow != 0) return ThemeMode.system;
    final oldMode = settings['ThemeMode'];
    return oldMode == true || oldMode == 1 || oldMode == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  static Map<String, Object> encode(ThemeMode mode) => {
        'AppearanceThemeMode': mode.name,
        // Keep older versions able to read this settings file on downgrade.
        'UseSystemThemeMode': mode == ThemeMode.system,
        'ThemeMode': mode == ThemeMode.dark,
      };
}
