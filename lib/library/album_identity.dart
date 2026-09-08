import 'dart:convert';

/// Exactly the established category normalization; no guessed release tags.
String? normalizedMusicTag(String? value) {
  final name = value?.trim();
  return name == null || name.isEmpty || name.toUpperCase() == 'UNKNOWN'
      ? null
      : name;
}

class AlbumIdentity {
  AlbumIdentity(String album, String? albumArtist, String artist)
      : title = normalizedMusicTag(album),
        owner = normalizedMusicTag(albumArtist) ?? normalizedMusicTag(artist);

  final String? title;
  final String? owner;
  String get id => jsonEncode(['album', title, owner]);
  String get displayTitle => title ?? '未知专辑';
  String get displayOwner => owner ?? '未知专辑艺术家';
}
