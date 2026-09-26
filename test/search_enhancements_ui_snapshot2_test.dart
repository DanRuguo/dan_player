import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';
import 'support/search_history_fixture.dart';

UnionSearchResult empty(String query) => UnionSearchResult(query)
  ..online = Future.value(const OnlineSearchResponse(tracks: [], failures: {}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.name} landing help spacing and trailing results help fit short enlarged windows',
        (tester) async {
      uiLanguage.value = language;
      tester.view.physicalSize = const Size(360, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = MemorySearchHistory();
      addTearDown(history.dispose);
      final boundary = GlobalKey();
      var calls = 0;
      const query = '(filesize:>=20MiB | rating:>=4) -filename:live';
      Future<void> mount(Widget page, {double scale = 2}) async {
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: language.locale,
              supportedLocales: [
                for (final item in UiLanguage.values) item.locale
              ],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: Entry(welcome: false).fromSchemeAndFontFamily(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness:
                          language == UiLanguage.zh || language == UiLanguage.ko
                              ? Brightness.dark
                              : Brightness.light)),
              builder: (context, child) => UiLanguageScope(
                  child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: true),
                      child: child!)),
              home: Scaffold(body: page),
            )));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      Future<void> capture(String stage) async {
        const output = String.fromEnvironment('DAN_SEARCH_ENHANCEMENTS_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file = File('$output/${language.name}-$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      void checkSpacing(bool result) {
        if (result) {
          expect(
              find.byKey(const ValueKey('result-help-spacing')), findsNothing);
          final rail = tester
              .getRect(find.byKey(const ValueKey('search-category-rail')));
          final help = tester
              .getRect(find.byKey(const ValueKey('result-local-search-help')));
          expect(help.center.dy, closeTo(rail.center.dy, 1));
          expect(rail.right - help.right, lessThanOrEqualTo(8));
          return;
        }
        final outer = tester.getRect(find.byKey(
            ValueKey(result ? 'result-help-spacing' : 'landing-help-spacing')));
        final inner = tester.getRect(find.byKey(ValueKey(
            result ? 'result-local-search-help' : 'local-search-help')));
        expect(inner.top - outer.top, 12);
        expect(outer.bottom - inner.bottom, 12);
      }

      await mount(SearchPage(
          history: history,
          search: (_, {onlineCancellation}) async {
            calls++;
            return empty(query);
          }));
      checkSpacing(false);
      await capture('landing-500-200');
      await tester.enterText(find.byType(TextField), 'bitrate:320 OR');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(ui('搜索分组无效。')), findsOneWidget);
      expect(calls, 0);
      expect(history.value, isEmpty);
      await tester
          .ensureVisible(find.byKey(const ValueKey('local-search-help')));
      await capture('invalid-group-500-200');
      await tester.tap(find.byKey(const ValueKey('local-search-help')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.text('track:1..3 bitrate:>=320 samplerate:>=48kHz'));
      await tester.pumpAndSettle();
      await capture('help-quality-500-200');
      await tester.ensureVisible(
          find.text('playcount:<5 completed:>=1 skipped:0 listened:>=30:00'));
      await tester.pumpAndSettle();
      await capture('help-history-500-200');
      await tester.tap(find.widgetWithText(TextButton, ui('关闭')));
      await tester.pumpAndSettle();
      await mount(SearchResultPage(
          searchResult: empty(query),
          history: history,
          search: (_, {onlineCancellation}) async {
            calls++;
            return empty(query);
          }));
      checkSpacing(true);
      await capture('results-500-200');
      tester.view.physicalSize = const Size(360, 240);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const ValueKey('result-local-search-help')));
      await tester.pumpAndSettle();
      checkSpacing(true);
      await capture('results-240-200');
      await tester.tap(find.byKey(const ValueKey('result-local-search-help')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSearchHelpDialog), findsOneWidget);
      await capture('help-240-200');
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, ui('关闭')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'visible personal and history filters refresh on their own publications and unsubscribe on dispose',
      (tester) async {
    final library = AudioLibrary.instance;
    final saved = List<Audio>.of(library.audioCollection);
    final audio = CategoryTestAudio('personal-history-target');
    library.audioCollection
      ..clear()
      ..add(audio);
    AudioLibrary.searchRevision++;
    addTearDown(() {
      library.audioCollection
        ..clear()
        ..addAll(saved);
      AudioLibrary.searchRevision++;
    });
    final statistics = PlaybackStatistics.inMemory();
    addTearDown(statistics.dispose);
    var personal = <String, PersonalTrack>{
      audio.stableTrackId: const PersonalTrack(rating: 2)
    };
    final result = empty('rating:>=4 OR playcount:>=1');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SearchResultPage(
                searchResult: result,
                history: MemorySearchHistory(),
                statistics: statistics,
                loadPersonal: () async => personal))));
    await tester.pumpAndSettle();
    expect(find.byType(AudioTile), findsNothing);
    personal = {audio.stableTrackId: const PersonalTrack(rating: 5)};
    PersonalLibrary.changes.value++;
    await tester.pumpAndSettle();
    expect(result.audios, [audio]);
    expect(find.byType(AudioTile), findsOneWidget);
    personal = {audio.stableTrackId: const PersonalTrack(rating: 2)};
    PersonalLibrary.changes.value++;
    await tester.pumpAndSettle();
    expect(find.byType(AudioTile), findsNothing);
    statistics.start(audio);
    await tester.pumpAndSettle();
    expect(result.audios, [audio]);
    await tester.pumpWidget(const SizedBox());
    statistics.pause();
    PersonalLibrary.changes.value++;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new grammar stays local and malformed field input never reaches providers or history',
      (tester) async {
    final actual = (await tester.runAsync(
        () => UnionSearchResult.search('filename:missing | bitrate:>320')))!;
    expect(actual.localOnly, isTrue);
    final online = (await tester.runAsync(() => actual.online))!;
    expect(online.tracks, isEmpty);
    final history = MemorySearchHistory();
    addTearDown(history.dispose);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SearchResultPage(
                searchResult: actual,
                history: history,
                search: (query, {onlineCancellation}) async {
                  calls++;
                  return empty(query);
                }))));
    await tester.pumpAndSettle();
    for (final query in [
      'filesize:-1',
      'added:2026-02-30',
      'has:channels',
      '(bitrate:320'
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(calls, 0, reason: query);
      expect(history.value, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
