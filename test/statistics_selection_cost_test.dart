import 'dart:ui' as raster;

import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

Future<List<int>> _chartPixels(WidgetTester tester, GlobalKey boundary) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final chart = tester.getRect(_key('statistics-trends-chart'));
  final origin = render.localToGlobal(Offset.zero);
  return (await tester.runAsync(() async {
    final image = await render.toImage();
    try {
      final bytes =
          (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final left = (chart.left - origin.dx).round();
      final top = (chart.top - origin.dy).round();
      return [
        for (var y = top; y < top + chart.height.round(); y++)
          ...bytes.sublist((y * image.width + left) * 4,
              (y * image.width + left + chart.width.round()) * 4),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('date inspection repaints without rebuilding static statistics',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    final semantics = tester.ensureSemantics();
    try {
      final boundary = GlobalKey();
      final snapshot = ListeningTrendsSnapshot.fromDaily(dailyMilliseconds: {
        for (var offset = 1; offset <= 14; offset++)
          listeningDayKey(DateTime(2026, 10, 7 - offset)): offset * 60000,
      }, capturedAt: DateTime(2026, 10, 7));
      await tester.pumpWidget(listeningStatusHost(
          SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: StatisticsListeningTrends(snapshot: snapshot))),
          boundary: boundary));
      await tester.pumpAndSettle();
      final initialPixels = await _chartPixels(tester, boundary);
      final rect = tester.getRect(_key('statistics-trends-chart'));
      var staticBuilds = 0;
      final previousObserver = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousObserver?.call(element, builtOnce);
        if (element.widget is StatisticsListeningTrends) {
          staticBuilds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousObserver);

      final mouse =
          await tester.createGesture(kind: raster.PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.center);
      for (var day = 0; day < 7; day++) {
        await mouse.moveTo(Offset(
            rect.left + 12 + day * (rect.width - 24) / 6, rect.center.dy));
        await tester.pump();
        expect(
            tester.widget<Text>(_key('statistics-trends-selected-day')).data,
            contains(
                listeningDayKey(snapshot.comparisons[7]!.current[day].date)));
        final node =
            tester.getSemantics(_key('statistics-trends-chart-semantics'));
        expect(
            node.value,
            contains(
                listeningDayKey(snapshot.comparisons[7]!.current[day].date)));
        if (day == 0) {
          expect(await _chartPixels(tester, boundary), isNot(initialPixels),
              reason:
                  'The painted marker must follow inspection without a rebuild');
        }
      }
      expect(await _chartPixels(tester, boundary), initialPixels,
          reason:
              'Returning to the initial date must preserve exact plot pixels');
      await mouse.removePointer();
      await tester.tapAt(rect.center);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      final node =
          tester.getSemantics(_key('statistics-trends-chart-semantics'));
      node.owner!.performAction(node.id, raster.SemanticsAction.increase);
      await tester.pump();
      expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
          contains(listeningDayKey(snapshot.comparisons[7]!.current[1].date)));
      expect(staticBuilds, 0,
          reason:
              'Hover, keyboard and semantics only change the plot and date detail');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
}
