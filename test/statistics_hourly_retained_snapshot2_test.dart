import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const output = String.fromEnvironment('DAN_HOURLY_RETAINED_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
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
            ..addFont(korean.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final item in [
    (UiLanguage.zh, false),
    (UiLanguage.en, true),
    (UiLanguage.ja, true),
    (UiLanguage.ko, true)
  ]) {
    final language = item.$1;
    final narrow = item.$2;
    testWidgets(
        'merged real statistics page retains 24 clickable hour bars $language narrow=$narrow',
        (tester) async {
      final previousLibrary = AudioLibrary.instance.audioCollection;
      final previousRevision = AudioLibrary.revision;
      final previousLanguage = uiLanguage.value;
      AudioLibrary.instance.audioCollection = [
        Audio('Northern Lights', 'Demo Ensemble', 'Seasons', 1, 180, 320, 44100,
            'C:/Synthetic/hourly.mp3', 1, 1, 'fixture',
            language: 'en'),
      ];
      AudioLibrary.revision++;
      uiLanguage.value = language;
      addTearDown(() {
        AudioLibrary.instance.audioCollection = previousLibrary;
        AudioLibrary.revision = previousRevision;
        uiLanguage.value = previousLanguage;
      });
      final stats = PlaybackStatistics.inMemory(initialData: {
        'version': 3,
        'tracks': [
          TrackPlaybackStatistics(
                  id: 'demo',
                  title: 'Northern Lights',
                  artist: 'Demo Ensemble',
                  album: 'Seasons',
                  online: false,
                  playCount: 24,
                  completedCount: 20,
                  skippedCount: 4,
                  listenMilliseconds: 7200000)
              .toMap(),
        ],
        'hours': List.generate(
            24, (hour) => (hour % 6 + 1) * 600000 + (hour == 18 ? 3600000 : 0)),
        'days': {
          '2026-09-24': 1800000,
          '2026-09-25': 2400000,
          '2026-09-26': 3600000
        },
        'playCountTrackingStartedOn': '2026-09-24',
        'dailyPlayCounts': {'2026-09-24': 6, '2026-09-25': 8, '2026-09-26': 10},
      });
      addTearDown(stats.dispose);
      final width = narrow ? 400.0 : 1100.0;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: UiLanguageScope(
              child: MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            locale: uiLanguage.value.locale,
            supportedLocales:
                UiLanguage.values.map((language) => language.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal,
                    brightness: narrow ? Brightness.dark : Brightness.light)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(narrow ? 2 : 1)),
                child: child!),
            home: Scaffold(
                body: StatisticsPage(
                    statistics: stats,
                    now: DateTime(2026, 9, 26),
                    scanner: LibraryStatisticsScanner(
                        readLyrics: (_) async => null,
                        inspectFile: (_) async =>
                            const LocalAudioFileInfo.available(
                                8 * 1024 * 1024)))),
          ))));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('statistics-calendar-card'));
      expect(card, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('statistics-calendar-daily')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('statistics-calendar-daily')))
              .selected,
          isTrue);
      expect(find.byKey(const ValueKey('statistics-daily-distribution')),
          findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await capture(tester, boundary,
          '${language.name}-${narrow ? 'narrow' : 'wide'}-daily-entry');
      final main = find.byType(Scrollable).first;
      final heading = find.text(ui('24 小时收听分布'));
      await tester.scrollUntilVisible(heading, 300,
          scrollable: main, maxScrolls: 20);
      await tester.ensureVisible(narrow ? heading : card);
      await tester.pumpAndSettle();
      for (var hour = 0; hour < 24; hour++) {
        expect(find.byKey(ValueKey('listening-bar-$hour')), findsOneWidget);
        expect(find.byKey(ValueKey('listening-hour-$hour')), findsOneWidget);
        expect(
            tester.getSize(find.byKey(ValueKey('listening-bar-$hour'))).height,
            greaterThan(0));
      }
      final horizontal = find.byKey(const ValueKey('listening-hours-scroll'));
      final rail = tester.widget<SingleChildScrollView>(horizontal).controller!;
      final selectedHour = narrow ? 23 : 6;
      if (narrow) {
        expect(rail.position.maxScrollExtent, greaterThan(0));
        final before = rail.offset;
        await tester.drag(horizontal, const Offset(-450, 0));
        await tester.pumpAndSettle();
        expect(rail.offset, greaterThan(before));
        rail.jumpTo(rail.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text(ui('滚轮或横向滑动查看全部 24 个时段')), findsOneWidget);
      }
      await tester.tap(find.byKey(ValueKey('listening-hour-$selectedHour')));
      await tester.pumpAndSettle();
      final selection = find.byKey(const ValueKey('listening-hour-selection'));
      expect(
          find.descendant(
              of: selection,
              matching: find.text(
                  '${selectedHour.toString().padLeft(2, '0')}:00–${(selectedHour + 1).toString().padLeft(2, '0')}:00')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await capture(tester, boundary,
          '${language.name}-${narrow ? 'narrow-hour23' : 'wide-hour06'}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
