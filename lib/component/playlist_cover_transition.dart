import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A one-shot transition between lazy playlist layouts. No images or ticker
/// remain after settling. Rapid repeated changes deliberately switch directly.
class PlaylistCoverTransitionController extends ChangeNotifier {
  _PlaylistCoverTransitionHostState? _host;
  bool get busy => _host?._busy ?? false;
  bool get active => _host?._flights.isNotEmpty ?? false;
  @visibleForTesting
  int get debugSnapshotCount => _host?._flights.length ?? 0;

  Future<void> transition(VoidCallback update) async {
    final host = _host;
    if (host == null) {
      update();
    } else {
      await host._transition(update);
    }
  }

  void cancel() => _host?._cancel();

  void _notify() => notifyListeners();

  @override
  void dispose() {
    final host = _host;
    _host = null;
    host?._cancel(notify: false);
    super.dispose();
  }
}

/// Place around the bounded scrolling body, excluding headers and toolbars.
class PlaylistCoverTransitionHost extends StatefulWidget {
  const PlaylistCoverTransitionHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final PlaylistCoverTransitionController controller;
  final Widget child;
  static const duration = Duration(milliseconds: 220);
  static const maximumSnapshots = 40;
  static const maximumSnapshotSide = 384.0;
  static const captureBudget = Duration(milliseconds: 64);

  @override
  State<PlaylistCoverTransitionHost> createState() =>
      _PlaylistCoverTransitionHostState();
}

