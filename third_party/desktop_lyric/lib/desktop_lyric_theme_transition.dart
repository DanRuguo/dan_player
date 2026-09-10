import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'message.dart';

/// One colour clock for the desktop lyric's explicit message-based colours.
/// First frames and hidden/reduced-motion updates use the final palette; a
/// visible replacement starts at the currently rendered intermediate colour.
class DesktopLyricThemeTransition extends StatefulWidget {
  const DesktopLyricThemeTransition({
    super.key,
    required this.colors,
    required this.builder,
    this.child,
    this.enabled = true,
  });

  final ThemeChangedMessage colors;
  final Widget Function(BuildContext, ThemeChangedMessage, Widget?) builder;
  final Widget? child;
  final bool enabled;

  @override
  State<DesktopLyricThemeTransition> createState() =>
      _DesktopLyricThemeTransitionState();
}

class _DesktopLyricThemeTransitionState
    extends State<DesktopLyricThemeTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late ThemeChangedMessage _from = widget.colors;
  late ThemeChangedMessage _to = widget.colors;
  bool _visible = true;
  bool _contextAnimations = true;
  bool _snapOnNextBuild = false;

  bool get _canAnimate {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return widget.enabled &&
        _visible &&
        !_snapOnNextBuild &&
        _contextAnimations &&
        !features.disableAnimations &&
        !features.reduceMotion;
  }

  ThemeChangedMessage get _current {
    final t = AppMotion.standardCurve.transform(_animation.value);
    int lerp(int a, int b) => Color.lerp(Color(a), Color(b), t)!.toARGB32();
    return ThemeChangedMessage(
        lerp(_from.primary, _to.primary),
        lerp(_from.surfaceContainer, _to.surfaceContainer),
        lerp(_from.onSurface, _to.onSurface));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
  }

  bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _contextAnimations = TickerMode.valuesOf(context).enabled &&
        MediaQuery.maybeDisableAnimationsOf(context) != true;
    if (!_canAnimate) _animation.value = 1;
  }

  @override
  void didUpdateWidget(covariant DesktopLyricThemeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.colors;
    if (_to.primary != next.primary ||
        _to.surfaceContainer != next.surfaceContainer ||
        _to.onSurface != next.onSurface) {
      _from = _current;
      _to = next;
      if (_canAnimate) {
        _animation.forward(from: 0);
      } else {
        _animation.value = 1;
      }
    } else if (!_canAnimate) {
      _animation.value = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = _isVisible(state);
    if (visible != _visible) {
      setState(() {
        _visible = visible;
        // Updates can remain unbuilt while Flutter suspends hidden frames.
        // The first resumed build must consume their final palette directly.
        if (visible) _snapOnNextBuild = true;
      });
    }
    if (!_canAnimate) _animation.value = 1;
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (!_canAnimate) _animation.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _snapOnNextBuild = false;
    return AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) => widget.builder(context, _current, child));
  }
}
