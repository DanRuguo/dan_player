import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.album})
      : groupId = null,
        initialGroup = null;

  const AlbumDetailPage.group({
    super.key,
    required this.groupId,
    this.initialGroup,
  }) : album = null;

  final Album? album;
  final String? groupId;
  final MusicCategoryGroup? initialGroup;

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

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        AudioLibrary.changes,
        CategoryCoverStore.shared,
        CoverCache.instance.changes
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
      primaryPic: CategoryCoverStore.shared.hasCover(currentGroup)
          ? CategoryCoverStore.shared.imageFor(currentGroup)
          : currentGroup.coverAudio!.coverForDisplay(
              size: 200,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
      backgroundPic: CategoryCoverStore.shared.hasCover(currentGroup)
          ? CategoryCoverStore.shared.imageFor(currentGroup)
          : currentGroup.coverAudio!.cover,
      picShape: PicShape.rrect,
      title: currentGroup.title,
      subtitle: [
        ui("{0} 首作品", [currentGroup.audios.length]),
        if (currentGroup.subtitle != null) currentGroup.subtitle!,
      ].join(' · '),
      secondaryContent: secondaryContent,
      secondaryContentSearchText: (audio) =>
          '${audio.displayTitle}\n${audio.artist}\n${audio.album}',
      secondaryContentBuilder:
          (context, audio, i, visibleContent, multiSelectController) =>
              AudioTile(
        leading: Text(
            (audio.track > 0 ? audio.track : i + 1).toString().padLeft(2, '0')),
        audioIndex: i,
        playlist: visibleContent,
        multiSelectController: _selection,
      ),
      tertiaryContentTitle: ui("艺术家"),
      tertiaryContent: artists,
      tertiaryContentBuilder: (context, artist, i, multiSelectController) =>
          ListTile(
        onTap: () => context.push(artist.location, extra: artist),
        leading: const Icon(Symbols.artist),
        title: Text(artist.title),
        subtitle: Text(ui("{0} 首作品", [artist.audios.length])),
        shape: AppShape.control,
      ),
      enablePlayAll: true,
      enableShufflePlay: true,
      enableAddAllToPlaylist: true,
      extraActions: [
        IconButton.outlined(
          tooltip: ui('重新读取封面'),
          icon: const Icon(Symbols.image_search),
          onPressed: () => showCoverRepairDialog(context, currentGroup.audios,
              album: currentGroup),
        )
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
