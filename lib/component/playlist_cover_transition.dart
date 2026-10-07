import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_toolbar_style.dart';
import 'category_cover_flight.dart';
import 'category_tile_layout.dart';
import 'cover_image_readiness.dart';
import 'cover_route_landing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Route navigation is separate from the bounded, in-page layout tracker.
/// Reuse the decoded source artwork while the card lands in the detail header.
class PlaylistCoverRouteFlight extends StatefulWidget {
  const PlaylistCoverRouteFlight({
    super.key,
    required this.playlistId,
    required this.borderRadius,
    required this.child,
  });

  final String playlistId;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<PlaylistCoverRouteFlight> createState() =>
      _PlaylistCoverRouteFlightState();
}

class _PlaylistCoverRouteFlightState extends State<PlaylistCoverRouteFlight>
    with WidgetsBindingObserver {
  final _contentKey = GlobalKey();
  late final _landing =
      CoverRouteLandingController(canRetain: () => mounted && _allowsFlight);

  bool get _allowsFlight => coverFlightMotionAllowed(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (!mounted) return;
    if (!_allowsFlight) _landing.retire(notify: false);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (!_allowsFlight) _landing.retire(notify: false);
    setState(() {});
  }

  @override
  void didUpdateWidget(PlaylistCoverRouteFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId) {
      _landing.retire(notify: false);
    }
  }

  @override
  void dispose() {
    _landing.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _PlaylistRouteContent(
        key: _contentKey,
        owner: this,
        borderRadius: widget.borderRadius,
        // The artwork owns its natural square in centered circle tiles. Only
        // the temporary landing image fills that already established geometry.
        child: CoverRouteLanding(
            controller: _landing,
            identity: widget.playlistId,
            borderRadius: widget.borderRadius,
            imageKey: const ValueKey('playlist-route-landing-image'),
            child: widget.child));
    if (!_allowsFlight) {
      return content;
    }
    return Hero(
      tag: ('playlist-route-cover', widget.playlistId),
      // Keep the destination's image future and decoded image mounted. Hero's
      // default empty placeholder would restart artwork on arrival/pop.
      placeholderBuilder: (_, size, child) => SizedBox.fromSize(
          size: size,
          child: Offstage(child: TickerMode(enabled: false, child: child))),
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final source = (from.widget as Hero).child as _PlaylistRouteContent;
        final destination = (to.widget as Hero).child as _PlaylistRouteContent;
        final render = from.findRenderObject();
        final image = render == null ? null : firstDecodedCoverImage(render);
        destination.owner._landing.acceptSource(image);
        return CoverFlightMotionGate(
            child: _PlaylistRouteShuttle(
                animation: animation,
                direction: direction,
                from: source.borderRadius,
                to: destination.borderRadius,
                image: image,
                placeholderColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                placeholderIconColor: Theme.of(context).colorScheme.primary));
      },
      child: content,
    );
  }
}

class _PlaylistRouteContent extends StatelessWidget {
  const _PlaylistRouteContent(
      {super.key,
      required this.owner,
      required this.borderRadius,
      required this.child});
  final _PlaylistCoverRouteFlightState owner;
  final BorderRadius borderRadius;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _PlaylistRouteShuttle extends StatefulWidget {
  const _PlaylistRouteShuttle({
    required this.animation,
    required this.direction,
    required this.from,
    required this.to,
    required this.image,
    required this.placeholderColor,
    required this.placeholderIconColor,
  });
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final BorderRadius from, to;
  final ui.Image? image;
  final Color placeholderColor, placeholderIconColor;
  @override
  State<_PlaylistRouteShuttle> createState() => _PlaylistRouteShuttleState();
}

class _PlaylistRouteShuttleState extends State<_PlaylistRouteShuttle> {
  ui.Image? _image;
  @override
  void initState() {
    super.initState();
    _image = widget.image?.clone();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.animation,
      child: _image == null
          ? ColoredBox(
              color: widget.placeholderColor,
              child: Center(
                  child: Icon(Icons.queue_music,
                      color: widget.placeholderIconColor)))
          : RawImage(
              key: const ValueKey('playlist-route-flight-image'),
              image: _image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium),
      builder: (context, child) => ClipRRect(
          borderRadius: BorderRadius.lerp(
              widget.from,
              widget.to,
              widget.direction == HeroFlightDirection.push
                  ? widget.animation.value
                  : 1 - widget.animation.value)!,
          child: child));
}

/// Tree song cards share a lazy row; map occurrence IDs to those visual rows.
class PlaylistCoverLayoutIndices extends InheritedWidget {
  const PlaylistCoverLayoutIndices(
      {super.key,
      required this.indices,
      this.seekTreeSong,
      this.motion,
      required super.child});
  final Map<Object, int> indices;
  final Listenable? motion;

