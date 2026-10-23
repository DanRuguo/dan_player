import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/cover_contour_mask.dart';
import 'package:dan_player/component/cover_uniform_regions.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/frame_pacing.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _pointer = ValueNotifier<Offset?>(null);
  final _refraction = CoverRefractionMesh();
  late final _fade =
      AnimationController(vsync: this, duration: AppMotion.standard)
        ..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) {
            _pointer.value = null;
            _maskReveal.stop();
            _maskReveal.value = _mask == null ? 0 : 1;
          }
        });
  late final _maskReveal =
      AnimationController(vsync: this, duration: AppMotion.standard);
  late final _tapPulse =
      AnimationController(vsync: this, duration: AppMotion.emphasized)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _tapPoint = null;
        });
  // Contour decoding only changes the overlay, never the base lens geometry.
  late final _clipChanges = Listenable.merge([_pointer, _fade]);
  late final _paintChanges = Listenable.merge([_clipChanges, _maskReveal]);
  final _pointerClock = Stopwatch()..start();
  late final _trackingPacer = FrameRequestPacer(
      now: () => _pointerClock.elapsed, emit: _requestPointerFrame);
  ValueListenable<RenderingPreferences>? _preferences;
  CoverContourLease? _lease;
  ui.Image? _mask;
  CoverUniformRegions? _uniform;
  ui.Image? _uniformFrame;
  bool _uniformAttempted = false;
  bool _uniformBusy = false;
  int _uniformGeneration = 0;
  ImageConfiguration _configuration = ImageConfiguration.empty;
  AppLifecycleState? _lifecycle;
  Offset? _pending;
  int? _frame;
  int? _device;
  // Keep physical hover ownership when a proven unchanged region stops paint.
  // A new animation frame can need the effect again without another mouse move.
  Offset? _hoverPosition;
  int? _hoverDevice;
  int _generation = 0;
  bool _enabled = false;
  bool _feedbackEnabled = false;
  final _pressedPointers = <int>{};
  int? _tapPointer;
  Offset? _tapOrigin;
  Offset? _tapPoint;
  Duration? _tapStarted;
  double _tapSlop = kTouchSlop;
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
      _forgetHover();
      _clearPointer();
      _clearTap();
      _uniformGeneration++;
      _uniformAttempted = false;
      _uniformFrame = null;
      _uniform = null;
    } else if (_uniformFrame case final frame?) {
      if (!(widget.currentFrame?.isCloneOf(frame) ?? false)) {
        // A new GIF/display frame invalidates the proof. Never read back each
        // animation frame; this provider epoch has already used its one scan.
        _uniform = null;
      }
    }
    _syncActivity();
    if (_enabled && _pointer.value == null && _hoverPosition != null) {
      _track(_hoverPosition!, _hoverDevice!);
    }
  }

  void _syncActivity() {
    if (!mounted) return;
    final preferences = _preferences?.value ?? const RenderingPreferences();
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final feedbackEnabled = _attached &&
        _treeVisible &&
        _mediaMotion &&
        !(widget.hidden?.value ?? false) &&
        (widget.isActive?.call() ?? true) &&
        preferences.animations.allows(MotionKind.feedback) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        preferences.allowsVisualUpdates(lifecycle: _lifecycle);
    final enabled = feedbackEnabled && preferences.coverContourGlow;
    if (!feedbackEnabled) _clearTap();
    if (!enabled) {
      _forgetHover();
      _clearPointer();
      // Stop waiting on decoding immediately on hide. A bounded worker already
      // running may finish, but its stale result cannot repaint this surface.
      if (_mask == null) _releaseMask();
    }
    _enabled = enabled;
    _feedbackEnabled = feedbackEnabled;
  }

  void _forgetHover() {
    _hoverPosition = null;
    _hoverDevice = null;
  }

  void _clearTap() {
    _pressedPointers.clear();
    _tapPointer = null;
    _tapOrigin = null;
    _tapStarted = null;
    _tapPoint = null;
    _tapPulse.stop();
    _tapPulse.value = 0;
  }

  void _press(PointerDownEvent event) {
    if (!_feedbackEnabled || event.buttons != kPrimaryButton) return;
    _pressedPointers.add(event.pointer);
    if (_pressedPointers.length != 1) {
      _tapPointer = null;
      return;
    }
    _tapPointer = event.pointer;
    _tapOrigin = event.localPosition;
    _tapStarted = event.timeStamp;
    _tapSlop =
        computeHitSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context));
  }

  void _pointerMoved(PointerMoveEvent event) {
    if (_tapPointer == event.pointer &&
        (event.buttons != kPrimaryButton ||
            (event.localPosition - _tapOrigin!).distance > _tapSlop)) {
      _tapPointer = null;
    }
    _move(event);
  }

  void _releasePress(PointerUpEvent event) {
    final box = context.findRenderObject();
    if (_feedbackEnabled &&
        _tapPointer == event.pointer &&
        _pressedPointers.length == 1 &&
        event.timeStamp - _tapStarted! <= const Duration(milliseconds: 500) &&
        (event.localPosition - _tapOrigin!).distance <= _tapSlop &&
        box is RenderBox &&
        box.hasSize &&
        (Offset.zero & box.size).contains(event.localPosition)) {
      _tapPoint = event.localPosition;
      _tapPulse.forward(from: 0);
    }
    _cancelPress(event);
  }

  void _cancelPress(PointerEvent event) {
    _pressedPointers.remove(event.pointer);
    if (_tapPointer == event.pointer) {
      _tapPointer = null;
      _tapOrigin = null;
      _tapStarted = null;
    }
  }

  void _clearPointer() {
    _trackingPacer.reset();
    if (_frame case final frame?)
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    _pending = null;
    _device = null;
    _fade.stop();
    _fade.value = 0;
    _maskReveal.stop();
    _maskReveal.value = _mask == null ? 0 : 1;
    _pointer.value = null;
  }

  void _releaseMask() {
    _generation++;
    _lease?.dispose();
    _lease = null;
    _mask?.dispose();
    _mask = null;
    _maskReveal.stop();
    _maskReveal.value = 0;
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
      if (_stopIfUnchanged()) return;
      // A first contour decode can finish after the hover fade. Reveal only
      // the new contours, without resetting an already visible refraction.
      if (mask != null) {
        if (_device != null && _pointer.value != null && !_fade.isDismissed) {
          _maskReveal.forward(from: 0);
        } else if (_fade.isDismissed) {
          _maskReveal.value = 1;
        }
      }
    }));
  }

  void _prepareUniform() {
    final frame = widget.currentFrame;
    if (_uniformBusy || _uniformAttempted || frame == null) return;
    _uniformBusy = true;
    _uniformAttempted = true;
    _uniformFrame = frame;
    final generation = _uniformGeneration;
    unawaited(CoverUniformRegions.inspect(frame).then((index) {
      if (!mounted ||
          generation != _uniformGeneration ||
          !(widget.currentFrame?.isCloneOf(frame) ?? false)) return;
      _uniform = index;
      _stopIfUnchanged();
    }).whenComplete(() {
      _uniformBusy = false;
      if (mounted && _enabled && _device != null && !_uniformAttempted) {
        _prepareUniform();
      }
    }));
  }

  bool _unchangedAt(Offset global) {
    final index = _uniform;
    final coverage = _lease?.coverage;
    final box = context.findRenderObject();
    if (index == null ||
        coverage == null ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) return false;
    final point = box.globalToLocal(global);
    if (!point.dx.isFinite || !point.dy.isFinite) return false;
    final lens = Rect.fromCircle(
        center: point,
        radius: CoverRefractionMesh.radiusFor(box.size) +
            CoverRefractionMesh.maximumDisplacement);
    if (!index.isUniform(_coverSourceRegion(
        Size(index.width.toDouble(), index.height.toDouble()),
        box.size,
        lens))) {
      return false;
    }
    return _clearCoverGlow(coverage, box.size, point);
  }

  bool _stopIfUnchanged() {
    final point = _pending ?? _pointer.value;
    if (point == null || !_unchangedAt(point)) return false;
    _clearPointer();
    return true;
  }

  void _move(PointerEvent event) {
    if (!_enabled ||
        (event.kind != ui.PointerDeviceKind.mouse &&
            event.kind != ui.PointerDeviceKind.stylus)) return;
    _hoverPosition = event.position;
    _hoverDevice = event.device;
    _track(event.position, event.device);
  }

  void _track(Offset position, int device) {
    _device = device;
    _prepareMask();
    _prepareUniform();
    if (_unchangedAt(position)) {
      if (_pointer.value != null ||
          _pending != null ||
          _frame != null ||
          !_fade.isDismissed ||
          _maskReveal.isAnimating) {
        _clearPointer();
      } else {
        _device = null;
      }
      return;
    }
    if (_pending == position && _pointer.value != null) return;
    _pending = position;
    _trackingPacer.request(30);
  }

  void _requestPointerFrame() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (!_enabled || _device == null) return;
      _pointer.value = _pending;
      if (_fade.status != AnimationStatus.forward && !_fade.isCompleted)
        _fade.forward();
      if (_mask != null && !_maskReveal.isCompleted && !_maskReveal.isAnimating)
        _maskReveal.forward();
    });
  }

  void _exit(PointerExitEvent event) {
    if (_hoverDevice == event.device) _forgetHover();
    if (_device != event.device) return;
    _device = null;
    _pending = null;
    _trackingPacer.cancel();
    if (_frame case final frame?)
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    // Exit fades the already visible composite; late decoding must not add
    // fresh highlights while that composite is disappearing.
    _maskReveal.stop();
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
    _clearTap();
    _releaseMask();
    _fade.dispose();
    _maskReveal.dispose();
    _tapPulse.dispose();
    _pointerClock.stop();
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
          behavior: HitTestBehavior.translucent,
          onPointerDown: _press,
          onPointerMove: _pointerMoved,
          onPointerUp: _releasePress,
          onPointerCancel: _cancelPress,
          child: Stack(fit: StackFit.passthrough, children: [
            ClipPath(
              clipper: _CoverBaseClipper(
                hasFrame: widget.currentFrame != null,
                pointer: _localPointer,
                opacity: () => AppMotion.standardCurve.transform(_fade.value),
                reclip: _clipChanges,
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
                maskCoverage: _lease?.coverage,
                currentFrame: widget.currentFrame,
                refraction: _refraction,
                repaint: _paintChanges,
                pointer: _localPointer,
                opacity: () => AppMotion.standardCurve.transform(_fade.value),
                maskOpacity: () =>
                    AppMotion.standardCurve.transform(_maskReveal.value),
                color: Theme.of(context).colorScheme.primary,
              )),
            ))),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: CoverTapPainter(
                      pointer: () => _tapPoint,
                      progress: () => _tapPulse.value,
                      color: Theme.of(context).colorScheme.primary,
                      repaint: _tapPulse,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// A single decorative pulse observes input without entering the gesture arena.
/// Its own layer leaves the artwork, refraction and swipe hit geometry intact.
class CoverTapPainter extends CustomPainter {
  CoverTapPainter(
      {required this.pointer,
      required this.progress,
      required this.color,
      super.repaint});
  final Offset? Function() pointer;
  final double Function() progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final point = pointer();
    final t = progress();
    if (point == null || t <= 0 || t >= 1 || size.isEmpty) return;
    final amount = AppMotion.standardCurve.transform(t);
    final radius = 8 + math.min(48.0, size.shortestSide * .16) * amount;
    final alpha = math.sin(math.pi * t) * .46;
    final tint = Color.lerp(color, Colors.white, .65)!;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(
        point,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = tint.withValues(alpha: alpha * .18));
    canvas.drawCircle(
        point,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = tint.withValues(alpha: alpha));
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverTapPainter oldDelegate) =>
      pointer != oldDelegate.pointer ||
      progress != oldDelegate.progress ||
      color != oldDelegate.color;
}

