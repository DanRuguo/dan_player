import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:flutter/material.dart';

/// Backwards-compatible /albums entry; the saved route remains valid.
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const CategoriesPage(initialCategory: MusicCategoryKind.album);
}
