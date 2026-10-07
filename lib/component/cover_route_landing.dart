import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'artwork_handoff.dart';
import 'cover_image_readiness.dart';

/// Hero can ask for its shuttle before the destination placeholder mounts.
/// Own that short-lived handle here so it can also retire without another frame.
class CoverRouteLandingController {
  CoverRouteLandingController({required this.canRetain});
  final bool Function() canRetain;
  _CoverRouteLandingState? _owner;
  ui.Image? _queued;
  bool _disposed = false;

  void acceptSource(ui.Image? image) {
    if (_disposed || image == null || !canRetain()) return;
    if (_owner case final owner?) {
      owner._acceptSource(image);
    } else {
      _queued?.dispose();
      _queued = image.clone();
    }
  }

  void _flush() {
    final image = _queued;
    _queued = null;
    if (image == null) return;
    if (!_disposed) _owner?._acceptSource(image);
    image.dispose();
  }

  void retire({bool notify = true}) {
    _queued?.dispose();
    _queued = null;
    _owner?._clear(notify: notify);
  }

  void dispose() {
    _disposed = true;
    retire(notify: false);
    _owner = null;
  }
}

/// Retains a route's decoded source until the real destination cover paints.
/// The endpoint's motion policy is evaluated outside Hero's offstage placeholder,
/// which must keep decoding even while its temporary TickerMode is disabled.
class CoverRouteLanding extends StatefulWidget {
  const CoverRouteLanding({
    super.key,
    required this.identity,
    required this.controller,
    required this.borderRadius,
    required this.imageKey,
    required this.child,
  });
  final Object? identity;
  final CoverRouteLandingController controller;
  final BorderRadius borderRadius;
  final Key imageKey;
  final Widget child;

  @override
  State<CoverRouteLanding> createState() => _CoverRouteLandingState();
}

class _CoverRouteLandingState extends State<CoverRouteLanding>
    with WidgetsBindingObserver {
  final _artKey = GlobalKey();
  final _pendingImages = <ui.Image>{};
  final _imageAnimations = <Animation<double>>{};
  ui.Image? _image;
  Timer? _timeout;
  int _generation = 0;
  bool _readinessScheduled = false;
  bool _suspendPlaceholder = false;

  void _acceptSource(ui.Image? image) {
    if (image == null || !mounted || !widget.controller.canRetain()) return;
    final render = _artKey.currentContext?.findRenderObject();
    if (render is RenderBox && decodedCoverImage(render) != null) return;
    final retained = image.clone();
    _pendingImages.add(retained);
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pendingImages.remove(retained)) return;
      if (!mounted ||
          generation != _generation ||
          !widget.controller.canRetain()) {
        retained.dispose();
        return;
      }
      _clear();
      setState(() {
        _image = retained;
        final render = _artKey.currentContext?.findRenderObject();
        _suspendPlaceholder = render == null || !hasDecodedCoverImage(render);
      });
      _timeout = Timer(ArtworkHandoff.loadTimeout, _clear);
      _imageMayBeReady();
    });
  }

  void _imageMayBeReady() {
    if (_image == null || _readinessScheduled) return;
    _readinessScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readinessScheduled = false;
      if (!mounted || _image == null) return;
      final render = _artKey.currentContext?.findRenderObject();
      _watchImageAnimations(render);
      // A real image can begin at zero opacity. Restore its own finite fade
      // before waiting for strict readiness; only a covered spinner is muted.
      if (_suspendPlaceholder &&
          render != null &&
          hasDecodedCoverImage(render)) {
        setState(() => _suspendPlaceholder = false);
      }
      if (render is RenderBox && decodedCoverImage(render) != null) _clear();
    });
  }

  void _clear({bool notify = true}) {
    ++_generation;
    for (final animation in _imageAnimations) {
      animation.removeListener(_imageMayBeReady);
    }
    _imageAnimations.clear();
    for (final image in _pendingImages) {
      image.dispose();
    }
    _pendingImages.clear();
    _timeout?.cancel();
    _timeout = null;
    final image = _image;
    _image = null;
    _suspendPlaceholder = false;
    if (image == null) return;
    if (notify && mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    } else {
      image.dispose();
    }
  }

  void _watchImageAnimations(RenderObject? render) {
    // FadeTransition changes its composited layer without invalidating an
    // ancestor's paint. Reuse that finite animation until strict readiness.
    final next = <Animation<double>>{};
    void visit(RenderObject render) {
      if (render is RenderAnimatedOpacity) next.add(render.opacity);
      render.visitChildren(visit);
    }

    if (render != null) visit(render);
    for (final animation in _imageAnimations.difference(next)) {
      animation.removeListener(_imageMayBeReady);
    }
    for (final animation in next.difference(_imageAnimations)) {
      animation.addListener(_imageMayBeReady);
    }
    _imageAnimations
      ..clear()
      ..addAll(next);
  }

  void _motionChanged() {
    if (mounted && !widget.controller.canRetain()) {
      _clear(notify: false);
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    assert(widget.controller._owner == null);
    widget.controller._owner = this;
  }

  @override
  void didChangeAccessibilityFeatures() => _motionChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _motionChanged();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.controller._flush();
    if (!widget.controller.canRetain()) _clear(notify: false);
  }

  @override
  void didUpdateWidget(CoverRouteLanding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (identical(oldWidget.controller._owner, this)) {
        oldWidget.controller._owner = null;
      }
      _clear(notify: false);
      assert(widget.controller._owner == null);
      widget.controller._owner = this;
      widget.controller._flush();
    }
    if (oldWidget.identity != widget.identity ||
        !widget.controller.canRetain()) {
      _clear(notify: false);
    }
  }

  @override
  void dispose() {
    _clear(notify: false);
    if (identical(widget.controller._owner, this)) {
      widget.controller._owner = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Stack(fit: StackFit.passthrough, children: [
        CoverImageReadinessObserver(
            key: _artKey,
            onChanged: _imageMayBeReady,
            child:
                TickerMode(enabled: !_suspendPlaceholder, child: widget.child)),
        if (_image != null)
          Positioned.fill(
              child: ExcludeSemantics(
                  child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: RawImage(
                          key: widget.imageKey,
                          image: _image,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium)))),
      ]);
}
