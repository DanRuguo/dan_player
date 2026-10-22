import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/cover_contour_mask.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Pointer-local contours on the large playback cover only. The image, clip,
/// spectrum envelope and handoff geometry remain unchanged. No idle clock.
class CoverContourGlow extends StatefulWidget {
  const CoverContourGlow(
      {super.key,
      required this.image,
      this.currentFrame,
      required this.child,
      this.hidden,
      this.activity,
      this.isActive});
  final ImageProvider image;

  /// Borrowed from the displayed artwork; its stream owner retains/disposes it.
  final ui.Image? currentFrame;
  final Widget child;
  final ValueListenable<bool>? hidden;
  final Listenable? activity;
  final bool Function()? isActive;

  @override
  State<CoverContourGlow> createState() => _CoverContourGlowState();
}

class _CoverContourGlowState extends State<CoverContourGlow>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _pointer = ValueNotifier<Offset?>(null);
  final _refraction = CoverRefractionMesh();
  late final _fade =
      AnimationController(vsync: this, duration: AppMotion.standard)
        ..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) _pointer.value = null;
        });
  late final _paintChanges = Listenable.merge([_pointer, _fade]);
  ValueListenable<RenderingPreferences>? _preferences;
  CoverContourLease? _lease;
  ui.Image? _mask;
  ImageConfiguration _configuration = ImageConfiguration.empty;
  AppLifecycleState? _lifecycle;
  Offset? _pending;
  int? _frame;
  int? _device;
  int _generation = 0;
  bool _enabled = false;
  bool _treeVisible = true;
  bool _mediaMotion = true;
  bool _attached = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
    widget.activity?.addListener(_syncActivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncActivity);
      _preferences = preferences..addListener(_syncActivity);
    }
    _configuration = createLocalImageConfiguration(context);
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _mediaMotion = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncActivity();
  }

  @override
  void didUpdateWidget(CoverContourGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
    }
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity?.removeListener(_syncActivity);
      widget.activity?.addListener(_syncActivity);
    }
    if (oldWidget.image != widget.image) {
      _releaseMask();
      _clearPointer();
    }
    _syncActivity();
  }

  void _syncActivity() {
    if (!mounted) return;
    final preferences = _preferences?.value ?? const RenderingPreferences();
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final enabled = _attached &&
        _treeVisible &&
        _mediaMotion &&
        !(widget.hidden?.value ?? false) &&
        (widget.isActive?.call() ?? true) &&
        preferences.coverContourGlow &&
        preferences.animations.allows(MotionKind.feedback) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        preferences.allowsVisualUpdates(lifecycle: _lifecycle);
    if (!enabled) {
      _clearPointer();
      // Stop waiting on decoding immediately on hide. A bounded worker already
      // running may finish, but its stale result cannot repaint this surface.
      if (_mask == null) _releaseMask();
    }
    _enabled = enabled;
  }

  void _clearPointer() {
    if (_frame case final frame?)
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    _pending = null;
    _device = null;
    _fade.stop();
    _fade.value = 0;
    _pointer.value = null;
  }

  void _releaseMask() {
    _generation++;
    _lease?.dispose();
    _lease = null;
    _mask?.dispose();
    _mask = null;
  }

  void _prepareMask() {
    if (!_enabled || _lease != null || _mask != null) return;
    final lease = CoverContourCache.acquire(widget.image, _configuration);
    if (lease == null) return;
    _lease = lease;
    final generation = _generation;
    unawaited(lease.image.then((mask) {
      if (!mounted || generation != _generation || !_enabled) {
        mask?.dispose();
        return;
      }
      setState(() => _mask = mask);
    }));
  }

  void _move(PointerEvent event) {
    if (!_enabled ||
        (event.kind != ui.PointerDeviceKind.mouse &&
            event.kind != ui.PointerDeviceKind.stylus)) return;
    _device = event.device;
    _prepareMask();
    if (_pending == event.position && _pointer.value != null) return;
    _pending = event.position;
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (!_enabled || _device == null) return;
      _pointer.value = _pending;
      if (_fade.status != AnimationStatus.forward && !_fade.isCompleted)
        _fade.forward();
    });
  }

  void _exit(PointerExitEvent event) {
    if (_device != event.device) return;
    _device = null;
    _pending = null;
    if (_frame case final frame?)
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    if (_enabled && !_fade.isDismissed) {
      _fade.reverse();
    } else {
      _clearPointer();
    }
  }

  Offset? _localPointer() {
    final point = _pointer.value;
    final box = context.findRenderObject();
    if (point == null || box is! RenderBox || !box.attached || !box.hasSize)
      return null;
    final local = box.globalToLocal(point);
    return local.dx.isFinite && local.dy.isFinite ? local : null;
  }

  @override
  void didChangeAccessibilityFeatures() => _syncActivity();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncActivity();
  }

  @override
  void deactivate() {
    _attached = false;
    _syncActivity();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _syncActivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences?.removeListener(_syncActivity);
    widget.hidden?.removeListener(_syncActivity);
    widget.activity?.removeListener(_syncActivity);
    _clearPointer();
    _releaseMask();
    _fade.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        opaque: false,
        onEnter: _move,
        onHover: _move,
        onExit: _exit,
        child: Listener(
          onPointerMove: _move,
          child: Stack(fit: StackFit.passthrough, children: [
            ClipPath(
              clipper: _CoverBaseClipper(
                hasFrame: widget.currentFrame != null,
                pointer: _localPointer,
                opacity: () => AppMotion.standardCurve.transform(_fade.value),
                reclip: _paintChanges,
              ),
              clipBehavior: Clip.hardEdge,
              child: RepaintBoundary(child: widget.child),
            ),
            Positioned.fill(
                child: IgnorePointer(
                    child: RepaintBoundary(
              child: CustomPaint(
                  painter: CoverContourPainter(
                mask: _mask,
                currentFrame: widget.currentFrame,
                refraction: _refraction,
                repaint: _paintChanges,
                pointer: _localPointer,
                opacity: () => AppMotion.standardCurve.transform(_fade.value),
                color: Theme.of(context).colorScheme.primary,
              )),
            ))),
          ]),
        ),
      );
}

