import 'dart:async';

import 'package:dan_player/component/song_comment_match_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'manual match shows metadata, one comment preview and exact result',
      (tester) async {
    final candidate = commentAudio(id: '321', title: '候选歌曲');
    Audio? selected;
    final transport =
        FakeCommentsTransport((_) => neteaseComments([neteaseComment(1)]));
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: FilledButton(
            onPressed: () async {
              selected = await showSongCommentMatchDialog(
                context,
                localAudio: localCommentAudio(),
                search: (_) async => OnlineSearchResponse(
                  tracks: [candidate],
                  failures: const {},
                ),
                commentsService: SongCommentsService(transport: transport),
              );
            },
            child: const Text('打开'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('候选歌曲'), findsOneWidget);
    expect(find.textContaining('候选演唱者'), findsNothing);
    expect(find.textContaining('测试艺术家'), findsOneWidget);
    expect(find.textContaining('作曲：平台未提供'), findsOneWidget);
    expect(transport.requests, isEmpty,
        reason: 'comment preview loads only for the selected candidate');
    await tester.tap(find.text('候选歌曲'));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.target.identity, 'netease:321');
    expect(find.textContaining('测试评论 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('song-comment-match-confirm')));
    await tester.pumpAndSettle();
    expect(selected, same(candidate));
  });

  testWidgets('new candidate cancels and ignores stale preview',
      (tester) async {
    final first = commentAudio(id: '1', title: '第一候选');
    final second = commentAudio(id: '2', title: '第二候选');
    final pending = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) async {
      if (request.target.songId == '1') return pending.future;
      return neteaseComments([neteaseComment(2)]);
    });
    await tester.pumpWidget(MaterialApp(
      home: SongCommentMatchDialog(
        localAudio: localCommentAudio(),
        search: (_) async => OnlineSearchResponse(
          tracks: [first, second],
          failures: const {},
        ),
        commentsService: SongCommentsService(transport: transport),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一候选'));
    await tester.pump();
    await tester.tap(find.text('第二候选'));
    await tester.pumpAndSettle();
    expect(transport.requests.first.cancellation.isCancelled, isTrue);
    expect(find.textContaining('测试评论 2'), findsOneWidget);
    pending.complete(neteaseComments([neteaseComment(1)]));
    await tester.pumpAndSettle();
    expect(find.textContaining('测试评论 1'), findsNothing);
    expect(find.textContaining('测试评论 2'), findsOneWidget);
  });

  testWidgets('partial provider failure keeps usable candidates visible',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SongCommentMatchDialog(
        localAudio: localCommentAudio(),
        search: (_) async => OnlineSearchResponse(
          tracks: [commentAudio(title: '仍可选择')],
          failures: const {'QQ音乐': 'QQ音乐暂时不可用'},
        ),
        commentsService: SongCommentsService(
          transport: FakeCommentsTransport((_) => neteaseComments([])),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('仍可选择'), findsOneWidget);
    expect(find.textContaining('QQ音乐暂时不可用'), findsOneWidget);
  });

  testWidgets(
      'candidates are shown by shared relevance instead of provider order',
      (tester) async {
    final unrelated = commentAudio(id: '8', title: '完全无关');
    final relevant = Audio.online(
      provider: 'netease',
      id: '9',
      title: '本地歌曲',
      artist: '本地艺术家',
      album: '本地专辑',
      duration: 180,
    );
    await tester.pumpWidget(MaterialApp(
      home: SongCommentMatchDialog(
        localAudio: localCommentAudio(),
        search: (_) async => OnlineSearchResponse(
          tracks: [unrelated, relevant],
          failures: const {},
        ),
        commentsService: SongCommentsService(
          transport: FakeCommentsTransport((_) => neteaseComments([])),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('本地歌曲')).dy,
      lessThan(tester.getTopLeft(find.text('完全无关')).dy),
    );
  });
}
