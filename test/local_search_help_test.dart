import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_history_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
    testWidgets(
        '${language.name} search help and invalid input fit normal and enlarged narrow windows',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final history = MemorySearchHistory(['青花瓷', 'Beyoncé', 'title:晴天 -live']);
      addTearDown(history.dispose);
      final boundary = GlobalKey();
      var calls = 0;
      var scale = 1.0;
      late StateSetter resize;
      final theme = applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: language == UiLanguage.zh || language == UiLanguage.ko
                ? Brightness.dark
                : Brightness.light),
        visualDensity: VisualDensity.compact,
      ));
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) =>
              StatefulBuilder(builder: (context, setState) {
            resize = setState;
            return UiLanguageScope(
                child: MotionPreferencesScope(
              preferences: const MotionPreferences().all(false),
              child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
            ));
          }),
          home: Scaffold(
              body: SearchPage(
                  history: history,
                  search: (query, {onlineCancellation}) async {
                    calls++;
                    throw StateError(
                        'Invalid filters must not invoke the search provider');
                  })),
        ),
      ));
      await tester.pumpAndSettle();
      Future<void> capture(String stage) async {
        const output = String.fromEnvironment('DAN_LOCAL_SEARCH_RENDER');
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

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('landing');
      await tester.tap(find.byKey(const ValueKey('local-search-help')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSearchHelpDialog), findsOneWidget);
      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.center.dx, closeTo(450, 1));
      await capture('help');
      tester.view.physicalSize = const Size(360, 500);
      resize(() => scale = 2);
      await tester.pumpAndSettle();
      await capture('help-narrow-200');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(ui('不加筛选语法时保留原有搜索；西文重音与全角字母自动兼容。')));
      await tester.pumpAndSettle();
      await capture('help-narrow-200-bottom');
      // The close action stays reachable while only the content scrolls.
      final close = find.widgetWithText(TextButton, ui('关闭'));
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(500));
      await tester.tap(close);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'duration:bad');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(ui('时长条件无效。')), findsOneWidget);
      expect(history.value, isNot(contains('duration:bad')));
      expect(calls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final error = tester.getRect(find.text(ui('时长条件无效。')));
      final help =
          tester.getRect(find.byKey(const ValueKey('local-search-help')));
      expect(error.bottom, lessThanOrEqualTo(help.top));
      expect(help.bottom, lessThanOrEqualTo(500));
      await capture('invalid-narrow-200');
      await tester.enterText(find.byType(TextField), 'title:晴天');
      await tester.pumpAndSettle();
      expect(find.text(ui('时长条件无效。')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
