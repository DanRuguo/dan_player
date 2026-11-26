import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/component/detail_related_group_card.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playing_audio_list_row.dart';
import 'package:dan_player/component/text_motion_stabilizer.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.album, this.nowPlayingPath})
      : groupId = null,
        initialGroup = null;

  const AlbumDetailPage.group({
    super.key,
    required this.groupId,
    this.initialGroup,
    this.nowPlayingPath,
  }) : album = null;

  final Album? album;
  final String? groupId;
  final MusicCategoryGroup? initialGroup;
  final ValueListenable<String?>? nowPlayingPath;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final _selection = MultiSelectController<Audio>();
  bool _allowInitialGroup = true;
  late int _classificationRevision;

  @override
  void initState() {
    super.initState();
    _classificationRevision = AudioLibrary.classificationRevision;
    CategoryCoverStore.shared.load();
  }

  @override
  void didUpdateWidget(covariant AlbumDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.album?.name != widget.album?.name ||
        !identical(oldWidget.initialGroup, widget.initialGroup)) {
      _allowInitialGroup = true;
      _classificationRevision = AudioLibrary.classificationRevision;
    }
  }

  /// Whether [visibleContent] should display multi-disc section headers.
  ///
  /// Requires track-based ordering, at least two distinct disc buckets (or an
  /// explicit `discSubtitle`), and contiguous disc runs so non-disc sorts never
  /// fragment the list with repeated disc banners.
  static bool _showsDiscHeaders(
    List<Audio> visibleContent,
    SortMethodDesc<Audio>? sortMethod,
  ) {
    if (visibleContent.length < 2) return false;
    if (sortMethod is AudioSortMethodDesc &&
        sortMethod.field != AudioSortField.track) {
      return false;
    }
    final seenDiscs = <int?>{};
    var hasExplicitSubtitle = false;
    int? previousDisc;
    var started = false;
    for (final audio in visibleContent) {
      final disc = audio.discNumber;
      if (audio.discSubtitle != null && audio.discSubtitle!.trim().isNotEmpty) {
        hasExplicitSubtitle = true;
      }
      if (!started || disc != previousDisc) {
        if (!seenDiscs.add(disc)) {
          // Discontiguous disc numbers indicate an order incompatible with
          // clean per-disc grouping.
          return false;
        }
        previousDisc = disc;
        started = true;
      }
    }
    final numberedCount = seenDiscs.whereType<int>().length;
    return numberedCount >= 2 ||
        (numberedCount >= 1 && seenDiscs.length >= 2) ||
        (numberedCount >= 1 && hasExplicitSubtitle);
  }

  Widget? _buildDiscSectionHeader(
    BuildContext context,
    Audio audio,
    int index,
    List<Audio> visibleContent,
    SortMethodDesc<Audio>? sortMethod,
    SortOrder sortOrder,
  ) {
    if (!_showsDiscHeaders(visibleContent, sortMethod)) return null;
    final disc = audio.discNumber;
    if (index > 0 && visibleContent[index - 1].discNumber == disc) {
      return null;
    }
    final discTracks = <Audio>[];
    String? discSubtitle;
    for (var i = index; i < visibleContent.length; i++) {
      final candidate = visibleContent[i];
      if (candidate.discNumber != disc) break;
      discTracks.add(candidate);
      discSubtitle ??= candidate.discSubtitle?.trim().isNotEmpty == true
          ? candidate.discSubtitle!.trim()
          : null;
    }
    return _AlbumDiscHeader(
      key: ValueKey('album-disc-header-${disc ?? 0}'),
      discNumber: disc,
      discSubtitle: discSubtitle,
      discTracks: discTracks,
      startIndex: index,
      visibleQueue: visibleContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        AudioLibrary.changes,
        CategoryCoverStore.shared,
        CoverCache.instance.changes,
      ]),
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (_classificationRevision != AudioLibrary.classificationRevision) {
      _classificationRevision = AudioLibrary.classificationRevision;
      _allowInitialGroup = false;
    }
    // Legacy album extras used a title-only map. Ask the user to choose the
    // release when that snapshot contains different album artists.
    if (widget.groupId == null &&
        (widget.album == null || widget.album!.works.isEmpty)) {
      return const CategoriesPage(initialCategory: MusicCategoryKind.album);
    }
    final originalGroups = widget.groupId == null
        ? MusicCategories(widget.album!.works).groups(MusicCategoryKind.album)
        : const <MusicCategoryGroup>[];
    if (widget.groupId == null && originalGroups.length != 1) {
      final originalIds = originalGroups.map((group) => group.id).toSet();
      final currentCandidates =
          LibraryMusicCategories.groups(MusicCategoryKind.album)
              .where((group) => originalIds.contains(group.id))
              .expand((group) => group.audios)
              .toList();
      return CategoriesPage(
        initialCategory: MusicCategoryKind.album,
        // Old title-only route payloads may not belong to the current indexed
        // library (migration/deep-link tests exercise this). Prefer live
        // matches, but retain the legacy disambiguation candidates when none
        // can be resolved.
        audios:
            currentCandidates.isEmpty ? widget.album!.works : currentCandidates,
      );
    }
    final targetId = widget.groupId ?? originalGroups.single.id;
    final live = LibraryMusicCategories.find(MusicCategoryKind.album, targetId);
    if (live != null) _allowInitialGroup = false;
    final initial = widget.initialGroup;
    final currentGroup = live ??
        (widget.groupId != null &&
                _allowInitialGroup &&
                initial?.kind == MusicCategoryKind.album &&
                initial?.id == widget.groupId
            ? initial
            : null);
    if (currentGroup == null || currentGroup.audios.isEmpty) {
      return const CategoriesPage(initialCategory: MusicCategoryKind.album);
    }
    final currentAudios = currentGroup.audios.toSet();
    final artists = LibraryMusicCategories.groups(MusicCategoryKind.artist)
        .where((artist) => artist.audios.any(currentAudios.contains))
        .toList(growable: false);
    final secondaryContent = List<Audio>.from(currentGroup.audios);
    return UniDetailPage<String, Audio, MusicCategoryGroup>(
      pref: AppPreference.instance.albumDetailPagePref,
      primaryContent: currentGroup.id,
      coverFlightTag: ('category-detail-cover', currentGroup.persistenceKey),
      primaryPic: CategoryCoverStore.shared.hasCover(currentGroup)
          ? CategoryCoverStore.shared.imageFor(currentGroup)
          : currentGroup.coverAudio!.coverForDisplay(
              size: 192,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
      backgroundPic: CategoryCoverStore.shared.hasCover(currentGroup)
          ? CategoryCoverStore.shared.imageFor(currentGroup)
          : currentGroup.coverAudio!.cover,
      picShape: PicShape.rrect,
      badgeLabel: ui('专辑'),
      title: currentGroup.title,
      subtitle: [
        ui('{0} 首作品', [currentGroup.audios.length]),
        if (formatCollectionDurationSeconds(
              sumKnownDurationSeconds(
                  currentGroup.audios.map((audio) => audio.duration)),
            )
            case final totalDuration?)
          totalDuration,
        if (currentGroup.subtitle != null) currentGroup.subtitle!,
      ].join(' · '),
      secondaryContent: secondaryContent,
      secondaryContentSearchText: (audio) =>
          '${audio.displayTitle}\n${audio.artist}\n${audio.album}'
          '${audio.discSubtitle == null ? '' : '\n${audio.discSubtitle}'}',
      secondarySectionHeaderBuilder: _buildDiscSectionHeader,
      secondaryContentBuilder:
          (context, audio, i, visibleContent, multiSelectController) {
        final tile = AudioTile(
          leading: Text(
            (audio.track > 0 ? audio.track : i + 1)
                .toString()
                .padLeft(2, '0'),
            style: const TextStyle(fontFeatures: tabularFiguresFeatures),
          ),
          audioIndex: i,
          playlist: visibleContent,
          multiSelectController: _selection,
        );
        return MusicGridScope.of(context)
            ? tile
            : PlayingAudioListRow(
                audioPath: audio.path,
                nowPlayingPath: widget.nowPlayingPath,
                child: tile,
              );
      },
      tertiaryContentTitle: ui('艺术家'),
      tertiaryContent: artists,
      tertiaryContentBuilder: (context, artist, i, multiSelectController) =>
          DetailRelatedGroupCard(
        group: artist,
        picShape: PicShape.oval,
        fallbackIcon: Symbols.artist,
        onTap: () => context.push(artist.location, extra: artist),
      ),
      enablePlayAll: true,
      enableShufflePlay: true,
      enableAddAllToPlaylist: true,
      enableLocatePlaying: true,
      nowPlayingPath: widget.nowPlayingPath,
      extraActions: [
        IconButton.outlined(
          style: appToolbarControlStyle(context, iconOnly: true),
          tooltip: ui('重新读取封面'),
          icon: const Icon(Symbols.image_search),
          onPressed: () => showCoverRepairDialog(
            context,
            currentGroup.audios,
            album: currentGroup,
          ),
        ),
      ],
      enableSortMethod: true,
      enableSortOrder: true,
      enableSecondaryContentViewSwitch: true,
      multiSelectController: _selection,
      enableMultiSelectAddToPlaylist: true,
      sortMethods: audioSortMethods(AudioSortProfile.album),
    );
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }
}

