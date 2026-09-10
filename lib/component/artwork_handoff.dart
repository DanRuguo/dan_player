import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';

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
  });

  final Object artworkKey;
  final Future<ImageProvider?> Function() loadArtwork;
  final Widget Function(ImageProvider) imageBuilder;
  final Widget placeholder;
  final Widget? loading;

  static const loadTimeout = Duration(seconds: 10);

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
  late final _transition = AnimationController(
      vsync: this, duration: AppMotion.standard, value: 1)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && _previous != null && mounted) {
        setState(() => _previous = null);
      }
    });
  late final _opacity =
      _transition.drive(CurveTween(curve: AppMotion.standardCurve));
  bool _animationsEnabled = true;

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_animationsEnabled || _platformReducesMotion) _transition.value = 1;
    _resolve();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducesMotion) _transition.value = 1;
  }

  @override
  void didUpdateWidget(covariant ArtworkHandoff oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    if (_key == widget.artworkKey) return;
    _key = widget.artworkKey;
    final request = ++_request;
    _cancelPending();
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
        listener = ImageStreamListener((image, _) {
          image.dispose();
          if (accepted || !_isCurrent(request)) return;
          accepted = true;
          _timeout?.cancel();
          _timeout = null;
          setState(() {
            _previous = _displayed != provider &&
                    _animationsEnabled &&
                    !_platformReducesMotion
                ? _displayed
                : null;
            _displayed = provider;
            _loading = false;
          });
          if (_previous == null) {
            _transition.value = 1;
          } else {
            _transition.forward(from: 0);
          }
          // Keep the cache live until Image has subscribed on the next frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            stream.removeListener(listener);
            if (_isCurrent(request)) _removeListener = null;
          });
        }, onError: (Object _, StackTrace? __) => _finish(request, null));
        _removeListener = () => stream.removeListener(listener);
        stream.addListener(listener);
      } catch (_) {
        _finish(request, null);
      }
    }, onError: (Object _, StackTrace __) => _finish(request, null));
  }

  bool _isCurrent(int request) => mounted && request == _request;

  void _finish(int request, ImageProvider? provider) {
    if (!_isCurrent(request)) return;
    // Invalidate late loader/codec results after failure or timeout as well.
    ++_request;
    _cancelPending();
    setState(() {
      _displayed = provider;
      _previous = null;
      _loading = false;
    });
    _transition.value = 1;
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
    WidgetsBinding.instance.removeObserver(this);
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _displayed != null
      ? Stack(fit: StackFit.expand, children: [
          // The outgoing image stays fully opaque underneath: fading both
          // images would expose the dark fallback halfway through the change.
          if (_previous != null)
            ExcludeSemantics(child: widget.imageBuilder(_previous!)),
          FadeTransition(
              opacity: _opacity, child: widget.imageBuilder(_displayed!)),
        ])
      : _loading
          ? widget.loading ?? widget.placeholder
          : widget.placeholder;
}