  /// Returns null for a non-song, otherwise whether the lazy tree rail moved.
  final bool? Function(Object id, bool atStart)? seekTreeSong;
  @override
  bool updateShouldNotify(PlaylistCoverLayoutIndices oldWidget) =>
      oldWidget.indices != indices ||
      oldWidget.seekTreeSong != seekTreeSong ||
      oldWidget.motion != motion;
}

/// A one-shot transition between lazy playlist layouts. No images or ticker
/// remain after settling. Rapid repeated changes deliberately switch directly.
class PlaylistCoverTransitionController extends ChangeNotifier {
  _PlaylistCoverTransitionHostState? _host;
  bool get busy => _host?._busy ?? false;
  bool get active => _host?._flights.isNotEmpty ?? false;
  @visibleForTesting
  int get debugSnapshotCount => _host?._flights.length ?? 0;

  @visibleForTesting
  int get debugCaptureCount => _host?._captureCount ?? 0;
  @visibleForTesting
  int get debugRasterCaptureCount => _host?._rasterCaptureCount ?? 0;
  @visibleForTesting
  int get debugReusedImageCount => _host?._reusedImageCount ?? 0;

  Future<void> transition(VoidCallback update,
      {bool preserveAnchor = true,
      bool animateArrival = true,
      Set<Object>? captureIds}) async {
    final host = _host;
    if (host == null) {
      update();
    } else {
      await host._transition(update,
          preserveAnchor: preserveAnchor,
          animateArrival: animateArrival,
          captureIds: captureIds);
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
    this.itemIds = const [],
  });

  final PlaylistCoverTransitionController controller;
  final Widget child;
  final List<Object> itemIds;
  static const duration = Duration(milliseconds: 220);
  static const maximumSnapshots = 40;
  static const maximumSnapshotSide = 384.0;
  static const captureBudget = Duration(milliseconds: 64);

