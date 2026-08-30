import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';

enum AudioFolderSortField { path, modified, songCount }

/// Uses existing directory descriptors only; a zero modified timestamp means
/// unknown, while a folder containing zero songs has a valid count of zero.
void sortAudioFoldersInPlace(
    List<AudioFolder> folders, AudioFolderSortField field,
    {SortDirection direction = SortDirection.ascending}) {
  final rows = folders.asMap().entries.toList();
  rows.sort((left, right) {
    final a = left.value;
    final b = right.value;
    final compared = switch (field) {
      AudioFolderSortField.path =>
        compareSortText(a.path, b.path, direction: direction),
      AudioFolderSortField.modified => compareSortNumbers(
          a.modified > 0 ? a.modified : null,
          b.modified > 0 ? b.modified : null,
          direction: direction),
      AudioFolderSortField.songCount => compareSortNumbers(
          a.audios.length, b.audios.length,
          direction: direction),
    };
    return compared == 0 ? left.key.compareTo(right.key) : compared;
  });
  folders.setAll(0, rows.map((row) => row.value));
}