RRect? _refractionRegion(Size size, Offset? point, double amount) {
  if (point == null ||
      !point.dx.isFinite ||
      !point.dy.isFinite ||
      !amount.isFinite ||
      amount <= 0 ||
      size.isEmpty ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      !(Offset.zero & size).inflate(150).contains(point)) return null;
  return CoverRefractionMesh.lensFor(size, point);
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
    // The optical displacement is zero outside the inscribed circle. Include
    // those unchanged corner pixels in one rectangular sampling tile instead
    // of stitching separately rasterized curved clips across two layers.
    if (region != null) path.addRect(region.outerRect);
    return path;
  }

  @override
  bool shouldReclip(_CoverBaseClipper old) =>
      hasFrame != old.hasFrame ||
      pointer != old.pointer ||
      opacity != old.opacity;
}

/// One small rounded lens bends actual artwork coordinates. The optical
/// displacement has compact circular support inside it; the rest of the art
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
      (math.min(size.width, size.height) * .11).clamp(16.0, 44.0);

  static RRect lensFor(Size size, Offset center) => AppShape.surfaceRadius
      .toRRect(Rect.fromCircle(center: center, radius: radiusFor(size)));

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
    if (!amount.isFinite || amount <= 0) return;
    // Keep the sampled image fixed during a fade. Scaling the UV displacement
    // too would sweep bright artwork edges across otherwise dark pixels just
    // before exit, even when both fade endpoints are dark.
    final draw = _prepare(size, frame, center, 1);
    if (draw == null) return;
    try {
      final alpha = amount.clamp(0.0, 1.0);
      if (alpha >= 1) {
        draw.paint(canvas);
        return;
      }
      // Crossfade premultiplied pixels with addition in a small transparent
      // layer: (1-a)*original + a*warped. Ordinary source-over would darken
      // translucent PNG/GIF pixels. The base clip uses this exact lens too.
      final imageSize = Size(frame.width.toDouble(), frame.height.toDouble());
      final source = Alignment.center.inscribe(
          applyBoxFit(BoxFit.cover, imageSize, size).source,
          Offset.zero & imageSize);
      canvas.save();
      canvas.clipRect(draw.bounds);
      canvas.clipRect(draw.region, doAntiAlias: false);
      canvas.saveLayer(draw.region.intersect(draw.bounds), Paint());
      canvas.drawImageRect(
          frame,
          source,
          draw.bounds,
          Paint()
            ..filterQuality = FilterQuality.high
            ..color = Colors.white.withValues(alpha: 1 - alpha));
      draw.paint(canvas, alpha: alpha, blendMode: BlendMode.plus, clip: false);
      canvas.restore();
      canvas.restore();
    } finally {
      draw.dispose();
    }
  }

  _RefractionDraw? _prepare(
      Size size, ui.Image frame, Offset center, double amount,
      {FilterQuality filterQuality = FilterQuality.high}) {
    final region = _refractionRegion(size, center, amount);
    if (region == null ||
        !region.outerRect.overlaps(Offset.zero & size) ||
        !update(size, Size(frame.width.toDouble(), frame.height.toDouble()),
            center, amount)) return null;
    // Keep triangle coverage beyond the hard replacement clip. When a mesh
    // edge coincides with a fractional clip, GPU coverage can differ inside
    // the fade layer and leak the background through transparent artwork.
    return _prepareGlow(size, frame, center, radiusFor(size) + 2,
        region: region.outerRect, filterQuality: filterQuality);
  }

  // One continuous mask surface, including the undeformed outer glow. Splitting
  // it into independently clipped inside/outside paths creates coverage seams.
  _RefractionDraw _prepareGlow(
      Size size, ui.Image frame, Offset center, double extent,
      {Rect? region, FilterQuality filterQuality = FilterQuality.medium}) {
    final imageSize = Size(frame.width.toDouble(), frame.height.toDouble());
    final source = Alignment.center.inscribe(
        applyBoxFit(BoxFit.cover, imageSize, size).source,
        Offset.zero & imageSize);
    final radius = radiusFor(size);
    const side = divisions + 3;
    final positions = Float32List(side * side * 2);
    final coordinates = Float32List(positions.length);
    final triangles = Uint16List((side - 1) * (side - 1) * 6);
    double axis(int at) => at == 0
        ? -extent
        : at == side - 1
            ? extent
            : ((at - 1) / divisions * 2 - 1) * radius;
    var at = 0;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final position = center + Offset(axis(x), axis(y));
        final sample = refractedPoint(position, center, radius, 1);
        positions[at] = position.dx;
        coordinates[at++] = source.left + sample.dx / size.width * source.width;
        positions[at] = position.dy;
        coordinates[at++] =
            source.top + sample.dy / size.height * source.height;
      }
    }
    at = 0;
    for (var y = 0; y < side - 1; y++) {
      for (var x = 0; x < side - 1; x++) {
        final a = y * side + x;
        triangles[at++] = a;
        triangles[at++] = a + 1;
        triangles[at++] = a + side;
        triangles[at++] = a + 1;
        triangles[at++] = a + side + 1;
        triangles[at++] = a + side;
      }
    }
    return _RefractionDraw(
        ui.ImageShader(frame, TileMode.clamp, TileMode.clamp, _identity,
            filterQuality: filterQuality),
        ui.Vertices.raw(VertexMode.triangles, positions,
            textureCoordinates: coordinates, indices: triangles),
        Offset.zero & size,
        region ?? Rect.fromCircle(center: center, radius: extent));
  }
}

