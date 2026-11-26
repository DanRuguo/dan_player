import 'package:dan_player/component/animated_artwork.dart';
import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/category_cover_flight.dart';
import 'package:dan_player/component/text_motion_stabilizer.dart';
import 'package:dan_player/library/artwork_animation_provider.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/uni_detail_page.dart' show PicShape;
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

/// Material 3 Expressive related-entity card used in [AlbumDetailPage] (for
/// contributing artists) and [ArtistDetailPage] (for albums).
///
/// Wraps its 48x48 cover thumbnail in [CategoryCoverFlight] using the target
/// group's `('category-detail-cover', group.persistenceKey)` tag so navigating
/// between AlbumDetailPage and ArtistDetailPage morphs the cover smoothly in
/// both push and pop directions, while providing a hover/focus quick-play pill.
class DetailRelatedGroupCard extends StatefulWidget {
  const DetailRelatedGroupCard({
    super.key,
    required this.group,
    required this.picShape,
    required this.fallbackIcon,
    required this.onTap,
    this.onPlayAll,
    this.covers,
  });

  final MusicCategoryGroup group;
  final PicShape picShape;
  final IconData fallbackIcon;
  final VoidCallback onTap;
  final VoidCallback? onPlayAll;
  final CategoryCoverStore? covers;

  @override
  State<DetailRelatedGroupCard> createState() => _DetailRelatedGroupCardState();
}

class _DetailRelatedGroupCardState extends State<DetailRelatedGroupCard> {
  bool _hovered = false;
  bool _focused = false;
  Object? _request;
  Future<ImageProvider?>? _artwork;
  ImageProvider? _initialArtwork;
  int? _coverGeneration;

  CategoryCoverStore get _covers => widget.covers ?? CategoryCoverStore.shared;

  @override
  void initState() {
    super.initState();
    CoverCache.instance.changes.addListener(_onCoverCacheChanged);
  }

  void _onCoverCacheChanged() {
    final audio = widget.group.coverAudio;
    if (!mounted || audio == null) return;
    final gen = CoverCache.instance.generationFor(audio.localFilePath);
    if (gen == _coverGeneration) return;
    setState(() {
      _coverGeneration = gen;
      _request = null;
    });
  }

  @override
  void dispose() {
    CoverCache.instance.changes.removeListener(_onCoverCacheChanged);
    super.dispose();
  }

  ({bool hit, ImageProvider? provider}) _peekSync(
    MusicCategoryGroup group,
    ArtworkSize target,
  ) {
    final customPeek = _covers.peekImageFor(group);
    if (!customPeek.hit) return (hit: false, provider: null);
    final customProvider = customPeek.provider;
    if (customProvider != null) {
      final animated = mayAnimateArtwork(customProvider);
      final source = customProvider is AnimatedArtworkSource
          ? customProvider.source
          : customProvider;
      ImageProvider wrapped = ArtworkImageProvider(
        source,
        target,
        revision: _covers.coverIdFor(group),
      );
      if (animated) wrapped = AnimatedArtworkSource(wrapped);
      return (hit: true, provider: wrapped);
    }
    final audio = group.coverAudio;
    if (audio == null) return (hit: true, provider: null);
    return audio.peekArtworkForSize(target);
  }

  Future<ImageProvider?> _load(
    MusicCategoryGroup group,
    ArtworkSize target,
  ) async {
    ImageProvider? provider = await _covers.imageFor(group);
    if (provider != null) {
      final animated = mayAnimateArtwork(provider);
      final source =
          provider is AnimatedArtworkSource ? provider.source : provider;
      provider = ArtworkImageProvider(
        source,
        target,
        revision: _covers.coverIdFor(group),
      );
      if (animated) provider = AnimatedArtworkSource(provider);
    }
    provider ??= await group.coverAudio?.artworkForSize(target);
    return provider;
  }

