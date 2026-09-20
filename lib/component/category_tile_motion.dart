import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';

/// FLIP-style paint interpolation keeps the sliver's final geometry correct
/// while visible tiles travel together, including interrupted resize/reorders.
class CategoryTileMotion extends StatefulWidget {
  const CategoryTileMotion(
      {super.key,
      required this.rect,
      required this.child,
      this.linear = false,
      this.scaleSize = true});
  final Rect rect;
  final Widget child;
  final bool linear;
  final bool scaleSize;
  @override
  State<CategoryTileMotion> createState() => _CategoryTileMotionState();
}

class _CategoryTileMotionState extends State<CategoryTileMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late Rect _from = widget.rect;
  // A fill-mode toggle may change the requested curve without moving this tile.
  // Keep the active segment's curve until a new target starts another flight.
  late bool _activeLinear = widget.linear;
  double get _progress => _activeLinear
      ? _controller.value
      : AppMotion.standardCurve.transform(_controller.value);
  Rect get _current => Rect.lerp(_from, widget.rect, _progress)!;
  @override
  void didUpdateWidget(CategoryTileMotion old) {
    super.didUpdateWidget(old);
    if (old.rect != widget.rect) {
      _from = Rect.lerp(_from, old.rect, _progress)!;
      _activeLinear = widget.linear;
      if (appToolbarReduceMotion(context, kind: MotionKind.layout)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Settle while hidden, rather than exposing a stale transform on the first
    // visible frame before the resumed ticker catches up to elapsed wall time.
    if (appToolbarReduceMotion(context, kind: MotionKind.layout)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final rect = _current;
        return Transform(
            transform: Matrix4.identity()
              ..translateByDouble(rect.left - widget.rect.left,
                  rect.top - widget.rect.top, 0, 1)
              ..scaleByDouble(
                  widget.scaleSize ? rect.width / widget.rect.width : 1,
                  widget.scaleSize ? rect.height / widget.rect.height : 1,
                  1,
                  1),
            alignment: Alignment.topLeft,
            child: child);
      });
}
