import 'dart:async';
import 'dart:io';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/online/song_comments_cache.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-cache-refresh-');
  });
  tearDown(() => directory.delete(recursive: true));

  Lyric lyric(String text) =>
      Lrc.fromLrcText('[00:01.00]$text', LrcSource.web)!;
  SongCommentsTarget target() => SongCommentsService.targetFor(commentAudio())!;

  for (final localFirst in [true, false]) {
    test(
        'switching tracks during a saved lyric lookup starts no search '
        '($localFirst)', () async {
      final saved = Completer<Lyric?>();
      var current = true;
      var calls = 0;
      final resolving = resolveAutomaticLyricSources(
        localFirst: localFirst,
        local: () {
          calls++;
          return saved.future;
        },
        cachedOnline: () {
          calls++;
          return saved.future;
        },
        stillCurrent: () => current,
      );
      current = false;
      saved.complete(null);
      expect(await resolving, isNull);
      expect(calls, 1);
    });
  }

  test('saved lyrics remain readable while a manual refresh is pending',
      () async {
    final cache = OnlineLyricCache(directory: () async => directory);
    await cache.resolve('track', () async => lyric('saved'));
    final response = Completer<Lyric?>();
    final started = Completer<void>();
    final refresh = cache.resolve('track', () {
      started.complete();
      return response.future;
    }, refresh: true);
    await started.future;
    try {
      final saved =
          await cache.read('track').timeout(const Duration(seconds: 2));
      expect((saved!.lines.single as UnsyncLyricLine).content, 'saved');
    } finally {
      response.complete(lyric('new'));
      await refresh;
    }
    expect(
        ((await cache.read('track'))!.lines.single as UnsyncLyricLine).content,
        'new');
  });

  test('a cache-only lyric read never joins an initial network lookup',
      () async {
    final cache = OnlineLyricCache(directory: () async => directory);
    final response = Completer<Lyric?>();
    final started = Completer<void>();
    final lookup = cache.resolve('track', () {
      started.complete();
      return response.future;
    });
    await started.future;
    try {
      expect(await cache.read('track').timeout(const Duration(seconds: 2)),
          isNull);
    } finally {
      response.complete(lyric('online'));
      await lookup;
    }
  });

  test('legacy lyrics display immediately during a newer cache refresh',
      () async {
    final cache = OnlineLyricCache(directory: () async => directory);
    await cache.resolve('legacy', () async => lyric('legacy'));
    final response = Completer<Lyric?>();
    final refresh =
        cache.resolve('current', () => response.future, refresh: true);
    try {
      final saved = await cache
          .read('current', legacyIdentity: () => 'legacy')
          .timeout(const Duration(seconds: 2));
      expect((saved!.lines.single as UnsyncLyricLine).content, 'legacy');
    } finally {
      response.complete(lyric('new'));
      await refresh;
    }
    expect(
        ((await cache.read('current'))!.lines.single as UnsyncLyricLine)
            .content,
        'new');
  });

  test('a slower old comment refresh cannot overwrite the newest refresh',
      () async {
    final cache = SongCommentsCache(directory: () async => directory);
    final older = Completer<Map<String, dynamic>>();
    final newer = Completer<Map<String, dynamic>>();
    var calls = 0;
    final service = SongCommentsService(
        cache: cache,
        transport: FakeCommentsTransport(
            (_) => ++calls == 1 ? older.future : newer.future));
    final first = service.loadPage(
        target: target(), sort: SongCommentSort.hot, refresh: true);
    final second = service.loadPage(
        target: target(), sort: SongCommentSort.hot, refresh: true);
    newer.complete(neteaseComments([neteaseComment(2)]));
    await second;
    older.complete(neteaseComments([neteaseComment(1)]));
    await first;
    expect(
        (await cache.read(target(), SongCommentSort.hot, 0))!
            .comments
            .single
            .id,
        '2');
  });

  test('old pagination cannot repopulate pages removed by a refresh', () async {
    final cache = SongCommentsCache(directory: () async => directory);
    final olderPage = Completer<Map<String, dynamic>>();
    final pageStarted = Completer<void>();
    final service = SongCommentsService(
        cache: cache,
        transport: FakeCommentsTransport((request) {
          if (request.page == 1) {
            pageStarted.complete();
            return olderPage.future;
          }
          return neteaseComments([neteaseComment(20)], more: true);
        }));
    final old =
        service.loadPage(target: target(), sort: SongCommentSort.hot, page: 1);
    await pageStarted.future;
    await service.loadPage(
        target: target(), sort: SongCommentSort.hot, refresh: true);
    olderPage.complete(neteaseComments([neteaseComment(11)]));
    await old;
    expect(await cache.read(target(), SongCommentSort.hot, 1), isNull);
    expect(
        (await cache.read(target(), SongCommentSort.hot, 0))!
            .comments
            .single
            .id,
        '20');
  });

  test('cancelling during cache IO preserves the previous comments', () async {
    final blocked = Completer<void>();
    final release = Completer<Directory>();
    var block = false;
    final cache = SongCommentsCache(directory: () {
      if (!block) return Future.value(directory);
      if (!blocked.isCompleted) blocked.complete();
      return release.future;
    });
    var revision = 1;
    final service = SongCommentsService(
        cache: cache,
        transport: FakeCommentsTransport(
            (_) => neteaseComments([neteaseComment(revision)])));
    await service.loadPage(target: target(), sort: SongCommentSort.hot);
    block = true;
    revision = 2;
    final cancellation = SongCommentsCancellation();
    final refresh = service.loadPage(
        target: target(),
        sort: SongCommentSort.hot,
        refresh: true,
        cancellation: cancellation);
    final cancelled =
        expectLater(refresh, throwsA(isA<SongCommentsCancelled>()));
    await blocked.future;
    cancellation.cancel();
    block = false;
    release.complete(directory);
    await cancelled;
    expect(
        (await cache.read(target(), SongCommentSort.hot, 0))!
            .comments
            .single
            .id,
        '1');
    expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.tmp')),
        isEmpty);
  });
}