Rect? _refractionRegion(Size size, Offset? point, double amount) {
  if (point == null ||
      !point.dx.isFinite ||
      !point.dy.isFinite ||
      !amount.isFinite ||
      amount <= 0 ||
      size.isEmpty ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      !(Offset.zero & size).inflate(150).contains(point)) return null;
  return Rect.fromCircle(
      center: point, radius: CoverRefractionMesh.radiusFor(size));
}

/// Replace the base artwork inside the lens, rather than alpha-compositing a
/// second copy on top. This preserves translucent PNG/GIF artwork exactly.
class _CoverBaseClipper extends CustomClipper<Path> {
  _CoverBaseClipper(
      {required this.hasFrame,
      required this.pointer,
      required this.opacity,
      super.reclip});
  final bool hasFrame;
  final Offset? Function() pointer;
  final double Function() opacity;

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    final region =
        hasFrame ? _refractionRegion(size, pointer(), opacity()) : null;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds);
    if (region != null) path.addRect(region);
    return path;
  }

  @override
  bool shouldReclip(_CoverBaseClipper old) =>
      hasFrame != old.hasFrame ||
      pointer != old.pointer ||
      opacity != old.opacity;
}

/// One small texture mesh bends actual artwork coordinates inside a circular
/// lens. The boundary and center have zero displacement; the rest of the art
/// is never re-rasterized from the low-resolution contour mask.
class CoverRefractionMesh {
  CoverRefractionMesh() {
    var at = 0;
    for (var y = 0; y < divisions; y++) {
      for (var x = 0; x < divisions; x++) {
        final a = y * (divisions + 1) + x;
        final b = a + 1;
        final c = a + divisions + 1;
        indices[at++] = a;
        indices[at++] = b;
        indices[at++] = c;
        indices[at++] = b;
        indices[at++] = c + 1;
        indices[at++] = c;
      }
    }
  }
  static const divisions = 20;
  static const maximumVertices = (divisions + 1) * (divisions + 1);
  static const maximumDisplacement = 4.0;
  final positions = Float32List(maximumVertices * 2);
  final textureCoordinates = Float32List(maximumVertices * 2);
  final indices = Uint16List(divisions * divisions * 6);
  static final _identity =
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  double radius = 0;
  static double radiusFor(Size size) =>
      (math.min(size.width, size.height) * .16).clamp(24.0, 64.0);

  static Offset refractedPoint(
      Offset point, Offset center, double radius, double amount) {
    if (!radius.isFinite || radius <= 0 || !amount.isFinite) return point;
    final delta = (point - center) / radius;
    final square = delta.dx * delta.dx + delta.dy * delta.dy;
    if (!square.isFinite || square >= 1) return point;
    // A compact C2 profile: displacement, slope and curvature reach zero
    // before the unmodified artwork. No hard circular optical boundary.
    // max(r*(1-r²)³) occurs at r=1/sqrt(7).
    final displacement = maximumDisplacement *
        4.20134547705238 *
        amount.clamp(0.0, 1.0) *
        (1 - square) *
        (1 - square) *
        (1 - square);
    return point + delta * displacement;
  }

  bool update(Size size, Size imageSize, Offset center, double amount) {
    if (size.isEmpty ||
        imageSize.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        !center.dx.isFinite ||
        !center.dy.isFinite ||
        !amount.isFinite ||
        amount <= 0) return false;
    radius = radiusFor(size);
    final source = Alignment.center.inscribe(
        applyBoxFit(BoxFit.cover, imageSize, size).source,
        Offset.zero & imageSize);
    var index = 0;
    for (var y = 0; y <= divisions; y++) {
      for (var x = 0; x <= divisions; x++) {
        final position = center +
            Offset((x / divisions * 2 - 1) * radius,
                (y / divisions * 2 - 1) * radius);
        final sample = refractedPoint(position, center, radius, amount);
        positions[index] = position.dx;
        // Keep the affine source mapping outside the clipped cover too.
        // Clamping individual vertices bends even the zero-displacement
        // triangles as the pointer crosses an edge (visible as judder).
        textureCoordinates[index++] =
            source.left + sample.dx / size.width * source.width;
        positions[index] = position.dy;
        textureCoordinates[index++] =
            source.top + sample.dy / size.height * source.height;
      }
    }
    return true;
  }

