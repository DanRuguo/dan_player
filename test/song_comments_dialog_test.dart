import 'dart:async';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';

import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

const _open = ValueKey('open-test-comments');
const _hot = ValueKey('song-comments-hot');
const _latest = ValueKey('song-comments-latest');
const _close = ValueKey('song-comments-close');
const _more = ValueKey('song-comments-load-more');
const _retry = ValueKey('song-comments-retry');

Widget _app(
  SongCommentsService service, {
  Audio? audio,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool highContrast = false,
  bool reduced = false,
  bool direct = false,
  bool windowsDensity = false,
}) =>
    MaterialApp(
      theme: ThemeData(
          useMaterial3: true,
          visualDensity:
              windowsDensity ? VisualDensity.compact : VisualDensity.standard,
          materialTapTargetSize: windowsDensity
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo, brightness: brightness)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              highContrast: highContrast,
              disableAnimations: reduced),
          child: child!),
      home: Scaffold(
          body: direct
              ? SongCommentsDialog(
                  key: const ValueKey('direct-dialog'),
                  audio: audio ?? commentAudio(),
                  service: service)
              : Builder(
                  builder: (context) => Center(
                          child: FilledButton(
                        key: _open,
                        onPressed: () => showSongCommentsDialog(
                            context, audio ?? commentAudio(),
                            service: service),
                        child: const Text('打开评论'),
                      )))),
    );

Future<void> _launch(
  WidgetTester tester,
  SongCommentsService service, {
  Audio? audio,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Size size = const Size(800, 700),
  bool highContrast = false,
  bool reduced = false,
  bool windowsDensity = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(_app(service,
      audio: audio,
      scale: scale,
      brightness: brightness,
      highContrast: highContrast,
      windowsDensity: windowsDensity,
      reduced: reduced));
  await tester.tap(find.byKey(_open));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _list() => find.byType(ListView);
Finder _scrollable() =>
    find.descendant(of: _list(), matching: find.byType(Scrollable)).first;

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 350,
      scrollable: _scrollable(), maxScrolls: 150);
  await tester.pump();
}