class _AlbumDiscHeader extends StatelessWidget {
  const _AlbumDiscHeader({
    super.key,
    required this.discNumber,
    required this.discSubtitle,
    required this.discTracks,
    required this.startIndex,
    required this.visibleQueue,
  });

  final int? discNumber;
  final String? discSubtitle;
  final List<Audio> discTracks;
  final int startIndex;
  final List<Audio> visibleQueue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final title = discNumber == null
        ? ui('其他音轨')
        : (discSubtitle != null && discSubtitle!.isNotEmpty)
            ? ui('碟片 {0} · {1}', [discNumber!, discSubtitle!])
            : ui('碟片 {0}', [discNumber!]);
    final durationText = formatCollectionDurationSeconds(
      sumKnownDurationSeconds(discTracks.map((audio) => audio.duration)),
    );
    final meta = [
      ui('{0} 首作品', [discTracks.length]),
      if (durationText != null) durationText,
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(4, startIndex == 0 ? 2 : 12, 4, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow.withValues(
            alpha: isDark ? .76 : .88,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: isDark ? .32 : .42),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.primaryContainer,
                  shape: AppShape.pill,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Symbols.album,
                    size: 16,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    appFontText(
                      context,
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontFeatures: tabularFiguresFeatures,
                      ),
                    ),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFiguresFeatures,
                      ),
                    ),
                  ],
                ),
              ),
              if (PlayService.isInitialized && visibleQueue.isNotEmpty)
                IconButton.filledTonal(
                  key: ValueKey('album-play-disc-${discNumber ?? 0}'),
                  tooltip: ui('从本碟开始播放'),
                  onPressed: () => PlayService.instance.playbackService.play(
                    startIndex,
                    List<Audio>.of(visibleQueue),
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(32),
                    maximumSize: const Size.square(32),
                    padding: EdgeInsets.zero,
                    shape: AppShape.pill,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
