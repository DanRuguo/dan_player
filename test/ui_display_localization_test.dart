import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/song_comment_match_dialog.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/page/now_playing_page/component/equalizer_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

class _EqualizerPlayback extends Fake implements PlaybackService {
  @override
  final eqEnabled = ValueNotifier(true);
  final gains = List<double>.filled(10, 1);
  var applications = 0;

  @override
  List<double> get eqGains => List.of(gains);

  @override
  void applyEqGains(List<double> values) {
    applications++;
    gains.setAll(0, values);
  }
}

Widget _host(Widget child, {double scale = 1}) => UiLanguageScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

Future<void> _language(WidgetTester tester, UiLanguage value) async {
  uiLanguage.value = value;
  await tester.pumpAndSettle();
}

Audio _local() => Audio('暂停', '保存', '取消', 0, 180, null, null,
    r'C:\isolated-ui-fixtures\not-real.mp3', 0, 0, null);

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
    testWidgets(
        'EQ labels change but preset IDs still work in ${language.code}',
        (tester) async {
      final playback = _EqualizerPlayback();
      addTearDown(playback.eqEnabled.dispose);
      await tester
          .pumpWidget(_host(EqualizerDialog(playbackService: playback)));
      final state = tester.state(find.byType(EqualizerDialog));
      await _language(tester, language);
      var dropdown = tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>));
      expect(dropdown.initialSelection, '自定义');
      final rock = dropdown.dropdownMenuEntries
          .singleWhere((entry) => entry.value == '摇滚');
      expect(rock.label, isNot('摇滚'));
      dropdown.onSelected!('摇滚');
      await tester.pumpAndSettle();
      expect(playback.gains, contains(11.2));
      expect(playback.applications, 1);
      await tester.tap(find.byTooltip(ui('重置为平坦')));
      await tester.pumpAndSettle();
      expect(playback.gains, everyElement(0));
      expect(playback.applications, 2);
      dropdown = tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>));
      expect(dropdown.initialSelection, '平坦');
      expect(tester.state(find.byType(EqualizerDialog)), same(state));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('EQ stays scrollable at 507x320 and 200% in all four languages',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = _EqualizerPlayback();
    addTearDown(playback.eqEnabled.dispose);
    await tester.pumpWidget(
        _host(EqualizerDialog(playbackService: playback), scale: 2));
    for (final language in UiLanguage.values) {
      await _language(tester, language);
      expect(find.text(ui('完成')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('search tabs localize without modifying query or search data',
      (tester) async {
    final result = UnionSearchResult('暂停 {1}')
      ..online =
          Future.value(const OnlineSearchResponse(tracks: [], failures: {}));
    final originalOnline = result.online;
    final originalAudios = result.audios;
    await tester.pumpWidget(_host(SearchResultPage(searchResult: result)));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(SearchResultPage));
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      await _language(tester, language);
      const categories = ['所有', '总乐库', '联网', '艺术家', '专辑', '歌词'];
      final tabBar = find.byType(TabBar);
      final tabLabels =
          find.descendant(of: tabBar, matching: find.byType(Text));
      // Both Tab.text and icon/label tabs render Text descendants. Verify what
      // the user reads instead of coupling this test to a Tab constructor.
      expect(tester.widgetList<Text>(tabLabels).map((text) => text.data),
          categories.map(ui));
      for (final source in categories) {
        await tester.ensureVisible(
            find.descendant(of: tabBar, matching: find.text(ui(source))));
        await tester.pumpAndSettle();
        expect(
            find
                .descendant(of: tabBar, matching: find.text(ui(source)))
                .hitTestable(),
            findsOneWidget);
        expect(find.descendant(of: tabBar, matching: find.text(source)),
            findsNothing);
      }
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '暂停 {1}');
      expect(result.query, '暂停 {1}');
      expect(result.online, same(originalOnline));
      expect(result.audios, same(originalAudios));
      expect(tester.state(find.byType(SearchResultPage)), same(state));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large multi-source online results build lazily', (tester) async {
    tester.view.physicalSize = const Size(900, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tracks = <Audio>[
      for (var index = 0; index < 500; index++)
        Audio.online(
          provider: 'custom:source-${index % 3}',
          id: 'track-$index',
          title: 'Track $index',
          artist: 'Artist',
          album: 'Album',
          duration: 120,
        ),
    ];
    final result = UnionSearchResult('many')
      ..online = Future.value(OnlineSearchResponse(
        tracks: tracks,
        failures: const {},
      ));

    await tester.pumpWidget(_host(SearchResultPage(searchResult: result)));
    await tester.pumpAndSettle();

    expect(find.byType(AudioTile), findsWidgets);
    expect(find.byType(AudioTile).evaluate().length, lessThan(100));
    final initialIndices = tester
        .widgetList<AudioTile>(find.byType(AudioTile))
        .map((tile) => tile.audioIndex)
        .toList();
    expect(initialIndices, contains(0));
    expect(find.byKey(ValueKey(tracks.last.path)), findsNothing);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.decoration!.hintText, ui('搜索本地曲库和联网音乐'));
    expect(input.controller!.text, 'many');

    await tester.drag(find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, -1600));
    await tester.pumpAndSettle();
    final laterTiles =
        tester.widgetList<AudioTile>(find.byType(AudioTile)).toList();
    expect(laterTiles, isNotEmpty);
    expect(laterTiles.length, lessThan(100));
    expect(
        laterTiles
            .map((tile) => tile.audioIndex)
            .reduce((a, b) => a > b ? a : b),
        greaterThan(initialIndices.reduce((a, b) => a > b ? a : b)));
    expect(
        laterTiles.every((tile) => identical(tile.playlist, tracks)), isTrue);
    expect(result.query, 'many');
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration notification does not replace visible search results',
      (tester) async {
    final result = UnionSearchResult('no structural change')
      ..online =
          Future.value(const OnlineSearchResponse(tracks: [], failures: {}));
    final originalAudios = result.audios;
    final originalArtists = result.artists;
    final originalAlbums = result.album;
    await tester.pumpWidget(_host(SearchResultPage(searchResult: result)));
    await tester.pumpAndSettle();

    AudioLibrary.instance.publishDurationChanges();
    await tester.pumpAndSettle();

    expect(result.audios, same(originalAudios));
    expect(result.artists, same(originalArtists));
    expect(result.album, same(originalAlbums));
    expect(tester.takeException(), isNull);
  });

  testWidgets('comment sort and count suffix update without refetching media',
      (tester) async {
    final transport = FakeCommentsTransport((request) =>
        neteaseComments([neteaseComment(1, content: '暂停 {0}')], total: 123));
    final audio = commentAudio(title: '保存');
    await tester.pumpWidget(_host(SongCommentsDialog(
        audio: audio, service: SongCommentsService(transport: transport))));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(SongCommentsDialog));
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      await _language(tester, language);
      expect(find.text(ui('热门')), findsOneWidget);
      expect(find.text('热门'), findsNothing);
      expect(
          find.text(ui('已显示 {0} 条{1}', [
            1,
            ui(' · 平台统计 {0} 条', [123]),
          ])),
          findsOneWidget);
      expect(find.textContaining('平台统计'), findsNothing);
      expect(find.text('暂停 {0}'), findsOneWidget);
      expect(find.text('保存 · 测试艺术家'), findsOneWidget);
      expect(audio.title, '保存');
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.sort, SongCommentSort.hot);
      expect(tester.state(find.byType(SongCommentsDialog)), same(state));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cached comment failure follows language without another request',
      (tester) async {
    final transport = FakeCommentsTransport((_) {
      throw const SongCommentsException(
          SongCommentsFailure.timeout, '评论请求超时，请检查网络后重试。');
    });
    await tester.pumpWidget(_host(SongCommentsDialog(
        audio: commentAudio(),
        service: SongCommentsService(transport: transport))));
    await tester.pumpAndSettle();
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      await _language(tester, language);
      expect(find.text(ui('评论请求超时，请检查网络后重试。')), findsOneWidget);
      expect(find.text('评论请求超时，请检查网络后重试。'), findsNothing);
      expect(transport.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'cached lyric candidate failure localizes without rerunning lookup',
      (tester) async {
    final audio = _local();
    final candidate = SongSearchResult(ResultSource.qq, '暂停', '保存', '取消', 1,
        qqSongId: 123, qqSongMid: 'MID123');
    var searches = 0;
    var reads = 0;
    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async {
        searches++;
        return LyricSearchResponse(candidates: [candidate], failures: const {});
      },
      loadCandidate: (_) async {
        reads++;
        return null;
      },
    )));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('lyric-candidate-${candidate.identity}')));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(LyricSourceDialog));
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      await _language(tester, language);
      expect(find.text(ui('{0}未返回可用歌词，可选择其他候选或重试。', [ui('QQ音乐')])),
          findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('保存 · 取消'), findsOneWidget);
      expect(searches, 1);
      expect(reads, 1);
      expect(tester.state(find.byType(LyricSourceDialog)), same(state));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('matching candidate translates missing credit, never actual tags',
      (tester) async {
    final audio = Audio.online(
        provider: 'netease',
        id: '99',
        title: '播放',
        artist: '暂停',
        album: '取消',
        duration: 120);
    var searches = 0;
    await tester.pumpWidget(_host(SongCommentMatchDialog(
      localAudio: _local(),
      search: (_) async {
        searches++;
        return OnlineSearchResponse(tracks: [audio], failures: const {});
      },
    )));
    await tester.pumpAndSettle();
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      await _language(tester, language);
      expect(
          find.text(ui('{0}\n专辑：{1} · 作曲：{2} · {3}', [
            '暂停',
            '取消',
            ui('平台未提供'),
            ui('网易云音乐'),
          ])),
          findsOneWidget);
      expect(audio.title, '播放');
      expect(audio.composer, isNull);
      expect(searches, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'compact empty artist localizes but identical user artist stays raw',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
      width: 560,
      height: 250,
      child: CompactPlayerView(),
    )));
    await _language(tester, UiLanguage.en);
    expect(find.text('No track selected'), findsOneWidget);
    await tester.pumpWidget(_host(const SizedBox(
      width: 560,
      height: 250,
      child: CompactPlayerView(title: '播放', artist: '尚未选择歌曲'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('尚未选择歌曲'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
