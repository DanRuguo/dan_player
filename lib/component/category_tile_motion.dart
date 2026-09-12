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
      this.linear = false});
  final Rect rect;
  final Widget child;
  final bool linear;
  @override
  State<CategoryTileMotion> createState() => _CategoryTileMotionState();
}

class _CategoryTileMotionState extends State<CategoryTileMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late Rect _from = widget.rect;
  Rect get _current => Rect.lerp(
      _from,
      widget.rect,
      widget.linear
          ? _controller.value
          : AppMotion.standardCurve.transform(_controller.value))!;
  @override
  void didUpdateWidget(CategoryTileMotion old) {
    super.didUpdateWidget(old);
    if (old.rect != widget.rect) {
      _from = Rect.lerp(
          _from,
          old.rect,
          old.linear
              ? _controller.value
              : AppMotion.standardCurve.transform(_controller.value))!;
      if (appToolbarReduceMotion(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
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
              ..scaleByDouble(rect.width / widget.rect.width,
                  rect.height / widget.rect.height, 1, 1),
            alignment: Alignment.topLeft,
            child: child);
      });
}
