import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/song_comments_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final comments = SongCommentAssociationStore.instance;
  final documents = LyricDocumentStore.instance;
  late Directory fixture;
  late Directory data;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent = await Directory(p.join(Directory.current.parent.path, 'tool',
            'qa-local', 'delivery-2606-oct4', 'lyrics', 'data'))
        .create(recursive: true);
    fixture = await parent.createTemp('comment-document-owner-');
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    data = await getAppDataDir();
    expect(p.isWithin(fixture.path, data.path), isTrue);
    comments.resetForTesting();
    LYRIC_SOURCES.clear();
    await comments.initialize(directory: data);
    await documents.load();
  });
  tearDownAll(() async {
    comments.resetForTesting();
    LYRIC_SOURCES.clear();
    messenger.setMockMethodCallHandler(channel, null);
    final resolved = await fixture.resolveSymbolicLinks();
    final parent = p.join(Directory.current.parent.path, 'tool', 'qa-local',
        'delivery-2606-oct4', 'lyrics', 'data');
    expect(p.isWithin(parent, resolved), isTrue);
    await Directory(resolved).delete(recursive: true);
  });
  Audio audio(String name) => Audio('Local song', 'Artist', 'Album', 0, 180,
      null, null, p.join(fixture.path, '$name-not-opened.mp3'), 0, 0, null);
  final lyric = Lrc.fromLrcText('[00:01.00]Saved lyric', LrcSource.web)!;

  test('follow comments uses the committed document instead of a legacy ID',
      () async {
    final track = audio('legacy');
    LYRIC_SOURCES[track.path] = LyricSource(LyricSourceType.qq, qqSongId: 111);
    await documents.select(track, lyric,
        source: LyricSource(LyricSourceType.netease, neteaseSongId: '222'));
    expect(comments.lyricIdentityFor(track)?.identity, 'netease:222');
    await comments.followLyric(track);
    expect(SongCommentsService.targetFor(track)?.identity, 'netease:222');
    await documents.select(track, lyric,
        source: LyricSource(LyricSourceType.qq, qqSongId: 333));
    expect(comments.identityFor(track)?.identity, 'qq:333');
    await documents.select(track, lyric,
        source: LyricSource(LyricSourceType.local));
    expect(comments.identityFor(track), isNull,
        reason: 'A selected local source cannot resurrect an old platform ID');
    expect(SongCommentsService.unavailableReason(track), contains('跟随联网歌词'));
    expect(LYRIC_SOURCES[track.path]?.qqSongId, 111,
        reason: 'Comments must not repair or rewrite the legacy lyric index');
    final saved = jsonDecode(
        await File(p.join(data.path, 'lyric_documents.json')).readAsString());
    expect(
        saved['documents'][track.stableTrackId]['source']['source'], 'local');
  });

  test(
      'fresh document can follow but an unknown source cannot guess legacy IDs',
      () async {
    final track = audio('fresh');
    await documents.select(track, lyric,
        source: LyricSource(LyricSourceType.netease, neteaseSongId: '444'));
    expect(comments.lyricIdentityFor(track)?.identity, 'netease:444');
    await comments.followLyric(track);
    expect(comments.identityFor(track)?.identity, 'netease:444');
    LYRIC_SOURCES[track.path] = LyricSource(LyricSourceType.qq, qqSongId: 555);
    await documents.select(track, lyric);
    expect(comments.identityFor(track), isNull,
        reason: 'An authored document without provenance cannot follow '
            'the previously configured platform song');
    expect(SongCommentsService.targetFor(track), isNull);
  });

  testWidgets('open follow-comments cancels the old committed document owner',
      (tester) async {
    final automatic = AppSettings.instance.automaticOnlineLyrics;
    final originalAutomatic = automatic.value;
    automatic.value = false;
    final track = audio('open-dialog');
    final pending = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) {
      if (request.target.identity == 'netease:611') return pending.future;
      return neteaseComments([neteaseComment(62)]);
    });
    try {
      await tester.runAsync(() async {
        await documents.select(track, lyric,
            source: LyricSource(LyricSourceType.netease, neteaseSongId: '611'));
        await comments.followLyric(track);
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SongCommentsDialog(
              audio: track, service: SongCommentsService(transport: transport)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(transport.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('song-comments-refresh')));
      await tester.pump();
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.target.identity, 'netease:611');

      await tester.runAsync(() => documents.select(track, lyric,
          source: LyricSource(LyricSourceType.netease, neteaseSongId: '622')));
      expect(transport.requests.single.cancellation.isCancelled, isTrue,
          reason: 'The dialog must revoke the old lyric document owner '
              'before its late reply can display or enter the cache');
      pending.complete(neteaseComments([neteaseComment(61)]));
      await tester.pumpAndSettle();
      expect(find.text('测试评论 61'), findsNothing);
      expect(transport.requests, hasLength(1),
          reason: 'A document notification is not explicit network consent');

      await tester.tap(find.byKey(const ValueKey('song-comments-refresh')));
      await tester.pumpAndSettle();
      expect(transport.requests, hasLength(2));
      expect(transport.requests.last.target.identity, 'netease:622');
      expect(find.text('测试评论 62'), findsOneWidget);
      await tester.runAsync(() => documents.setOffset(track, 100));
      await tester.pumpAndSettle();
      expect(transport.requests, hasLength(2),
          reason: 'Offset-only edits cannot discard or reload the same owner');
      expect(find.text('测试评论 62'), findsOneWidget);
      await tester.runAsync(() => documents.select(track, lyric));
      await tester.pumpAndSettle();
      expect(find.text('测试评论 62'), findsNothing,
          reason: 'A provenance-free version cannot keep the old comments');
      expect(find.byKey(const ValueKey('song-comments-refresh')), findsNothing);
      expect(transport.requests, hasLength(2));
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) {
        pending.complete(neteaseComments([neteaseComment(61)]));
      }
      await tester.pumpWidget(const SizedBox());
      automatic.value = originalAutomatic;
    }
  });
}