  @override
  State<PlaylistCoverTransitionHost> createState() =>
      _PlaylistCoverTransitionHostState();
}

class _PlaylistCoverTransitionHostState
    extends State<PlaylistCoverTransitionHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _boxKey = GlobalKey();
  final _markers = <Object, _PlaylistCoverTransitionMarkerState>{};
  final _flights = <_CoverFlight>[];
  final _geometryMotion = ValueNotifier(0);
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
  // The old image fades over an opaque destination. Fading both surfaces
  // against the background would dim identical artwork halfway through.
  late final Animation<double> _destinationVisibility =
      _handoff.drive(CurveTween(curve: const Threshold(0)));
  late final Animation<double> _arrival = _animation.drive(
      CurveTween(curve: const Interval(0, .7, curve: Curves.easeOutCubic)));
  Timer? _readinessTimeout;
  bool _waitingForImage = false;
  bool _readinessScheduled = false;
  bool _busy = false;
  bool _starting = false;
  int _generation = 0;
  _CaptureJob? _capture;
  Timer? _burstCooldown;
  bool _animateArrival = true;
  int _captureCount = 0;
  int _rasterCaptureCount = 0, _reusedImageCount = 0;
  BoxConstraints? _viewportConstraints;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (_busy && appToolbarReduceMotion(context, kind: MotionKind.tracking)) {
      // Dependency changes run during build; clear this frame without setState.
      _retireForMotionPolicy(notify: false);
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_busy && appToolbarReduceMotion(context, kind: MotionKind.tracking)) {
      _retireForMotionPolicy();
    }
  }

  void _retireForMotionPolicy({bool notify = true}) {
    _burstCooldown?.cancel();
    _burstCooldown = null;
    if (_capture case final capture?) {
      // Retire pixels, preserving the user's pending view change. The bounded
      // capture completion applies it without a flight, just as scrolling does.
      capture.dispose();
    } else {
      _cancel(notify: notify);
    }
  }

  RenderBox? get _hostBox {
    final render = _boxKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render
        : null;
  }

  _CoverGeometry? _geometry(_PlaylistCoverTransitionMarkerState marker,
      {bool visibleOnly = true}) {
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
    if (visibleOnly && !visible.overlaps(rect)) return null;
    return _CoverGeometry(rect, marker.widget.borderRadius, render);
  }

  _CoverGeometry? _movingTarget(Object id) {
    final marker = _markers[id];
    if (marker == null) return null;
    // A first circular/list appearance can still rise on its own staggered
    // entrance clock. Its first laid-out rectangle is not its landing position.
    // Resolve during paint, including while a late destination image is held.
    return _geometry(marker);
  }

  void _markerMotion(Object id) {
    if (!_hidden.contains(id)) return;
    _geometryMotion.value++;
    _imageMayBeReady();
  }

  Future<void> _transition(VoidCallback update,
      {required bool preserveAnchor,
      required bool animateArrival,
      Set<Object>? captureIds}) async {
    if (!mounted) return;
    final visible = <(Object, _CoverGeometry)>[
      for (final entry in _markers.entries)
        if (_geometry(entry.value) case final geometry?) (entry.key, geometry),
    ]..sort((a, b) {
        final vertical = a.$2.rect.top.compareTo(b.$2.rect.top);
        return vertical != 0
            ? vertical
            : a.$2.rect.left.compareTo(b.$2.rect.left);
      });
    final anchor = visible.isEmpty ? null : visible.first.$1;
    final sourceScroll = anchor == null
        ? null
        : Scrollable.maybeOf(_markers[anchor]!.context)?.position;
    final atStart = sourceScroll == null ||
        sourceScroll.pixels <= sourceScroll.minScrollExtent + 1;
    if (_busy || _burstCooldown != null) {
      final retained = <_CoverFlight>[];
      if (!appToolbarReduceMotion(context, kind: MotionKind.tracking)) {
        final oldFlights = {for (final flight in _flights) flight.id: flight};
        for (final entry
            in visible.take(PlaylistCoverTransitionHost.maximumSnapshots)) {
          if (captureIds != null && !captureIds.contains(entry.$1)) continue;
          final old = oldFlights[entry.$1];
          final image = decodedCoverImage(entry.$2.boundary) ??
              (old?.hadImage == true ? old!.image : null);
          if (image != null) {
            retained.add(_CoverFlight(entry.$1, entry.$2, image.clone(),
                hadImage: true));
            _reusedImageCount++;
          }
        }
      }
      _cancel();
      _burstCooldown?.cancel();
      // One finite cooldown covers the whole click burst. Keep decoded artwork
      // until the new Image attaches, without another raster capture or flight.
      _burstCooldown = Timer(const Duration(milliseconds: 250), () {
        _burstCooldown = null;
      });
      if (retained.isNotEmpty) {
        setState(() {
          _animation.value = 1;
          _handoff.value = 0;
          _flights.addAll(retained);
          _hidden = retained.map((flight) => flight.id).toSet();
          _animateArrival = false;
          _busy = true;
          _starting = true;
        });
      }
      update();
      _land(_generation, preserveAnchor ? anchor : null, 0,
          atStart: atStart, animate: retained.isNotEmpty, instant: true);
      return;
    }
    if (appToolbarReduceMotion(context, kind: MotionKind.tracking) ||
        _hostBox == null) {
      update();
      return;
    }
    final sources = visible
        .where((entry) => captureIds == null || captureIds.contains(entry.$1))
        .take(PlaylistCoverTransitionHost.maximumSnapshots)
        .toList();
    if (sources.isEmpty) {
      update();
      return;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final viewportConstraints = _viewportConstraints;
    final generation = ++_generation;
    final capture = _CaptureJob();
    _capture = capture;
    _animateArrival = animateArrival;
    _captureCount++;
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
          final retained = decodedCoverImage(geometry.boundary);
          final ui.Image image;
          if (retained != null) {
            // The decoded texture already exists. Clone only its handle, not
            // pixels; pure cover flights need no GPU render/readback batch.
            image = retained.clone();
            _reusedImageCount++;
          } else {
            _rasterCaptureCount++;
            image = await geometry.boundary.toImage(pixelRatio: ratio);
          }
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
    if (viewportConstraints != _viewportConstraints) {
      // Resizing while GPU capture is pending must still apply the requested
      // view change; only its obsolete snapshots are discarded.
      capture.dispose();
      _busy = false;
      widget.controller._notify();
      update();
      return;
    }
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
    _land(generation, preserveAnchor ? anchor : null, 0, atStart: atStart);
  }

  void _land(int generation, Object? anchor, int attempt,
      {required bool atStart, bool animate = true, bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (anchor != null &&
          attempt < 8 &&
          _seekAnchor(anchor, atStart: atStart)) {
        _land(generation, anchor, attempt + 1,
            atStart: atStart, animate: animate, instant: instant);
        WidgetsBinding.instance.ensureVisualUpdate();
        return;
      }
      if (!animate) return;
      for (final flight in _flights) {
        final marker = _markers[flight.id];
        flight.target = marker == null ? null : _geometry(marker);
      }
      _starting = false;
      if (instant) {
        _tryReveal();
      } else {
        _animation.forward(from: 0);
      }
    });
  }

  // Reposition only the lazy viewport. Never build the full playlist to find a
  // destination, and never change model order or per-level view preferences.
  bool _seekAnchor(Object id, {required bool atStart}) {
    final targetIndex = widget.itemIds.indexOf(id);
    if (targetIndex < 0 || _markers.isEmpty) return false;
    final treeLayout = _markers.values.first.context
        .getInheritedWidgetOfExactType<PlaylistCoverLayoutIndices>();
    if (treeLayout?.seekTreeSong?.call(id, atStart) case final bool moved) {
      return moved;
    }
    final marker = _markers[id] ?? _markers.values.first;
    final scroll = Scrollable.maybeOf(marker.context);
    final geometry = _geometry(marker, visibleOnly: false);
    if (scroll == null || geometry == null) return false;
    final position = scroll.position;
    if (!position.hasContentDimensions) return false;
    // Tree search/actions sit above the list inside this host. Anchor against
    // the actual scroll viewport, otherwise each retry adds that header again.
    final viewport = scroll.context.findRenderObject();
    final host = _hostBox;
    final viewportTop = viewport is RenderBox && host != null
        ? MatrixUtils.transformRect(
                viewport.getTransformTo(host), Offset.zero & viewport.size)
            .top
        : 0.0;
    double offset;
    if (atStart) {
      // A cover's inset is not a scroll offset. Keep the first row whole,
      // regardless of the destination's search bar or card padding.
      offset = position.minScrollExtent;
    } else if (marker.widget.entryId == id) {
      offset = position.pixels + geometry.rect.top - viewportTop;
    } else {
      RenderObject? child = marker._boundary.currentContext?.findRenderObject();
      while (child != null && child.parent is! RenderSliverMultiBoxAdaptor) {
        child = child.parent;
      }
      final sliver = child?.parent;
      if (sliver is RenderSliverGrid) {
        var index = targetIndex;
        final delegate = sliver.gridDelegate;
        if (delegate is CategoryTileGridDelegate) {
          index =
              delegate.tiles.indexWhere((tile) => tile.index == targetIndex);
        }
        if (index < 0) return false;
        offset = delegate
            .getLayout(sliver.constraints)
            .getGeometryForChildIndex(index)
            .scrollOffset;
      } else if (child is RenderBox) {
        final visualRows = marker.context
            .getInheritedWidgetOfExactType<PlaylistCoverLayoutIndices>()
            ?.indices;
        final index = visualRows?[marker.widget.entryId] ??
            widget.itemIds.indexOf(marker.widget.entryId);
        final rowTarget = visualRows?[id] ?? targetIndex;
        if (index < 0) return false;
        offset = position.pixels +
            geometry.rect.top -
            viewportTop +
            (rowTarget - index) * child.size.height;
      } else {
        return false;
      }
    }
    final target =
        offset.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 1) return false;
    position.jumpTo(target);
    return true;
  }

  void _motionTick() {
    if (_animation.value >= .7 && !_waitingForImage) _tryReveal();
  }

  bool _targetsReady() => _flights.every((flight) =>
      flight.target == null ||
      ((_markers[flight.id]?._motionReady ?? true) &&
          (!flight.hadImage || hasDecodedCoverImage(flight.target!.boundary))));

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
      if (_capture case final capture?) {
        // Scrolling invalidates the source geometry, not the user's selected
        // view. Empty the capture so its completion applies that selection
        // without a flight. A newer selection/explicit cancel still invalidates
        // its generation and cannot be overwritten by this pending request.
        capture.dispose();
      } else {
        _cancel();
      }
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel(notify: false);
    if (identical(widget.controller._host, this)) {
      widget.controller._host = null;
    }
    _burstCooldown?.cancel();
    _animation.dispose();
    _handoff.dispose();
    _geometryMotion.dispose();
    super.dispose();
  }

  Rect? _visibleViewport() {
    final host = _hostBox;
    if (host == null) return null;
    for (final marker in _markers.values) {
      final viewport = Scrollable.maybeOf(marker.context, axis: Axis.vertical)
          ?.context
          .findRenderObject();
      if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
        return MatrixUtils.transformRect(
            viewport.getTransformTo(host), Offset.zero & viewport.size);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (_viewportConstraints != constraints) {
          _viewportConstraints = constraints;
          // Snapshots and landing rectangles belong to the captured viewport.
          // A window/header resize must expose the freshly laid-out covers instead
          // of flying to old coordinates (or holding them while artwork loads).
          if (_flights.isNotEmpty) {
            _cancel(notify: false);
            final generation = _generation;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && generation == _generation) {
                widget.controller._notify();
              }
            });
          }
        }
        return _CoverTransitionScope(
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
                          List.unmodifiable(_flights), _animation, _reveal,
                          geometryMotion: _geometryMotion,
                          clip: _visibleViewport,
                          resolveTarget: _movingTarget)),
                ))),
            ]),
          ),
        );
      });
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