  void paint(
      Canvas canvas, Size size, ui.Image frame, Offset center, double amount) {
    final draw = _prepare(size, frame, center, amount);
    if (draw == null) return;
    try {
      draw.paint(canvas);
    } finally {
      draw.dispose();
    }
  }

  _RefractionDraw? _prepare(
      Size size, ui.Image frame, Offset center, double amount) {
    final region = _refractionRegion(size, center, amount);
    if (region == null ||
        !update(size, Size(frame.width.toDouble(), frame.height.toDouble()),
            center, amount)) return null;
    final shader = ui.ImageShader(
        frame, TileMode.clamp, TileMode.clamp, _identity,
        filterQuality: FilterQuality.high);
    final vertices = ui.Vertices.raw(VertexMode.triangles, positions,
        textureCoordinates: textureCoordinates, indices: indices);
    return _RefractionDraw(
        shader, vertices, Offset.zero & size, Path()..addRect(region));
  }
}

class _RefractionDraw {
  _RefractionDraw(this.shader, this.vertices, this.bounds, this.lens);
  final ui.ImageShader shader;
  final ui.Vertices vertices;
  final Rect bounds;
  final Path lens;
  void paint(Canvas canvas,
      {ColorFilter? colorFilter, bool antialias = false}) {
    canvas.save();
    canvas.clipRect(bounds);
    canvas.clipPath(lens, doAntiAlias: antialias);
    try {
      canvas.drawVertices(
          vertices,
          BlendMode.srcOver,
          Paint()
            ..shader = shader
            ..colorFilter = colorFilter);
    } finally {
      canvas.restore();
    }
  }

  void dispose() {
    vertices.dispose();
    shader.dispose();
  }
}

class CoverContourPainter extends CustomPainter {
  CoverContourPainter(
      {required this.mask,
      this.currentFrame,
      this.refraction,
      required this.pointer,
      required this.opacity,
      required this.color,
      super.repaint});
  final ui.Image? mask;
  final ui.Image? currentFrame;
  final CoverRefractionMesh? refraction;
  final Offset? Function() pointer;
  final double Function() opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final image = mask;
    final point = pointer();
    final alpha = opacity();
    if (point == null ||
        !alpha.isFinite ||
        alpha <= 0 ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.isEmpty) return;
    final bounds = Offset.zero & size;
    // During exit the last global pointer can fall just outside a resized
    // cover. Preserve the fade, letting the cover clip trim the local lens.
    if (!bounds.inflate(150).contains(point)) return;
    if (currentFrame case final frame?) {
      refraction?.paint(canvas, size, frame, point, alpha);
    }
    if (image == null) return;
    final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, sourceSize, size);
    final source =
        Alignment.center.inscribe(fit.source, Offset.zero & sourceSize);
    final radius = (math.min(size.width, size.height) * .31).clamp(36.0, 150.0);
    final shader = RadialGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: const [0, .28, 1])
        .createShader(Rect.fromCircle(center: point, radius: radius));
    final tint = Color.lerp(color, Colors.white, .62)!;
    // The mask follows exactly the same deformation as the displayed frame.
    // Its old lens region must not remain underneath the refracted contours.
    final maskDraw = currentFrame == null
        ? null
        : refraction?._prepare(size, image, point, alpha);
    final outsideLens = maskDraw == null
        ? null
        : (Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(bounds)
          ..addPath(maskDraw.lens, Offset.zero));
    canvas.save();
    canvas.clipRect(bounds);
    try {
      for (final soft in [true, false]) {
        final layer = Paint();
        if (soft)
          layer.imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2);
        canvas.saveLayer(bounds, layer);
        final tintFilter = ColorFilter.mode(
            tint.withValues(alpha: alpha.clamp(0, 1) * (soft ? .45 : .82)),
            BlendMode.srcIn);
        canvas.save();
        if (outsideLens != null)
          canvas.clipPath(outsideLens, doAntiAlias: false);
        canvas.drawImageRect(
            image,
            source,
            bounds,
            Paint()
              ..filterQuality = FilterQuality.medium
              ..colorFilter = tintFilter);
        canvas.restore();
        maskDraw?.paint(canvas, colorFilter: tintFilter, antialias: false);
        canvas.drawRect(
            bounds,
            Paint()
              ..shader = shader
              ..blendMode = BlendMode.dstIn);
        canvas.restore();
      }
    } finally {
      canvas.restore();
      maskDraw?.dispose();
      shader.dispose();
    }
  }

  @override
  bool shouldRepaint(CoverContourPainter oldDelegate) =>
      mask != oldDelegate.mask ||
      currentFrame != oldDelegate.currentFrame ||
      color != oldDelegate.color ||
      pointer != oldDelegate.pointer ||
      opacity != oldDelegate.opacity;
}
