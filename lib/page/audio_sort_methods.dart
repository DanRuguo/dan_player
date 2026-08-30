import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/component/audio_sort_options.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/ui_language.dart';

/// These profiles preserve the exact historical preference indexes. New fields
/// are appended, never inserted before an existing entry (including custom 5).
enum AudioSortProfile { library, artist, album, folder }

class AudioSortMethodDesc extends SortMethodDesc<Audio> {
  AudioSortMethodDesc(this.field)
      : super(
          name: field.label,
          icon: audioSortIcon(field),
          usesSortOrder: field != AudioSortField.original,
          method: (list, order) => sortAudiosInPlace(list, field,
              direction: order == SortOrder.ascending
                  ? SortDirection.ascending
                  : SortDirection.descending),
        );

  final AudioSortField field;
}

List<SortMethodDesc<Audio>> audioSortMethods(AudioSortProfile profile,
    {SortMethodDesc<Audio>? custom}) {
  if (profile == AudioSortProfile.library && custom == null) {
    throw ArgumentError(ui("音乐页必须提供旧自定义排序，保留索引 5。"));
  }
  final prefix = switch (profile) {
    AudioSortProfile.library || AudioSortProfile.folder => const [
        AudioSortField.name,
        AudioSortField.artist,
        AudioSortField.album,
        AudioSortField.added,
        AudioSortField.modified,
      ],
    AudioSortProfile.artist => const [
        AudioSortField.name,
        AudioSortField.album,
        AudioSortField.added,
        AudioSortField.modified,
      ],
    AudioSortProfile.album => const [
        AudioSortField.name,
        AudioSortField.artist,
        AudioSortField.track,
        AudioSortField.added,
        AudioSortField.modified,
      ],
  };
  return [
    for (final field in prefix) AudioSortMethodDesc(field),
    if (profile == AudioSortProfile.library) custom!,
    for (final field in AudioSortField.values)
      if (field != AudioSortField.original && !prefix.contains(field))
        AudioSortMethodDesc(field),
  ];
}
