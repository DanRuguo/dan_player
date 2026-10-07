import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_toolbar_style.dart';

bool _pressedHoverDevice(PointerMoveEvent event) =>
    event.kind == PointerDeviceKind.mouse ||
    event.kind == PointerDeviceKind.stylus;

/// Consume the most recent hardware sample once per rendered frame. Gaming
/// mice can deliver hundreds of samples between frames; none need a separate
/// walk of the mounted grid's coordinate transforms.
class _FramePointer extends ValueNotifier<Offset?> {
  _FramePointer({required Offset? Function(Offset) project})
      : _project = project,
        super(null);
  final Offset? Function(Offset) _project;
  int? _callback;
  int? _device;
  Offset? _pending;
  bool _paintProjectionCached = false;
  Offset? _paintProjection;

  Offset? get paintValue {
    final point = value;
    if (point == null) return null;
    // Frame callbacks precede layout. Resolve in paint so a move and parent
    // relayout in the same frame use the current bounds and transform.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return _project(point);
    }
    if (!_paintProjectionCached) {
      _paintProjection = _project(point);
      _paintProjectionCached = true;
      // Shared covers reuse one scope bounds check during this paint. This
      // finite invalidation neither requests another frame nor starts a clock.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paintProjectionCached = false;
      });
    }
    return _paintProjection;
  }

  void move(Offset point, int device) {
    // Even an identical coordinate transfers ownership. An older device's
    // exit must not clear a newer sample or cancel its pending frame.
    _device = device;
    if (point == (_callback == null ? value : _pending)) return;
    _pending = point;
    _callback ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callback = null;
      _paintProjectionCached = false;
      value = _pending;
    });
  }

  void exit(int device) {
    if (_device == device) clear();
  }

  void clear() {
    _paintProjectionCached = false;
    _device = null;
    final hadPendingSample = _callback != null;
    if (_callback case final callback?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
      _callback = null;
    }
    _pending = null;
    if (value != null) {
      value = null;
    } else if (hadPendingSample) {
      // A first hover can be cancelled before the shared sample is published;
      // also invalidate any dependent paint already requested in that frame.
      notifyListeners();
    }
  }

  void refresh() {
    _paintProjectionCached = false;
    notifyListeners();
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

class _CoverPointerScopeState extends State<CoverPointerScope>
    with WidgetsBindingObserver {
  late final position = _FramePointer(project: _pointWithinScope);
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    // Native reduceMotion is not a MediaQuery field. Retire the shared sample
    // even when no inherited dependency changes or new pointer input arrives.
    final enabled = !appToolbarReduceMotion(context);
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) position.clear();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = !appToolbarReduceMotion(context);
    if (!_enabled) position.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    position.dispose();
    super.dispose();
  }

  void _pressedMove(PointerMoveEvent event) {
    if (!_enabled || !_pressedHoverDevice(event)) return;
    position.move(event.position, event.device);
  }

  Offset? _pointWithinScope(Offset point) {
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !(Offset.zero & box.size).contains(box.globalToLocal(point))) {
      return null;
    }
    return point;
  }

  @override
  Widget build(BuildContext context) => _CoverPointerData(
      position: position,
      child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            position.clear();
            return false;
          },
          child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: _pressedMove,
              child: MouseRegion(
                  opaque: false,
                  hitTestBehavior: HitTestBehavior.translucent,
                  onEnter: _enabled
                      ? (event) => position.move(event.position, event.device)
                      : null,
                  onHover: _enabled
                      ? (event) => position.move(event.position, event.device)
                      : null,
                  onExit: (event) => position.exit(event.device),
                  child: widget.child))));
}

/// Reuse a tile's existing layout clock when it moves under a stationary mouse.
/// No clock is started for pointer feedback, and artwork remains its own layer.
class CoverPointerMotion extends InheritedWidget {
  const CoverPointerMotion(
      {super.key, required this.motion, required super.child});
  final Listenable motion;
  @override
  bool updateShouldNotify(CoverPointerMotion oldWidget) =>
      motion != oldWidget.motion;
}

