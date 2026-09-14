import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

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

class _CategoryCoverFlightState extends State<CategoryCoverFlight> {
  // Hero's default destination placeholder unmounts its subtree. Preserve the
  // decoded artwork across both placeholder transitions, not just the flight.
  final _contentKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    if (widget.tag == null || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
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
          return AnimatedBuilder(
              animation: animation,
              builder: (_, __) {
                final t = direction == HeroFlightDirection.push
                    ? animation.value
                    : 1 - animation.value;
                return ClipRRect(
                    borderRadius: BorderRadius.circular(
                        lerpDouble(a.radius, b.radius, t)!),
                    child: provider == null
                        ? b.child
                        : Image(
                            key: const ValueKey('category-flight-image'),
                            image: provider,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium));
              });
        },
        child: _FlightContent(
            key: _contentKey,
            radius: widget.radius,
            image: widget.image,
            child: widget.child));
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
