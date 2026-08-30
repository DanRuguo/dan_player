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
    // Legacy album extras used a title-only map. Ask the user to choose the
    // release when that snapshot contains different album artists.
    if (album.works.isEmpty ||
        MusicCategories(album.works).groups(MusicCategoryKind.album).length >
            1) {
      return CategoriesPage(
        initialCategory: MusicCategoryKind.album,
        audios: album.works,
      );
    }
    final secondaryContent = List<Audio>.from(album.works);
    final multiSelectController = MultiSelectController<Audio>();

    return UniDetailPage<Album, Audio, Artist>(
      pref: AppPreference.instance.albumDetailPagePref,
      primaryContent: album,
      primaryPic: album.works.first.coverForDisplay(
          size: 200, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
      backgroundPic: album.works.first.cover,
      picShape: PicShape.rrect,
      title: album.name,
      subtitle: ui("{0} 首作品", [album.works.length]),
      secondaryContent: secondaryContent,
      secondaryContentBuilder: (context, audio, i, multiSelectController) =>
          AudioTile(
        leading: Text(audio.track < 10 ? "0${audio.track}" : "${audio.track}"),
        audioIndex: i,
        playlist: secondaryContent,
        multiSelectController: multiSelectController,
      ),
      tertiaryContentTitle: ui("艺术家"),
      tertiaryContent: album.artistsMap.values.toList(),
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
