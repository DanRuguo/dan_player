import 'dart:ui' as ui;

import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';

/// An app-local, lightly frosted menu. Material retains the original shape,
/// outline, shadow and ink; only its clipped background is filtered.
class AppMenuSurface extends StatefulWidget {
  const AppMenuSurface({
    super.key,
    required this.child,
    required this.color,
    required this.shape,
    this.surfaceTintColor,
    this.shadowColor,
    this.elevation = 3,
  });

  final Widget child;
  final Color color;
  final ShapeBorder shape;
  final Color? surfaceTintColor, shadowColor;
  final double elevation;

  @override
  State<AppMenuSurface> createState() => _AppMenuSurfaceState();
}

class _AppMenuSurfaceState extends State<AppMenuSurface>
    with WidgetsBindingObserver {
  static final _filter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);
  AppLifecycleState? _lifecycle;

  bool get _hidden =>
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasHidden = _hidden;
    _lifecycle = state;
    if (_hidden != wasHidden) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = RenderingPreferencesScope.of(context);
    final highContrast = (MediaQuery.maybeOf(context)?.highContrast ?? false) ||
        WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.highContrast ||
        context
                .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
                ?.foreground !=
            null;
    final visible = TickerMode.valuesOf(context).enabled && !_hidden;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<WindowBackdropStatus>(
      valueListenable: WindowBackdropService.instance,
      child: widget.child,
      builder: (context, status, child) {
        // Use known native accessibility/power signals without enabling or
        // configuring the window backdrop on behalf of an opened menu.
        final systemFallback = switch (status.reason) {
          'high_contrast' ||
          'transparency_disabled' ||
          'energy_saver' ||
          'battery_saver' =>
            true,
          _ => false,
        };
        final blurred = preferences.surfaceBlur &&
            visible &&
            !highContrast &&
            !systemFallback;
        final base = ElevationOverlay.applySurfaceTint(
            widget.color, widget.surfaceTintColor, widget.elevation);
        return Material(
          color: blurred ? Colors.transparent : widget.color,
          surfaceTintColor:
              blurred ? Colors.transparent : widget.surfaceTintColor,
          shadowColor: widget.shadowColor,
          elevation: widget.elevation,
          shape: widget.shape,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            enabled: blurred,
            filter: _filter,
            // Menu opening uses opacity saveLayers. Replace their backdrop
            // contribution instead of blending the same background twice.
            blendMode: BlendMode.src,
            child: ColoredBox(
              color: blurred
                  ? base.withValues(alpha: base.a * (dark ? .88 : .90))
                  : Colors.transparent,
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
