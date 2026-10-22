import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/library/artwork_animation_provider.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Owns the GIF stream subscription. Native hiding releases it immediately,
/// even when Flutter will not produce another frame for a widget rebuild.
class AnimatedArtwork extends StatefulWidget {
  const AnimatedArtwork(
      {super.key,
      required this.image,
      required this.errorBuilder,
      this.hidden,
      this.frameDecorator});
  final ImageProvider image;
  final ImageErrorWidgetBuilder errorBuilder;
  final ValueListenable<bool>? hidden;
  final Widget Function(BuildContext, ui.Image?, Widget)? frameDecorator;
  @override
  State<AnimatedArtwork> createState() => _AnimatedArtworkState();
}

class _AnimatedArtworkState extends State<AnimatedArtwork>
    with WidgetsBindingObserver {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider? _resolved;
  ImageInfo? _info;
  final _retired = <ImageInfo>[];
  Object? _error;
  StackTrace? _trace;
  ValueListenable<RenderingPreferences>? _preferences;
  late ValueListenable<bool> _hidden;
  bool _treeVisible = true, _mediaMotion = true, _attached = true;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _hidden = widget.hidden ?? DesktopIntegration.instance.isHidden;
    _hidden.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_sync);
      _preferences = preferences..addListener(_sync);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _mediaMotion = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hidden = widget.hidden ?? DesktopIntegration.instance.isHidden;
    if (!identical(hidden, _hidden)) {
      _hidden.removeListener(_sync);
      _hidden = hidden..addListener(_sync);
    }
    if (widget.image != oldWidget.image) {
      _detach();
      _resolved = null;
    }
    _sync();
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
  }

  void _sync() {
    if (!_attached || !mounted || _preferences == null) return;
    final preferences = _preferences!.value;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final visible = preferences.allowsVisualUpdates(
        lifecycle: _lifecycle,
        treeVisible: _treeVisible,
        nativeHidden: _hidden.value);
    if (!visible && _info != null) {
      _detach();
      return;
    }
    final motion = visible &&
        preferences.animatedArtwork &&
        preferences.animations.allows(MotionKind.theme) &&
        _mediaMotion &&
        !features.disableAnimations &&
        !features.reduceMotion;
    final source = widget.image is AnimatedArtworkSource
        ? (widget.image as AnimatedArtworkSource).source
        : widget.image;
    final provider = motion ? source : FirstFrameArtworkProvider(source);
    if (_listener != null && provider == _resolved) return;
    if (!motion && provider == _resolved && _info != null && _error == null)
      return;
    _detach();
    _resolved = provider;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    final listener = ImageStreamListener((info, _) {
      if (!mounted || !identical(stream, _stream)) {
        info.dispose();
        return;
      }
      final previous = _info;
      setState(() {
        _info = info;
        _error = null;
        _trace = null;
      });
      if (previous != null) {
        _retired.add(previous);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_retired.remove(previous)) previous.dispose();
        });
      }
      if (!motion)
        scheduleMicrotask(() {
          if (identical(stream, _stream)) _detach();
        });
    }, onError: (Object error, StackTrace? trace) {
      if (!mounted || !identical(stream, _stream)) return;
      setState(() {
        _error = error;
        _trace = trace;
      });
      scheduleMicrotask(() {
        if (identical(stream, _stream)) _detach();
      });
    });
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _sync();
  }

  @override
  void didChangeAccessibilityFeatures() => _sync();
  @override
  void deactivate() {
    _attached = false;
    _detach();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hidden.removeListener(_sync);
    _preferences?.removeListener(_sync);
    _detach();
    _info?.dispose();
    for (final image in _retired) {
      image.dispose();
    }
    _retired.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _error == null
        ? Semantics(
            image: true,
            child: RawImage(
                image: _info?.image,
                scale: _info?.scale ?? 1,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high))
        : widget.errorBuilder(context, _error!, _trace);
    return widget.frameDecorator
            ?.call(context, _error == null ? _info?.image : null, child) ??
        child;
  }
}
