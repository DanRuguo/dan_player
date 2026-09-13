import 'package:flutter/material.dart';

/// Pointer-driven paint only: no timer, ticker, layout or image filtering.
class CategoryPointerGlow extends StatefulWidget {
  const CategoryPointerGlow(
      {super.key, required this.child, this.circle = false});
  final Widget child;
  final bool circle;
  @override
  State<CategoryPointerGlow> createState() => _CategoryPointerGlowState();
}

class _CategoryPointerGlowState extends State<CategoryPointerGlow> {
  final _position = ValueNotifier<Offset?>(null);
  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onHover: (event) => _position.value = event.localPosition,
        onExit: (_) => _position.value = null,
        child: RepaintBoundary(
            child: CustomPaint(
          foregroundPainter: _GlowPainter(
              _position, Theme.of(context).colorScheme.primary, widget.circle),
          child: widget.child,
        )),
      );
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.position, this.color, this.circle)
      : super(repaint: position);
  final ValueNotifier<Offset?> position;
  final Color color;
  final bool circle;
  @override
  void paint(Canvas canvas, Size size) {
    final point = position.value;
    if (point == null) return;
    final rect = Offset.zero & size;
    canvas.save();
    if (circle) {
      canvas.clipPath(
          Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.width)));
    } else {
      canvas.clipRect(rect);
    }
    final radius = size.shortestSide.clamp(60.0, 140.0);
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: .18),
        color.withValues(alpha: .08),
        Colors.transparent,
      ], stops: const [
        0,
        .35,
        1
      ]).createShader(Rect.fromCircle(center: point, radius: radius));
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      color != old.color || circle != old.circle || position != old.position;
  @override
  bool? hitTest(Offset position) => false;
}
