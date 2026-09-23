import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/online/song_comments_cache.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

const _refresh = ValueKey('song-comments-refresh');
const _motion = ValueKey('song-comments-refresh-motion');

class _Cache extends SongCommentsCache {
  _Cache({this.page})
      : super(
            directory: () async => throw StateError('No disk in widget test'));
  SongCommentsPage? page;

  @override
  Future<SongCommentsPage?> read(
          SongCommentsTarget target, SongCommentSort sort, int page) async =>
      sort == SongCommentSort.hot ? this.page : null;

  @override
  Future<void> write(
      SongCommentsTarget target, SongCommentSort sort, SongCommentsPage result,
      {bool replaceSort = false, bool Function()? stillCurrent}) async {
    if (stillCurrent?.call() == false) return;
    if (sort == SongCommentSort.hot) page = result;
  }
}

SongCommentsPage _saved() => SongCommentsPage(
      comments: const [
        SongComment(id: 'saved', author: 'Author', content: 'Saved comment')
      ],
      hasMore: false,
      page: 0,
    );

Widget _app(SongCommentsService service,
        {String id = '123', bool reduced = false, bool visible = true}) =>
    MaterialApp(
      builder: (context, child) => AppPresentationHost(child: child!),
      home: MotionPreferencesScope(
        preferences:
            MotionPreferences(disabled: reduced ? {MotionKind.feedback} : {}),
        child: Scaffold(
          body: TickerMode(
            enabled: visible,
            child: SongCommentsDialog(
                audio: commentAudio(id: id), service: service),
          ),
        ),
      ),
    );

Animation<double> _turns(WidgetTester tester) =>
    tester.widget<RotationTransition>(find.byKey(_motion)).turns;

void main() {
  testWidgets(
      'opening, rebuilding, and changing track read only local comments',
      (tester) async {
    final transport =
        FakeCommentsTransport((_) => throw StateError('Unexpected network'));
    final service = SongCommentsService(transport: transport, cache: _Cache());
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text('暂无本地评论，请点击右上角更新。'), findsOneWidget);
    await tester.pumpWidget(_app(service, reduced: true));
    await tester.pumpWidget(_app(service, id: '456'));
    await tester.pumpAndSettle();
    expect(transport.requests, isEmpty);
    expect(find.text('平台暂未返回这首歌曲的评论。'), findsNothing);
  });

  testWidgets(
      'manual refresh rotates only its glyph and reports successful completion',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((_) => response.future);
    final cache = _Cache(page: _saved());
    final service = SongCommentsService(transport: transport, cache: cache);
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(transport.requests, isEmpty);
    await tester.tap(find.byKey(_refresh));
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(_refresh)).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(_refresh)).tooltip, '正在更新评论…');
    final before = _turns(tester).value;
    await tester.pump(const Duration(milliseconds: 225));
    expect(_turns(tester).value, isNot(before));
    expect(find.text('Saved comment'), findsOneWidget);
    expect(find.text('评论已更新'), findsNothing);
    response.complete(neteaseComments([neteaseComment(7)]));
    await tester.pumpAndSettle();
    expect(find.text('评论已更新'), findsOneWidget);
    expect(find.text('测试评论 7'), findsOneWidget);
    expect(find.text('Saved comment'), findsNothing);
    expect(_turns(tester).value, 0);
    expect(cache.page!.comments.single.id, '7');
  });

  testWidgets(
      'failed manual refresh stops motion and retains saved comments without success notice',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((_) => response.future);
    await tester.pumpWidget(_app(SongCommentsService(
        transport: transport, cache: _Cache(page: _saved()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_refresh));
    await tester.pump(const Duration(milliseconds: 200));
    response.completeError(const SongCommentsException(
        SongCommentsFailure.network, '评论服务暂时不可用，请稍后重试。'));
    await tester.pumpAndSettle();
    expect(find.text('Saved comment'), findsOneWidget);
    expect(find.text('评论已更新'), findsNothing);
    expect(find.text('评论服务暂时不可用，请稍后重试。'), findsOneWidget);
    expect(find.text('评论更新失败'), findsOneWidget);
    expect(_turns(tester).value, 0);
    expect(
        tester.widget<IconButton>(find.byKey(_refresh)).onPressed, isNotNull);
  });

  testWidgets(
      'manual category switch cancels refresh and suppresses its late completion notice',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) {
      if (request.sort == SongCommentSort.hot) return response.future;
      return neteaseComments([neteaseComment(8)], sort: request.sort);
    });
    final cache = _Cache(page: _saved());
    await tester.pumpWidget(
        _app(SongCommentsService(transport: transport, cache: cache)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_refresh));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('song-comments-latest')));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(2));
    expect(transport.requests.first.cancellation.isCancelled, isTrue);
    response.complete(neteaseComments([neteaseComment(9)]));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 8'), findsOneWidget);
    expect(find.text('评论已更新'), findsNothing);
    expect(cache.page!.comments.single.id, 'saved');
  });

  testWidgets(
      'reduced feedback motion stays static and resumes only while visible',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final service = SongCommentsService(
        transport: FakeCommentsTransport((_) => response.future));
    await tester.pumpWidget(_app(service, reduced: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_turns(tester).value, 0);
    expect(tester.widget<IconButton>(find.byKey(_refresh)).tooltip, '正在更新评论…');
    await tester.pumpWidget(_app(service, visible: false));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_turns(tester).value, 0);
    await tester.pumpWidget(_app(service));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_turns(tester).value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    response.complete(neteaseComments([]));
    await tester.pumpAndSettle();
    expect(find.text('评论已更新'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('new comment feedback messages have all four UI languages', () {
    for (final source in ['评论已更新', '评论更新失败', '正在更新评论…', '暂无本地评论，请点击右上角更新。']) {
      for (final language in UiLanguage.values) {
        final translated = translateUi(source, language);
        expect(translated, isNotEmpty);
        if (language != UiLanguage.zh) expect(translated, isNot(source));
      }
    }
  });
}
