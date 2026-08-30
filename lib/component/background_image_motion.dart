import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Slow, bounded drift of an already decoded background image. No audio samples,
/// shaders, image IO, or page layout are performed by the 20-Hz clock.
///
/// Native desktop glass is never passed through this widget. The caller owns
/// source selection; only the background texture, not its veil/content, moves.
class BackgroundImageMotion extends StatefulWidget {
  const BackgroundImageMotion({
    super.key,
    required this.child,
    this.enabled = false,
    this.isPlaying = false,
    this.isVisible = true,
    this.hidden,
  });

  final Widget child;
  final bool enabled;
  final bool isPlaying;
  final bool isVisible;

  /// Direct notification cancels the clock even if a hidden HWND draws no more
  /// Flutter frames. The pure renderer need not construct a native controller.
  final ValueListenable<bool>? hidden;

  static const frameInterval = Duration(milliseconds: 50);
  static const cycle = Duration(seconds: 36);

  @override
  State<BackgroundImageMotion> createState() => _BackgroundImageMotionState();
}

class _BackgroundImageMotionState extends State<BackgroundImageMotion>
    with WidgetsBindingObserver {
  final _phase = ValueNotifier(0.0);
  Timer? _timer;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = false;
  bool _accessibilityAllowsMotion = false;
  ValueListenable<RenderingPreferences>? _preferences;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncClock);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncClock);
      _preferences = preferences..addListener(_syncClock);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _accessibilityAllowsMotion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
            !(MediaQuery.maybeHighContrastOf(context) ?? false);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant BackgroundImageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncClock);
      widget.hidden?.addListener(_syncClock);
    }
    _syncClock();
  }

  @override
  void didChangeAccessibilityFeatures() => _syncClock();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // A hidden app may not build again. Cancel its timer immediately.
    _syncClock();
  }

  void _syncClock() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final active = widget.enabled &&
        widget.isPlaying &&
        (_preferences?.value ?? const RenderingPreferences())
            .allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: _treeVisible && widget.isVisible,
          nativeHidden: widget.hidden?.value ?? false,
        ) &&
        _accessibilityAllowsMotion &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        !features.highContrast;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(BackgroundImageMotion.frameInterval, (_) {
      _phase.value = (_phase.value +
              BackgroundImageMotion.frameInterval.inMicroseconds /
                  BackgroundImageMotion.cycle.inMicroseconds) %
          1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ClipRect(
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return ValueListenableBuilder<double>(
          valueListenable: _phase,
          child: RepaintBoundary(child: widget.child),
          builder: (context, phase, child) {
            final angle = phase * math.pi * 2;
            // Overscan is always larger than translation; no empty edge can
            // appear, and a paused background keeps its current position.
            return Transform.translate(
              key: const ValueKey('background-motion-offset'),
              offset: Offset(math.sin(angle) * width * .012,
                  math.sin(angle + math.pi / 3) * height * .012),
              child: Transform.scale(
                scale: 1.06 + math.cos(angle) * .012,
                child: child,
              ),
            );
          },
        );
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.hidden?.removeListener(_syncClock);
    _preferences?.removeListener(_syncClock);
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }
}
