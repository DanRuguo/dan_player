import 'dart:ui' as raster;

import 'package:crypto/crypto.dart';
import 'package:dan_player/component/statistics_comparison_lines.dart';
import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

// Captured from the pre-cache painter in the same Skia test engine.
const _baselineRasters = [
  '3a679ea7ef943414c983c1d9da22c794bfa73dcc539a84b9b19ea9baec759d0b',
  '490c35e3db46b60d2874b6fd9d325c7699cd401a0a9c65bd40d0f54ca47294d7',
  'eaec0c4e51b8f78ac746de69b04a434e7cabe1803ae020e0bdc4f4fa6b43d1cb',
  '17a8b1e87748ebc76797540497d529bd69b1d08f15d47445b51bb9a086076a7a',
  '7310ba6728e278fd71d508910fedd8fc9a48fe0db92acd020341444ab7dee675',
  '60b80ab3f5e0823ef7afbcfef2c35f0a1de1f1a147dfa5315c4db27f9db1fa19',
  'cba27554906c22f7d140785af5c15f0cc3edb8f1f1d07e79c628ad2cb0a5d2d3',
  '4b488abe8648749f8d664aeba83963f724317653df4080bed9b8e7c43ef2dbee',
  'fc1ebc2f22219a58b6d000105231378a89f4dcaec622764ded1efd53e08940df',
  '314f045607ca25a2b840da869e9501571883fb75f5e5273c1b10a0e85f323ef2',
  'fad514239d1792b8045c9f62ddf4abcd79c35fbfba0299d5b8fd11c8477c67ca',
  'ffb39a362cdbbb6b38889cb313c41c6acef83f6a4a769f23fec6823e6dd42d58',
];

Future<String> _render(StatisticsComparisonLineGeometry geometry, int series,
    int selection) async {
  final recorder = raster.PictureRecorder();
  geometry.paint(Canvas(recorder),
      selection: selection,
      currentColor: const Color(0xff007c80),
      previousColor: const Color(0xff516a94),
      gridColor: const Color(0xffd0dadd),
      showCurrent: series != 1,
      showPrevious: series != 0);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
      geometry.size.width.toInt(), geometry.size.height.toInt());
  try {
    final bytes =
        await image.toByteData(format: raster.ImageByteFormat.rawRgba);
    return sha256.convert(bytes!.buffer.asUint8List()).toString();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: _key('statistics-trends-chart'),
        matching: find.byType(CustomPaint)))
    .painter;
ListeningTrendsSnapshot _snapshot({int factor = 1, bool equalMax = false}) =>
    ListeningTrendsSnapshot.fromDaily(dailyMilliseconds: {
      for (var offset = 1; offset <= 180; offset++)
        listeningDayKey(DateTime(2026, 10, 7 - offset)):
            factor * (equalMax ? 7 - (offset - 1) % 7 : offset % 8 + 1) * 60000,
    }, capturedAt: DateTime(2026, 10, 7));

