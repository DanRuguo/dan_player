import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';

/// The route surface follows one reversible opacity path in both directions.
/// Content keeps its small staggered entrances, while the opaque backing never
/// translates or exposes an unpainted native-window edge.
class AppRouteTransition extends StatefulWidget {
  const AppRouteTransition(
      {super.key, required this.animation, required this.child});

  // Route changes need enough time for the backing fade and the first content
  // group to read as one motion. Keep both directions identical so popping a
  // detail page is the literal reverse of entering it, not a faster shortcut.
  static const enterDuration = Duration(milliseconds: 420);
  static const exitDuration = enterDuration;
  final Animation<double> animation;
  final Widget child;

  @override
  State<AppRouteTransition> createState() => _AppRouteTransitionState();
}

class _AppRouteTransitionState extends State<AppRouteTransition> {
  bool _exiting = false;

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
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        features.disableAnimations ||
        features.reduceMotion;
    return AnimatedBuilder(
      animation: widget.animation,
      child: AppEntranceScope(child: widget.child),
      builder: (context, child) {
        final opacity = reduced
            ? (_exiting ? 0.0 : 1.0)
            : AppMotion.emphasizedCurve.transform(
                widget.animation.value.clamp(0.0, 1.0),
              );
        return IgnorePointer(
          ignoring: _exiting,
          child: ExcludeFocus(
            excluding: _exiting,
            child: ExcludeSemantics(
              excluding: _exiting,
              child: Opacity(opacity: opacity, child: child),
            ),
          ),
        );
      },
    );
  }
}
