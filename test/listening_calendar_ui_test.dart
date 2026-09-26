import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/listening_calendar_card.dart';
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
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_CALENDAR_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes =
          (await image.toByteData(format: raster.ImageByteFormat.png))!
              .buffer
              .asUint8List();
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      image.dispose();
    }
  });
}

PlaybackStatistics _statistics() {
  final days = <String, int>{};
  for (var date = DateTime(2026, 7, 6);
      !date.isAfter(DateTime(2026, 9, 26));
      date = DateTime(date.year, date.month, date.day + 1)) {
    if (date.day % 4 == 0) continue;
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    days[key] = date.day % 5 == 0 ? 0 : (date.day % 7 + 1) * 1800000;
  }
  return PlaybackStatistics.inMemory(initialData: {
    'version': 3,
    'days': days,
    'playCountTrackingStartedOn': '2026-07-06',
    'dailyPlayCounts': {'2026-09-21': 3, '2026-09-23': 2, '2026-09-26': 4}
  });
}

void main() {
  late List<Audio> previousLibrary;
  late UiLanguage previousLanguage;
  setUpAll(() async {
    final windowsDirectory = Platform.environment['WINDIR'] ?? 'C:/Windows';
    final koreanFont = File('$windowsDirectory/Fonts/malgun.ttf');
    if (await koreanFont.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(koreanFont
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes))))
          .load();
    }
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() {
    previousLibrary = AudioLibrary.instance.audioCollection;
    AudioLibrary.instance.audioCollection = [];
    previousLanguage = uiLanguage.value;
  });
  tearDown(() {
    AudioLibrary.instance.audioCollection = previousLibrary;
    uiLanguage.value = previousLanguage;
  });

  Future<GlobalKey> pumpPage(WidgetTester tester, PlaybackStatistics stats,
      {double width = 1100,
      double scale = 1,
      Brightness brightness = Brightness.light,
      bool reduced = false}) async {
    tester.view.physicalSize = Size(width, width < 400 ? 1500 : 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: UiLanguageScope(
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Entry(welcome: false).fromSchemeAndFontFamily(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal, brightness: brightness)),
                home: MediaQuery(
                    data: MediaQueryData(
                        size: Size(width, 1500),
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: reduced),
                    child: Scaffold(
                        body: StatisticsPage(
                            statistics: stats,
                            now: DateTime(2026, 9, 26),
                            scanner: LibraryStatisticsScanner(
                                readLyrics: (_) async => null,
                                inspectFile: (_) async =>
                                    const LocalAudioFileInfo.available(
                                        0)))))))));
    await tester.pumpAndSettle();
    return key;
  }

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets('real page calendar $language $brightness wide and year',
          (tester) async {
        uiLanguage.value = language;
        final stats = _statistics();
        addTearDown(stats.dispose);
        final key = await pumpPage(tester, stats, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('statistics-calendar-card')),
            findsOneWidget);
        final plays = find.byKey(const ValueKey('statistics-activity-plays'));
        expect(
            find.descendant(of: plays, matching: find.text(ui('{0} 次', [9]))),
            findsOneWidget);
        await _capture(
            tester, key, '${language.name}-${brightness.name}-weeks');
        await tester
            .tap(find.byKey(const ValueKey('statistics-calendar-year')));
        await tester.pumpAndSettle();
        final rail = tester.widget<SingleChildScrollView>(
            find.byKey(const ValueKey('statistics-calendar-scroll')));
        expect(
            rail.controller!.offset, rail.controller!.position.maxScrollExtent);
        expect(rail.controller!.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
        await _capture(tester, key, '${language.name}-${brightness.name}-year');
      });
    }
    testWidgets('narrow real page $language large text reduced motion',
        (tester) async {
      uiLanguage.value = language;
      final stats = _statistics();
      addTearDown(stats.dispose);
      final key =
          await pumpPage(tester, stats, width: 320, scale: 1.6, reduced: true);
      expect(tester.takeException(), isNull);
      final metrics = [
        for (final name in ['plays', 'duration', 'active'])
          tester.getRect(find.byKey(ValueKey('statistics-activity-$name')))
      ];
      expect(metrics[0].bottom, lessThan(metrics[1].top));
      expect(metrics[1].bottom, lessThan(metrics[2].top));
      expect(metrics.map((rect) => rect.left).toSet().length, 1);
      await _capture(tester, key, '${language.name}-narrow-large-reduced');
    });
  }

  testWidgets(
      'one behavior card switches real range metrics and retained hourly totals',
      (tester) async {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 3,
      'tracks': [
        {
          'id': 'online:netease:history',
          'playCount': 99,
          'listenMilliseconds': 28800000
        }
      ],
      'hours': [for (var hour = 0; hour < 24; hour++) hour == 6 ? 7200000 : 0],
      'days': {'2026-06-01': 3600000, '2026-09-26': 120000},
      'dailyPlayCounts': {'2026-06-01': 7, '2026-09-26': 3},
      'playCountTrackingStartedOn': '2025-09-27',
    });
    addTearDown(stats.dispose);
    await pumpPage(tester, stats);
    Finder metric(String name, String value) => find.descendant(
        of: find.byKey(ValueKey('statistics-activity-$name')),
        matching: find.text(value));
    expect(find.text('听歌行为'), findsOneWidget);
    expect(find.text('本周'), findsNothing);
    expect(find.byType(ListeningCalendarCard), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('statistics-calendar-twelveWeeks')))
            .selected,
        isTrue);
    final chips = ['daily', 'twelveWeeks', 'year']
        .map((name) =>
            tester.getRect(find.byKey(ValueKey('statistics-calendar-$name'))))
        .toList();
    expect(chips[0].left, lessThan(chips[1].left));
    expect(chips[1].left, lessThan(chips[2].left));
    expect(metric('plays', '3 次'), findsOneWidget);
    expect(metric('duration', '2 分钟'), findsOneWidget);
    expect(metric('active', '1 天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
    await tester.pumpAndSettle();
    expect(metric('plays', '10 次'), findsOneWidget);
    expect(metric('duration', '1 小时 2 分'), findsOneWidget);
    expect(metric('active', '2 天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-daily')));
    await tester.pump();
    expect(
        tester
            .widget<FadeTransition>(
                find.byKey(const ValueKey('calendar-range-fade')))
            .opacity
            .value,
        0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(
        tester
            .widget<FadeTransition>(
                find.byKey(const ValueKey('calendar-range-fade')))
            .opacity
            .value,
        inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(metric('plays', '99 次'), findsOneWidget);
    expect(metric('duration', '8 小时 0 分'), findsOneWidget);
    expect(metric('active', '06:00–07:00'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('statistics-calendar-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('statistics-daily-distribution')),
        findsOneWidget);
    expect(find.text('全部记录 · 按小时累计'), findsOneWidget);
    expect(find.text('小时分布包含全部历史记录，不表示某一天；恢复播放不重复计次。'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('statistics-calendar-twelveWeeks')));
    await tester.pumpAndSettle();
    final rail = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('statistics-calendar-scroll')))
        .controller!;
    expect(rail.positions.length, 1);
    expect(metric('plays', '3 次'), findsOneWidget);
    expect(stats.totalPlayCount, 99);
    expect(stats.dailyPlayCounts.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'calendar wheel/touch scroll and day selection retain outer vertical scroll',
      (tester) async {
    final stats = _statistics();
    addTearDown(stats.dispose);
    await pumpPage(tester, stats, width: 320);
    final railFinder = find.byKey(const ValueKey('statistics-calendar-scroll'));
    final rail = tester.widget<SingleChildScrollView>(railFinder).controller!;
    final before = rail.offset;
    final point = tester.getCenter(railFinder);
    await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(0, -50)));
    await tester.pumpAndSettle();
    expect(rail.offset, lessThan(before));
    await tester.drag(railFinder, const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(rail.offset, greaterThan(0));
    rail.jumpTo(rail.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('listening-day-2026-09-26'));
    await tester.tap(selected);
    await tester.pumpAndSettle();
    final detail = tester
        .widget<Text>(find.byKey(const ValueKey('statistics-calendar-detail')))
        .data!;
    expect(detail, contains('2026-09-26'));
    expect(detail, contains('4 次'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(selected));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(detail), findsNWidgets(2));
    await mouse.removePointer();
    await tester.pumpAndSettle();
    final outer = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first)
        .position;
    await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(160, 40), scrollDelta: Offset(0, 80)));
    await tester.pumpAndSettle();
    expect(outer.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'old counts unknown; missing duration differs from a recorded zero',
      (tester) async {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 2,
      'days': {'2026-09-25': 0}
    });
    addTearDown(stats.dispose);
    await pumpPage(tester, stats);
    expect(stats.dailyPlayCounts, isEmpty);
    expect(stats.playCountTrackingStartedOn, isNull);
    final plays = find.byKey(const ValueKey('statistics-activity-plays'));
    expect(
        find.descendant(of: plays, matching: find.text('—')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listening-day-2026-09-25')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('statistics-calendar-detail')))
            .data,
        contains('0 秒'));
    await tester.tap(find.byKey(const ValueKey('listening-day-2026-09-26')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('statistics-calendar-detail')))
            .data,
        contains('无时长记录'));
    expect(find.text('旧记录没有每日播放次数；启用记录后才显示，不从累计次数推算。'), findsOneWidget);
    expect(find.byType(ListeningCalendarCard), findsOneWidget);
  });

  testWidgets(
      'actual recording stays live while display waits for manual refresh',
      (tester) async {
    final stats = PlaybackStatistics.inMemory(
        clock: () => DateTime(2026, 9, 26),
        initialData: {
          'version': 2,
          'days': {'2026-09-21': 60000}
        });
    addTearDown(stats.dispose);
    await pumpPage(tester, stats);
    final audio = Audio.online(
        provider: 'netease',
        id: 'live',
        title: 'Live',
        artist: 'Artist',
        album: 'Album',
        duration: 180);
    stats.start(audio);
    await tester.pumpAndSettle();
    final plays = find.byKey(const ValueKey('statistics-activity-plays'));
    expect(
        find.descendant(of: plays, matching: find.text('—')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('statistics-refresh')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: plays, matching: find.text('1 次')), findsOneWidget);
    expect(find.text('播放次数自 2026-09-26 开始记录，该范围此前次数未知。'), findsOneWidget);
    expect(stats.dailyMilliseconds, {'2026-09-21': 60000});
    expect(stats.dailyPlayCounts, {'2026-09-26': 1});
    stats.pause();
    stats.start(audio);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: plays, matching: find.text('1 次')), findsOneWidget);
  });

  testWidgets('day cells support keyboard activation and readable semantics',
      (tester) async {
    final stats = _statistics();
    addTearDown(stats.dispose);
    await pumpPage(tester, stats);
    final selected = find.byKey(const ValueKey('listening-day-2026-09-26'));
    final focus = Focus.of(tester.element(find
        .descendant(of: selected, matching: find.byType(MouseRegion))
        .first));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final detail = tester
        .widget<Text>(find.byKey(const ValueKey('statistics-calendar-detail')))
        .data!;
    expect(detail, contains('2026-09-26'));
    expect(detail, contains('4 次'));
    final material = tester.widget<Material>(
        find.ancestor(of: selected, matching: find.byType(Material)).first);
    expect((material.shape as RoundedRectangleBorder).side.width, 2);
    final semantics = tester.ensureSemantics();
    try {
      expect(tester.getSemantics(selected).label, contains('2026-09-26'));
    } finally {
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'twelve-week rectangular cells fill the wide card; narrow cells retain minimum width',
      (tester) async {
    final stats = _statistics();
    addTearDown(stats.dispose);
    await pumpPage(tester, stats);
    final rail = tester
        .getRect(find.byKey(const ValueKey('statistics-calendar-scroll')));
    final first =
        tester.getRect(find.byKey(const ValueKey('listening-day-2026-07-06')));
    final last =
        tester.getRect(find.byKey(const ValueKey('listening-day-2026-09-21')));
    expect(first.left, closeTo(rail.left, .01));
    expect(last.right, closeTo(rail.right - 4, .01));
    expect(first.width, greaterThan(first.height * 3));
    await pumpPage(tester, stats, width: 320);
    final narrow =
        tester.getRect(find.byKey(const ValueKey('listening-day-2026-09-21')));
    expect(narrow.width, greaterThanOrEqualTo(18));
    expect(tester.takeException(), isNull);
  });
}
