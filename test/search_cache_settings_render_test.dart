import 'package:dan_player/page/search_page/settings_search_results.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/component/search_category_tabs.dart';
import 'package:dan_player/page/search_page/lyric_search_results.dart';
import 'package:dan_player/search/lyric_search_index.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf'
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets('search settings and target ${language.name} narrow render',
        (tester) async {
      tester.view.physicalSize = const Size(480, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final boundary = GlobalKey();
      SettingsSearchEntry? opened;
      final theme = applyAppControlTheme(ThemeData(
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange, brightness: Brightness.dark)));
      Widget app(Widget child) => RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: UiLanguageScope(
                  child: Scaffold(
                      body: Padding(
                          padding: const EdgeInsets.all(16), child: child)))));
      Future<void> capture(String name) async {
        const output = String.fromEnvironment('DAN_SETTING_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          final file = File('$output/${language.name}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(app(DefaultTabController(
          length: 7,
          initialIndex: 6,
          child: Column(children: [
            const SearchCategoryTabs(),
            const SizedBox(height: 12),
            Expanded(
                child: SettingsSearchResultsView(
                    query: translateUi('联网与歌词', language),
                    open: (entry) => opened = entry))
          ]))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('settings-results');
      await tester.tap(find.byKey(const ValueKey('settings-result-batch')));
      expect(opened!.id, 'batch');
      await tester.pumpWidget(app(SettingsPage(
          initialSection: opened!.section, initialSetting: opened!.id)));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('setting-batch')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThan(820));
      expect(tester.takeException(), isNull);
      await capture('settings-target');
      final docs = LyricDocumentStore(
          storageDirectory: Directory(
              '${Platform.environment['DAN_PLAYER_DATA_DIR']}/render-docs'));
      await tester.runAsync(docs.load);
      final index = LyricSearchIndex(
          documents: docs, audios: () => [], libraryRevision: () => 0);
      await tester.pumpWidget(
          app(LyricSearchResultsView(query: 'fixture', index: index)));
      await tester.runAsync(() => index.search('fixture'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lyric-index');
      await tester.pumpWidget(const SizedBox.shrink());
      index.dispose();
      docs.dispose();
    });
  }
}
