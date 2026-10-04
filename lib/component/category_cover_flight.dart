import 'dart:ui' show lerpDouble;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';

bool coverFlightMotionAllowed(BuildContext context) {
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  return !appToolbarReduceMotion(context, kind: MotionKind.tracking) &&
      lifecycle != AppLifecycleState.hidden &&
      lifecycle != AppLifecycleState.paused &&
      lifecycle != AppLifecycleState.detached;
}

/// A cancelled overlay never resumes within the same Hero flight. Its route
/// may finish its own finite transition, but no cover texture remains moving.
class CoverFlightMotionGate extends StatefulWidget {
  const CoverFlightMotionGate({super.key, required this.child});
  final Widget child;

  @override
  State<CoverFlightMotionGate> createState() => _CoverFlightMotionGateState();
}

class _CoverFlightMotionGateState extends State<CoverFlightMotionGate>
    with WidgetsBindingObserver {
  bool _retired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _motionChanged() {
    if (!mounted || _retired || coverFlightMotionAllowed(context)) return;
    setState(() => _retired = true);
  }

  @override
  void didChangeAccessibilityFeatures() => _motionChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _motionChanged();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!coverFlightMotionAllowed(context)) _retired = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _retired ? const SizedBox.shrink() : widget.child;
}

/// Reuses the source image during the route flight; no snapshots or idle work.
class CategoryCoverFlight extends StatefulWidget {
  const CategoryCoverFlight(
      {super.key,
      required this.tag,
      required this.radius,
      required this.child,
      this.image});
  final Object? tag;
  final double radius;
  final ImageProvider? image;
  final Widget child;
  @override
  State<CategoryCoverFlight> createState() => _CategoryCoverFlightState();
}

class _CategoryCoverFlightState extends State<CategoryCoverFlight>
    with WidgetsBindingObserver {
  // Hero's default destination placeholder unmounts its subtree. Preserve the
  // decoded artwork across both placeholder transitions, not just the flight.
  final _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _FlightContent(
        key: _contentKey,
        radius: widget.radius,
        image: widget.image,
        child: widget.child);
    if (widget.tag == null || !coverFlightMotionAllowed(context)) {
      return content;
    }
    return Hero(
        tag: widget.tag!,
        placeholderBuilder: (_, size, child) => SizedBox.fromSize(
            size: size,
            child: Offstage(child: TickerMode(enabled: false, child: child))),
        flightShuttleBuilder: (_, animation, direction, from, to) {
          final a = (from.widget as Hero).child as _FlightContent;
          final b = (to.widget as Hero).child as _FlightContent;
          final provider = a.image ?? b.image;
          return CoverFlightMotionGate(
              child: AnimatedBuilder(
                  animation: animation,
                  child: provider == null
                      ? b.child
                      : Image(
                          key: const ValueKey('category-flight-image'),
                          image: provider,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium),
                  builder: (_, child) {
                    final t = direction == HeroFlightDirection.push
                        ? animation.value
                        : 1 - animation.value;
                    return ClipRRect(
                        borderRadius: BorderRadius.circular(
                            lerpDouble(a.radius, b.radius, t)!),
                        child: child);
                  }));
        },
        child: content);
  }
}

class _FlightContent extends StatelessWidget {
  const _FlightContent(
      {super.key,
      required this.radius,
      required this.image,
      required this.child});
  final double radius;
  final ImageProvider? image;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
