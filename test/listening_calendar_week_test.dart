import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
ListeningTrendsSnapshot _snapshot() => ListeningTrendsSnapshot.fromDaily(
        capturedAt: DateTime(2026, 10, 7, 12),
        currentDayMilliseconds: 1200000,
        dailyMilliseconds: {
          for (var offset = 1; offset <= 90; offset++)
            listeningDayKey(DateTime(2026, 10, 7 - offset)):
                (offset % 6 + 1) * 600000,
          '2026-10-05': 0,
          '2026-10-08': 999999999,
        });

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    final output = Platform.environment['DAN_CALENDAR_WEEK_RENDER_DIR'];
    if (output == null) return;
    final qa = path.normalize(
        path.join(Directory.current.parent.path, 'tool', 'qa-local'));
    expect(path.isWithin(qa, path.normalize(path.absolute(output))), isTrue);
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('calendar week aligns Mondays and never imports future saved totals',
      () {
    final snapshot = _snapshot();
    final week = snapshot.calendarWeek;
    expect(week.current.map((day) => listeningDayKey(day.date)), [
      '2026-10-05',
      '2026-10-06',
      '2026-10-07',
      '2026-10-08',
      '2026-10-09',
      '2026-10-10',
      '2026-10-11',
    ]);
    expect(listeningDayKey(week.previous.first.date), '2026-09-28');
    expect(listeningDayKey(week.previous.last.date), '2026-10-04');
    expect(week.current[2].milliseconds, 1200000);
    expect(
        week.current
            .skip(3)
            .every((day) => day.milliseconds == 0 && !day.hasRecord),
        isTrue);
    expect(week.current.first.hasRecord, isTrue);
    expect(snapshot.comparisons[7]!.current.last.date, DateTime(2026, 10, 6));
    expect(() => week.current.clear(), throwsUnsupportedError);
  });

  test(
      'week boundaries and frozen missing records stay distinct from recorded zero',
      () {
    final daily = {'2024-02-26': 0, '2024-02-29': 1500};
    final snapshot = ListeningTrendsSnapshot.fromDaily(
        dailyMilliseconds: daily,
        capturedAt: DateTime(2024, 3, 3, 23),
        currentDayMilliseconds: 2000);
    daily['2024-02-27'] = 9000000;
    final week = snapshot.calendarWeek;
    expect(week.current.first.date, DateTime(2024, 2, 26));
    expect(week.current.last.date, DateTime(2024, 3, 3));
    expect(week.current.first.hasRecord, isTrue);
    expect(week.current[1].hasRecord, isFalse);
    expect(week.current[1].milliseconds, 0);
    expect(week.currentMilliseconds, 3500);
    final monday = ListeningTrendsSnapshot.fromDaily(
            dailyMilliseconds: {},
            capturedAt: DateTime(2026, 1, 5),
            currentDayMilliseconds: 1)
        .calendarWeek;
    expect(monday.previous.first.date, DateTime(2025, 12, 29));
    expect(
        monday.current.skip(1).every((day) => day.milliseconds == 0), isTrue);
  });

  Future<void> mount(WidgetTester tester,
      {double width = 1080,
      double scale = 1,
      GlobalKey? boundary,
      ListeningTrendsSnapshot? snapshot}) async {
    sizePlaylistFeature(tester, width: width, height: 1000);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: StatisticsListeningTrends(
                    snapshot: snapshot ?? _snapshot()))),
        scale: scale,
        boundary: boundary));
    await tester.pumpAndSettle();
    await tester.tap(_key('statistics-trends-period'));
    await tester.pumpAndSettle();
    await tester.tap(_key('statistics-trends-calendar-week'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'strict week stays in one chart and distinguishes future from missing data',
      (tester) async {
    await mount(tester);
    expect(_key('statistics-trends-chart'), findsOneWidget);
    expect(find.text('2026-10-05 – 2026-10-11'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    final rect = tester.getRect(_key('statistics-trends-chart'));
    await tester
        .tapAt(Offset(rect.left + rect.width * 5.5 / 7, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
        contains('未来日期，按 0 占位'));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
        isNot(contains('缺失记录')));
    expect(find.textContaining('增减为暂时结果'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('curve menu hides unselected data and keeps the selected weekday',
      (tester) async {
    await mount(tester);
    for (final choice in ['current', 'previous', 'both']) {
      await tester.ensureVisible(_key('statistics-trends-series'));
      await tester.tap(_key('statistics-trends-series'));
      await tester.pumpAndSettle();
      await tester.tap(_key('statistics-trends-series-$choice'));
      await tester.pumpAndSettle();
      final dynamic painter = tester
          .widget<CustomPaint>(find.descendant(
              of: _key('statistics-trends-chart'),
              matching: find.byType(CustomPaint)))
          .painter;
      expect(painter.showCurrent, choice != 'previous');
      expect(painter.showPrevious, choice != 'current');
      final detail =
          tester.widget<Text>(_key('statistics-trends-selected-day')).data!;
      expect(detail.contains(ui('本期（实线）')), choice != 'previous');
      expect(detail.contains(ui('前期（虚线）')), choice != 'current');
      expect(
          detail, contains(choice == 'previous' ? '2026-09-30' : '2026-10-07'));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow week scrolls horizontally and canceled input does not select',
      (tester) async {
    await mount(tester, width: 420, scale: 1.5);
    await tester.ensureVisible(_key('statistics-trends-chart'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(_key('statistics-trends-chart'));
    final touch = await tester.startGesture(
        Offset(rect.left + 40, rect.top + 60),
        kind: raster.PointerDeviceKind.touch);
    await touch.moveBy(const Offset(-25, 0));
    await touch.moveBy(const Offset(-90, 0));
    await touch.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
        contains('2026-10-07'));
    final scroll = tester
        .widget<SingleChildScrollView>(_key('statistics-trends-week-scroll'))
        .controller!;
    expect(scroll.offset, greaterThan(0));
    await tester.tapAt(Offset(rect.left + 100, rect.top + 60));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
        contains('2026-10-11'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow week reveals today after entry refresh and width changes',
      (tester) async {
    ListeningTrendsSnapshot capture(int day) =>
        ListeningTrendsSnapshot.fromDaily(
            dailyMilliseconds: {}, capturedAt: DateTime(2026, 10, day, 12));
    final sunday = capture(11);
    await mount(tester, width: 420, scale: 1.5, snapshot: sunday);
    void expectVisible(int weekday) {
      final chart = tester.getRect(_key('statistics-trends-chart'));
      final viewport = tester.getRect(_key('statistics-trends-week-scroll'));
      final selectedX = chart.left + chart.width * (weekday - .5) / 7;
      expect(selectedX, greaterThanOrEqualTo(viewport.left));
      expect(selectedX, lessThanOrEqualTo(viewport.right));
      expect(tester.binding.transientCallbackCount, 0);
    }

    expectVisible(7);
    Future<void> refresh(ListeningTrendsSnapshot snapshot) async {
      await tester.pumpWidget(listeningStatusHost(
          SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatisticsListeningTrends(snapshot: snapshot))),
          scale: 1.5));
      await tester.pumpAndSettle();
    }

    await refresh(capture(12));
    expectVisible(1);
    await refresh(sunday);
    expectVisible(7);
    tester.view.physicalSize = const Size(360, 1000);
    await tester.pumpAndSettle();
    expectVisible(7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'integrated week renders four languages in wide and narrow large layouts',
      (tester) async {
    final boundary = GlobalKey();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final wide in [true, false]) {
        await mount(tester,
            width: wide ? 1100 : 420,
            scale: wide ? 1 : 1.5,
            boundary: boundary);
        await tester.ensureVisible(_key('statistics-trends-chart'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = Platform.environment['DAN_CALENDAR_WEEK_RENDER_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File(
                      '$output/${language.name}-${wide ? 'wide' : 'narrow'}-calendar-week.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
