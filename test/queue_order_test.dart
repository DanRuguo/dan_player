import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_order.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String id,
        {String artist = 'Artist',
        String album = 'Album',
        String? albumArtist,
        String? language,
        int track = 0,
        int? bitrate = 320,
        int? rate = 44100,
        int created = 10,
        int modified = 5,
        String? path,
        String? provider,
        CueTrackReference? cue}) =>
    Audio(
        id,
        artist,
        album,
        track,
        120,
        bitrate,
        rate,
        path ??
            (provider == null
                ? 'J:/queue-fixture/$id.mp3'
                : 'online://$provider/$id'),
        modified,
        created,
        'Test',
        albumArtist: albumArtist,
        language: language,
        onlineProvider: provider,
        onlineId: provider == null ? null : id,
        cueTrack: cue);

List<QueueOccurrence<Audio>> _entries(List<Audio> audios) =>
    [for (final audio in audios) QueueOccurrence(audio)];

List<String> _titles(QueueEdit<QueueOccurrence<Audio>> edit) =>
    [for (final entry in edit.items) entry.item.title];

class _KeepOrderRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => .999;
}

void main() {
  test('upcoming permutation rejects missing, replaced or extra occurrences',
      () {
    final items = _entries([_audio('current'), _audio('a'), _audio('b')]);
    expect(() => QueueEdit.replaceUpcoming(items, 0, [items[1]]),
        throwsArgumentError);
    expect(() => QueueEdit.replaceUpcoming(items, 0, [items[1], items[1]]),
        throwsArgumentError);
    expect(
        () => QueueEdit.replaceUpcoming(
            items, 0, [items[1], QueueOccurrence(items[2].item)]),
        throwsArgumentError);
    expect(QueueEdit.replaceUpcoming(items, 0, items.sublist(1)), isNull);
  });

  for (final order in UpcomingQueueOrder.values) {
    test('${order.name} protects prefix, active, stop token and duplicates',
        () {
      final repeated = _audio('repeat', artist: 'B', track: 2);
      final items = _entries([
        _audio('played'),
        _audio('current', artist: 'A'),
        _audio('z',
            artist: 'B',
            album: 'Z',
            track: 3,
            language: 'zh',
            bitrate: 128,
            created: 1,
            modified: 1),
        repeated,
        _audio('a',
            artist: 'A',
            album: 'A',
            track: 1,
            language: 'en',
            bitrate: 960,
            created: 40,
            modified: 40,
            path: 'J:/queue-fixture/a.flac'),
        repeated,
        _audio('online', artist: 'C', provider: 'qq', language: 'ja')
      ]);
      final edit = organizeUpcomingQueue(items, 1, order, random: Random(3));
      final result = edit?.items ?? items;
      expect(result.take(2), orderedEquals(items.take(2)));
      expect(result.map((entry) => entry.id).toSet(),
          items.map((entry) => entry.id).toSet());
      expect(result.where((entry) => identical(entry.item, repeated)),
          hasLength(2));
      expect(edit?.currentIndex ?? 1, 1);
      if (edit != null) {
        final backup = items.reversed.toList();
        final history = QueueEditHistory<QueueOccurrence<Audio>>();
        expect(
            history.record(QueueSnapshot(items, backup, 1),
                QueueSnapshot(result, backup, 1)),
            isTrue);
        final undo = history.undo(result, backup, 1)!;
        expect(undo.items, orderedEquals(items));
        expect(undo.backup, orderedEquals(backup));
        expect(history.redo(undo.items, undo.backup, 1)!.items,
            orderedEquals(result));
      }
    });
  }

  test('no active or fewer than two upcoming items consumes no history', () {
    final items = _entries([_audio('current'), _audio('next')]);
    for (final order in UpcomingQueueOrder.values) {
      for (final current in [-1, 0, 1, 2]) {
        expect(organizeUpcomingQueue(items, current, order, random: Random(3)),
            isNull);
      }
    }
  });

  test('random draws that preserve the order return a no-op edit', () {
    final items = _entries([
      _audio('current'),
      _audio('one', album: 'One'),
      _audio('two', album: 'Two'),
      _audio('three', album: 'Three')
    ]);
    for (final order in [
      UpcomingQueueOrder.shuffle,
      UpcomingQueueOrder.albumShuffle
    ]) {
      expect(organizeUpcomingQueue(items, 0, order, random: _KeepOrderRandom()),
          isNull);
    }
  });

  test('album shuffle distinguishes album artist and preserves internal order',
      () {
    final items = _entries([
      _audio('current'),
      _audio('a1', album: 'Same', albumArtist: 'One'),
      _audio('b1', album: 'Same', albumArtist: 'Two'),
      _audio('a2', album: 'Same', albumArtist: 'One'),
      _audio('b2', album: 'Same', albumArtist: 'Two'),
      _audio('u1', album: ''),
      _audio('u2', album: '')
    ]);
    final edit = organizeUpcomingQueue(
        items, 0, UpcomingQueueOrder.albumShuffle,
        random: Random(4))!;
    final titles = _titles(edit);
    expect(titles.indexOf('a2'), titles.indexOf('a1') + 1);
    expect(titles.indexOf('b2'), titles.indexOf('b1') + 1);
    expect(titles.indexOf('u2'), isNot(titles.indexOf('u1') + 1));
  });

  test('artist interleave respects current artist and stable per-artist order',
      () {
    final items = _entries([
      _audio('current', artist: 'A'),
      _audio('a1', artist: 'A'),
      _audio('a2', artist: 'A'),
      _audio('a3', artist: 'A'),
      _audio('b1', artist: 'B'),
      _audio('b2', artist: 'B'),
      _audio('b3', artist: 'B')
    ]);
    final edit =
        organizeUpcomingQueue(items, 0, UpcomingQueueOrder.interleaveArtists)!;
    expect(_titles(edit), ['current', 'b1', 'a1', 'b2', 'a2', 'b3', 'a3']);
    expect(
        organizeUpcomingQueue(
            edit.items, 0, UpcomingQueueOrder.interleaveArtists),
        isNull);
  });

  test('unavoidable artist repeats are retained and unknown artists singleton',
      () {
    final items = _entries([
      _audio('current', artist: 'A'),
      _audio('a1', artist: 'A'),
      _audio('a2', artist: 'A'),
      _audio('a3', artist: 'A'),
      _audio('b1', artist: 'B'),
      _audio('u1', artist: ''),
      _audio('u2', artist: '')
    ]);
    final result =
        organizeUpcomingQueue(items, 0, UpcomingQueueOrder.interleaveArtists)!
            .items;
    expect(result, hasLength(items.length));
    expect(
        result
            .where((entry) => entry.item.artist == 'A')
            .map((entry) => entry.item.title),
        ['current', 'a1', 'a2', 'a3']);
  });

  test('album track uses CUE number and physical format, ignores online format',
      () {
    const cue = CueTrackReference(
        cuePath: 'J:/fixture/disk.cue',
        sourcePath: 'J:/fixture/disk.flac',
        number: 2,
        startFrame: 0);
    final items = _entries([
      _audio('current'),
      _audio('mp3', track: 3),
      _audio('cue', track: 0, path: cue.identity, cue: cue),
      _audio('first', track: 1),
      _audio('online', provider: 'qq')
    ]);
    expect(
        _titles(
            organizeUpcomingQueue(items, 0, UpcomingQueueOrder.albumTrack)!),
        ['current', 'first', 'cue', 'mp3', 'online']);
    expect(_titles(organizeUpcomingQueue(items, 0, UpcomingQueueOrder.format)!),
        ['current', 'cue', 'mp3', 'first', 'online']);
  });

  for (final order in [
    UpcomingQueueOrder.bitrate,
    UpcomingQueueOrder.sampleRate,
    UpcomingQueueOrder.added,
    UpcomingQueueOrder.modified
  ]) {
    test('${order.name} high first, unknown last, ties stable', () {
      final items = _entries([
        _audio('current'),
        _audio('unknown', bitrate: null, rate: null, created: 0, modified: 0),
        _audio('low', bitrate: 128, rate: 44100, created: 1, modified: 1),
        _audio('high1', bitrate: 960, rate: 192000, created: 9, modified: 9),
        _audio('high2', bitrate: 960, rate: 192000, created: 9, modified: 9)
      ]);
      expect(_titles(organizeUpcomingQueue(items, 0, order)!),
          ['current', 'high1', 'high2', 'low', 'unknown']);
    });
  }

  test(
      'source groups local and distinct online providers, language unknown last',
      () {
    final items = _entries([
      _audio('current'),
      _audio('qq1', provider: 'qq', language: 'zh'),
      _audio('local', language: 'en'),
      _audio('wy', provider: 'netease', language: 'ja'),
      _audio('qq2', provider: 'qq', language: 'zh'),
      _audio('unknown', provider: 'qq')
    ]);
    expect(_titles(organizeUpcomingQueue(items, 0, UpcomingQueueOrder.source)!),
        ['current', 'local', 'wy', 'qq1', 'qq2', 'unknown']);
    expect(
        _titles(organizeUpcomingQueue(items, 0, UpcomingQueueOrder.language)!),
        ['current', 'local', 'wy', 'qq1', 'qq2', 'unknown']);
  });

  test('online modification time is unavailable even if descriptor has a value',
      () {
    final items = _entries([
      _audio('current'),
      _audio('online', provider: 'qq', modified: 100),
      _audio('older', modified: 1),
      _audio('newer', modified: 10)
    ]);
    expect(
        _titles(organizeUpcomingQueue(items, 0, UpcomingQueueOrder.modified)!),
        ['current', 'newer', 'older', 'online']);
  });

  test(
      'large artist interleave retains all slots without adjacent repeated artists',
      () {
    final items = _entries([
      _audio('current', artist: 'Artist 0'),
      for (var artist = 0; artist < 1000; artist++)
        for (var track = 0; track < 12; track++)
          _audio('$artist-$track', artist: 'Artist $artist')
    ]);
    final edit =
        organizeUpcomingQueue(items, 0, UpcomingQueueOrder.interleaveArtists)!;
    expect(edit.items.map((entry) => entry.id).toSet(),
        items.map((entry) => entry.id).toSet());
    for (var i = 1; i < edit.items.length; i++) {
      expect(edit.items[i].item.artist, isNot(edit.items[i - 1].item.artist));
    }
  });
}
