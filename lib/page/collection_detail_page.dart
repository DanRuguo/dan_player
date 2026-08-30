import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/playlist_detail_page.dart';
import 'package:dan_player/page/playlists_page.dart';
import 'package:flutter/material.dart';

/// Old route payloads still resolve to the migrated node, never a second copy.
class CollectionDetailPage extends StatelessWidget {
  const CollectionDetailPage({super.key, required this.collection});

  final UserCollection collection;

  @override
  Widget build(BuildContext context) {
    final playlist = playlistTree.findByLegacyCollectionId(collection.id) ??
        playlistTree.findPlaylist(collection.id);
    return playlist == null
        ? const PlaylistsPage()
        : PlaylistDetailPage(playlist: playlist);
  }
}
