import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  int _albumCountRevision = -1;
  int _albumCount = 0;
  late int _classificationRevision;

  @override
  void initState() {
    super.initState();
    _classificationRevision = AudioLibrary.classificationRevision;
    AudioLibrary.changes.addListener(_refreshLibraryMembership);
  }

  void _refreshLibraryMembership() {
    final revision = AudioLibrary.classificationRevision;
    if (!mounted || revision == _classificationRevision) return;
    _classificationRevision = revision;
    setState(() {});
  }

  int get _currentAlbumCount {
    if (_albumCountRevision != AudioLibrary.classificationRevision) {
      _albumCountRevision = AudioLibrary.classificationRevision;
      _albumCount = LibraryMusicCategories.albumCount;
    }
    return _albumCount;
  }

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
        // Match the category page's release identity. The old title-only
        // albumCollection merged equal titles owned by different artists.
        albumCount: _currentAlbumCount,
        onNavigate: (playlist) {
          if (playlist != null) {
            context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: playlist);
          }
        },
      );

  @override
  void dispose() {
    AudioLibrary.changes.removeListener(_refreshLibraryMembership);
    super.dispose();
  }
}

int libraryAlbumReleaseCount(Iterable<Audio> audios) =>
    MusicCategories(audios).groups(MusicCategoryKind.album).length;
