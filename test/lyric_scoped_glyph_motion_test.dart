import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<({double x, double y})> center(
    WidgetTester tester, RenderRepaintBoundary boundary, double ratio) async {
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      var mass = 0.0;
      var x = 0.0;
      var y = 0.0;
      for (var row = 0; row < image.height; row++) {
        for (var col = 0; col < image.width; col++) {
          final at = (row * image.width + col) * 4;
          final ink = (765 - data[at] - data[at + 1] - data[at + 2]) / 765;
          if (ink < .02) continue;
          mass += ink;
          x += col * ink;
          y += row * ink;
        }
      }
      return (x: x / mass, y: y / mass);
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });
  for (final ratio in [1.0, 1.25]) {
    testWidgets('production fractional filter steadies glyph ink at ${ratio}x',
        (tester) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap(const {
          'lyricTextAlign': 'left',
          'lyricFontSize': 22,
          'translationFontSize': 18,
          'showLyricTimestamps': false,
          'showLyricTranslation': false,
          'showLyricRomanization': false,
        }),
      );
      addTearDown(settings.dispose);
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 140,
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ChangeNotifierProvider.value(
                      value: settings,
                      child: LyricFractionalFilterScope(
                        sigma: 0,
                        dpr: ratio,
                        enabled: true,
                        repaintToken: 0,
                        child: LyricViewTile(
                          line: LrcLine(Duration.zero, 'Moonlight 2026',
                              isBlank: false),
                          position: position,
                          opacity: 1,
                          distance: 0,
                          reducedMotion: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final centers = <({double x, double y})>[
        await center(tester, boundary, ratio),
      ];
      settings.increaseFontSize();
      await tester.pump();
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        centers.add(await center(tester, boundary, ratio));
      }
      final xSteps = [
        for (var i = 1; i < centers.length; i++) centers[i].x - centers[i - 1].x
      ];
      final ySteps = [
        for (var i = 1; i < centers.length; i++) centers[i].y - centers[i - 1].y
      ];
      debugPrint(
          'Scoped $ratio x ${xSteps.map((v) => v.toStringAsFixed(3)).join(', ')}');
      debugPrint(
          'Scoped $ratio y ${ySteps.map((v) => v.toStringAsFixed(3)).join(', ')}');
      expect(xSteps.every((step) => step >= -.15 * ratio), isTrue,
          reason: 'Glyph ink must not recoil during font growth');
      expect(ySteps.every((step) => step.abs() < .75 * ratio), isTrue,
          reason: 'No frame may jump by one physical pixel vertically');
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