  void _triggerQuickPlay() {
    final audios = widget.group.audios;
    if (audios.isEmpty) return;
    if (widget.onPlayAll != null) {
      widget.onPlayAll!();
      return;
    }
    if (PlayService.isInitialized) {
      PlayService.instance.playbackService.play(0, List<Audio>.of(audios));
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final group = widget.group;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final isOval = widget.picShape == PicShape.oval;
    const thumbSize = 48.0;
    final thumbRadius = isOval ? thumbSize / 2 : 12.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = ArtworkSize.forDisplay(
      logicalWidth: thumbSize,
      logicalHeight: thumbSize,
      devicePixelRatio: dpr,
    );
    final audio = group.coverAudio;
    _coverGeneration = audio == null
        ? null
        : CoverCache.instance.generationFor(audio.localFilePath);
    final request = (
      group.persistenceKey,
      _covers.coverIdFor(group),
      _covers.revision,
      audio?.path,
      audio?.modified,
      audio?.coverFingerprint,
      audio?.artworkUrl,
      _coverGeneration ?? 0,
      target,
    );
    if (request != _request) {
      _request = request;
      final syncHit = _peekSync(group, target);
      if (syncHit.hit) {
        _initialArtwork = syncHit.provider;
        _artwork = SynchronousFuture<ImageProvider?>(syncHit.provider);
      } else {
        _initialArtwork = null;
        _artwork = _load(group, target);
      }
    }

    final durationText = formatCollectionDurationSeconds(
      sumKnownDurationSeconds(group.audios.map((item) => item.duration)),
    );
    final subtitleParts = <String>[
      if (group.subtitle != null && group.subtitle!.trim().isNotEmpty)
        group.subtitle!.trim(),
      ui('{0} 首作品', [group.audios.length]),
      if (durationText != null) durationText,
    ];
    final motionDuration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    final active = _hovered || _focused;
    final canQuickPlay =
        group.audios.isNotEmpty && (widget.onPlayAll != null || PlayService.isInitialized);

    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(thumbRadius),
      ),
      child: SizedBox.square(
        dimension: thumbSize,
        child: Icon(
          widget.fallbackIcon,
          size: 22,
          color: scheme.primary,
        ),
      ),
    );

    final thumbnail = SizedBox.square(
      dimension: thumbSize,
      child: FutureBuilder<ImageProvider?>(
        initialData: _initialArtwork,
        future: _artwork,
        builder: (context, snapshot) => CategoryCoverFlight(
          tag: ('category-detail-cover', group.persistenceKey),
          radius: thumbRadius,
          image: snapshot.data,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(thumbRadius),
            child: ArtworkHandoff(
              artworkKey: _request!,
              loadArtwork: () => _artwork!,
              placeholder: placeholder,
              imageBuilder: (provider) => mayAnimateArtwork(provider)
                  ? AnimatedArtwork(
                      image: provider,
                      errorBuilder: (_, __, ___) => placeholder,
                    )
                  : Image(
                      image: provider,
                      width: thumbSize,
                      height: thumbSize,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => placeholder,
                    ),
            ),
          ),
        ),
      ),
    );

    const cardRadius = BorderRadius.all(Radius.circular(16));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedContainer(
          duration: motionDuration,
          curve: AppMotion.standardCurve,
          decoration: BoxDecoration(
            color: active
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLow.withValues(
                    alpha: isDark ? .72 : .84,
                  ),
            borderRadius: cardRadius,
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: isDark ? .34 : .28)
                  : scheme.outlineVariant.withValues(alpha: isDark ? .30 : .38),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onFocusChange: (focused) {
                if (_focused != focused) setState(() => _focused = focused);
              },
              child: AppItemInkWell(
                key: ValueKey('related-card-${group.persistenceKey}'),
                borderRadius: cardRadius,
                onTap: widget.onTap,
                child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    thumbnail,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          appFontText(
                            context,
                            group.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          appFontText(
                            context,
                            subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                              fontFeatures: tabularFiguresFeatures,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canQuickPlay) ...[
                      const SizedBox(width: 8),
                      AnimatedScale(
                        duration: motionDuration,
                        curve: AppMotion.standardCurve,
                        scale: active ? 1.0 : 0.92,
                        child: AnimatedOpacity(
                          duration: motionDuration,
                          curve: AppMotion.standardCurve,
                          opacity: active ? 1.0 : 0.76,
                          child: IconButton.filledTonal(
                            key:
                                ValueKey('related-play-${group.persistenceKey}'),
                            tooltip: ui('播放全部'),
                            onPressed: _triggerQuickPlay,
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(36),
                              maximumSize: const Size.square(36),
                              padding: EdgeInsets.zero,
                              shape: AppShape.pill,
                              backgroundColor: active
                                  ? scheme.primaryContainer
                                  : scheme.secondaryContainer
                                      .withValues(alpha: .72),
                              foregroundColor: active
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSecondaryContainer,
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    AnimatedSlide(
                      duration: motionDuration,
                      curve: AppMotion.standardCurve,
                      offset: active ? const Offset(0.08, 0) : Offset.zero,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: active
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