class _PlaylistCoverTransitionHostState
    extends State<PlaylistCoverTransitionHost> with TickerProviderStateMixin {
  final _boxKey = GlobalKey();
  final _markers = <Object, _PlaylistCoverTransitionMarkerState>{};
  final _flights = <_CoverFlight>[];
  Set<Object> _hidden = const {};
  late final _animation = AnimationController(
    vsync: this,
    duration: PlaylistCoverTransitionHost.duration,
    value: 1,
  )
    ..addStatusListener(_status)
    ..addListener(_motionTick);
  late final _handoff = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 66),
    value: 1,
  )..addStatusListener(_handoffStatus);
  late final Animation<double> _reveal =
      _handoff.drive(CurveTween(curve: Curves.easeOut));
  Timer? _readinessTimeout;
  bool _waitingForImage = false;
  bool _readinessScheduled = false;
  bool _busy = false;
  bool _starting = false;
  int _generation = 0;
  _CaptureJob? _capture;

  @override
  void initState() {
    super.initState();
    assert(widget.controller._host == null);
    widget.controller._host = this;
  }

  @override
  void didUpdateWidget(PlaylistCoverTransitionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._host = null;
      _cancel(notify: false);
      assert(widget.controller._host == null);
      widget.controller._host = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_busy && appToolbarReduceMotion(context)) {
      // Dependency changes run during build; clear this frame without setState.
      _cancel(notify: false);
    }
  }

  RenderBox? get _hostBox {
    final render = _boxKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render
        : null;
  }

  _CoverGeometry? _geometry(_PlaylistCoverTransitionMarkerState marker) {
    final host = _hostBox;
    final render = marker._boundary.currentContext?.findRenderObject();
    if (host == null ||
        render is! RenderRepaintBoundary ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
        render.getTransformTo(host), Offset.zero & render.size);
    if (!rect.isFinite || rect.isEmpty) return null;
    var visible = Offset.zero & host.size;
    final scroll = Scrollable.maybeOf(marker.context);
    final viewport = scroll?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      visible = visible.intersect(MatrixUtils.transformRect(
          viewport.getTransformTo(host), Offset.zero & viewport.size));
    }
    if (!visible.overlaps(rect)) return null;
    return _CoverGeometry(rect, marker.widget.borderRadius, render);
  }

  Future<void> _transition(VoidCallback update) async {
    if (!mounted) return;
    if (_busy) {
      _cancel();
      update();
      return;
    }
    if (appToolbarReduceMotion(context) || _hostBox == null) {
      update();
      return;
    }
    final sources = <(Object, _CoverGeometry)>[];
    for (final entry in _markers.entries) {
      final geometry = _geometry(entry.value);
      if (geometry != null) sources.add((entry.key, geometry));
      if (sources.length == PlaylistCoverTransitionHost.maximumSnapshots) break;
    }
    if (sources.isEmpty) {
      update();
      return;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final generation = ++_generation;
    final capture = _CaptureJob();
    _capture = capture;
    _busy = true;
    widget.controller._notify();
    var next = 0;
    Future<void> worker() async {
      while (!capture.closed && next < sources.length) {
        final source = sources[next++];
        final geometry = source.$2;
        try {
          var needsPaint = false;
          assert(() {
            needsPaint = geometry.boundary.debugNeedsPaint;
            return true;
          }());
          if (needsPaint || !geometry.boundary.attached) continue;
          final ratio = math.min(
            pixelRatio,
            PlaylistCoverTransitionHost.maximumSnapshotSide /
                math.max(geometry.boundary.size.width,
                    geometry.boundary.size.height),
          );
          final image = await geometry.boundary.toImage(pixelRatio: ratio);
          if (capture.closed || !mounted || generation != _generation) {
            image.dispose();
          } else {
            capture.flights.add(_CoverFlight(source.$1, geometry, image));
          }
        } catch (_) {
          // An unpainted/disposed cover falls back to the ordinary lazy layout.
        }
      }
    }

    await Future.wait(
            List.generate(math.min(4, sources.length), (_) => worker()))
        .timeout(PlaylistCoverTransitionHost.captureBudget,
            onTimeout: () => []);
    capture.closed = true;
    if (!mounted || generation != _generation) {
      capture.dispose();
      return;
    }
    _capture = null;
    _flights.addAll(capture.flights);
    capture.flights.clear();
    if (_flights.isEmpty) {
      _busy = false;
      widget.controller._notify();
      update();
      return;
    }
    setState(() {
      _starting = true;
      _hidden = _flights.map((flight) => flight.id).toSet();
      _animation.value = 0;
      _handoff.value = 0;
    });
    update();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      for (final flight in _flights) {
        final marker = _markers[flight.id];
        flight.target = marker == null ? null : _geometry(marker);
      }
      _starting = false;
      _animation.forward(from: 0);
    });
  }

  void _motionTick() {
    if (_animation.value >= .7 && !_waitingForImage) _tryReveal();
  }

  bool _targetsReady() => _flights.every((flight) =>
      flight.target == null ||
      !flight.source.hadImage ||
      _hasImage(flight.target!.boundary));

  void _tryReveal() {
    if (!_busy ||
        _flights.isEmpty ||
        _handoff.value > 0 ||
        _handoff.isAnimating) {
      return;
    }
    if (_targetsReady()) {
      _beginReveal();
    } else {
      _waitingForImage = true;
      // Match ArtworkHandoff's bounded load lifetime. This one-shot timeout
      // never polls or drives idle frames while a disk/network codec is pending.
      _readinessTimeout ??= Timer(const Duration(seconds: 10), _beginReveal);
    }
  }

  void _beginReveal() {
    if (!mounted || !_busy) return;
    _readinessTimeout?.cancel();
    _readinessTimeout = null;
    _waitingForImage = false;
    _handoff.forward();
  }

  void _imageMayBeReady() {
    if (!_waitingForImage || _readinessScheduled) return;
    _readinessScheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readinessScheduled = false;
      if (mounted &&
          generation == _generation &&
          _waitingForImage &&
          _targetsReady()) {
        _beginReveal();
      }
    });
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && _busy) {
      if (_handoff.isCompleted) {
        _cancel();
      } else {
        _tryReveal();
      }
    }
  }

  void _handoffStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _animation.isCompleted &&
        _busy) {
      _cancel();
    }
  }

  void _cancel({bool notify = true}) {
    _generation++;
    _capture?.dispose();
    _capture = null;
    _animation.stop();
    _handoff.stop();
    _readinessTimeout?.cancel();
    _readinessTimeout = null;
    _waitingForImage = false;
    _readinessScheduled = false;
    final images = _flights.map((flight) => flight.image).toList();
    if (notify && mounted && images.isNotEmpty) {
      // A scroll notification can arrive after layout: retire the old paint
      // layer before releasing its textures at the end of that frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final image in images) {
          image.dispose();
        }
      });
    } else {
      for (final image in images) {
        image.dispose();
      }
    }
    _flights.clear();
    _hidden = const {};
    final changed = _busy;
    _busy = false;
    _starting = false;
    if (notify && mounted) {
      setState(() {});
      if (changed && identical(widget.controller._host, this)) {
        widget.controller._notify();
      }
    }
  }

  bool _scroll(ScrollNotification notification) {
    if (_busy &&
        !_starting &&
        (notification is ScrollStartNotification ||
            notification is ScrollUpdateNotification)) {
      _cancel();
    }
    return false;
  }

  @override
  void dispose() {
    _cancel(notify: false);
    if (identical(widget.controller._host, this)) {
      widget.controller._host = null;
    }
    _animation.dispose();
    _handoff.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CoverTransitionScope(
        owner: this,
        hidden: _hidden,
        child: NotificationListener<ScrollNotification>(
          onNotification: _scroll,
          child: Stack(key: _boxKey, fit: StackFit.expand, children: [
            widget.child,
            if (_flights.isNotEmpty)
              Positioned.fill(
                  child: IgnorePointer(
                      child: RepaintBoundary(
                child: CustomPaint(
                    painter: _CoverFlightsPainter(
                        List.unmodifiable(_flights), _animation, _reveal)),
              ))),
          ]),
        ),
      );
}

class _CoverTransitionScope extends InheritedWidget {
  const _CoverTransitionScope(
      {required this.owner, required this.hidden, required super.child});
  final _PlaylistCoverTransitionHostState owner;
  final Set<Object> hidden;
  @override
  bool updateShouldNotify(_CoverTransitionScope oldWidget) =>
      owner != oldWidget.owner || !identical(hidden, oldWidget.hidden);
}

