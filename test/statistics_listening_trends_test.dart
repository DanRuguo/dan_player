import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

Map<String, int> _days() => {
      for (var offset = 1; offset <= 180; offset++)
        listeningDayKey(DateTime(2026, 10, 3 - offset)): offset <= 7
            ? (8 - offset) * 1800000
            : offset <= 14
                ? (15 - offset) * 900000
                : offset % 5 == 0
                    ? 0
                    : (offset % 6 + 1) * 600000,
      '2026-10-03': 900000000,
    };
ListeningTrendsSnapshot _snapshot() => ListeningTrendsSnapshot.fromDaily(
    dailyMilliseconds: _days(), capturedAt: DateTime(2026, 10, 3, 14, 30));

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, ListeningTrendsSnapshot snapshot,
      {double width = 1080,
      double height = 1000,
      double scale = 1,
      Color seed = Colors.teal,
      Brightness brightness = Brightness.light,
      GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: height);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: StatisticsListeningTrends(snapshot: snapshot))),
        scale: scale,
        seed: seed,
        brightness: brightness,
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  dynamic painter(WidgetTester tester) => tester
      .widget<CustomPaint>(find.descendant(
          of: _key('statistics-trends-chart'),
          matching: find.byType(CustomPaint)))
      .painter;

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    final root = Platform.environment['DAN_STATISTICS_TRENDS_RENDER_DIR'];
    if (root == null) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.png);
        await Directory(root).create(recursive: true);
        await File('$root/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets(
      'period menu reuses frozen comparisons across theme and locale rebuilds',
      (tester) async {
    final snapshot = _snapshot();
    await mount(tester, snapshot);
    expect(painter(tester).data, same(snapshot.comparisons[7]));
    expect(find.text('2026-09-26 – 2026-10-02'), findsOneWidget);
    for (final days in [30, 90]) {
      await tester.tap(_key('statistics-trends-period'));
      await tester.pumpAndSettle();
      await tester.tap(_key('statistics-trends-period-$days'));
      await tester.pumpAndSettle();
      expect(painter(tester).data, same(snapshot.comparisons[days]));
    }
    uiLanguage.value = UiLanguage.ko;
    await mount(tester, snapshot,
        seed: Colors.amber, brightness: Brightness.dark);
    expect(painter(tester).data, same(snapshot.comparisons[90]));
    final scheme =
        Theme.of(tester.element(find.byType(StatisticsListeningTrends)))
            .colorScheme;
    expect(painter(tester).currentColor, scheme.primary);
    expect(painter(tester).previousColor, scheme.tertiary);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch keyboard and real semantics select the paired dates',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, _snapshot());
      final chart = tester.getRect(_key('statistics-trends-chart'));
      final touch = await tester.startGesture(
          Offset(chart.left + 12, chart.center.dy),
          kind: raster.PointerDeviceKind.touch);
      await touch.up();
      await tester.pumpAndSettle();
      expect(painter(tester).selection, 0);
      expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
          contains('2026-09-26'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(painter(tester).selection, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(painter(tester).selection, 6);
      final node =
          tester.getSemantics(_key('statistics-trends-chart-semantics'));
      node.owner!.performAction(node.id, raster.SemanticsAction.decrease);
      await tester.pump();
      expect(painter(tester).selection, 5);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(painter(tester).selection, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('hover inspects a day without creating new data or idle frames',
      (tester) async {
    final snapshot = _snapshot();
    await mount(tester, snapshot);
    final chart = tester.getRect(_key('statistics-trends-chart'));
    final mouse =
        await tester.createGesture(kind: raster.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(chart.left + 12, chart.center.dy));
    await mouse.moveTo(Offset(chart.center.dx, chart.center.dy));
    await tester.pumpAndSettle();
    expect(painter(tester).selection, 3);
    expect(painter(tester).data, same(snapshot.comparisons[7]));
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 20));
    expect(painter(tester).selection, 3);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty prior data states no percentage and current day remains excluded',
      (tester) async {
    final snapshot = ListeningTrendsSnapshot.fromDaily(
        dailyMilliseconds: {'2026-10-03': 900000},
        capturedAt: DateTime(2026, 10, 3));
    await mount(tester, snapshot);
    expect(find.text('前期无收听记录，不计算百分比。'), findsOneWidget);
    expect(painter(tester).data.currentMilliseconds, 0);
    expect(painter(tester).data.changePercent, isNull);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real statistics page keeps trend capture until explicit refresh',
      (tester) async {
    final previousLibrary = AudioLibrary.instance.audioCollection;
    AudioLibrary.instance.audioCollection = [];
    addTearDown(() => AudioLibrary.instance.audioCollection = previousLibrary);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 4,
      'tracks': <Object>[],
      'days': {'2026-10-02': 1000},
      'hours': List.filled(24, 0),
      'dailyPlayCounts': <String, int>{},
      'playCountTrackingStartedOn': null,
      'recentTrackingStartedAt': null,
      'recentPlayStarts': <int>[],
      'recentListeningIntervals': <Object>[],
    });
    addTearDown(stats.dispose);
    var reads = 0;
    Widget app(Color seed) => listeningStatusHost(
        StatisticsPage(
            statistics: stats,
            now: DateTime(2026, 10, 3, 12),
            scanner: LibraryStatisticsScanner(
                readLyrics: (_) async => null,
                inspectFile: (_) async {
                  reads++;
                  return const LocalAudioFileInfo.available(0);
                })),
        seed: seed);
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    await tester.pumpWidget(app(Colors.teal));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(_key('statistics-trends-chart'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final frozen = painter(tester).data;
    expect(frozen.currentMilliseconds, 1000);
    stats.dailyMilliseconds['2026-10-02'] = 9000;
    await tester.pumpWidget(app(Colors.pink));
    await tester.pumpAndSettle();
    expect(painter(tester).data, same(frozen));
    expect(painter(tester).data.currentMilliseconds, 1000);
    // Header sliver is lazily discarded while the comparison card is visible.
    await tester.scrollUntilVisible(_key('statistics-refresh'), -400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(_key('statistics-refresh'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(_key('statistics-trends-chart'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(painter(tester).data.currentMilliseconds, 9000);
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'trends render ${language.name} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await mount(tester, _snapshot(),
            width: narrow ? 360 : 1080,
            height: 1200,
            scale: narrow ? 2 : 1,
            boundary: boundary,
            seed: narrow ? Colors.amber : Colors.indigo,
            brightness: narrow ? Brightness.dark : Brightness.light);
        final name = '${language.name}-${narrow ? 'narrow-large' : 'wide'}';
        expect(_key('statistics-trends-period').hitTestable(), findsOneWidget);
        await capture(tester, boundary, '$name-summary');
        await tester.ensureVisible(_key('statistics-trends-chart'));
        await tester.pumpAndSettle();
        final chart = tester.getRect(_key('statistics-trends-chart'));
        expect(chart.left, greaterThanOrEqualTo(0));
        expect(chart.right, lessThanOrEqualTo(narrow ? 360 : 1080));
        await capture(tester, boundary, '$name-chart');
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
