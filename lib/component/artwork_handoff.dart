import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the last decoded frame while a replacement is loading, then commits
/// the new provider only after its first frame is ready. Missing/failed art
/// clears immediately; a stalled request is bounded so old art cannot persist.
class ArtworkHandoff extends StatefulWidget {
  const ArtworkHandoff({
    super.key,
    required this.artworkKey,
    required this.loadArtwork,
    required this.imageBuilder,
    required this.placeholder,
    this.loading,
    this.animateFirstFrame = false,
    this.hidden,
    this.isVisible = true,
    this.presentationKey,
  });

  final Object artworkKey;
  final Future<ImageProvider?> Function() loadArtwork;
  final Widget Function(ImageProvider) imageBuilder;
  final Widget placeholder;
  final Widget? loading;
  final bool animateFirstFrame;
  final ValueListenable<bool>? hidden;
  final bool isVisible;
  final Object? presentationKey;

  static const loadTimeout = Duration(seconds: 10);
  // At most one retained composite. The temporary replacement can coexist
  // with it for one frame: <= 128 MiB of RGBA, including a full 4K backdrop.
  static const maximumSnapshotPixels = 16 * 1024 * 1024;
  static const maximumSnapshotSide = 8192;

  @override
  State<ArtworkHandoff> createState() => _ArtworkHandoffState();
}

