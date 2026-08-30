import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_lyric/ui_language.dart';

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({super.key, required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    if (artist.works.isEmpty) return const CategoriesPage();
    final secondaryContent = List<Audio>.from(artist.works);
    final multiSelectController = MultiSelectController<Audio>();

    return UniDetailPage<Artist, Audio, Album>(
      pref: AppPreference.instance.artistDetailPagePref,
      primaryContent: artist,
      primaryPic: artist.works.first.coverForDisplay(
          size: 200, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
      backgroundPic: artist.works.first.cover,
      picShape: PicShape.oval,
      title: artist.name,
      subtitle: ui("{0} 首作品", [artist.works.length]),
      secondaryContent: secondaryContent,
      secondaryContentBuilder: (context, audio, i, multiSelectController) =>
          AudioTile(
        audioIndex: i,
        playlist: secondaryContent,
        multiSelectController: multiSelectController,
      ),
      tertiaryContentTitle: ui("专辑"),
      tertiaryContent: artist.albumsMap.values.toList(),
      tertiaryContentBuilder: (context, album, i, multiSelectController) =>
          ListTile(
        onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album),
        title: Text(album.name),
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
      sortMethods: audioSortMethods(AudioSortProfile.artist),
    );
  }
}
