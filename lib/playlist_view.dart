/// Playlist-only layouts. Do not add these to the shared song/library views.
enum PlaylistViewMode {
  list,
  grid,
  circular;

  /// Accept the old shared grid name when migrating earlier preferences.
  static PlaylistViewMode? parse(Object? value) => switch (value) {
        'list' => list,
        'grid' || 'table' => grid,
        'circular' => circular,
        _ => null,
      };

  static PlaylistViewMode resolve(Object? saved, {required String legacy}) =>
      parse(saved) ?? parse(legacy) ?? list;
}
