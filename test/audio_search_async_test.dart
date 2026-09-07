import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String title, int id) => Audio(title, '', '', 1, 240, 320, 44100,
    'J:/synthetic/search/$id.mp3', 1, 1, 'test');

void replaceLibrary(List<Audio> songs) {
  final library = AudioLibrary.instance;
  library.audioCollection
    ..clear()
    ..addAll(songs);
  library.artistCollection.clear();
  library.albumCollection.clear();
  AudioLibrary.searchRevision++;
  AudioLibrary.revision++;
}

void main() {
  tearDown(() => replaceLibrary([]));

  test('late exact matches beat an already full result cutoff', () async {
    final weak = [
      for (var i = 9999; i >= 0; i--)
        song('prefix target ${i.toString().padLeft(5, '0')}', i),
    ];
    final exact = song('target', 10000);
    final prefix = song('target album', 10001);
    replaceLibrary([...weak, prefix, exact]);
    final results =
        await AudioSearchIndex.instance.searchAll('target', audioLimit: 4);
    expect(results.audios.map((s) => s.title), [
      'target',
      'target album',
      'prefix target 00000',
      'prefix target 00001',
    ]);
  });

  test('equal names and ranks preserve their original occurrences', () async {
    final songs = [
      for (var i = 0; i < 1000; i++)
        song('same', i)..path = 'J:/synthetic/search/$i/same.mp3',
    ];
    replaceLibrary(songs);
    final result =
        await AudioSearchIndex.instance.searchAll('same', audioLimit: 7);
    expect(result.audios, orderedEquals(songs.take(7)));
    expect(AudioSearchIndex.instance.searchAudios('same', limit: 7),
        orderedEquals(songs.take(7)));
    expect(
        (await AudioSearchIndex.instance.searchAll('same', audioLimit: 0))
            .audios,
        isEmpty);
  });

  test('a warm broad query yields while scoring, so input can cancel it',
      () async {
    replaceLibrary([for (var i = 0; i < 5000; i++) song('song $i', i)]);
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    var cancelled = false;
    var observedChecks = 0;
    final query = index.searchAll('song', checkCancelled: () {
      observedChecks++;
      if (cancelled) throw StateError('cancelled by new input');
      // Query check, post-build check, then the first scoring batch check.
      if (observedChecks == 3) Timer.run(() => cancelled = true);
    });
    await expectLater(query, throwsA(isA<StateError>()));
    expect(cancelled, isTrue);
    expect(observedChecks, lessThan(8),
        reason: 'Cancelled queries must not score all remaining batches.');
  });

  test('metadata changes awaiting publication cannot change heap ordering',
      () async {
    final songs = [
      for (var i = 0; i < 600; i++)
        song('song ${i.toString().padLeft(5, '0')}', i)
          ..path =
              'J:/synthetic/search/song ${i.toString().padLeft(5, '0')}.mp3',
    ];
    replaceLibrary(songs);
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    var checks = 0;
    final result =
        await index.searchAll('song', audioLimit: 2, checkCancelled: () {
      if (++checks != 4) return;
      // Metadata synchronization mutates Audio, then awaits cover invalidation
      // before publishing its next search revision. The first batch has
      // already filled a worst-first heap at this point.
      songs.first.applyEditedMetadata(
        newPath: 'J:/synthetic/search/song zzzzz.mp3',
        newTitle: 'song zzzzz',
        newArtist: '',
        newAlbum: '',
        newModified: 2,
      );
    });
    expect(checks, greaterThanOrEqualTo(4));
    expect(result.audios, orderedEquals(songs.take(2)),
        reason: 'The current revision retains its original scoring/sort keys.');

    AudioLibrary.searchRevision++;
    final published = await index.searchAll('song', audioLimit: 2);
    expect(published.audios, orderedEquals(songs.skip(1).take(2)),
        reason:
            'Once published, the edited title participates in a fresh index.');
  });

  test('a revision change retries and publishes only the latest index',
      () async {
    replaceLibrary([for (var i = 0; i < 1000; i++) song('needle old $i', i)]);
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    final current = song('needle current', 1100);
    var checks = 0;
    var replaced = false;
    final result = await index.searchAll('needle', checkCancelled: () {
      if (++checks == 4 && !replaced) {
        replaced = true;
        replaceLibrary([current]);
      }
    });
    expect(replaced, isTrue);
    expect(result.audios, [same(current)]);
    expect(result.artists, isEmpty);
    expect(result.albums, isEmpty);
  });

  test('a broad warm query leaves repeated event-loop opportunities', () async {
    replaceLibrary([for (var i = 0; i < 12000; i++) song('song $i', i)]);
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    var completed = false;
    var eventTurns = 0;
    void heartbeat() {
      if (!completed) {
        eventTurns++;
        Timer.run(heartbeat);
      }
    }

    Timer.run(heartbeat);
    try {
      final result = await index.searchAll('song');
      expect(result.audios, hasLength(200));
      expect(eventTurns, greaterThan(3));
    } finally {
      completed = true;
    }
  });

  test('large artist and album collections build and return one revision',
      () async {
    replaceLibrary([]);
    final library = AudioLibrary.instance;
    for (var i = 1499; i >= 0; i--) {
      final name = 'group ${i.toString().padLeft(4, '0')}';
      library.artistCollection[name] = Artist(name: name);
      library.albumCollection[name] = Album(name: name);
    }
    final result =
        await AudioSearchIndex.instance.searchAll('group', nameLimit: 3);
    expect(result.artists.map((artist) => artist.name),
        ['group 0000', 'group 0001', 'group 0002']);
    expect(result.albums.map((album) => album.name),
        ['group 0000', 'group 0001', 'group 0002']);
    expect(result.audios, isEmpty);
  });

  test('search survives LRU capacity churn with shared pinyin and late titles',
      () async {
    final index = AudioSearchIndex.instance;
    final tracks = [
      for (var i = 0; i < index.debugSearchKeyCacheLimit + 128; i++)
        Audio(
            'Fixture ${i.toString().padLeft(5, '0')}',
            '阳光乐队',
            'Shared album',
            1,
            180,
            320,
            44100,
            'J:/synthetic/lru/${i.toString().padLeft(5, '0')}.flac',
            1,
            1,
            'test'),
      Audio('最后匹配', '阳光乐队', 'Shared album', 1, 180, 320, 44100,
          'J:/synthetic/lru/last.flac', 1, 1, 'test'),
    ];
    replaceLibrary(tracks);
    final late = await index.searchAll('zuihoupipei', audioLimit: 1);
    expect(late.audios, [same(tracks.last)]);
    final shared = await index.searchAll('yangguang', audioLimit: 4);
    expect(shared.audios, orderedEquals(tracks.take(4)));
    expect(index.debugCachedSearchKeyCount, 0,
        reason: 'Both the value map and recency nodes are build-only data.');

    // A newer revision must not retain a stale key or linked-list entry after
    // clearing the interning pool and rebuilding with a different title.
    final replacement = song('replacement', 123456);
    replaceLibrary([replacement]);
    expect((await index.searchAll('zuihoupipei')).audios, isEmpty);
    expect((await index.searchAll('replacement')).audios, [same(replacement)]);
    expect(index.debugCachedSearchKeyCount, 0);
  });
}
