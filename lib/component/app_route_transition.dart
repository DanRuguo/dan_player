import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';

/// The route surface follows one reversible opacity path in both directions.
/// Content keeps its small staggered entrances and exact Hero coordinates,
/// while the opaque backing never translates or exposes an unpainted
/// native-window edge. When a secondary route pushes on top, the covered
/// route gently dims its foreground contrast without shifting geometry.
class AppRouteTransition extends StatefulWidget {
  const AppRouteTransition({
    super.key,
    required this.animation,
    this.secondaryAnimation,
    required this.child,
  });

  // Both directions share the page-transition tier. Reversing an unfinished
  // entrance follows the same opacity path without an extra fade or pause.
  static const enterDuration = AppMotion.emphasized;
  static const exitDuration = enterDuration;
  final Animation<double> animation;
  final Animation<double>? secondaryAnimation;
  final Widget child;

  @override
  State<AppRouteTransition> createState() => _AppRouteTransitionState();
}

class _AppRouteTransitionState extends State<AppRouteTransition> {
  bool _exiting = false;
  late Listenable _mergedAnimation = _buildMergedAnimation();

  Listenable _buildMergedAnimation() {
    final secondary = widget.secondaryAnimation;
    return secondary == null
        ? widget.animation
        : Listenable.merge([widget.animation, secondary]);
  }

  @override
  void initState() {
    super.initState();
    _exiting = widget.animation.status == AnimationStatus.reverse;
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(AppRouteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
      _exiting = widget.animation.status == AnimationStatus.reverse;
    }
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _mergedAnimation = _buildMergedAnimation();
    }
  }

  void _onStatus(AnimationStatus status) {
    // Retain the invisible exit state at dismissed until Navigator unmounts
    // the route. Resetting it there would paint a one-frame flash.
    final exiting = switch (status) {
      AnimationStatus.reverse => true,
      AnimationStatus.forward || AnimationStatus.completed => false,
      AnimationStatus.dismissed => _exiting,
    };
    if (_exiting != exiting && mounted) setState(() => _exiting = exiting);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final reduced = (!AppMotion.enabled(context, MotionKind.transitions)) ||
        features.disableAnimations ||
        features.reduceMotion;
    return AnimatedBuilder(
      animation: _mergedAnimation,
      child: AppEntranceScope(child: widget.child),
      builder: (context, child) {
        final primaryOpacity = reduced
            ? (_exiting ? 0.0 : 1.0)
            : AppMotion.emphasizedCurve.transform(
                widget.animation.value.clamp(0.0, 1.0),
              );
        final secondaryRaw =
            widget.secondaryAnimation?.value.clamp(0.0, 1.0) ?? 0.0;
        final secondaryFactor = reduced || secondaryRaw <= 0.0
            ? 1.0
            : 1.0 - 0.08 * AppMotion.standardCurve.transform(secondaryRaw);
        final opacity = (primaryOpacity * secondaryFactor).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: _exiting,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: ExcludeFocus(
              excluding: _exiting,
              child: ExcludeSemantics(
                excluding: _exiting,
                child: Opacity(opacity: opacity, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