/// Reuses the flight clock; paint-only scaling leaves target geometry and
/// drag hit boxes at their final layout positions throughout the transition.
class PlaylistItemArrival extends StatelessWidget {
  const PlaylistItemArrival({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_CoverTransitionScope>();
    final animation =
        scope != null && scope.hidden.isNotEmpty && scope.owner._animateArrival
            ? scope.owner._arrival
            : const AlwaysStoppedAnimation<double>(1);
    return FadeTransition(
        opacity: animation,
        child: _ArrivalScale(animation: animation, child: child));
  }
}

class _ArrivalScale extends SingleChildRenderObjectWidget {
  const _ArrivalScale({required this.animation, required super.child});
  final Animation<double> animation;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArrivalScale(animation);
  @override
  void updateRenderObject(
      BuildContext context, _RenderArrivalScale renderObject) {
    renderObject.animation = animation;
  }
}

class _RenderArrivalScale extends RenderProxyBox {
  _RenderArrivalScale(this._animation);
  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    if (attached) _animation.removeListener(markNeedsPaint);
    _animation = value;
    if (attached) _animation.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final scale = .94 + .06 * _animation.value;
    if (scale >= 1) {
      super.paint(context, offset);
      return;
    }
    final matrix = Matrix4.identity()
      ..translateByDouble(
          size.width * (1 - scale) / 2, size.height * (1 - scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    context.pushTransform(needsCompositing, offset, matrix, super.paint);
  }
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
  Animation<double>? _entranceMotion;
  Listenable? _layoutMotion;

  // Retiring an opaque flight before the card's first-appearance fade ends
  // would briefly dim the artwork even when its moving geometry is aligned.
  bool get _motionReady =>
      (_entranceMotion?.value ?? 1) >= 1 &&
      !(_layoutMotion is AnimationController &&
          (_layoutMotion as AnimationController).isAnimating);

  void _motionChanged() => _owner?._markerMotion(widget.entryId);

  void _detachMotion() {
    _entranceMotion?.removeListener(_motionChanged);
    _layoutMotion?.removeListener(_motionChanged);
    _entranceMotion = null;
    _layoutMotion = null;
  }

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
    final entranceMotion = AppEntrance.motionOf(context);
    final layoutMotion = context
        .dependOnInheritedWidgetOfExactType<PlaylistCoverLayoutIndices>()
        ?.motion;
    if (entranceMotion != _entranceMotion || layoutMotion != _layoutMotion) {
      _detachMotion();
      _entranceMotion = entranceMotion;
      _layoutMotion = layoutMotion;
      _entranceMotion?.addListener(_motionChanged);
      _layoutMotion?.addListener(_motionChanged);
    }
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
    _detachMotion();
    _unregister();
    super.deactivate();
  }

