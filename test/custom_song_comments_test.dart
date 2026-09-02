import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom comment capability routes by stable provider identity',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late Uri requested;
    final subscription = server.listen((request) async {
      requested = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write('''
        {"comments":[{"id":"comment-1","author":"Listener",
        "content":"A useful comment","publishedAt":"2026-09-02T12:00:00Z",
        "likeCount":7}],"hasMore":false,"total":1}
      ''');
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'comments-source',
      name: 'Test comments',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {CustomMusicSourceCapability.comments},
      endpoints: const {CustomMusicSourceCapability.comments: '/comments'},
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final audio = Audio.online(
      provider: profile.providerId,
      id: 'track-42',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 60,
    );

    expect(SongCommentsService.unavailableReason(audio), isNull);
    final target = SongCommentsService.targetFor(audio)!;
    expect(target.sourceLabel, 'Test comments');
    final page = await SongCommentsService().loadPage(
      target: target,
      sort: SongCommentSort.hot,
    );

    expect(requested.path, '/comments');
    expect(requested.queryParameters['id'], 'track-42');
    expect(requested.queryParameters['sort'], 'hot');
    expect(page.comments.single.author, 'Listener');
    expect(page.comments.single.content, 'A useful comment');
    expect(page.comments.single.likeCount, 7);
    expect(page.reportedTotal, 1);

    AppSettings.instance.customMusicSources.value = [
      profile.copyWith(enabled: false),
    ];
    expect(SongCommentsService.canRead(audio), isFalse);
    expect(SongCommentsService.unavailableReason(audio), contains('停用'));
  });

  test('an equivalent profile replacement invalidates an in-flight response',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      if (!requested.isCompleted) requested.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"comments":[],"hasMore":false}');
      await request.response.close();
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'comments-race',
      name: 'Comments race',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {CustomMusicSourceCapability.comments},
      endpoints: const {CustomMusicSourceCapability.comments: '/comments'},
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final target = SongCommentsService.targetFor(Audio.online(
      provider: profile.providerId,
      id: 'safe-id',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 60,
    ))!;

    final pending = SongCommentsService().loadPage(
      target: target,
      sort: SongCommentSort.hot,
    );
    await requested.future;
    final equivalentReplacement = profile.copyWith();
    expect(equivalentReplacement, equals(profile));
    expect(equivalentReplacement, isNot(same(profile)));
    AppSettings.instance.customMusicSources.value = [equivalentReplacement];
    release.complete();

    await expectLater(
      pending,
      throwsA(isA<SongCommentsException>().having(
        (error) => error.kind,
        'kind',
        SongCommentsFailure.unavailable,
      )),
    );
  });
}
