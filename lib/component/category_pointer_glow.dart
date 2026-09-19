import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_motion.dart';

/// Consume the most recent hardware sample once per rendered frame. Gaming
/// mice can deliver hundreds of samples between frames; none need a separate
/// walk of the mounted grid's coordinate transforms.
class _FramePointer extends ValueNotifier<Offset?> {
  _FramePointer() : super(null);
  int? _callback;
  Offset? _pending;

  void move(Offset point) {
    if (point == (_callback == null ? value : _pending)) return;
    _pending = point;
    _callback ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callback = null;
      value = _pending;
    });
  }

  void clear() {
    final hadPendingSample = _callback != null;
    if (_callback case final callback?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
      _callback = null;
    }
    _pending = null;
    if (value != null) {
      value = null;
    } else if (hadPendingSample) {
      // A first hover can be cancelled before the shared sample is published.
      // Circles also queue a local sample, so they still need this reset even
      // though ValueNotifier would suppress the unchanged null value.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}

/// Shared by a scrollable cover grid, including its empty gutters. Only mounted
/// covers near the pointer change their paint notifier; no animation ticker.
class CoverPointerScope extends StatefulWidget {
  const CoverPointerScope({super.key, required this.child});
  final Widget child;
  @override
  State<CoverPointerScope> createState() => _CoverPointerScopeState();
}

class _CoverPointerScopeState extends State<CoverPointerScope> {
  final position = _FramePointer();
  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CoverPointerData(
      position: position,
      child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            position.clear();
            return false;
          },
          child: MouseRegion(
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              onHover: AppMotion.enabled(context, MotionKind.feedback)
                  ? (event) => position.move(event.position)
                  : null,
              onExit: (_) => position.clear(),
              child: widget.child)));
}

class _CoverPointerData extends InheritedWidget {
  const _CoverPointerData({required this.position, required super.child});
  final ValueNotifier<Offset?> position;
  @override
  bool updateShouldNotify(_CoverPointerData oldWidget) =>
      position != oldWidget.position;
}

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
  final _position = _FramePointer();
  ValueNotifier<Offset?>? _shared;
  bool _enabled = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = AppMotion.enabled(context, MotionKind.feedback);
    if (!_enabled) _position.clear();
    final next = context
        .dependOnInheritedWidgetOfExactType<_CoverPointerData>()
        ?.position;
    if (next == _shared) return;
    _shared?.removeListener(_move);
    _shared = next;
    _shared?.addListener(_move);
  }

  void _move() {
    final global = _shared?.value;
    if (global == null) {
      _position.clear();
      return;
    }
    if (widget.circle || !_enabled) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _position.clear();
      return;
    }
    final point = box.globalToLocal(global);
    _position.value =
        (Offset.zero & box.size).inflate(72).contains(point) ? point : null;
  }

  @override
  void didUpdateWidget(CategoryPointerGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.circle != widget.circle) _position.clear();
  }

  @override
  void dispose() {
    _shared?.removeListener(_move);
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onHover: (event) {
          if (!_enabled) return;
          if (widget.circle || _shared == null) {
            _position.move(event.localPosition);
          }
        },
        onExit: (_) {
          if (widget.circle || _shared == null) _position.clear();
        },
        child: RepaintBoundary(
            child: CustomPaint(
          foregroundPainter: _GlowPainter(
              _position, Theme.of(context).colorScheme.primary, widget.circle),
          // The foreground is volatile, but decoded artwork, text and ink are
          // independent layers. Hover must not repaint the entire cover.
          child: RepaintBoundary(child: widget.child),
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
    if (point == null || size.isEmpty) return;
    final rect = Offset.zero & size;
    final coverRect =
        circle ? Rect.fromLTWH(0, 0, size.width, size.width) : rect;
    final edgeDistance = circle
        ? coverRect.width / 2 - (point - coverRect.center).distance
        : [point.dx, point.dy, size.width - point.dx, size.height - point.dy]
            .reduce((a, b) => a < b ? a : b);
    // Circle captions are outside the artwork and must not light its edge.
    if (circle && edgeDistance < 0) return;
    canvas.save();
    if (circle) {
      canvas.clipPath(Path()..addOval(coverRect));
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
    // Two narrow contrast strokes keep the reveal visible over both pale and
    // dark artwork. They stay inside the cover and only paint near the pointer;
    // unlike a blur/shadow this needs no offscreen layer or continuous ticker.
    final edgeStrength = (1 - edgeDistance.abs() / 72).clamp(0.0, 1.0);
    if (edgeStrength > 0 && coverRect.shortestSide > 4) {
      final border = coverRect.deflate(1.75);
      final halo = Rect.fromCircle(
          center: point, radius: coverRect.shortestSide.clamp(56.0, 100.0));
      void stroke(Color tint, double width) {
        final edgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = RadialGradient(
            colors: [tint, tint.withValues(alpha: 0)],
          ).createShader(halo);
        if (circle) {
          canvas.drawOval(border, edgePaint);
        } else {
          canvas.drawRect(border, edgePaint);
        }
      }

      stroke(Colors.black.withValues(alpha: .72 * edgeStrength), 3.5);
      stroke(
          Color.lerp(color, Colors.white, .72)!
              .withValues(alpha: .96 * edgeStrength),
          1.5);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      color != old.color || circle != old.circle || position != old.position;
  @override
  bool? hitTest(Offset position) => false;
}
