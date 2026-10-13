import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('local trend demo ${language.name} narrow=$narrow',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester,
            width: narrow ? 360 : 1080, height: narrow ? 2200 : 1100);
        final hidden = ValueNotifier(false);
        final boundary = GlobalKey();
        addTearDown(hidden.dispose);
        await tester.pumpWidget(listeningStatusHost(
            SingleChildScrollView(
                child: PlayerGuideDemo(
                    kind: PlayerGuideDemoKind.statistics, isHidden: hidden)),
            scale: narrow ? 2 : 1,
            boundary: boundary));
        await tester.pumpAndSettle();
        expect(find.text(ui('试一试：收听趋势')), findsOneWidget);
        expect(find.text(ui('这里使用固定示例记录。可以切换范围和曲线，点按日期或用方向键查看；不会读取或保存你的听歌记录。')),
            findsOneWidget);
        final initial = tester
            .widget<StatisticsListeningTrends>(
                find.byType(StatisticsListeningTrends))
            .snapshot;

        await tester.ensureVisible(_key('statistics-trends-period'));
        await tester.tap(_key('statistics-trends-period'));
        await tester.pumpAndSettle();
        await tester.tap(_key('statistics-trends-period-90'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('statistics-trends-series'));
        await tester.tap(_key('statistics-trends-series'));
        await tester.pumpAndSettle();
        await tester.tap(_key('statistics-trends-series-previous'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('statistics-trends-chart'));
        await tester.pumpAndSettle();
        final chart = tester.getRect(_key('statistics-trends-chart'));
        await tester.tapAt(chart.center);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
            contains('2026-04-10'));
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(tester.widget<Text>(_key('statistics-trends-selected-day')).data,
            contains('2026-07-08'));
        expect(
            tester
                .widget<StatisticsListeningTrends>(
                    find.byType(StatisticsListeningTrends))
                .snapshot,
            same(initial));

        final output = Platform.environment['DAN_GUIDE_STATISTICS_RENDER_DIR'];
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
                      '$output/${language.name}-${narrow ? 'narrow-large' : 'wide'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        hidden.value = true;
        await tester.pumpAndSettle();
        hidden.value = false;
        await tester.pumpAndSettle();
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
