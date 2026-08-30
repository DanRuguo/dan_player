import 'package:flutter/material.dart';

/// A foreground override for controls painted directly on the native backdrop.
/// It does not install a Theme: opaque pages and artwork keep their own colour
/// scheme, and selected navigation capsules retain their paired theme colours.
class WindowChromeTheme extends InheritedWidget {
  const WindowChromeTheme({
    super.key,
    this.foreground,
    required super.child,
  });

  final Color? foreground;

  static ColorScheme colorSchemeOf(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = context
        .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
        ?.foreground;
    return foreground == null ? scheme : scheme.copyWith(onSurface: foreground);
  }

  /// Accent foreground for controls painted directly over the window scene.
  /// A native high-contrast override always wins; otherwise the generated
  /// primary colour follows the current artwork/theme instead of falling back
  /// to an almost-black default icon/text colour.
  static Color foregroundOf(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
        ?.foreground;
    return inherited ?? Theme.of(context).colorScheme.primary;
  }

  @override
  bool updateShouldNotify(WindowChromeTheme oldWidget) =>
      foreground != oldWidget.foreground;
}
