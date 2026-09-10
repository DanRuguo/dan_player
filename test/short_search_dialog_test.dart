import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/online_metadata_lookup_dialog.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/component/song_comment_match_dialog.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/song_comments_fixtures.dart';

void main() {
  late BuildContext pageContext;
  final notice = find.byKey(const ValueKey('app-notice-bubble'));

  Future<void> mount(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AppPresentationHost(child: child!),
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 48, bottom: 12, right: 12),
          child: AppContentRegion(child: Builder(builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          })),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      expect(PlayService.isInitialized, isFalse);
    });
  }

  Finder viewportFor(String key) {
    final compact = find.byKey(const ValueKey('metadata-lookup-compact'));
    return key.startsWith('metadata-lookup-') && compact.evaluate().isNotEmpty
        ? compact
        : find.byKey(ValueKey(key));
  }

  Future<void> scrollTo(
      WidgetTester tester, String scrollKey, Finder item) async {
    await tester.scrollUntilVisible(item, 60,
        scrollable: find
            .descendant(
                of: viewportFor(scrollKey), matching: find.byType(Scrollable))
            .first,
        maxScrolls: 500);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tapInViewport(
      WidgetTester tester, String scrollKey, Finder item) async {
    final visible =
        tester.getRect(item).intersect(tester.getRect(viewportFor(scrollKey)));
    expect(visible.isEmpty, isFalse);
    await tester.tapAt(visible.center);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> checkNotice(WidgetTester tester, Finder action) async {
    showAppNotice('操作结果尚未保存，请核对后确认。');
    for (final elapsed in [0, 16, 48, 100]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(
          tester.getRect(action).bottom, lessThan(tester.getRect(notice).top));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('song picker scrolls all rows and retains selection at $scale',
        (tester) async {
      await mount(tester, scale);
      final audios = List.generate(18, (i) => CategoryTestAudio('候选歌曲$i'));
      final result = showPlaylistSongPicker(pageContext,
          library: audios, existingPaths: {}, replaceSelection: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last = find.byKey(ValueKey('playlist-pick-${audios.last.path}'));
      await scrollTo(tester, 'playlist-song-picker-scroll', last);
      await tapInViewport(tester, 'playlist-song-picker-scroll', last);
      final save = find.widgetWithText(FilledButton, '保存选择（1 首）');
      await checkNotice(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(await result, [audios.last]);
    });

    testWidgets('metadata lookup reaches candidates and options at $scale',
        (tester) async {
      await mount(tester, scale);
      final candidates =
          List.generate(18, (i) => commentAudio(id: '$i', title: '候选歌曲$i'));
      final result = showOnlineMetadataLookupDialog(pageContext,
          audio: CategoryTestAudio('本地歌曲'),
          search: (_) async => OnlineSearchResponse(
              tracks: candidates, failures: {'QQ音乐': 'QQ音乐暂时不可用'}));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last =
          find.byKey(ValueKey('metadata-candidate-${candidates.last.path}'));
      await scrollTo(tester, 'metadata-lookup-results', last);
      await tapInViewport(tester, 'metadata-lookup-results', last);
      final album = find.widgetWithText(FilterChip, '专辑');
      await scrollTo(tester, 'metadata-lookup-controls', album);
      await tapInViewport(tester, 'metadata-lookup-controls', album);
      final apply = find.widgetWithText(FilledButton, '填入编辑器');
      await checkNotice(tester, apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      final selection = await result;
      expect(selection?.title, candidates.last.title);
      expect(selection?.album, isNull);
    });

    testWidgets('comment matching scrolls results and preview at $scale',
        (tester) async {
      await mount(tester, scale);
      final candidates =
          List.generate(18, (i) => commentAudio(id: '$i', title: '评论候选$i'));
      final transport = FakeCommentsTransport((_) => neteaseComments(
          [neteaseComment(3, content: '一段较长的评论预览，需要在短窗口中保持可滚动阅读。')]));
      final result = showSongCommentMatchDialog(pageContext,
          localAudio: localCommentAudio(),
          search: (_) async => OnlineSearchResponse(
              tracks: candidates, failures: {'QQ音乐': '部分来源不可用'}),
          commentsService: SongCommentsService(transport: transport));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last =
          find.byKey(ValueKey('song-comment-match-${candidates.last.path}'));
      await scrollTo(tester, 'song-comment-match-scroll', last);
      await tapInViewport(tester, 'song-comment-match-scroll', last);
      await scrollTo(tester, 'song-comment-match-scroll',
          find.textContaining('一段较长的评论预览'));
      final confirm = find.byKey(const ValueKey('song-comment-match-confirm'));
      await checkNotice(tester, confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(await result, same(candidates.last));
      expect(transport.requests, hasLength(1));
    });

    testWidgets('lyric sources scroll notices, local row and results at $scale',
        (tester) async {
      await mount(tester, scale);
      final audio = CategoryTestAudio('本地歌词测试');
      final candidates = List.generate(
          18,
          (i) => SongSearchResult(
                ResultSource.qq,
                '歌词候选$i',
                '测试艺术家',
                '测试专辑',
                1,
                qqSongId: i + 1,
                qqSongMid: 'MID$i',
              ));
      showAppDialog<void>(
        context: pageContext,
        builder: (_) => LyricSourceDialog(
          audio: audio,
          currentTrackPath: () => audio.path,
          search: (_) async => LyricSearchResponse(
              candidates: candidates,
              failures: {ResultSource.netease: '部分来源暂时不可用，请稍后重试。'}),
          // Only descriptor display is tested: no load/save/apply or playback.
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last =
          find.byKey(ValueKey('lyric-candidate-${candidates.last.identity}'));
      await scrollTo(tester, 'lyric-source-scroll', last);
      expect(
          tester.getRect(last).overlaps(tester
              .getRect(find.byKey(const ValueKey('lyric-source-scroll')))),
          isTrue);
      final close = find.byKey(const ValueKey('lyric-source-close'));
      await checkNotice(tester, close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(LyricSourceDialog), findsNothing);
    });
  }

  testWidgets('closed metadata lookup does not start fallback searches',
      (tester) async {
    await mount(tester, 2);
    final pending = Completer<OnlineSearchResponse>();
    var calls = 0;
    final result = showOnlineMetadataLookupDialog(pageContext,
        audio: CategoryTestAudio('本地歌曲 -OP- short ver.'), search: (_) {
      calls++;
      return pending.future;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    pending.complete(const OnlineSearchResponse(tracks: [], failures: {}));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
