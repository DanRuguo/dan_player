import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:flutter/material.dart';

/// Backwards-compatible /artists entry; the saved route remains valid.
class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const CategoriesPage(initialCategory: MusicCategoryKind.artist);
}
