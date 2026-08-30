import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) => PlaylistBrowser(
        initialPlaylist: playlist,
        initialView: AppPreference.instance.unifiedPlaylistDetailsLayout ??
            PlaylistViewMode.resolve(null,
                legacy: (AppPreference.instance.unifiedPlaylistDetailsView ??
                        (playlist.legacyCollectionKey != null
                            ? AppPreference
                                .instance.collectionDetailPagePref.contentView
                            : AppPreference
                                .instance.playlistDetailPagePref.contentView))
                    .name),
        onViewChanged: (view) =>
            AppPreference.instance.unifiedPlaylistDetailsLayout = view,
        onNavigate: (destination) {
          if (destination == null) {
            context.go(app_paths.PLAYLISTS_PAGE);
          } else {
            context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: destination);
          }
        },
      );
}
