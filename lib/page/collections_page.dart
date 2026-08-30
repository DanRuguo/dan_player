import 'package:dan_player/page/playlists_page.dart';
import 'package:flutter/material.dart';

/// Compatibility route for saved /collections startup destinations.
/// The only editable library is now the unified playlist tree.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaylistsPage();
}
