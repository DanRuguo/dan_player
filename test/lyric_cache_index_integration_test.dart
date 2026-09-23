import 'dart:async';
import 'dart:io';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/cached_lyric.dart';
import 'package:dan_player/lyric/lyric_cache_batch.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/search/lyric_search_index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late OnlineLyricCache cache;
  late LyricDocumentStore documents;
  late LyricSearchIndex index;
  late List<Audio> audios;
  late ValueNotifier<int> library;
  var reads = 0;
  Lrc lyric(String text) => Lrc.fromLrcText('[00:02.00]$text', LrcSource.web)!;
  LyricSearchIndex newIndex() => LyricSearchIndex(
      documents: documents,
      cache: cache,
      audios: () => audios,
      libraryRevision: () => library.value,
      libraryChanges: library);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lyric-cache-index-');
    reads = 0;
    cache = OnlineLyricCache(directory: () async {
      reads++;
      return Directory('${directory.path}/cache');
    });
    documents = LyricDocumentStore(
        storageDirectory: Directory('${directory.path}/docs'));
    await documents.load();
    audios = [
      for (var i = 0; i < 3; i++)
        Audio('Song $i', 'Artist', 'Album', 0, 120, null, null,
            '${directory.path}/$i.mp3', 0, 0, null,
            stableTrackId: 'cache-index-$i')
    ];
    library = ValueNotifier(0);
    index = newIndex();
  });
  tearDown(() async {
    index.dispose();
    documents.dispose();
    library.dispose();
    cache.changes.dispose();
    await directory.delete(recursive: true);
  });

  test(
      'previous batch cache is indexed on first search and after restart without fetching',
      () async {
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('红石音乐'));
    final result = await index.search('红石');
    expect(result.indexedSongs, 1);
    expect(result.hits.single.song.audio, audios[0]);
    expect(result.hits.single.song.source, '缓存');
    final before = reads;
    await index.search('音乐');
    expect(reads, before, reason: 'unchanged queries do not rescan files');
    index.dispose();
    index = newIndex();
    expect((await index.search('红石')).hits, hasLength(1));
  });

  test(
      'committed batch results update open index and local skipped lyrics persist',
      () async {
    await index.search('needle');
    var notices = 0;
    index.addListener(() => notices++);
    final batch = LyricCacheBatch(
        cache: cache,
        documents: documents,
        searchIndex: index,
        scan: (_, __) async => audios.take(2).toList(),
        readLocal: (audio) async =>
            audio == audios[0] ? lyric('local needle') : null,
        lookup: (_, __) async => lyric('cached needle'));
    await batch.start(directory.path);
    expect(batch.saved, 1);
    expect(batch.skipped, 1);
    expect(notices, greaterThan(0));
    expect((await index.search('needle')).indexedSongs, 2);
    batch.dispose();
    index.dispose();
    index = newIndex();
    expect((await index.search('needle')).hits, hasLength(2));
  });

  test('only changed track reloads and user edits/no-lyrics supersede cache',
      () async {
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('old'));
    final old = (await index.search('old')).hits.single.song;
    final before = reads;
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('new'),
        refresh: true);
    expect(index.isCurrent(old), isFalse);
    expect((await index.search('new')).hits, hasLength(1));
    expect(reads - before, lessThan(8));
    await documents.select(audios[0], lyric('manual'));
    expect((await index.search('new')).hits, isEmpty);
    expect((await index.search('manual')).hits, hasLength(1));
    await documents.setNoLyrics(audios[0], true);
    expect((await index.search('manual')).indexedSongs, 0);
  });

  test(
      'source-specific and local snapshots share storage without overwriting defaults',
      () async {
    final source = LyricSource(LyricSourceType.qq, qqSongId: 123);
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('default'));
    await cache.resolve(onlineLyricCacheIdentity(audios[0], source: source),
        () async => lyric('chosen'));
    await cacheLocalLyric(audios[0], lyric('local'), cache: cache);
    expect(
        (await readAvailableCachedLyric(audios[0], cache: cache))!
            .lines
            .first
            .toString(),
        contains('local'));
    expect(
        (await readAvailableCachedLyric(audios[0],
                cache: cache, source: source))!
            .lines
            .first
            .toString(),
        contains('chosen'));
    expect(
        (await readCachedOnlineLyric(audios[0], cache: cache))!
            .lines
            .first
            .toString(),
        contains('default'));
  });

  test(
      'batch cancellation and mid-request user source changes never commit stale lyrics',
      () async {
    for (final cancel in [true, false]) {
      final pending = Completer<Lrc?>();
      final entered = Completer<void>();
      final batch = LyricCacheBatch(
          cache: cache,
          documents: documents,
          scan: (_, __) async => [audios[1]],
          hasSaved: (_) async => false,
          lookup: (_, __) {
            entered.complete();
            return pending.future;
          });
      final job = batch.start(directory.path);
      await entered.future;
      if (cancel) {
        batch.cancel();
      } else {
        await documents.setOffset(audios[1], 500);
      }
      pending.complete(lyric('stale'));
      await job;
      expect(await cache.read(onlineLyricCacheIdentity(audios[1])), isNull);
      expect(batch.saved, 0);
      batch.dispose();
    }
  });

  test('cache commit guard checks again after writing temporary file',
      () async {
    var checks = 0;
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('cancelled'),
        shouldStore: () => ++checks == 1);
    expect(await cache.read(onlineLyricCacheIdentity(audios[0])), isNull);
    expect(await Directory('${directory.path}/cache').list().toList(), isEmpty);
  });

  test('library removal during cache read cannot resurrect removed songs',
      () async {
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('removed'));
    await index.search('removed');
    audios.removeAt(0);
    library.value++;
    expect((await index.search('removed')).hits, isEmpty);
  });

  test('timestamp-only results are not cached and matching falls through',
      () async {
    final blank = PlainLyric('   ');
    expect(
        await cache.resolve(
            onlineLyricCacheIdentity(audios[0]), () async => blank),
        isNull);
    final first = SongSearchResult(
        ResultSource.qq, 'Song', 'Artist', 'Album', .9,
        qqSongId: 1);
    final next = SongSearchResult(
        ResultSource.qq, 'Song', 'Artist', 'Album', .8,
        qqSongId: 2);
    final selected = await getMostMatchedLyric(audios[0],
        candidateSearch: (_) async =>
            LyricSearchResponse(candidates: [first, next], failures: {}),
        candidateLyricLoader: (candidate) async =>
            candidate == first ? blank : lyric('valid'));
    expect(selected!.lines.first.toString(), contains('valid'));
  });

  test(
      'local cache publication does not invalidate an active search play-and-seek',
      () async {
    index.rememberLoadedLocal(audios[0], lyric('local'));
    final hit = (await index.search('local')).hits.single.song;
    var notifications = 0;
    index.addListener(() => notifications++);
    await cacheLocalLyric(audios[0], lyric('local'), cache: cache);
    expect(index.isCurrent(hit), isTrue);
    expect(notifications, 0);
    var commits = 0;
    cache.changes.addListener(() => commits++);
    await cacheLocalLyric(audios[0], lyric('local'), cache: cache);
    expect(commits, 0, reason: 'identical local snapshots are not rewritten');
  });

  test(
      'batch skips a cache hit before reading media and reads a missing track only once',
      () async {
    await cache.resolve(
        onlineLyricCacheIdentity(audios[0]), () async => lyric('existing'));
    final localReads = <Audio>[];
    final batch = LyricCacheBatch(
        cache: cache,
        documents: documents,
        scan: (_, __) async => audios.take(2).toList(),
        readLocal: (audio) async {
          localReads.add(audio);
          return null;
        },
        lookup: (_, __) async => lyric('fetched'));
    await batch.start(directory.path);
    expect(localReads, [audios[1]]);
    expect(batch.saved, 1);
    expect(batch.skipped, 1);
    batch.dispose();
  });

  test('saved online library tracks join the same offline lyric index',
      () async {
    final track = Audio.online(
        provider: 'qq',
        id: 'fixture-online',
        title: 'Online',
        artist: 'Artist',
        album: 'Album',
        duration: 120);
    audios.add(track);
    library.value++;
    await cache.resolve(
        onlineLyricCacheIdentity(track), () async => lyric('online cached'));
    expect((await index.search('online cached')).hits.single.song.audio, track);
  });

  for (final text in ['中文歌词', 'ENGLISH Lyrics', '日本語の歌詞', '한국어 가사']) {
    test('cached lyric search supports $text', () async {
      await cache.resolve(
          onlineLyricCacheIdentity(audios[0]), () async => lyric(text));
      expect((await index.search(text.toLowerCase())).hits, hasLength(1));
    });
  }
}
