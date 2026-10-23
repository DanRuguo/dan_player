import 'package:dan_player/app_settings.dart';
import 'dart:ui' as ui;
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/animated_artwork.dart';
import 'package:dan_player/library/artwork_animation_provider.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter/material.dart';

typedef AudioArtworkLoader = Future<ImageProvider?> Function(
    Audio audio, ArtworkSize size);

/// Stable cover loading for rows, cards and full-size artwork. It follows this
/// widget's View/MediaQuery DPR and never polls frames or discards an already
/// displayed cover during scrolling or unrelated playback rebuilds.
class AudioArtwork extends StatefulWidget {
  const AudioArtwork({
    super.key,
    required this.audio,
    this.size = 48,
    required this.placeholder,
    this.loading,
    this.revision,
    this.loadArtwork,
    this.retainWhileLoading = false,
    this.animateFirstFrame = false,
    this.artworkDecorator,
  });

  final Audio audio;
  final double size;
  final Widget placeholder;
  final Widget? loading;
  final Object? revision;

  /// Injection point for isolated image tests; normal callers use Audio's
  /// bounded local cache / network codec pipeline.
  final AudioArtworkLoader? loadArtwork;

  /// Playback surfaces hand off between tracks; unrelated library rows must
  /// instead show their own placeholder when their source changes.
  final bool retainWhileLoading;

  /// Newly expanded content can reveal a late first decoded cover with the
  /// existing finite handoff, after its containing item's entrance finishes.
  final bool animateFirstFrame;
  final Widget Function(BuildContext, ImageProvider, ui.Image?, Widget)?
      artworkDecorator;

  @override
  State<AudioArtwork> createState() => _AudioArtworkState();
}

class _AudioArtworkState extends State<AudioArtwork> {
  Object? _requestKey;
  Future<ImageProvider?>? _future;
  ImageProvider? _readyProvider;
  ImageInfo? _readyFrame;

  void _rememberFirstFrame(ImageProvider provider, ImageInfo frame) {
    _releaseFirstFrame();
    final actual =
        provider is FirstFrameArtworkProvider ? provider.source : provider;
    if (!mayAnimateArtwork(actual)) return;
    _readyProvider = provider;
    _readyFrame = frame.clone();
  }

  ImageInfo? _takeFirstFrame(ImageProvider provider) {
    if (provider != _readyProvider) return null;
    final frame = _readyFrame;
    _readyProvider = null;
    _readyFrame = null;
    return frame;
  }

  void _releaseFirstFrame() {
    _readyFrame?.dispose();
    _readyFrame = null;
    _readyProvider = null;
  }

  void _releaseUnusedFirstFrameAfterMount() {
    final frame = _readyFrame;
    if (frame == null) return;
    // A retained outgoing provider may have committed immediately before the
    // next request. Give that child this frame to take its seed, then release
    // an unconsumed seed even if the replacement fails or has no artwork.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(frame, _readyFrame)) _releaseFirstFrame();
    });
  }

  @override
  void initState() {
    super.initState();
    CoverCache.instance.changes.addListener(_coverChanged);
    AppSettings.instance.networkProxy.addListener(_networkProxyChanged);
    AppSettings.instance.customMusicSources.addListener(_customProfilesChanged);
  }

  void _coverChanged() {
    final previous = _requestKey;
    _resolve();
    if (mounted && previous != _requestKey) setState(() {});
  }

  void _networkProxyChanged() {
    if (!mounted ||
        !widget.audio.canFetchRemoteArtwork ||
        widget.audio.artworkUrl?.isNotEmpty != true) {
      return;
    }
    final previous = _requestKey;
    _resolve();
    if (previous != _requestKey) setState(() {});
  }

  void _customProfilesChanged() {
    if (!mounted ||
        widget.audio.onlineProvider?.startsWith('custom:') != true) {
      return;
    }
    final previous = _requestKey;
    _resolve();
    if (previous != _requestKey) setState(() {});
  }

  @override
  void dispose() {
    _releaseFirstFrame();
    CoverCache.instance.changes.removeListener(_coverChanged);
    AppSettings.instance.networkProxy.removeListener(_networkProxyChanged);
    AppSettings.instance.customMusicSources
        .removeListener(_customProfilesChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AudioArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final audio = widget.audio;
    final target = ArtworkSize.forDisplay(
      logicalWidth: widget.size,
      logicalHeight: widget.size,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final source = (
      audio.path,
      audio.modified,
      audio.coverFingerprint,
      audio.artworkUrl,
      audio.isOnline ? AppSettings.instance.networkProxy.value : null,
      audio.customArtworkProfile,
      CoverCache.instance.epoch,
      CoverCache.instance.generationFor(audio.localFilePath),
      widget.revision,
    );
    final request = (source, target);
    if (_requestKey == request) return;
    _releaseUnusedFirstFrameAfterMount();
    _requestKey = request;
    _future = Future<ImageProvider?>.sync(() => widget.loadArtwork == null
        ? audio.artworkForSize(target)
        : widget.loadArtwork!(audio, target));
  }

  @override
  Widget build(BuildContext context) {
    final requestKey = _requestKey!;
    return SizedBox.square(
      dimension: widget.size,
      child: ArtworkHandoff(
        key: ValueKey(widget.retainWhileLoading ? null : widget.audio.path),
        artworkKey: requestKey,
        onFirstFrameReady: (provider, frame) {
          if (mounted && _requestKey == requestKey) {
            _rememberFirstFrame(provider, frame);
          }
        },
        loadArtwork: () async {
          final provider = await _future!;
          return provider != null && mayAnimateArtwork(provider)
              ? FirstFrameArtworkProvider(provider)
              : provider;
        },
        placeholder: widget.placeholder,
        loading: widget.loading,
        animateFirstFrame: widget.animateFirstFrame,
        imageBuilder: (provider) {
          final actual = provider is FirstFrameArtworkProvider
              ? provider.source
              : provider;
          final Widget child =
              mayAnimateArtwork(actual) || widget.artworkDecorator != null
                  ? AnimatedArtwork(
                      image: actual,
                      takeInitialFrame: () => _takeFirstFrame(provider),
                      errorBuilder: (_, __, ___) => widget.placeholder,
                      frameDecorator: widget.artworkDecorator == null
                          ? null
                          : (context, frame, child) => widget.artworkDecorator!(
                              context, actual, frame, child))
                  : Image(
                      image: actual,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => widget.placeholder);
          return child;
        },
      ),
    );
  }
}

/// Direct file/network/memory art (e.g. a custom playlist cover). Decode size is
/// based on both physical axes, not cacheWidth alone; portrait/landscape covers
/// keep their aspect ratio and do not need to be stretched back up after crop.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.image,
    required this.size,
    required this.errorBuilder,
    this.revision,
  });

  final ImageProvider image;
  final double size;
  final Object? revision;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: mayAnimateArtwork(image)
            ? AnimatedArtwork(
                image: AnimatedArtworkSource(ArtworkImageProvider(
                    image is AnimatedArtworkSource
                        ? (image as AnimatedArtworkSource).source
                        : image,
                    ArtworkSize.forDisplay(
                        logicalWidth: size,
                        logicalHeight: size,
                        devicePixelRatio:
                            MediaQuery.devicePixelRatioOf(context)),
                    revision: revision)),
                errorBuilder: errorBuilder,
              )
            : Image(
                image: ArtworkImageProvider(
                  image,
                  ArtworkSize.forDisplay(
                    logicalWidth: size,
                    logicalHeight: size,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  ),
                  revision: revision,
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: errorBuilder,
              ),
      );
}
