import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
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
  for (final sample in [
    (UiLanguage.zh, false),
    (UiLanguage.zh, true),
    (UiLanguage.en, true),
    (UiLanguage.ja, true),
    (UiLanguage.ko, true)
  ]) {
    testWidgets(
        'practical statistics exact daily insights and grouped rankings $sample',
        (tester) async {
      final language = sample.$1, narrow = sample.$2;
      final previousLanguage = uiLanguage.value;
      final previousLibrary = AudioLibrary.instance.audioCollection;
      uiLanguage.value = language;
      AudioLibrary.instance.audioCollection = [];
      addTearDown(() {
        uiLanguage.value = previousLanguage;
        AudioLibrary.instance.audioCollection = previousLibrary;
      });
      tester.view.physicalSize =
          Size(narrow ? 420 : 1120, narrow ? 1100 : 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 27, 12, 30);
      final stats = PlaybackStatistics.inMemory(initialData: {
        'version': 4,
        'recentTrackingStartedAt':
            now.subtract(const Duration(hours: 48)).millisecondsSinceEpoch,
        'recentPlayStarts': [
          for (var i = 0; i < 12; i++)
            now.subtract(Duration(hours: i)).millisecondsSinceEpoch
        ]..sort(),
        'recentListeningIntervals': [
          for (var i = 23; i >= 0; i--)
            [
              now
                  .subtract(Duration(hours: i, minutes: 25))
                  .millisecondsSinceEpoch,
              now
                  .subtract(Duration(hours: i, minutes: 5))
                  .millisecondsSinceEpoch
            ]
        ],
        'playCountTrackingStartedOn': '2025-09-28',
        'dailyPlayCounts': {'2026-09-27': 12, '2026-09-26': 18},
        'hours': List.generate(24, (hour) => (hour % 6 + 1) * 600000),
        'days': {
          for (var i = 0; i < 365; i++)
            if (i % 6 != 0)
              listeningDayKey(DateTime(2026, 9, 27 - i)): (i % 7 + 1) * 1200000
        },
        'tracks': [
          for (var i = 0; i < 4; i++)
            TrackPlaybackStatistics(
                    id: 'track-$i',
                    title: 'Seasons ${i + 1}',
                    artist: i < 2 ? 'Northern Lights' : 'The Local Ensemble',
                    album: i.isEven ? 'Autumn' : 'Spring',
                    online: false,
                    playCount: 20 - i * 3,
                    listenMilliseconds: 7200000 - i * 1000000)
                .toMap()
        ],
      });
      addTearDown(stats.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: UiLanguageScope(
              child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: language.locale,
            supportedLocales: UiLanguage.values.map((item) => item.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal,
                    brightness: narrow ? Brightness.dark : Brightness.light)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
                child: child!),
            home: Scaffold(
                body: StatisticsPage(
                    statistics: stats,
                    now: now,
                    scanner: LibraryStatisticsScanner(
                        readLyrics: (_) async => null,
                        inspectFile: (_) async =>
                            const LocalAudioFileInfo.available(0)))),
          ))));
      await tester.pumpAndSettle();
      Future<void> capture(String suffix) async {
        expect(tester.takeException(), isNull);
        const output =
            String.fromEnvironment('DAN_PRACTICAL_STATISTICS_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            final file = File(
                '$output/${language.name}-${narrow ? 'narrow' : 'wide'}-$suffix.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> reveal(Finder finder) async {
        await tester.scrollUntilVisible(finder, 300,
            scrollable: find.byType(Scrollable).first, maxScrolls: 50);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('statistics-calendar-daily')))
              .selected,
          isTrue);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('statistics-activity-plays')),
              matching: find.text(ui('{0} 次', [12]))),
          findsOneWidget);
      await capture('daily');
      await reveal(find.text(ui('24 小时收听分布')));
      await capture('rolling-hours');
      await reveal(find.byKey(const ValueKey('statistics-calendar-year')));
      await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
      await tester.pumpAndSettle();
      final calendar = ListeningCalendar(
          now: now,
          dailyMilliseconds: stats.dailyMilliseconds,
          dailyPlayCounts: stats.dailyPlayCounts,
          range: ListeningCalendarRange.year);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('statistics-activity-active')),
              matching: find.text(ui('{0} 周', [calendar.rangeActiveWeeks]))),
          findsOneWidget);
      await capture('year');
      await reveal(find.byKey(const ValueKey('statistics-listening-insights')));
      await capture('insights');
      await reveal(find.byKey(const ValueKey('statistics-busiest-day')));
      await tester.tap(find.byKey(const ValueKey('statistics-busiest-day')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('statistics-calendar-detail')))
              .data,
          contains(calendar.busiestDay!.key));
      await reveal(find.byKey(const ValueKey('statistics-ranking-artists')));
      await tester
          .tap(find.byKey(const ValueKey('statistics-ranking-artists')));
      await tester.pumpAndSettle();
      await capture('artists');
      await tester.tap(find.byKey(const ValueKey('statistics-ranking-albums')));
      await tester.pumpAndSettle();
      await capture('albums');
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