/// Wrap the raw image inside its existing shape clip. The marker does not change
/// hit testing or clipping; [entryId] must be stable across all three layouts.
class PlaylistCoverTransitionMarker extends StatefulWidget {
  const PlaylistCoverTransitionMarker(
      {super.key,
      required this.entryId,
      required this.child,
      this.borderRadius = BorderRadius.zero});
  final Object entryId;
  final Widget child;
  final BorderRadius borderRadius;
  @override
  State<PlaylistCoverTransitionMarker> createState() =>
      _PlaylistCoverTransitionMarkerState();
}

class _PlaylistCoverTransitionMarkerState
    extends State<PlaylistCoverTransitionMarker> {
  final _boundary = GlobalKey();
  _PlaylistCoverTransitionHostState? _owner;

  void _unregister() {
    if (identical(_owner?._markers[widget.entryId], this)) {
      _owner?._markers.remove(widget.entryId);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context
        .dependOnInheritedWidgetOfExactType<_CoverTransitionScope>()
        ?.owner;
    if (!identical(owner, _owner)) {
      _unregister();
      _owner = owner;
    }
    _owner?._markers[widget.entryId] = this;
  }

  @override
  void didUpdateWidget(PlaylistCoverTransitionMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId) {
      if (identical(_owner?._markers[oldWidget.entryId], this)) {
        _owner?._markers.remove(oldWidget.entryId);
      }
      _owner?._markers[widget.entryId] = this;
    }
  }

  @override
  void activate() {
    super.activate();
    _owner?._markers[widget.entryId] = this;
  }

  @override
  void deactivate() {
    _unregister();
    super.deactivate();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_CoverTransitionScope>();
    return FadeTransition(
      opacity: scope?.hidden.contains(widget.entryId) == true
          ? scope!.owner._reveal
          : const AlwaysStoppedAnimation(1),
      child: RepaintBoundary(
          key: _boundary,
          child: _CoverReadinessObserver(
              onChanged: () => _owner?._imageMayBeReady(),
              child: widget.child)),
    );
  }
}

class _CoverGeometry {
  _CoverGeometry(this.rect, this.radius, this.boundary)
      : hadImage = _hasImage(boundary);
  final bool hadImage;
  final Rect rect;
  final BorderRadius radius;
  final RenderRepaintBoundary boundary;
}

class _CoverFlight {
  _CoverFlight(this.id, this.source, this.image);
  final Object id;
  final _CoverGeometry source;
  final ui.Image image;
  _CoverGeometry? target;
}

class _CaptureJob {
  bool closed = false;
  final flights = <_CoverFlight>[];
  void dispose() {
    closed = true;
    for (final flight in flights) {
      flight.image.dispose();
    }
    flights.clear();
  }
}

class _CoverFlightsPainter extends CustomPainter {
  _CoverFlightsPainter(this.flights, this.animation, this.reveal)
      : super(repaint: Listenable.merge([animation, reveal]));
  final List<_CoverFlight> flights;
  final Animation<double> animation;
  final Animation<double> reveal;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final progress = Curves.easeInOutCubic.transform(animation.value);
    for (final flight in flights) {
      final target = flight.target ?? flight.source;
      final rect = Rect.lerp(flight.source.rect, target.rect, progress)!;
      final radius =
          BorderRadius.lerp(flight.source.radius, target.radius, progress)!;
      final opacity = flight.target == null ? 1 - progress : 1 - reveal.value;
      if (opacity <= 0) continue;
      final imageSize =
          Size(flight.image.width.toDouble(), flight.image.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, imageSize, rect.size);
      final sourceRect =
          Alignment.center.inscribe(fitted.source, Offset.zero & imageSize);
      canvas.save();
      canvas.clipRRect(radius.toRRect(rect));
      canvas.drawImageRect(
          flight.image,
          sourceRect,
          rect,
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = Colors.white.withValues(alpha: opacity));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverFlightsPainter oldDelegate) =>
      flights != oldDelegate.flights ||
      animation != oldDelegate.animation ||
      reveal != oldDelegate.reveal;
}

bool _hasImage(RenderObject render) {
  if (!render.attached) return false;
  if (render is RenderImage && render.image != null) return true;
  var found = false;
  render.visitChildren((child) {
    if (!found) found = _hasImage(child);
  });
  return found;
}

/// Image completion changes a descendant's layout/paint state even while the
/// target is fully transparent. Observe those events instead of polling frames.
class _CoverReadinessObserver extends SingleChildRenderObjectWidget {
  const _CoverReadinessObserver(
      {required this.onChanged, required super.child});
  final VoidCallback onChanged;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCoverReadiness(onChanged);
  @override
  void updateRenderObject(
      BuildContext context, _RenderCoverReadiness renderObject) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderCoverReadiness extends RenderProxyBox {
  _RenderCoverReadiness(this.onChanged);
  VoidCallback onChanged;
  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    onChanged();
  }

  @override
  void performLayout() {
    super.performLayout();
    onChanged();
  }
}
