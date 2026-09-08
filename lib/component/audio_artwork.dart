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
  });

  final Audio audio;
  final double size;
  final Widget placeholder;
  final Widget? loading;
  final Object? revision;

  /// Injection point for isolated image tests; normal callers use Audio's
  /// bounded local cache / network codec pipeline.
  final AudioArtworkLoader? loadArtwork;

  @override
  State<AudioArtwork> createState() => _AudioArtworkState();
}

class _AudioArtworkState extends State<AudioArtwork> {
  Object? _requestKey;
  Object? _sourceKey;
  Future<ImageProvider?>? _future;

  @override
  void initState() {
    super.initState();
    CoverCache.instance.changes.addListener(_coverChanged);
  }

  void _coverChanged() {
    final previous = _requestKey;
    _resolve();
    if (mounted && previous != _requestKey) setState(() {});
  }

  @override
  void dispose() {
    CoverCache.instance.changes.removeListener(_coverChanged);
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
      CoverCache.instance.generationFor(audio.localFilePath),
      AudioLibrary.revision,
      widget.revision,
    );
    final request = (source, target);
    if (_requestKey == request) return;
    _requestKey = request;
    _sourceKey = source;
    _future = Future<ImageProvider?>.sync(() => widget.loadArtwork == null
        ? audio.artworkForSize(target)
        : widget.loadArtwork!(audio, target));
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<ImageProvider?>(
          key: ValueKey(_sourceKey),
          future: _future,
          builder: (context, snapshot) {
            // A DPR/size upgrade keeps its already visible image until the
            // sharper one arrives. A different source gets a fresh builder.
            if (snapshot.data != null) {
              return Image(
                image: snapshot.data!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => widget.placeholder,
              );
            }
            return snapshot.connectionState == ConnectionState.done
                ? widget.placeholder
                : widget.loading ?? widget.placeholder;
          },
        ),
      );
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
        child: Image(
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
