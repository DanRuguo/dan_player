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
      for (var offset = 0; offset <= 180; offset++)
        listeningDayKey(DateTime(2026, 10, 3 - offset)): (offset + 1) * 60000,
    }, capturedAt: DateTime(2026, 10, 3, 14));

dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: _key('statistics-trends-chart'),
        matching: find.byType(CustomPaint)))
    .painter;

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<ListeningTrendsSnapshot> mount(WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 900);
    final snapshot = _snapshot();
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: StatisticsListeningTrends(snapshot: snapshot)))));
    await tester.pumpAndSettle();
    return snapshot;
  }

  for (final scenario in [
    ('period', 'calendar-week'),
    ('period', 'period-30'),
    ('series', 'series-previous'),
  ]) {
    testWidgets('deferred trend ${scenario.$2} selection retires on page exit',
        (tester) async {
      final snapshot = await mount(tester);
      await tester.tap(_key('statistics-trends-${scenario.$1}'));
      await tester.pumpAndSettle();
      final item = _key('statistics-trends-${scenario.$2}');
      expect(item.hitTestable(), findsOneWidget);

      // Material closes the menu now but dispatches its action post-frame.
      // Remove the page before that frame; do not call onPressed directly.
      await tester.tap(item);
      expect(_painter(tester).data, same(snapshot.comparisons[7]));
      expect(_painter(tester).showCurrent, isTrue);
      await tester.pumpWidget(listeningStatusHost(const SizedBox.shrink()));
      expect(find.byType(StatisticsListeningTrends), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