void main() {
  var baseline = 0;
  for (final count in [7, 90]) {
    for (final centered in [false, true]) {
      for (var series = 0; series < 3; series++) {
        final expected = _baselineRasters[baseline++];
        test('cached plot matches pre-change pixels $count/$centered/$series',
            () async {
          final geometry = StatisticsComparisonLineGeometry(
              centered ? const Size(294, 160) : const Size(1000, 160),
              count: count,
              maximum: 120,
              current: (index) => index % 9 * 13,
              previous: (index) => index % 7 * 19,
              centerSlots: centered);
          expect(await _render(geometry, series, count ~/ 2), expected);
        });
      }
    }
  }
  test('ninety selections and curve toggles never reread retained points',
      () async {
    var reads = 0;
    num point(int index) {
      reads++;
      return index % 9 * 13;
    }

    final geometry = StatisticsComparisonLineGeometry(const Size(1000, 160),
        count: 90, maximum: 120, current: point, previous: point);
    expect(reads, 180);
    for (var selection = 0; selection < 90; selection++) {
      await _render(geometry, selection % 3, selection);
    }
    expect(reads, 180);
  });
  test('empty and zero-total plots remain finite at small sizes', () async {
    for (final size in [const Size(1, 1), const Size(23, 23)]) {
      final geometry = StatisticsComparisonLineGeometry(size,
          count: 1, maximum: 0, current: (_) => 0, previous: (_) => 0);
      expect(await _render(geometry, 2, 0), hasLength(64));
    }
    var reads = 0;
    final recorder = raster.PictureRecorder();
    StatisticsComparisonLineGeometry(const Size(100, 160),
            count: 0,
            maximum: 0,
            current: (_) => ++reads,
            previous: (_) => ++reads)
        .paint(Canvas(recorder),
            selection: 0,
            currentColor: Colors.teal,
            previousColor: Colors.blue,
            gridColor: Colors.grey);
    recorder.endRecording().dispose();
    expect(reads, 0);
  });
  test('per-series maxima belong to the frozen comparison', () {
    final comparison = _snapshot().comparisons[7]!;
    int maximum(List<ListeningTrendDay> days) =>
        days.map((day) => day.milliseconds).reduce((a, b) => a > b ? a : b);
    expect(comparison.currentMaximumDailyMilliseconds,
        maximum(comparison.current));
    expect(comparison.previousMaximumDailyMilliseconds,
        maximum(comparison.previous));
    final empty = ListeningTrendsSnapshot.fromDaily(
            dailyMilliseconds: {}, capturedAt: DateTime(2026, 10, 7))
        .calendarWeek;
    expect((
      empty.currentMaximumDailyMilliseconds,
      empty.previousMaximumDailyMilliseconds
    ), (
      0,
      0
    ));
  });
  test('a hidden series far above the visible scale has bounded geometry',
      () async {
    var reads = 0;
    final geometry = StatisticsComparisonLineGeometry(const Size(1000, 160),
        count: 90, maximum: 1, current: (index) {
      reads++;
      return index % 2;
    }, previous: (index) {
      reads++;
      return index % 2 * 1000000000000;
    });
    expect(reads, 180);
    expect(await _render(geometry, 0, 89), hasLength(64));
    expect(reads, 180);
  });

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  Future<void> mount(WidgetTester tester, ListeningTrendsSnapshot snapshot,
      {double width = 1080, double scale = 1, Color seed = Colors.teal}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: StatisticsListeningTrends(snapshot: snapshot))),
        seed: seed,
        scale: scale));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String control, String value) async {
    await tester.tap(_key('statistics-trends-$control'));
    await tester.pumpAndSettle();
    await tester.tap(_key('statistics-trends-$value'));
    await tester.pumpAndSettle();
  }

  testWidgets('pointer keyboard and semantics reuse geometry until refresh',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, _snapshot());
      await menu(tester, 'period', 'period-90');
      final original = _painter(tester).geometry;
      final rect = tester.getRect(_key('statistics-trends-chart'));
      final mouse =
          await tester.createGesture(kind: raster.PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.center);
      for (var index = 0; index < 90; index++) {
        await mouse.moveTo(Offset(
            rect.left + 12 + index * (rect.width - 24) / 89, rect.center.dy));
        await tester.pump();
        expect(_painter(tester).geometry, same(original));
        expect(_painter(tester).selection, index);
      }
      await mouse.removePointer();
      await tester.tapAt(rect.center);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      final node =
          tester.getSemantics(_key('statistics-trends-chart-semantics'));
      node.owner!.performAction(node.id, raster.SemanticsAction.increase);
      await tester.pump();
      expect(_painter(tester).selection, 1);
      expect(_painter(tester).geometry, same(original));
      await mount(tester, _snapshot(factor: 2));
      expect(_painter(tester).geometry, isNot(same(original)));
      expect(_painter(tester).selection, 89);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('palette language and equal-scale curve toggles reuse geometry',
      (tester) async {
    final snapshot = _snapshot(equalMax: true);
    await mount(tester, snapshot);
    final original = _painter(tester).geometry;
    for (final series in ['current', 'previous', 'both']) {
      await menu(tester, 'series', 'series-$series');
      expect(_painter(tester).geometry, same(original));
    }
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await mount(tester, snapshot, seed: Colors.amber);
      expect(_painter(tester).geometry, same(original));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'a different visible maximum replaces geometry and keeps the date',
      (tester) async {
    await mount(tester, _snapshot());
    final original = _painter(tester).geometry;
    final maximum = _painter(tester).maximum;
    await menu(tester, 'series', 'series-previous');
    expect(_painter(tester).geometry, isNot(same(original)));
    expect(_painter(tester).maximum, lessThan(maximum));
    expect(_painter(tester).selection, 6);
  });
  testWidgets('resize scale and strict-week positioning replace geometry',
      (tester) async {
    final snapshot = _snapshot();
    await mount(tester, snapshot);
    final rolling = _painter(tester).geometry;
    await menu(tester, 'period', 'calendar-week');
    final week = _painter(tester).geometry;
    expect(week, isNot(same(rolling)));
    expect(_painter(tester).selection, 2);
    uiLanguage.value = UiLanguage.en;
    await mount(tester, snapshot, width: 360, scale: 2);
    final narrow = _painter(tester).geometry;
    expect(narrow, isNot(same(week)));
    expect(narrow.size.width, 588);
    await mount(tester, snapshot, width: 360, scale: 2);
    expect(_painter(tester).geometry, same(narrow));
    expect(_painter(tester).selection, 2);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