class _RefractionDraw {
  _RefractionDraw(this.shader, this.vertices, this.bounds, this.region);
  final ui.ImageShader shader;
  final ui.Vertices vertices;
  final Rect bounds;
  final Rect region;
  void paint(Canvas canvas,
      {ColorFilter? colorFilter,
      double alpha = 1,
      BlendMode blendMode = BlendMode.srcOver,
      bool clip = true,
      bool antialias = false}) {
    canvas.save();
    if (clip) {
      canvas.clipRect(bounds);
      canvas.clipRect(region, doAntiAlias: antialias);
    }
    try {
      canvas.drawVertices(
          vertices,
          BlendMode.srcOver,
          Paint()
            ..shader = shader
            ..isAntiAlias = false
            ..blendMode = blendMode
            // drawVertices can ignore Paint.color with an image shader.
            // Filter the sampled premultiplied pixels, including their alpha.
            ..colorFilter = colorFilter ??
                (alpha < 1
                    ? ColorFilter.mode(
                        Colors.white.withValues(alpha: alpha), BlendMode.dstIn)
                    : null));
    } finally {
      canvas.restore();
    }
  }

  void dispose() {
    vertices.dispose();
    shader.dispose();
  }
}

Rect _coverSourceRegion(Size pixels, Size size, Rect local) {
  final source = Alignment.center.inscribe(
      applyBoxFit(BoxFit.cover, pixels, size).source, Offset.zero & pixels);
  // Include interpolation support, including medium's downscale footprint.
  final padding = math.max(2.0,
      math.max(source.width / size.width, source.height / size.height) * 2);
  return Rect.fromLTRB(
          source.left + local.left / size.width * source.width,
          source.top + local.top / size.height * source.height,
          source.left + local.right / size.width * source.width,
          source.top + local.bottom / size.height * source.height)
      .inflate(padding);
}