class _CoverPointerData extends InheritedWidget {
  const _CoverPointerData({required this.position, required super.child});
  final _FramePointer position;
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

class _CategoryPointerGlowState extends State<CategoryPointerGlow>
    with WidgetsBindingObserver {
  late final _position = _FramePointer(project: _localPoint);
  _FramePointer? _shared;
  Listenable? _motion;
  bool _enabled = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    final enabled = !appToolbarReduceMotion(context);
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) _position.clear();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = !appToolbarReduceMotion(context);
    if (!_enabled) _position.clear();
    final motion = context
        .dependOnInheritedWidgetOfExactType<CoverPointerMotion>()
        ?.motion;
    if (motion != _motion) {
      _motion?.removeListener(_geometryChanged);
      _motion = motion;
      _motion?.addListener(_geometryChanged);
    }
    final next = context
        .dependOnInheritedWidgetOfExactType<_CoverPointerData>()
        ?.position;
    if (next == _shared) return;
    _shared?.removeListener(_move);
    _position.clear();
    _shared = next;
    _shared?.addListener(_move);
    // A cover can mount under a stationary pointer before its first layout.
    // Remember that live sample so a later scope clear repaints its cached light.
    _geometryChanged();
  }

  void _move() {
    final global = _shared?.value;
    if (global == null) {
      _position.clear();
      return;
    }
    if (!_enabled) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _position.clear();
      return;
    }
    final point = box.globalToLocal(global);
    _position.value = _nearCover(box.size, point) ? point : null;
  }

  void _geometryChanged() {
    if (!_enabled || _shared?.value == null) return;
    if (_position.value == null) {
      // A formerly distant tile can move into the light. Keep a live sample so
      // clearing the scope also invalidates that newly painted glow.
      _position.value = _shared!.value;
    } else {
      _position.refresh();
    }
  }

  bool _nearCover(Size size, Offset point) => (Offset.zero & size)
      .inflate(size.shortestSide.clamp(60.0, 140.0))
      .contains(point);

  Offset? _paintPosition() {
    if (!_enabled) return null;
    if (_shared == null) return _position.paintValue;
    final global = _shared!.paintValue;
    final box = context.findRenderObject();
    if (global == null || box is! RenderBox || !box.hasSize) return null;
    // Animation notifications precede layout/transform updates. Resolve only
    // during paint so the glow uses this frame's geometry, not the last frame.
    final point = box.globalToLocal(global);
    return _nearCover(box.size, point) ? point : null;
  }

  @override
  void didUpdateWidget(CategoryPointerGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.circle != widget.circle) {
      _position.clear();
      _geometryChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shared?.removeListener(_move);
    _motion?.removeListener(_geometryChanged);
    _position.dispose();
    super.dispose();
  }

  void _pressedMove(PointerMoveEvent event) {
    // Shared grids publish once at their scope. A Listener observes the input
    // without joining the gesture arena or intercepting tap/drag ownership.
    if (!_enabled || _shared != null || !_pressedHoverDevice(event)) return;
    _position.move(event.position, event.device);
  }

  Offset? _localPoint(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final point = box.globalToLocal(global);
    return (Offset.zero & box.size).contains(point) ? point : null;
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerMove: _pressedMove,
      child: MouseRegion(
        onHover: (event) {
          if (!_enabled) return;
          if (_shared == null) {
            _position.move(event.position, event.device);
          }
        },
        onExit: (event) {
          if (_shared == null) _position.exit(event.device);
        },
        child: RepaintBoundary(
            child: CustomPaint(
          foregroundPainter: _GlowPainter(_position, _paintPosition,
              Theme.of(context).colorScheme.primary, widget.circle),
          // The foreground is volatile, but decoded artwork, text and ink are
          // independent layers. Hover must not repaint the entire cover.
          child: RepaintBoundary(child: widget.child),
        )),
      ));
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.position, this.resolvePosition, this.color, this.circle)
      : super(repaint: position);
  final ValueNotifier<Offset?> position;
  final Offset? Function() resolvePosition;
  final Color color;
  final bool circle;
  @override
  void paint(Canvas canvas, Size size) {
    final point = resolvePosition();
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
