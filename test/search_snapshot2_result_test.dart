import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/library_search_field.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';
import 'support/search_history_fixture.dart';

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
    final file = File('C:/Windows/Fonts/malgun.ttf');
    if (await file.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  UnionSearchResult empty(String query) => UnionSearchResult(query)
    ..online =
        Future.value(const OnlineSearchResponse(tracks: [], failures: {}));

  testWidgets(
      'result validation preserves history and avoids invoking providers',
      (tester) async {
    final history = MemorySearchHistory();
    addTearDown(history.dispose);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SearchResultPage(
                searchResult: empty('format:flac'),
                history: history,
                search: (query, {onlineCancellation}) async {
                  calls++;
                  return empty(query);
                }))));
    await tester.pumpAndSettle();
    expect(find.text('总乐库中没有匹配歌曲'), findsOneWidget);
    await tester.tap(find.text('联网'));
    await tester.pumpAndSettle();
    expect(find.text('高级筛选仅查询本地乐库，不会发送给联网服务'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'duration:bad');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(history.value, isEmpty);
    expect(find.text('时长条件无效。'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'title:rain');
    await tester.pumpAndSettle();
    expect(find.text('时长条件无效。'), findsNothing);
  });

  testWidgets('duration-only publications refresh visible filtered results',
      (tester) async {
    final library = AudioLibrary.instance;
    final before = List<Audio>.of(library.audioCollection);
    final audio = CategoryTestAudio('short', duration: 90);
    library.audioCollection
      ..clear()
      ..add(audio);
    AudioLibrary.searchRevision++;
    addTearDown(() {
      library.audioCollection
        ..clear()
        ..addAll(before);
      AudioLibrary.searchRevision++;
    });
    final result = (await tester
        .runAsync(() => UnionSearchResult.search('duration:>=180')))!;
    expect(result.audios, isEmpty);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SearchResultPage(
                searchResult: result, history: MemorySearchHistory()))));
    await tester.pumpAndSettle();
    final textRevision = AudioLibrary.searchRevision;
    audio.duration = 200;
    library.publishDurationChanges();
    await tester.pumpAndSettle();
    expect(result.audios, [audio]);
    expect(AudioLibrary.searchRevision, textRevision);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'result input and validation stay reachable in a short enlarged window',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: SearchResultPage(
                searchResult: empty('format:flac'),
                history: MemorySearchHistory()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'duration:bad');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester
        .ensureVisible(find.byKey(const ValueKey('result-local-search-help')));
    await tester.tap(find.byKey(const ValueKey('result-local-search-help')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalSearchHelpDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search busy state stays visible without animation when motion is disabled',
      (tester) async {
    final controller = TextEditingController(text: 'title:rain');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: LibrarySearchField(
                    controller: controller,
                    onSubmitted: (_) {},
                    onChanged: (_) {},
                    busy: true)))));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('正在搜索'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('render local-only results in four languages and narrow windows',
      (tester) async {
    const output = String.fromEnvironment('DAN_SEARCH_RESULT_RENDER');
    if (output.isEmpty) return;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final narrow in [false, true]) {
        final size = Size(narrow ? 360 : 800, narrow ? 500 : 640);
        tester.view.physicalSize = size;
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: language.locale,
                supportedLocales: [
                  for (final language in UiLanguage.values) language.locale
                ],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: Entry(welcome: false).fromSchemeAndFontFamily(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal,
                        brightness:
                            narrow ? Brightness.dark : Brightness.light)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(narrow ? 2 : 1),
                        disableAnimations: narrow),
                    child: child!),
                home: Scaffold(
                    body: SearchResultPage(
                        searchResult: empty('format:flac -live'),
                        history: MemorySearchHistory())))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${language.name} narrow=$narrow');
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                (await image.toByteData(format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List();
            final file = File(
                '$output/result-${language.name}-${narrow ? 'narrow' : 'wide'}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
          } finally {
            image.dispose();
          }
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
