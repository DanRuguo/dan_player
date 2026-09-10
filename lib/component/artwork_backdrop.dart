import 'dart:ui' as ui;

import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A page-local artwork background, independent of native window materials.
///
/// [loadArtwork] runs once per [artworkKey], not on animation/parent rebuilds.
/// Include the track identity and metadata revision in the key. Failed requests
/// use the fallback; superseded results are ignored. The opaque fallback is
/// clipped here and cannot cover a sibling navigation rail or title bar.
class ArtworkBackdrop extends StatefulWidget {
  const ArtworkBackdrop({
    super.key,
    required this.artworkKey,
    required this.loadArtwork,
    required this.child,
    this.blur = 36,
    this.opacity,
    this.motion = false,
    this.isPlaying = false,
    this.isVisible = true,
    this.displaySized = false,
    this.hidden,
  });

  final Object artworkKey;
  final Future<ImageProvider?> Function() loadArtwork;
  final Widget child;
  final double blur;

  /// Null retains the legacy detail-page readability gradient.
  final double? opacity;
  final bool motion;
  final bool isPlaying;
  final bool isVisible;

  /// User-selected pictures use bounded physical-pixel cover sampling. Album
  /// backdrops keep the established 512px sample; foreground art is untouched.
  final bool displaySized;
  final ValueListenable<bool>? hidden;

  @override
  State<ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<ArtworkBackdrop> {
  late Future<ImageProvider?> _artwork;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkKey != widget.artworkKey) _load();
  }

  void _load() {
    // Future.sync also turns a synchronous provider failure into the same
    // handled fallback as an asynchronous I/O failure.
    _artwork = Future<ImageProvider?>.sync(widget.loadArtwork);
  }

  ImageProvider _sample(ImageProvider provider, ArtworkSize? size) {
    final source =
        provider is ArtworkImageProvider ? provider.source : provider;
    if (size == null) {
      return ResizeImage(source,
          width: 512, height: 512, policy: ResizeImagePolicy.fit);
    }
    return ArtworkImageProvider(source, size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: LayoutBuilder(builder: (context, constraints) {
                      final size = widget.displaySized
                          ? ArtworkSize.forDisplay(
                              logicalWidth: constraints.maxWidth,
                              logicalHeight: constraints.maxHeight,
                              devicePixelRatio:
                                  MediaQuery.devicePixelRatioOf(context),
                            )
                          : null;
                      return ArtworkHandoff(
                        artworkKey: (widget.artworkKey, size),
                        loadArtwork: () async {
                          final provider = await _artwork;
                          return provider == null
                              ? null
                              : _sample(provider, size);
                        },
                        placeholder: const SizedBox.expand(),
                        imageBuilder: (provider) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              BackgroundImageMotion(
                                enabled: widget.motion,
                                isPlaying: widget.isPlaying,
                                isVisible: widget.isVisible,
                                hidden: widget.hidden,
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: widget.blur.clamp(0, 100),
                                    sigmaY: widget.blur.clamp(0, 100),
                                    tileMode: ui.TileMode.clamp,
                                  ),
                                  child: Image(
                                    image: provider,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    filterQuality: FilterQuality.low,
                                    excludeFromSemantics: true,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              if (widget.opacity != null)
                                ColoredBox(
                                  color: scheme.surface.withValues(
                                    alpha: widget.opacity!.clamp(0, 1),
                                  ),
                                )
                              else
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        scheme.surface.withValues(
                                            alpha: isDark ? 0.78 : 0.82),
                                        scheme.surface.withValues(
                                            alpha: isDark ? 0.88 : 0.91),
                                        scheme.surface.withValues(alpha: 0.97),
                                      ],
                                      stops: const [0, 0.55, 1],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          // Filtering and repainting the artwork must never blur the content
          // or consume its taps/scroll gestures.
          widget.child,
        ],
      ),
    );
  }
}
