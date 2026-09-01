import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_lyric/ui_language.dart';

class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({super.key, required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<int>(
      valueListenable: AudioLibrary.changes,
      builder: (context, _, __) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    // Legacy album extras used a title-only map. Ask the user to choose the
    // release when that snapshot contains different album artists.
    if (album.works.isEmpty) {
      return const CategoriesPage(initialCategory: MusicCategoryKind.album);
    }
    final originalGroups =
        MusicCategories(album.works).groups(MusicCategoryKind.album);
    if (originalGroups.length != 1) {
      final originalIds = originalGroups.map((group) => group.id).toSet();
      final currentCandidates =
          MusicCategories(AudioLibrary.instance.audioCollection)
              .groups(MusicCategoryKind.album)
              .where((group) => originalIds.contains(group.id))
              .expand((group) => group.audios)
              .toList();
      return CategoriesPage(
        initialCategory: MusicCategoryKind.album,
        // Old title-only route payloads may not belong to the current indexed
        // library (migration/deep-link tests exercise this). Prefer live
        // matches, but retain the legacy disambiguation candidates when none
        // can be resolved.
        audios: currentCandidates.isEmpty ? album.works : currentCandidates,
      );
    }
    final currentGroup = MusicCategories(AudioLibrary.instance.audioCollection)
        .find(MusicCategoryKind.album, originalGroups.single.id);
    if (currentGroup == null || currentGroup.audios.isEmpty) {
      return const CategoriesPage(initialCategory: MusicCategoryKind.album);
    }
    final current = Album(name: currentGroup.title)
      ..works.addAll(currentGroup.audios);
    for (final audio in current.works) {
      for (final artistName in audio.splitedArtists) {
        final artist = AudioLibrary.instance.artistCollection[artistName];
        if (artist != null) current.artistsMap[artistName] = artist;
      }
    }
    final secondaryContent = List<Audio>.from(current.works);
    final multiSelectController = MultiSelectController<Audio>();

    return UniDetailPage<Album, Audio, Artist>(
      pref: AppPreference.instance.albumDetailPagePref,
      primaryContent: current,
      primaryPic: current.works.first.coverForDisplay(
          size: 200, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
      backgroundPic: current.works.first.cover,
      picShape: PicShape.rrect,
      title: current.name,
      subtitle: ui("{0} 首作品", [current.works.length]),
      secondaryContent: secondaryContent,
      secondaryContentBuilder: (context, audio, i, multiSelectController) =>
          AudioTile(
        leading: Text(audio.track < 10 ? "0${audio.track}" : "${audio.track}"),
        audioIndex: i,
        playlist: secondaryContent,
        multiSelectController: multiSelectController,
      ),
      tertiaryContentTitle: ui("艺术家"),
      tertiaryContent: current.artistsMap.values.toList(),
      tertiaryContentBuilder: (context, artist, i, multiSelectController) =>
          ListTile(
        onTap: () => context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist),
        title: Text(artist.name),
        shape: AppShape.control,
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableSecondaryContentViewSwitch: true,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: secondaryContent,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: audioSortMethods(AudioSortProfile.album),
    );
  }
}