void main() {
  for (final supportsSorts in [false, true]) {
    testWidgets(
        'custom source discovers orders only after its default read ($supportsSorts)',
        (tester) async {
      final previous = AppSettings.instance.customMusicSources.value;
      addTearDown(
          () => AppSettings.instance.customMusicSources.value = previous);
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'comments-widget',
        name: 'Comment source',
        baseUrl: 'https://example.invalid',
        capabilities: const {CustomMusicSourceCapability.comments},
        endpoints: const {CustomMusicSourceCapability.comments: '/comments'},
      )!;
      AppSettings.instance.customMusicSources.value = [profile];
      final transport = FakeCommentsTransport((request) => {
            '_danPlayerCustomSource': true,
            'comments': [
              {
                'id': 'comment-1',
                'author': 'Listener',
                'content': 'Source comment'
              }
            ],
            'hasMore': false,
            if (supportsSorts && request.sort == SongCommentSort.standard)
              'supportedSorts': ['latest', 'invalid-feature'],
          });
      await _launch(tester, SongCommentsService(transport: transport),
          audio: commentAudio(provider: profile.providerId));
      expect(transport.requests.single.sort, SongCommentSort.standard);
      expect(find.byKey(_hot), findsNothing);
      expect(
          find.byKey(_latest), supportsSorts ? findsOneWidget : findsNothing);
      expect(find.text('Source comment'), findsOneWidget);
      if (supportsSorts) {
        await tester.tap(find.byKey(_latest));
        await tester.pumpAndSettle();
        expect(transport.requests.last.sort, SongCommentSort.latest);
        // A later page need not repeat capability metadata.
        expect(find.byKey(_latest), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Windows compact shrinkWrap still gives every comment action a 44px hitbox',
      (tester) async {
    var failed = true;
    final transport = FakeCommentsTransport((request) {
      if (failed) {
        throw const SongCommentsException(
            SongCommentsFailure.network, '测试网络失败');
      }
      return neteaseComments([neteaseComment(1)], more: true);
    });
    await _launch(tester, SongCommentsService(transport: transport),
        windowsDensity: true);
    for (final key in [_hot, _latest, _close, _retry]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(44), reason: '$key');
      expect(size.width, greaterThanOrEqualTo(44), reason: '$key');
    }
    failed = false;
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(_more));
    expect(tester.getSize(find.byKey(_more)).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opening is user initiated and initially requests only hot comments',
      (tester) async {
    final transport = FakeCommentsTransport(
        (request) => neteaseComments([neteaseComment(1)], sort: request.sort));
    final service = SongCommentsService(transport: transport);
    await tester.pumpWidget(_app(service));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.requests, isEmpty);
    await tester.tap(find.byKey(_open));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.sort, SongCommentSort.hot);
    expect(find.textContaining('来源：网易云音乐'), findsOneWidget);
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(SelectableText), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final local in [true, false]) {
    testWidgets(
        '${local ? 'local' : 'missing QQ numeric ID'} explains unavailable without requests',
        (tester) async {
      final transport =
          FakeCommentsTransport((_) => throw StateError('unexpected network'));
      await _launch(tester, SongCommentsService(transport: transport),
          audio: local
              ? localCommentAudio()
              : commentAudio(provider: 'qq', numericId: null));
      expect(transport.requests, isEmpty);
      expect(find.byKey(_hot), findsNothing);
      expect(find.byKey(_latest), findsNothing);
      expect(find.textContaining(local ? '本地歌曲尚未关联' : '缺少平台数字 ID'),
          findsOneWidget);
      if (local) {
        expect(find.byKey(const ValueKey('song-comments-choose-association')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('song-comments-follow-lyric')),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tabs load independently once and preserve each loaded tab',
      (tester) async {
    final transport = FakeCommentsTransport((request) => neteaseComments(
        [neteaseComment(request.sort == SongCommentSort.hot ? 1 : 2)],
        sort: request.sort));
    await _launch(tester, SongCommentsService(transport: transport));
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 2'), findsOneWidget);
    await tester.tap(find.byKey(_hot));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(transport.requests.map((request) => request.sort),
        [SongCommentSort.hot, SongCommentSort.latest]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs cancels pending request and rejects late results',
      (tester) async {
    final hot = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) {
      if (request.sort == SongCommentSort.hot) return hot.future;
      return neteaseComments([neteaseComment(2)], sort: request.sort);
    });
    await _launch(tester, SongCommentsService(transport: transport));
    expect(find.text('正在加载评论…'), findsOneWidget);
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(transport.requests.first.cancellation.isCancelled, isTrue);
    hot.complete(neteaseComments([neteaseComment(1)]));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 2'), findsOneWidget);
    expect(find.text('测试评论 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'same title with a new exact ID resets state and ignores the old future',
      (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) {
      if (request.target.songId == '123') return old.future;
      return neteaseComments([neteaseComment(456)], sort: request.sort);
    });
    final service = SongCommentsService(transport: transport);
    await tester.pumpWidget(
        _app(service, direct: true, audio: commentAudio(id: '123')));
    await tester.pump();
    await tester.pumpWidget(
        _app(service, direct: true, audio: commentAudio(id: '456')));
    await tester.pumpAndSettle();
    expect(transport.requests.first.cancellation.isCancelled, isTrue);
    old.complete(neteaseComments([neteaseComment(123)]));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 456'), findsOneWidget);
    expect(find.text('测试评论 123'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'close cancels immediately before route exit and cannot pop the underlying page',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((_) => pending.future);
    await _launch(tester, SongCommentsService(transport: transport));
    await tester.tap(find.byKey(_close));
    expect(transport.requests.single.cancellation.isCancelled, isTrue);
    pending.complete(neteaseComments([neteaseComment(1)]));
    await tester.pumpAndSettle();
    expect(find.byType(SongCommentsDialog), findsNothing);
    expect(find.byKey(_open), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape dismisses comments and cancels pending transport',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((_) => pending.future);
    await _launch(tester, SongCommentsService(transport: transport));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(transport.requests.single.cancellation.isCancelled, isTrue);
    pending.complete(neteaseComments([]));
    await tester.pumpAndSettle();
    expect(find.byType(SongCommentsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame repeated close callback cannot pop the page beneath',
      (tester) async {
    final transport = FakeCommentsTransport(
        (request) => neteaseComments([neteaseComment(1)], sort: request.sort));
    await _launch(tester, SongCommentsService(transport: transport));
    final close = tester.widget<IconButton>(find.byKey(_close)).onPressed!;
    close();
    close();
    await tester.pumpAndSettle();
    expect(find.byType(SongCommentsDialog), findsNothing);
    expect(find.byKey(_open), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty is explicit and is not confused with denial or network errors',
      (tester) async {
    final transport = FakeCommentsTransport((_) => neteaseComments([]));
    await _launch(tester, SongCommentsService(transport: transport));
    expect(find.text('平台暂未返回这首歌曲的评论。'), findsOneWidget);
    expect(find.byKey(_retry), findsNothing);
    expect(find.byKey(_more), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('initial error can be retried without treating failure as empty',
      (tester) async {
    var failed = true;
    final transport = FakeCommentsTransport((request) {
      if (failed) {
        throw const SongCommentsException(
            SongCommentsFailure.denied, '平台暂不允许匿名读取评论');
      }
      return neteaseComments([neteaseComment(1)], sort: request.sort);
    });
    await _launch(tester, SongCommentsService(transport: transport));
    expect(find.text('平台暂不允许匿名读取评论'), findsOneWidget);
    expect(find.text('平台暂未返回这首歌曲的评论。'), findsNothing);
    expect(tester.getSize(find.byKey(_retry)).height, greaterThanOrEqualTo(44));
    failed = false;
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();
    expect(transport.requests.map((request) => request.page), [0, 0]);
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(find.byKey(_retry), findsNothing);
  });

  testWidgets(
      'load more preserves existing text through errors and deduplicates retried page',
      (tester) async {
    var failed = true;
    final transport = FakeCommentsTransport((request) {
      if (request.page == 0) {
        return neteaseComments([neteaseComment(1)], more: true, total: 3);
      }
      if (failed) {
        throw const SongCommentsException(SongCommentsFailure.network, '暂时离线');
      }
      return neteaseComments([neteaseComment(1), neteaseComment(2)], total: 3);
    });
    await _launch(tester, SongCommentsService(transport: transport));
    await _show(tester, find.byKey(_more));
    await tester.tap(find.byKey(_more));
    await tester.pumpAndSettle();
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(find.text('暂时离线'), findsOneWidget);
    failed = false;
    await _show(tester, find.byKey(_retry));
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();
    await _show(tester, find.text('测试评论 2'));
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(find.text('测试评论 2'), findsOneWidget);
    expect(transport.requests.map((request) => request.page), [0, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'repeated page is stopped explicitly instead of an infinite more loop',
      (tester) async {
    final transport = FakeCommentsTransport(
        (_) => neteaseComments([neteaseComment(1)], more: true));
    await _launch(tester, SongCommentsService(transport: transport));
    await _show(tester, find.byKey(_more));
    await tester.tap(find.byKey(_more));
    await tester.pumpAndSettle();
    expect(find.text('平台返回了重复页面，已停止继续请求。'), findsOneWidget);
    expect(find.byKey(_more), findsNothing);
    expect(find.text('测试评论 1'), findsOneWidget);
    expect(transport.requests, hasLength(2));
  });

  testWidgets('list is virtualized and tab scroll offsets survive switching',
      (tester) async {
    final transport = FakeCommentsTransport((request) => neteaseComments(
        List.generate(
            20,
            (i) =>
                neteaseComment(i + 1, content: '评论 ${i + 1}\n${'更多文字 ' * 12}')),
        sort: request.sort));
    await _launch(tester, SongCommentsService(transport: transport));
    expect(find.byKey(const ValueKey('song-comment-20')), findsNothing);
    expect(find.byType(SelectableText).evaluate().length, lessThan(40));
    await tester.drag(_list(), const Offset(0, -350));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(_scrollable()).position.pixels;
    expect(offset, greaterThan(250));
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(_scrollable()).position.pixels, 0);
    await tester.drag(_list(), const Offset(0, -500));
    await tester.pumpAndSettle();
    final latestOffset =
        tester.state<ScrollableState>(_scrollable()).position.pixels;
    expect(latestOffset, greaterThan(offset));
    await tester.tap(find.byKey(_hot));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(_scrollable()).position.pixels,
        closeTo(offset, 1));
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(_scrollable()).position.pixels,
        closeTo(latestOffset, 1));
    expect(transport.requests, hasLength(2));
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(find.byType(SongCommentsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '320x280 at 200% ${brightness.name} keeps long text scrollable and touch controls usable',
        (tester) async {
      final content = '这是一条完整的长评论，用于检查文本选择与窄窗换行。' * 40;
      final row = neteaseComment(1, content: content)
        ..['beReplied'] = [
          {
            'content': '较长的引用回复文本。' * 20,
            'user': {'nickname': '回复者'}
          }
        ];
      final transport = FakeCommentsTransport(
          (request) => neteaseComments([row], sort: request.sort, more: true));
      await _launch(tester, SongCommentsService(transport: transport),
          size: const Size(320, 280),
          scale: 2,
          brightness: brightness,
          highContrast: true,
          reduced: true);
      expect(tester.takeException(), isNull);
      for (final key in [_hot, _latest, _close]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      await _show(tester, find.text(content));
      final selectable = tester.widget<SelectableText>(find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == content));
      expect(selectable.maxLines, isNull);
      expect(selectable.data, content);
      await _show(tester, find.byKey(_more));
      expect(tester.getRect(find.byKey(_more)).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(Dialog)).bottom + 1));
      expect(
          tester.getSize(find.byKey(_more)).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byType(SongCommentsDialog), findsNothing);
    });
  }

  testWidgets(
      'pending more ignores repeated button activation and starts one page only',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport((request) {
      if (request.page == 0) {
        return neteaseComments([neteaseComment(1)], more: true);
      }
      return pending.future;
    });
    await _launch(tester, SongCommentsService(transport: transport));
    await _show(tester, find.byKey(_more));
    final action = tester.widget<OutlinedButton>(find.byKey(_more)).onPressed!;
    action();
    action();
    await tester.pump();
    expect(transport.requests.map((request) => request.page), [0, 1]);
    pending.complete(neteaseComments([neteaseComment(2)]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
