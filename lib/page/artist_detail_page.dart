import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/detail_related_group_card.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playing_audio_list_row.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({super.key, required this.artist, this.nowPlayingPath})
      : groupId = null,
        initialGroup = null;

  const ArtistDetailPage.group({
    super.key,
    required this.groupId,
    this.initialGroup,
    this.nowPlayingPath,
  }) : artist = null;

  final Artist? artist;
  final String? groupId;
  final MusicCategoryGroup? initialGroup;
  final ValueListenable<String?>? nowPlayingPath;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
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
  void didUpdateWidget(covariant ArtistDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.artist?.name != widget.artist?.name ||
        !identical(oldWidget.initialGroup, widget.initialGroup)) {
      _allowInitialGroup = true;
      _classificationRevision = AudioLibrary.classificationRevision;
    }
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
    final live = widget.groupId == null
        ? LibraryMusicCategories.groups(MusicCategoryKind.artist)
            .where((group) => group.title == widget.artist?.name)
            .firstOrNull
        : LibraryMusicCategories.find(
            MusicCategoryKind.artist, widget.groupId!);
    if (live != null) _allowInitialGroup = false;
    final initial = widget.initialGroup;
    final current = live ??
        (widget.groupId != null &&
                _allowInitialGroup &&
                initial?.kind == MusicCategoryKind.artist &&
                initial?.id == widget.groupId
            ? initial
            : null);
    if (current == null || current.audios.isEmpty) {
      return const CategoriesPage();
    }
    final secondaryContent = List<Audio>.from(current.audios);
    final currentAudios = current.audios.toSet();
    final albums = LibraryMusicCategories.groups(MusicCategoryKind.album)
        .where((album) => album.audios.any(currentAudios.contains))
        .toList(growable: false);
    return UniDetailPage<String, Audio, MusicCategoryGroup>(
      pref: AppPreference.instance.artistDetailPagePref,
      primaryContent: current.id,
      coverFlightTag: ('category-detail-cover', current.persistenceKey),
      primaryPic: CategoryCoverStore.shared.hasCover(current)
          ? CategoryCoverStore.shared.imageFor(current)
          : current.coverAudio!.coverForDisplay(
              size: 192,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
      backgroundPic: CategoryCoverStore.shared.hasCover(current)
          ? CategoryCoverStore.shared.imageFor(current)
          : current.coverAudio!.cover,
      picShape: PicShape.oval,
      badgeLabel: ui('艺术家'),
      title: current.title,
      subtitle: [
        ui('{0} 首作品', [current.audios.length]),
        if (formatCollectionDurationSeconds(
              sumKnownDurationSeconds(
                  current.audios.map((audio) => audio.duration)),
            )
            case final totalDuration?)
          totalDuration,
      ].join(' · '),
      secondaryContent: secondaryContent,
      secondaryContentSearchText: (audio) =>
          '${audio.displayTitle}\n${audio.artist}\n${audio.album}',
      secondaryContentBuilder:
          (context, audio, i, visibleContent, multiSelectController) {
        final tile = AudioTile(
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
      tertiaryContentTitle: ui('专辑'),
      tertiaryContent: albums,
      tertiaryContentBuilder: (context, album, i, multiSelectController) =>
          DetailRelatedGroupCard(
        group: album,
        picShape: PicShape.rrect,
        fallbackIcon: Symbols.album,
        onTap: () => context.push(album.location, extra: album),
      ),
      enablePlayAll: true,
      enableShufflePlay: true,
      enableAddAllToPlaylist: true,
      enableLocatePlaying: true,
      nowPlayingPath: widget.nowPlayingPath,
      enableSortMethod: true,
      enableSortOrder: true,
      enableSecondaryContentViewSwitch: true,
      multiSelectController: _selection,
      enableMultiSelectAddToPlaylist: true,
      sortMethods: audioSortMethods(AudioSortProfile.artist),
    );
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }
}