  @override
  void dispose() {
    _detachMotion();
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_CoverTransitionScope>();
    return FadeTransition(
      opacity: scope?.hidden.contains(widget.entryId) == true
          ? scope!.owner._destinationVisibility
          : const AlwaysStoppedAnimation(1),
      child: RepaintBoundary(
          key: _boundary,
          child: CoverImageReadinessObserver(
              onChanged: () => _owner?._imageMayBeReady(),
              hidePlaceholder: scope?.hidden.contains(widget.entryId) == true &&
                  scope!.owner._flights.any((flight) =>
                      flight.id == widget.entryId && flight.hadImage),
              child: widget.child)),
    );
  }
}

class _CoverGeometry {
  _CoverGeometry(this.rect, this.radius, this.boundary)
      : hadImage = hasDecodedCoverImage(boundary);
  final bool hadImage;
  final Rect rect;
  final BorderRadius radius;
  final RenderRepaintBoundary boundary;
}

class _CoverFlight {
  _CoverFlight(this.id, this.source, this.image, {bool? hadImage})
      : hadImage = hadImage ?? source.hadImage;
  final bool hadImage;
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
  _CoverFlightsPainter(this.flights, this.animation, this.reveal,
      {required this.clip,
      required Listenable geometryMotion,
      this.resolveTarget})
      : super(repaint: Listenable.merge([animation, reveal, geometryMotion]));
  final List<_CoverFlight> flights;
  final Animation<double> animation;
  final Animation<double> reveal;
  final Rect? Function() clip;
  final _CoverGeometry? Function(Object)? resolveTarget;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(
        (Offset.zero & size).intersect(clip() ?? (Offset.zero & size)));
    // Finish geometry before revealing the destination; otherwise two covers
    // at different positions overlap throughout the handoff.
    final progress =
        Curves.easeInOutCubic.transform((animation.value / .7).clamp(0.0, 1.0));
    for (final flight in flights) {
      final destination = resolveTarget?.call(flight.id) ?? flight.target;
      final target = destination ?? flight.source;
      final rect = Rect.lerp(flight.source.rect, target.rect, progress)!;
      final radius =
          BorderRadius.lerp(flight.source.radius, target.radius, progress)!;
      // The destination is already revealed during the handoff. Cross-fading
      // the same cover over it double-composites its pixels (and can dim solid
      // colors by one channel value), so keep the flight opaque until the
      // handoff clock finishes and the fully settled marker owns the pixels.
      final opacity = destination == null ? 1 - progress : 1.0;
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
