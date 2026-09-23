import 'dart:io';

import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/online/song_comments_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SongCommentsCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-comments-cache-');
    cache = SongCommentsCache(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  SongCommentsTarget target(String id) =>
      SongCommentsService.targetFor(commentAudio(id: id))!;

  test('reopening a source and sort reads all visited pages offline', () async {
    final transport = FakeCommentsTransport((request) => neteaseComments(
          [neteaseComment(request.page + 1)],
          sort: request.sort,
          more: request.page == 0,
        ));
    final service = SongCommentsService(transport: transport, cache: cache);
    for (final page in [0, 1]) {
      await service.loadPage(
          target: target('123'), sort: SongCommentSort.hot, page: page);
    }
    expect(transport.requests, hasLength(2));
    final offline = SongCommentsService(
        transport: FakeCommentsTransport((_) => throw StateError('offline')),
        cache: SongCommentsCache(directory: () async => directory));
    for (final page in [0, 1]) {
      final loaded = await offline.loadPage(
          target: target('123'), sort: SongCommentSort.hot, page: page);
      expect(loaded.comments.single.content, '测试评论 ${page + 1}');
      expect(loaded.hasMore, page == 0);
    }
    expect(await cache.read(target('124'), SongCommentSort.hot, 0), isNull);
    expect(await cache.read(target('123'), SongCommentSort.latest, 0), isNull);
  });

  test('explicit refresh updates first page and removes stale later pages',
      () async {
    var revision = 1;
    final transport = FakeCommentsTransport((request) => neteaseComments(
          [neteaseComment(revision * 10 + request.page)],
          sort: request.sort,
          more: true,
        ));
    final service = SongCommentsService(transport: transport, cache: cache);
    await service.loadPage(
        target: target('123'), sort: SongCommentSort.hot, page: 0);
    await service.loadPage(
        target: target('123'), sort: SongCommentSort.hot, page: 1);
    revision = 2;
    final updated = await service.loadPage(
      target: target('123'),
      sort: SongCommentSort.hot,
      refresh: true,
    );
    expect(updated.comments.single.id, '20');
    expect(
        (await cache.read(target('123'), SongCommentSort.hot, 0))!
            .comments
            .single
            .id,
        '20');
    expect(await cache.read(target('123'), SongCommentSort.hot, 1), isNull);
  });

  test('failed refresh retains the last usable snapshot', () async {
    var offline = false;
    final transport = FakeCommentsTransport((_) {
      if (offline) throw const SocketException('offline');
      return neteaseComments([neteaseComment(1)]);
    });
    final service = SongCommentsService(transport: transport, cache: cache);
    await service.loadPage(target: target('123'), sort: SongCommentSort.hot);
    offline = true;
    await expectLater(
      service.loadPage(
          target: target('123'), sort: SongCommentSort.hot, refresh: true),
      throwsA(isA<SongCommentsException>()),
    );
    final cached = await service.loadPage(
        target: target('123'), sort: SongCommentSort.hot);
    expect(cached.comments.single.id, '1');
    expect(transport.requests, hasLength(2));
  });

  test('corrupt snapshot is discarded and refetched for the exact ID',
      () async {
    final transport =
        FakeCommentsTransport((_) => neteaseComments([neteaseComment(3)]));
    final service = SongCommentsService(transport: transport, cache: cache);
    await service.loadPage(target: target('123'), sort: SongCommentSort.hot);
    final file = directory.listSync(recursive: true).whereType<File>().single;
    await file.writeAsString('{broken');
    final result = await service.loadPage(
        target: target('123'), sort: SongCommentSort.hot);
    expect(result.comments.single.id, '3');
    expect(transport.requests, hasLength(2));
  });

  test('switching exact platform song IDs never reuses another song cache',
      () async {
    final transport = FakeCommentsTransport((request) => neteaseComments(
        [neteaseComment(int.parse(request.target.songId))],
        sort: request.sort));
    final service = SongCommentsService(transport: transport, cache: cache);
    for (final id in ['123', '124', '123']) {
      final result =
          await service.loadPage(target: target(id), sort: SongCommentSort.hot);
      expect(result.comments.single.id, id);
    }
    expect(transport.requests.map((request) => request.target.songId),
        ['123', '124']);
  });

  test('many pages honor the byte cap without scanning on every write',
      () async {
    final transport = FakeCommentsTransport((request) => neteaseComments(
        [neteaseComment(request.page + 1)],
        sort: request.sort, more: true));
    await SongCommentsService(transport: transport, cache: cache)
        .loadPage(target: target('123'), sort: SongCommentSort.hot, page: 0);
    final firstSize = directory
        .listSync(recursive: true)
        .whereType<File>()
        .single
        .lengthSync();
    final cap = firstSize * 2 + 8;
    cache = SongCommentsCache(
        directory: () async => directory, totalBytesLimit: cap);
    final service = SongCommentsService(transport: transport, cache: cache);
    for (final page in [1, 2, 3]) {
      await service.loadPage(
          target: target('123'), sort: SongCommentSort.hot, page: page);
    }
    final files =
        directory.listSync(recursive: true).whereType<File>().toList();
    expect(files.fold<int>(0, (sum, file) => sum + file.lengthSync()),
        lessThanOrEqualTo(cap));
    expect(await cache.read(target('123'), SongCommentSort.hot, 3), isNotNull);
  });

  test('concurrent same-page refreshes leave one complete snapshot', () async {
    final transport =
        FakeCommentsTransport((_) => neteaseComments([neteaseComment(7)]));
    final service = SongCommentsService(transport: transport, cache: cache);
    await Future.wait([
      for (var i = 0; i < 12; i++)
        service.loadPage(
            target: target('123'), sort: SongCommentSort.hot, refresh: true)
    ]);
    expect(
        (await cache.read(target('123'), SongCommentSort.hot, 0))!
            .comments
            .single
            .id,
        '7');
    expect(directory.listSync(recursive: true).whereType<File>().length, 1);
  });
}
