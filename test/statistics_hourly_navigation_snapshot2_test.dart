import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_HOUR_NAVIGATION_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _signal(WidgetTester tester, Finder rail, Offset delta) async {
  tester.binding.handlePointerEvent(
      PointerScrollEvent(position: tester.getCenter(rail), scrollDelta: delta));
  await tester.pumpAndSettle();
}

Future<void> _keyActivate(WidgetTester tester, Finder button) async {
  Focus.of(tester
          .element(find.descendant(of: button, matching: find.byType(Icon))))
      .requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

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
  });

  for (final narrow in [true, false]) {
    testWidgets(
        'real hourly rail wheel touch keyboard and parent handoff narrow=$narrow',
        (tester) async {
      final previousLibrary = AudioLibrary.instance.audioCollection;
      final previousLanguage = uiLanguage.value;
      AudioLibrary.instance.audioCollection = [];
      uiLanguage.value = narrow ? UiLanguage.en : UiLanguage.zh;
      addTearDown(() {
        AudioLibrary.instance.audioCollection = previousLibrary;
        uiLanguage.value = previousLanguage;
      });
      final statistics = PlaybackStatistics.inMemory(initialData: {
        'version': 3,
        'hours': List.generate(24, (hour) => (hour % 6 + 1) * 600000),
      });
      addTearDown(statistics.dispose);
      tester.view.physicalSize = Size(narrow ? 400 : 1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: UiLanguageScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            scrollBehavior: const DanPlayerScrollBehavior(),
            locale: uiLanguage.value.locale,
            supportedLocales: UiLanguage.values.map((item) => item.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
              child: child!,
            ),
            home: Scaffold(
                body: StatisticsPage(
                    statistics: statistics,
                    now: DateTime(2026, 9, 26),
                    scanner: LibraryStatisticsScanner(
                        readLyrics: (_) async => null,
                        inspectFile: (_) async =>
                            const LocalAudioFileInfo.available(0)))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-calendar-daily')));
      await tester.pumpAndSettle();
      final rail = find.byKey(const ValueKey('listening-hours-scroll'));
      final outer =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      await tester.ensureVisible(rail);
      await tester.pumpAndSettle();
      final controller = tester.widget<SingleChildScrollView>(rail).controller!;
      if (narrow) {
        expect(controller.position.maxScrollExtent, greaterThan(300));
        final pageBefore = outer.pixels;
        await _signal(tester, rail, const Offset(0, 120));
        expect(controller.offset, closeTo(120, .01));
        expect(outer.pixels, closeTo(pageBefore, .01));
        await _signal(tester, rail, const Offset(80, 0));
        expect(controller.offset, closeTo(200, .01));
        await tester.drag(rail, const Offset(-120, 0));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(200));
        outer.jumpTo((outer.pixels - 120).clamp(0, outer.maxScrollExtent));
        await tester.pumpAndSettle();
        await _capture(tester, boundary, 'en-narrow-wheel-touch');
        controller.jumpTo(0);
        await tester.pumpAndSettle();
      } else {
        expect(controller.position.maxScrollExtent, 0);
      }
      await tester.tap(find.byKey(const ValueKey('listening-hour-0')));
      await tester.pumpAndSettle();
      final previous = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == ui('前一个时段'));
      final next = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == ui('后一个时段'));
      await tester.ensureVisible(previous);
      await tester.pumpAndSettle();
      await _keyActivate(tester, previous);
      final selection = find.byKey(const ValueKey('listening-hour-selection'));
      expect(find.descendant(of: selection, matching: find.text('23:00–24:00')),
          findsOneWidget);
      expect(
          controller.offset, closeTo(controller.position.maxScrollExtent, .01));
      await tester.ensureVisible(rail);
      outer.jumpTo((outer.pixels - 120).clamp(0, outer.maxScrollExtent));
      await tester.pumpAndSettle();
      await _capture(tester, boundary,
          narrow ? 'en-narrow-keyboard-last' : 'zh-wide-keyboard-last');
      await _keyActivate(tester, next);
      expect(find.descendant(of: selection, matching: find.text('00:00–01:00')),
          findsOneWidget);
      expect(controller.offset, 0);
      await tester.ensureVisible(rail);
      await tester.pumpAndSettle();
      expect(outer.pixels, greaterThan(0));
      final pageBefore = outer.pixels;
      await _signal(tester, rail, const Offset(0, -90));
      expect(controller.offset, 0);
      expect(outer.pixels, lessThan(pageBefore));
      if (narrow) {
        await tester.ensureVisible(rail);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final pageBefore = outer.pixels;
        expect(outer.maxScrollExtent, greaterThan(pageBefore));
        await _signal(tester, rail, const Offset(0, 90));
        expect(controller.offset,
            closeTo(controller.position.maxScrollExtent, .01));
        expect(outer.pixels, greaterThan(pageBefore));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
