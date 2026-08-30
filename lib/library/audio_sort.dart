import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/sorting/sort_direction.dart';
import 'package:dan_player/utils.dart';

export 'package:dan_player/sorting/sort_direction.dart';

/// Only existing descriptor fields are used. Sorting never resolves an online
/// track, scans files, infers tags, or persists a playlist's displayed order.
enum AudioSortField {
  original('乐库顺序', '原始顺序'),
  name('名称', '歌曲信息'),
  artist('艺术家', '歌曲信息'),
  album('专辑', '歌曲信息'),
  composer('作曲家', '歌曲信息'),
  duration('时长', '歌曲信息'),
  added('添加时间', '时间'),
  modified('修改时间', '时间'),
  track('音轨', '歌曲信息'),
  albumArtist('专辑艺术家', '歌曲信息'),
  bitrate('码率', '文件与来源'),
  sampleRate('采样率', '文件与来源'),
  fileSize('文件大小', '文件与来源'),
  format('文件格式', '文件与来源'),
  language('语言标签', '歌曲信息'),
  source('来源', '文件与来源');

  const AudioSortField(this.label, this.group);
  final String label;
  final String group;

  String? get note => switch (this) {
        added => '本地使用文件创建时间；联网使用加入乐库时间。',
        modified => '使用本地文件的修改时间；联网曲目没有此信息。',
        fileSize => '使用最近索引的本地字节数，不重新扫描；联网不算本地占用。',
        format => '使用本地文件扩展名；未提供格式的联网曲目排在最后。',
        language => '只使用已有语言标签，不根据名称猜测语言。',
        original => '保留原有乐库顺序。',
        _ => null,
      };
}

const audioSortMissingValueNote = '缺失或不适用的信息始终排在最后；相同值保留原有次序。';

String? _knownText(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  const placeholders = {
    'unknown',
    'unknown artist',
    'unknown album',
    '(unknown)',
    '<unknown>',
    'n/a',
    'null',
    '未知',
    '未知艺术家',
    '未知专辑',
    '未知作曲家',
    '未填写',
    '未提供',
    '不详',
    '未识别',
  };
  return placeholders.contains(text.toLowerCase()) ? null : text;
}

int _compareKnown<T>(
    T? a, T? b, int Function(T, T) compare, SortDirection direction) {
  // Apply direction only after handling unknowns: reversing the whole list
  // would move unknown values to the front and reverse equal-key occurrences.
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  final result = compare(a, b);
  return direction == SortDirection.ascending ? result : -result;
}

int compareSortText(String? a, String? b,
        {SortDirection direction = SortDirection.ascending}) =>
    _compareKnown(_knownText(a), _knownText(b),
        (left, right) => left.localeCompareTo(right), direction);

/// Zero is a valid number here (for example an empty file or empty playlist).
/// Callers pass null for descriptor-specific missing values such as track 0.
int compareSortNumbers(num? a, num? b,
        {SortDirection direction = SortDirection.ascending}) =>
    _compareKnown(
        a?.isFinite == true ? a : null,
        b?.isFinite == true ? b : null,
        (left, right) => left.compareTo(right),
        direction);

num? _positive(num? number) => number != null && number > 0 ? number : null;

String? _fileFormat(Audio audio) {
  if (audio.isOnline) return null;
  final name = audio.path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1
      ? null
      : name.substring(dot + 1).toLowerCase();
}

Object? _value(Audio? audio, AudioSortField field) {
  if (audio == null) return null;
  return switch (field) {
    AudioSortField.original => null,
    AudioSortField.name => _knownText(audio.displayTitle),
    AudioSortField.artist => _knownText(audio.artist),
    AudioSortField.album => _knownText(audio.album),
    AudioSortField.composer => _knownText(audio.composer),
    AudioSortField.albumArtist => _knownText(audio.albumArtist),
    AudioSortField.language => _knownText(audio.language),
    AudioSortField.duration => _positive(audio.duration),
    AudioSortField.added => _positive(audio.created),
    AudioSortField.modified =>
      audio.isOnline ? null : _positive(audio.modified),
    AudioSortField.track => _positive(audio.track),
    AudioSortField.bitrate => _positive(audio.bitrate),
    AudioSortField.sampleRate => _positive(audio.sampleRate),
    AudioSortField.fileSize =>
      audio.isOnline || audio.fileSizeBytes == null || audio.fileSizeBytes! < 0
          ? null
          : audio.fileSizeBytes,
    AudioSortField.format => _fileFormat(audio),
    AudioSortField.source =>
      audio.isOnline ? '联网 · ${audio.sourceLabel}' : '本地',
  };
}

int _compareValues(Object? a, Object? b, SortDirection direction) =>
    _compareKnown(a, b, (left, right) {
      if (left is num && right is num) return left.compareTo(right);
      return (left as String).localeCompareTo(right as String);
    }, direction);

/// Null audio is an entry without song-specific information, e.g. a child
/// playlist. Its position remains stable among other unknown entries.
int compareAudioSort(Audio? a, Audio? b, AudioSortField field,
    {SortDirection direction = SortDirection.ascending}) {
  if (field == AudioSortField.original) return 0;
  return _compareValues(_value(a, field), _value(b, field), direction);
}

/// Returns a sorted copy. Decorations avoid repeated descriptor extraction and
/// make equal keys stable even though List.sort itself does not promise that.
List<Audio> sortedAudios(Iterable<Audio> audios, AudioSortField field,
    {SortDirection direction = SortDirection.ascending}) {
  if (field == AudioSortField.original) return List<Audio>.of(audios);
  var index = 0;
  final rows = [
    for (final audio in audios)
      (audio: audio, position: index++, value: _value(audio, field)),
  ];
  rows.sort((a, b) {
    final result = _compareValues(a.value, b.value, direction);
    return result == 0 ? a.position.compareTo(b.position) : result;
  });
  return [for (final row in rows) row.audio];
}

/// Adapter for the existing UniPage contract. Only pass the page's own display
/// list, never AudioLibrary.audioCollection or Playlist.entries.
void sortAudiosInPlace(List<Audio> audios, AudioSortField field,
    {SortDirection direction = SortDirection.ascending}) {
  if (field == AudioSortField.original) return;
  audios.setAll(0, sortedAudios(audios, field, direction: direction));
}
