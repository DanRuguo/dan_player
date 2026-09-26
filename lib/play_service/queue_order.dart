import 'dart:collection';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';

/// One-off ordering of the upcoming suffix; never changes a playback mode.
enum UpcomingQueueOrder {
  shuffle('随机排列待播歌曲'),
  albumShuffle('按专辑块随机排列待播歌曲'),
  interleaveArtists('交错排列待播艺术家'),
  albumTrack('待播歌曲按专辑与音轨排序'),
  format('待播歌曲按文件格式排序'),
  bitrate('待播歌曲按码率从高到低排序'),
  sampleRate('待播歌曲按采样率从高到低排序'),
  added('待播歌曲按文件创建时间排序（新到旧）'),
  modified('待播歌曲按文件修改时间排序（新到旧）'),
  source('待播歌曲按本地与来源分组'),
  language('待播歌曲按语言标签分组');

  const UpcomingQueueOrder(this.label);
  final String label;
  bool get arrangement => index <= interleaveArtists.index;
}

String? _known(String? value) =>
    compareSortText(value, null) == 0 ? null : value!.trim().toLowerCase();
num? _positive(num? value) => value != null && value > 0 ? value : null;

Object _albumKey(QueueOccurrence<Audio> entry) {
  final audio = entry.item;
  final album = _known(audio.album);
  return album == null
      ? ('unknown-album', entry.id)
      : ('album', audio.albumIdentity.id);
}

Object _artistKey(QueueOccurrence<Audio> entry) =>
    _known(entry.item.artist) ?? ('unknown-artist', entry.id);

String? _format(Audio audio) {
  if (audio.isOnline) return null;
  final filename = audio.localFilePath.replaceAll('\\', '/').split('/').last;
  final dot = filename.lastIndexOf('.');
  return dot <= 0 || dot == filename.length - 1
      ? null
      : filename.substring(dot + 1).toLowerCase();
}

int _compare(Audio a, Audio b, UpcomingQueueOrder order) {
  const descending = SortDirection.descending;
  switch (order) {
    case UpcomingQueueOrder.albumTrack:
      final album = compareSortText(a.album, b.album);
      if (album != 0) return album;
      // Missing albums are not treated as one anonymous album.
      if (_known(a.album) == null) return 0;
      final artist = compareSortText(
          _known(a.albumArtist) ?? a.artist, _known(b.albumArtist) ?? b.artist);
      if (artist != 0) return artist;
      return compareSortNumbers(_positive(a.cueTrack?.number ?? a.track),
          _positive(b.cueTrack?.number ?? b.track));
    case UpcomingQueueOrder.format:
      return compareSortText(_format(a), _format(b));
    case UpcomingQueueOrder.bitrate:
      return compareSortNumbers(_positive(a.bitrate), _positive(b.bitrate),
          direction: descending);
    case UpcomingQueueOrder.sampleRate:
      return compareSortNumbers(
          _positive(a.sampleRate), _positive(b.sampleRate),
          direction: descending);
    case UpcomingQueueOrder.added:
      return compareSortNumbers(_positive(a.created), _positive(b.created),
          direction: descending);
    case UpcomingQueueOrder.modified:
      return compareSortNumbers(a.isOnline ? null : _positive(a.modified),
          b.isOnline ? null : _positive(b.modified),
          direction: descending);
    case UpcomingQueueOrder.source:
      if (a.isOnline != b.isOnline) return a.isOnline ? 1 : -1;
      return a.isOnline
          ? compareSortText(a.onlineProvider, b.onlineProvider)
          : 0;
    case UpcomingQueueOrder.language:
      return compareSortText(a.language, b.language);
    default:
      throw ArgumentError('Arrangement is not a metadata comparator');
  }
}

class _ArtistBucket {
  _ArtistBucket(this.key, this.firstSeen);
  final Object key;
  final int firstSeen;
  final items = <QueueOccurrence<Audio>>[];
  int cursor = 0;
  int get remaining => items.length - cursor;
}

List<QueueOccurrence<Audio>> _interleave(
    List<QueueOccurrence<Audio>> suffix, Object currentArtist) {
  final byArtist = <Object, _ArtistBucket>{};
  for (final entry in suffix) {
    final key = _artistKey(entry);
    (byArtist[key] ??= _ArtistBucket(key, byArtist.length)).items.add(entry);
  }
  final available = SplayTreeSet<_ArtistBucket>((a, b) {
    final count = b.remaining.compareTo(a.remaining);
    return count == 0 ? a.firstSeen.compareTo(b.firstSeen) : count;
  })
    ..addAll(byArtist.values);
  final ordered = <QueueOccurrence<Audio>>[];
  var previous = currentArtist;
  while (available.isNotEmpty) {
    var bucket = available.first;
    available.remove(bucket);
    if (bucket.key == previous && available.isNotEmpty) {
      final alternative = available.first;
      available.remove(alternative);
      available.add(bucket);
      bucket = alternative;
    }
    ordered.add(bucket.items[bucket.cursor++]);
    previous = bucket.key;
    if (bucket.remaining > 0) available.add(bucket);
  }
  return ordered;
}

/// Metadata-only, stable and occurrence-preserving. Random can be seeded in
/// tests; unknown tags stay last in metadata sorts and singleton in grouping.
QueueEdit<QueueOccurrence<Audio>>? organizeUpcomingQueue(
    List<QueueOccurrence<Audio>> items, int current, UpcomingQueueOrder order,
    {Random? random}) {
  if (current < 0 || current >= items.length - 2) return null;
  final suffix = items.sublist(current + 1);
  switch (order) {
    case UpcomingQueueOrder.shuffle:
      suffix.shuffle(random);
      break;
    case UpcomingQueueOrder.albumShuffle:
      final groups = <Object, List<QueueOccurrence<Audio>>>{};
      for (final entry in suffix) {
        (groups[_albumKey(entry)] ??= []).add(entry);
      }
      final blocks = groups.values.toList()..shuffle(random);
      return QueueEdit.replaceUpcoming(
          items, current, blocks.expand((block) => block).toList());
    case UpcomingQueueOrder.interleaveArtists:
      return QueueEdit.replaceUpcoming(
          items, current, _interleave(suffix, _artistKey(items[current])));
    default:
      return QueueEdit.orderUpcoming<QueueOccurrence<Audio>>(items, current,
          compare: (a, b) => _compare(a.item, b.item, order));
  }
  return QueueEdit.replaceUpcoming(items, current, suffix);
}
