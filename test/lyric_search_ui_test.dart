import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/search_page/lyric_search_results.dart';
import 'package:dan_player/search/lyric_search_index.dart';
import 'package:desktop_lyric/ui_language.dart' as locale;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _renderDirectory = String.fromEnvironment('DAN_PLAYER_UPDATE_RENDER_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final koreanFont =
        File('${Platform.environment['WINDIR']}\\Fonts\\malgun.ttf');
    if (await koreanFont.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(koreanFont
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes))))
          .load();
    }
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  late Directory directory;
  late LyricDocumentStore store;
  late LyricSearchIndex index;
  late Audio audio;
  setUp(() async {
    final base = await Directory(
            '${Platform.environment['DAN_PLAYER_DATA_DIR'] ?? '${Directory.current.path}/build/test-data'}/lyric-search-ui')
        .create(recursive: true);
    directory = await base.createTemp('isolated-');
    audio = Audio(
        '星光 · 沿着夜空寻找答案（虚构歌曲）',
        'QA Synthetic Artist',
        'QA Synthetic Album',
        0,
        180,
        null,
        null,
        '${directory.path}/fixture.wav',
        0,
        0,
        null);
    store = LyricDocumentStore(storageDirectory: directory);
    await store.select(
        audio,
        Lrc.fromLrcText(
            '[00:01.00]星光落在安静的夜里，沿着蜿蜒的小路寻找新的答案\n'
            '[00:08.00]星光引领我们前行，每一步都留下温柔的回响\n'
            '[00:16.00]当星光越过远方的山谷，我们仍然相信明天\n'
            '[00:24.00]星光与你相伴',
            LrcSource.local)!);
    index = LyricSearchIndex(
        documents: store, audios: () => [audio], libraryRevision: () => 0);
  });
  tearDown(() async {
    index.dispose();
    store.dispose();
    locale.uiLanguage.value = locale.UiLanguage.zh;
    await directory.delete(recursive: true);
  });

  Widget host(Widget body,
          {GlobalKey? capture,
          double scale = 1,
          Brightness brightness = Brightness.light}) =>
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff995741), brightness: brightness)),
          builder: (context, child) => RepaintBoundary(
              key: capture,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(scale)),
                  child: child!)),
          home: Scaffold(body: body));

  for (final scenario in [
    (
      name: 'lyric-search-wide',
      size: const Size(900, 800),
      scale: 1.0,
      brightness: Brightness.light,
      english: false
    ),
    (
      name: 'lyric-search-narrow-en',
      size: const Size(420, 780),
      scale: 1.8,
      brightness: Brightness.dark,
      english: true
    ),
    (
      name: 'lyric-search-narrow-ja',
      size: const Size(420, 780),
      scale: 1.6,
      brightness: Brightness.light,
      english: false
    ),
    (
      name: 'lyric-search-narrow-ko',
      size: const Size(420, 780),
      scale: 1.6,
      brightness: Brightness.dark,
      english: false
    ),
  ]) {
    testWidgets('production grouped lyrics and preview ${scenario.name}',
        (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      locale.uiLanguage.value =
          scenario.english ? locale.UiLanguage.en : locale.UiLanguage.zh;
      if (scenario.name.endsWith('-ja')) {
        locale.uiLanguage.value = locale.UiLanguage.ja;
      }
      if (scenario.name.endsWith('-ko')) {
        locale.uiLanguage.value = locale.UiLanguage.ko;
      }
      final capture = GlobalKey();
      var plays = 0;
      await tester.pumpWidget(host(
          LyricSearchResultsView(
              query: '星光',
              index: index,
              playLine: (song, line, valid) async {
                expect(valid(), isTrue);
                expect(song.positionFor(line), const Duration(seconds: 1));
                plays++;
                return true;
              }),
          capture: capture,
          scale: scenario.scale,
          brightness: scenario.brightness));
      await tester.runAsync(() => index.search('星光'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(audio.title), findsOneWidget);
      expect(find.text(locale.ui('从此句播放')), findsNWidgets(3));
      if (_renderDirectory.isNotEmpty) {
        await _capture(tester, capture, scenario.name);
      }
      await tester.tap(find.text(locale.ui('从此句播放')).first);
      await tester.pumpAndSettle();
      expect(plays, 1);
      final preview = find.text(locale.ui('预览歌词'));
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(find.byType(LyricSearchPreview), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (_renderDirectory.isNotEmpty) {
        await _capture(tester, capture, '${scenario.name}-preview');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
      'untimed preview has text and no play action; changed revisions refresh',
      (tester) async {
    await tester.runAsync(() =>
        store.select(audio, PlainLyric('Plain starlight\nSecond starlight')));
    await tester.pumpWidget(
        host(LyricSearchResultsView(query: 'starlight', index: index)));
    await tester.runAsync(() => index.search('starlight'));
    await tester.pumpAndSettle();
    expect(find.text(locale.ui('无时间歌词')), findsNWidgets(2));
    expect(find.text(locale.ui('从此句播放')), findsNothing);
    await tester.runAsync(() => store.setNoLyrics(audio, true));
    await tester.pumpAndSettle();
    expect(find.text(locale.ui('已索引歌词中没有匹配内容')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes =
          (await image.toByteData(format: drawing.ImageByteFormat.png))!;
      final file = File('$_renderDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}
