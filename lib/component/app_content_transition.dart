import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';

/// Reveals a changed in-page section without keeping an outgoing copy alive.
/// The stable wrapper preserves retained editors and scroll controllers below
/// it; ordinary rebuilds and locale/theme changes never replay the transition.
class AppContentTransition extends StatefulWidget {
  const AppContentTransition(
      {super.key, required this.identity, required this.child});

  final Object identity;
  final Widget child;

  @override
  State<AppContentTransition> createState() => _AppContentTransitionState();
}

class _AppContentTransitionState extends State<AppContentTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _controller =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late final _opacity =
      _controller.drive(CurveTween(curve: AppMotion.standardCurve));
  bool _enabled = true;

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_enabled || _platformReducesMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    if (_enabled && !_platformReducesMotion) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducesMotion) _controller.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _opacity, alwaysIncludeSemantics: true, child: widget.child);
}
