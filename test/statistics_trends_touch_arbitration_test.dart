import 'dart:ui' as raster;

import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

ListeningTrendsSnapshot _snapshot() =>
    ListeningTrendsSnapshot.fromDaily(dailyMilliseconds: {
      for (var offset = 1; offset <= 14; offset++)
        listeningDayKey(DateTime(2026, 10, 3 - offset)): offset * 60000,
    }, capturedAt: DateTime(2026, 10, 3));

int _selection(WidgetTester tester) {
  final dynamic painter = tester
      .widget<CustomPaint>(find.descendant(
          of: _key('statistics-trends-chart'),
          matching: find.byType(CustomPaint)))
      .painter;
  return painter.selection as int;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, ScrollController scroll,
      FocusNode previousFocus) async {
    sizePlaylistFeature(tester, width: 1080, height: 900);
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        controller: scroll,
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Focus(
                  focusNode: previousFocus,
                  child: const Text('Previously focused page control')),
              StatisticsListeningTrends(snapshot: _snapshot()),
              const SizedBox(height: 1000),
            ])))));
    await tester.pumpAndSettle();
    previousFocus.requestFocus();
    await tester.pump();
    expect(previousFocus.hasFocus, isTrue);
    expect(_selection(tester), 6);
  }

  testWidgets('cancelled chart touch retains the date and existing page focus',
      (tester) async {
    final scroll = ScrollController();
    final focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    await mount(tester, scroll, focus);
    final chart = tester.getRect(_key('statistics-trends-chart'));
    final touch = await tester.startGesture(
        Offset(chart.left + 12, chart.center.dy),
        kind: raster.PointerDeviceKind.touch);
    // A slow touch reaches the tap-down deadline before the system cancels it.
    await tester.pump(const Duration(milliseconds: 180));
    await touch.cancel();
    await tester.pumpAndSettle();
    expect((_selection(tester), focus.hasFocus), (6, true));
    expect(scroll.offset, 0);

    // A committed touch still selects the date and grants keyboard navigation.
    await tester.tapAt(Offset(chart.left + 12, chart.center.dy));
    await tester.pump();
    expect((_selection(tester), focus.hasFocus), (0, false));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page drag from chart retains the date and existing page focus',
      (tester) async {
    final scroll = ScrollController();
    final focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    await mount(tester, scroll, focus);
    final chart = tester.getRect(_key('statistics-trends-chart'));
    final touch = await tester.startGesture(
        Offset(chart.left + 12, chart.center.dy),
        kind: raster.PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 180));
    await touch.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 30));
    await touch.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 30));
    await touch.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(50));
    expect((_selection(tester), focus.hasFocus), (6, true));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
