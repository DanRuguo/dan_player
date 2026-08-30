import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) => PlaylistBrowser(
        initialView: AppPreference.instance.unifiedPlaylistsLayout ??
            PlaylistViewMode.resolve(null,
                legacy: (AppPreference.instance.unifiedPlaylistsView ??
                        AppPreference.instance.collectionsPagePref.contentView)
                    .name),
        onViewChanged: (view) =>
            AppPreference.instance.unifiedPlaylistsLayout = view,
        onOpenAlbums: () => context.push(app_paths.ALBUMS_PAGE),
        albumCount: AudioLibrary.instance.albumCollection.length,
        onNavigate: (playlist) {
          if (playlist != null) {
            context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: playlist);
          }
        },
      );
}