class _ArtworkHandoffState extends State<ArtworkHandoff>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ImageProvider? _displayed;
  ImageProvider? _previous;
  Object? _key;
  int _request = 0;
  bool _loading = false;
  Timer? _timeout;
  VoidCallback? _removeListener;
  VoidCallback? _releaseFirstFrame;
  final _snapshot = SnapshotController();
  final _snapshotPainter = _HandoffSnapshotPainter();
  ui.Image? _frozen;
  Size? _frozenSourceSize;
  Size? _frozenSize;
  bool _frozenOnly = false;
  Size _size = Size.zero;
  double _pixelRatio = 1;
  int _captureGeneration = 0;
  int? _captureRequest;
  ImageProvider? _captureTarget;
  bool _captureFirstFrame = false;
  Size? _captureSize;
  late final _transition =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _animatingFirstFrame = false;
            _releaseFirstFrameAnimation();
            if ((_previous != null || _frozen != null) && mounted) {
              setState(() {
                _previous = null;
                _releaseFrozen();
              });
            }
          }
        });
  late final _opacity =
      _transition.drive(CurveTween(curve: AppMotion.standardCurve));
  bool _animationsEnabled = true;
  bool _animatingFirstFrame = false;
  bool get _motionAllowed =>
      _animationsEnabled &&
      !_platformReducesMotion &&
      widget.isVisible &&
      !(widget.hidden?.value ?? false);

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_hiddenChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = TickerMode.valuesOf(context).enabled &&
        AppMotion.enabled(context, MotionKind.theme);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final changedRatio = pixelRatio != _pixelRatio;
    _pixelRatio = pixelRatio;
    if (!_motionAllowed ||
        changedRatio ||
        (_animatingFirstFrame &&
            !AppMotion.enabled(context, MotionKind.entrance))) {
      _settleMotion(notify: false);
    }
    _resolve();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducesMotion) {
      _settleMotion();
    }
  }

  @override
  void didUpdateWidget(covariant ArtworkHandoff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_hiddenChanged);
      widget.hidden?.addListener(_hiddenChanged);
    }
    if ((oldWidget.presentationKey != widget.presentationKey &&
            (_frozen != null || _captureRequest != null)) ||
        !_motionAllowed) {
      _settleMotion(notify: false);
    }
    _resolve();
  }

  void _hiddenChanged() {
    if (widget.hidden?.value == true) _settleMotion();
  }

  void _resolve() {
    if (_key == widget.artworkKey) return;
    _key = widget.artworkKey;
    final request = ++_request;
    _cancelPending();
    final firstFrame = _animatingFirstFrame || _captureFirstFrame;
    _cancelCapture(resume: !firstFrame);
    // Replacing an entrance returns its shared slot immediately. Preserve the
    // partial image without extending that entrance or snapping its alpha.
    _animatingFirstFrame = false;
    if (firstFrame && !_beginCapture(request, firstFrame: true)) {
      _transition.value = 1;
    }
    _releaseFirstFrameAnimation();
    _loading = true;
    final configuration = createLocalImageConfiguration(context);
    _timeout = Timer(ArtworkHandoff.loadTimeout, () => _finish(request, null));
    Future<ImageProvider?>.sync(widget.loadArtwork).then((provider) {
      if (!_isCurrent(request)) return;
      if (provider == null) {
        _finish(request, null);
        return;
      }
      try {
        final stream = provider.resolve(configuration);
        late final ImageStreamListener listener;
        var accepted = false;
        listener = ImageStreamListener((image, synchronousCall) {
          image.dispose();
          if (accepted || !_isCurrent(request)) return;
          accepted = true;
          _timeout?.cancel();
          _timeout = null;
          var animateInitial = _displayed == null &&
              widget.animateFirstFrame &&
              !synchronousCall &&
              _motionAllowed &&
              AppMotion.enabled(context, MotionKind.entrance);
          if (animateInitial) {
            _releaseFirstFrame = AppEntranceScope.reserveAnimationOf(context);
            animateInitial = _releaseFirstFrame != null;
          }
          if (_captureRequest == request) {
            _captureTarget = provider;
          } else if (_displayed != null &&
              !_frozenOnly &&
              _opacity.value < 1 &&
              (_previous != null || _frozen != null) &&
              _beginCapture(request, target: provider)) {
            // SnapshotWidget captures this same mixed subtree on its next
            // paint, then the post-frame handoff releases the old clocks.
          } else {
            _commitProvider(provider, animateInitial: animateInitial);
          }
        }, onError: (Object _, StackTrace? __) => _finish(request, null));
        _removeListener = () => stream.removeListener(listener);
        stream.addListener(listener);
      } catch (_) {
        _finish(request, null);
      }
    }, onError: (Object _, StackTrace __) => _finish(request, null));
  }

  bool _isCurrent(int request) => mounted && request == _request;

  bool _beginCapture(int request,
      {ImageProvider? target, bool firstFrame = false}) {
    if (!_size.width.isFinite || !_size.height.isFinite) return false;
    final width = (_size.width * _pixelRatio).ceil();
    final height = (_size.height * _pixelRatio).ceil();
    if (!_motionAllowed ||
        _size.isEmpty ||
        width > ArtworkHandoff.maximumSnapshotSide ||
        height > ArtworkHandoff.maximumSnapshotSide ||
        width * height > ArtworkHandoff.maximumSnapshotPixels) {
      return false;
    }
    _transition.stop();
    _captureRequest = request;
    _captureTarget = target;
    _captureFirstFrame = firstFrame;
    _captureSize = _size;
    final generation = ++_captureGeneration;
    _snapshotPainter.onSnapshot = (image, sourceSize, size) {
      final retained = image.clone();
      _snapshotPainter.onSnapshot = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrent(request) ||
            generation != _captureGeneration ||
            !_motionAllowed ||
            size != _size) {
          retained.dispose();
          return;
        }
        final next = _captureTarget;
        final firstFrame = _captureFirstFrame;
        _captureRequest = null;
        _captureTarget = null;
        _captureFirstFrame = false;
        _captureSize = null;
        _snapshot.allowSnapshotting = false;
        // The sampled bitmap already contains the entrance's partial alpha.
        // Retire its controller before installing that bitmap, so completion
        // cannot release the newly retained image or fill the presented frame.
        if (firstFrame) _transition.value = 1;
        setState(() {
          _previous = null;
          _releaseFrozen();
          _frozen = retained;
          _frozenSourceSize = sourceSize;
          _frozenSize = size;
          _frozenOnly = next == null;
        });
        if (next != null) _commitProvider(next);
      });
    };
    _snapshot.allowSnapshotting = true;
    return true;
  }

  void _commitProvider(ImageProvider provider, {bool animateInitial = false}) {
    setState(() {
      if (!_motionAllowed) _releaseFrozen();
      _previous = _frozen == null && _displayed != provider && _motionAllowed
          ? _displayed
          : null;
      _displayed = provider;
      _frozenOnly = false;
      _loading = false;
    });
    _animatingFirstFrame = animateInitial;
    if ((_previous == null && _frozen == null && !animateInitial) ||
        !_motionAllowed) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
    _releaseDecodedAfterMount();
  }

  void _releaseDecodedAfterMount() {
    final remove = _removeListener;
    if (remove == null) return;
    final request = _request;
    // An interrupted fade commits after paint; its target Image only mounts
    // on the following frame. Keep the codec live until that subscription.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      remove();
      if (_isCurrent(request) && identical(remove, _removeListener)) {
        _removeListener = null;
      }
    });
  }

  void _cancelCapture({bool resume = false}) {
    final pending = _captureRequest != null;
    final firstFrame = _captureFirstFrame;
    ++_captureGeneration;
    _captureRequest = null;
    _captureTarget = null;
    _captureFirstFrame = false;
    _captureSize = null;
    _snapshotPainter.onSnapshot = null;
    _snapshot.allowSnapshotting = false;
    if (pending &&
        resume &&
        !firstFrame &&
        _motionAllowed &&
        _transition.value < 1) {
      _transition.forward();
    }
  }

  void _releaseFrozen() {
    _frozen?.dispose();
    _frozen = null;
    _frozenSourceSize = null;
    _frozenSize = null;
    _frozenOnly = false;
  }

  void _settleMotion({bool notify = true}) {
    final ready = _captureRequest == _request ? _captureTarget : null;
    _cancelCapture();
    void settle() {
      if (ready != null) {
        _displayed = ready;
        _loading = false;
      }
      _previous = null;
      _releaseFrozen();
      _animatingFirstFrame = false;
    }

    if (notify && mounted) {
      setState(settle);
    } else {
      settle();
    }
    _transition.value = 1;
    _releaseFirstFrameAnimation();
    if (ready != null) _releaseDecodedAfterMount();
  }

  void _finish(int request, ImageProvider? provider) {
    if (!_isCurrent(request)) return;
    // Invalidate late loader/codec results after failure or timeout as well.
    ++_request;
    _cancelPending();
    _cancelCapture();
    setState(() {
      _displayed = provider;
      _previous = null;
      _loading = false;
      _animatingFirstFrame = false;
      _releaseFrozen();
    });
    _transition.value = 1;
    _releaseFirstFrameAnimation();
  }

  void _releaseFirstFrameAnimation() {
    final release = _releaseFirstFrame;
    _releaseFirstFrame = null;
    release?.call();
  }

  void _cancelPending() {
    _timeout?.cancel();
    _timeout = null;
    _removeListener?.call();
    _removeListener = null;
  }

  @override
  void dispose() {
    ++_request;
    _cancelPending();
    _cancelCapture();
    _releaseFrozen();
    _releaseFirstFrameAnimation();
    widget.hidden?.removeListener(_hiddenChanged);
    WidgetsBinding.instance.removeObserver(this);
    _transition.dispose();
    _snapshot.dispose();
    _snapshotPainter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _displayed != null
      ? LayoutBuilder(builder: (context, constraints) {
          _size = constraints.biggest;
          if ((_frozenSize != null && _frozenSize != _size) ||
              (_captureSize != null && _captureSize != _size)) {
            // A viewport change invalidates the old crop. Commit the current
            // decoded source, instead of stretching a stale composite bitmap.
            _settleMotion(notify: false);
          }
          return SnapshotWidget(
              controller: _snapshot,
              painter: _snapshotPainter,
              child: Stack(fit: StackFit.expand, children: [
                // The outgoing image stays fully opaque underneath: fading both
                // images would expose the dark fallback halfway through the change.
                if (_previous != null)
                  FadeTransition(
                      key: ValueKey(_previous),
                      opacity: const AlwaysStoppedAnimation(1.0),
                      child: ExcludeSemantics(
                          child: widget.imageBuilder(_previous!))),
                if (_frozen case final frozen?)
                  RepaintBoundary(
                      child: CustomPaint(
                          painter: _FrozenHandoffPainter(
                              frozen, _frozenSourceSize!))),
                if (!_frozenOnly)
                  FadeTransition(
                      key: ValueKey(_displayed),
                      opacity: _opacity,
                      child: ExcludeSemantics(
                          excluding: false,
                          child: widget.imageBuilder(_displayed!))),
              ]));
        })
      : _loading
          ? widget.loading ?? widget.placeholder
          : widget.placeholder;
}

class _HandoffSnapshotPainter extends SnapshotPainter {
  void Function(ui.Image, Size sourceSize, Size size)? onSnapshot;

  @override
  void paint(PaintingContext context, Offset offset, Size size,
          PaintingContextCallback painter) =>
      painter(context, offset);

  @override
  void paintSnapshot(PaintingContext context, Offset offset, Size size,
      ui.Image image, Size sourceSize, double pixelRatio) {
    context.canvas.drawImageRect(image, Offset.zero & sourceSize, offset & size,
        Paint()..filterQuality = FilterQuality.medium);
    onSnapshot?.call(image, sourceSize, size);
  }

  @override
  bool shouldRepaint(_HandoffSnapshotPainter oldPainter) => false;
}

class _FrozenHandoffPainter extends CustomPainter {
  const _FrozenHandoffPainter(this.image, this.sourceSize);
  final ui.Image image;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
      image,
      Offset.zero & sourceSize,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium);

  @override
  bool shouldRepaint(_FrozenHandoffPainter oldDelegate) =>
      image != oldDelegate.image || sourceSize != oldDelegate.sourceSize;
}