bool _clearCoverGlow(CoverContourCoverage coverage, Size size, Offset point) =>
    coverage.isClear(_coverSourceRegion(
        Size(coverage.width.toDouble(), coverage.height.toDouble()),
        size,
        Rect.fromCircle(
            center: point,
            radius: (size.shortestSide * .22).clamp(24.0, 104.0) + 11)));

class CoverContourPainter extends CustomPainter {
  CoverContourPainter(
      {required this.mask,
      this.maskCoverage,
      this.currentFrame,
      this.refraction,
      required this.pointer,
      required this.opacity,
      this.maskOpacity,
      required this.color,
      super.repaint});
  final ui.Image? mask;
  final CoverContourCoverage? maskCoverage;
  final ui.Image? currentFrame;
  final CoverRefractionMesh? refraction;
  final Offset? Function() pointer;
  final double Function() opacity;
  final double Function()? maskOpacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
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
    final frame = currentFrame;
    final mesh = refraction;
    if (alpha < 1 && frame != null && mesh != null) {
      final lens = CoverRefractionMesh.lensFor(size, point);
      if (!lens.outerRect.overlaps(bounds)) {
        _paintGlow(canvas, size, point, alpha);
        return;
      }
      final radius = (size.shortestSide * .22).clamp(24.0, 104.0);
      final fadeBounds =
          Rect.fromCircle(center: point, radius: radius + 7).intersect(bounds);
      canvas.save();
      canvas.clipRect(fadeBounds);
      canvas.saveLayer(fadeBounds, Paint());
      mesh.paint(canvas, size, frame, point, 1);
      _paintGlow(canvas, size, point, 1);
      // Fade the completed highlight and refraction together. Fading glow
      // over an independently mixed base introduces a second-order brightness
      // peak even with fixed UVs. This is a premultiplied convex crossfade.
      canvas.drawRect(
          fadeBounds,
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..blendMode = BlendMode.dstIn);
      final imageSize = Size(frame.width.toDouble(), frame.height.toDouble());
      final source = Alignment.center.inscribe(
          applyBoxFit(BoxFit.cover, imageSize, size).source,
          Offset.zero & imageSize);
      canvas.save();
      canvas.clipRect(lens.outerRect, doAntiAlias: false);
      canvas.drawImageRect(
          frame,
          source,
          bounds,
          Paint()
            ..filterQuality = FilterQuality.high
            ..color = Colors.white.withValues(alpha: 1 - alpha)
            ..blendMode = BlendMode.plus);
      canvas.restore();
      canvas.restore();
      canvas.restore();
      return;
    }
    if (currentFrame case final frame?) {
      refraction?.paint(canvas, size, frame, point, alpha);
    }
    _paintGlow(canvas, size, point, alpha);
  }

  void _paintGlow(Canvas canvas, Size size, Offset point, double alpha) {
    final image = mask;
    if (image == null) return;
    // A textured or alpha-varying frame can need refraction even when this
    // mask region has no contour. Do not allocate two empty glow layers or a
    // shader/mesh in that case; the artwork branch remains active.
    final coverage = maskCoverage;
    if (coverage != null && _clearCoverGlow(coverage, size, point)) return;
    final bounds = Offset.zero & size;
    final glowAlpha = alpha * (maskOpacity?.call() ?? 1);
    if (!glowAlpha.isFinite || glowAlpha <= 0) return;
    final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, sourceSize, size);
    final source =
        Alignment.center.inscribe(fit.source, Offset.zero & sourceSize);
    final radius = (math.min(size.width, size.height) * .22).clamp(24.0, 104.0);
    // Include three blur sigmas, then clip explicitly before either layer.
    // saveLayer's bounds alone are only an allocation hint to the backend.
    final glowBounds =
        Rect.fromCircle(center: point, radius: radius + 7).intersect(bounds);
    if (glowBounds.isEmpty) return;
    final shader = RadialGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: const [0, .28, 1])
        .createShader(Rect.fromCircle(center: point, radius: radius));
    final tint = Color.lerp(color, Colors.white, .62)!;
    // The central coordinates match the artwork; the outer ring has zero
    // displacement, so no rounded inside/outside mask partition is needed.
    final maskDraw = currentFrame == null
        ? null
        : refraction?._prepareGlow(size, image, point, radius + 7);
    canvas.save();
    canvas.clipRect(glowBounds);
    try {
      for (final soft in [true, false]) {
        final layer = Paint();
        if (soft)
          layer.imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2);
        canvas.saveLayer(glowBounds, layer);
        final tintFilter = ColorFilter.mode(
            tint.withValues(alpha: glowAlpha.clamp(0, 1) * (soft ? .45 : .82)),
            BlendMode.srcIn);
        if (maskDraw == null) {
          canvas.drawImageRect(
              image,
              source,
              bounds,
              Paint()
                ..filterQuality = FilterQuality.medium
                ..colorFilter = tintFilter);
        } else {
          maskDraw.paint(canvas,
              colorFilter: tintFilter, blendMode: BlendMode.src, clip: false);
        }
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
      maskCoverage != oldDelegate.maskCoverage ||
      currentFrame != oldDelegate.currentFrame ||
      maskOpacity != oldDelegate.maskOpacity ||
      color != oldDelegate.color ||
      pointer != oldDelegate.pointer ||
      opacity != oldDelegate.opacity;
}
