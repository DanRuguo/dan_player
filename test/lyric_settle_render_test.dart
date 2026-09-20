import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spring has one bounded visible return with a quiet endpoint', () {
    for (final distance in [40.0, 80.0, 200.0, 4000.0]) {
      final curve =
          LyricMotion.scrollCurveFor(spring: true, distance: distance);
      final peak = curve.transform(.66);
      expect((peak - 1) * distance, inInclusiveRange(2.3, 8.001));
      var previous = peak;
      for (var frame = 67; frame <= 100; frame++) {
        final value = curve.transform(frame / 100);
        expect(value, inInclusiveRange(1, previous));
        previous = value;
      }
      expect((curve.transform(.999) - 1) * distance, lessThan(.001));
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    }
  });
  testWidgets('completed follow keeps identical glyph sampling after cleanup',
      (tester) async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final key = GlobalKey();
    Widget surface(bool completed, {double scale = 1}) => Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
            key: key,
            child: ColoredBox(
                color: const Color(0xff535362),
                child: Center(
                    child: Transform.translate(
                        offset: const Offset(.35, .65),
                        child: SizedBox(
                            width: 420,
                            height: 100,
                            child: LyricFollowEffects(
                              clock: const AlwaysStoppedAnimation(1),
                              blur: 0,
                              transition: completed
                                  ? null
                                  : const LyricFollowTransition(
                                      distance: 85,
                                      delay: 0,
                                      curve: LyricMotion.scrollCurve,
                                      initialOffset: 0,
                                      initialBlur: 1.2,
                                      finalBlur: 0),
                              child: Transform.scale(
                                  scale: scale,
                                  alignment: Alignment.centerLeft,
                                  child: const Text('Sunshine Girl 阳光女孩',
                                      style: TextStyle(
                                          fontFamily: danEmbeddedFontFamily,
                                          fontSize: 35.2,
                                          color: Color(0xffaad9f0)))),
                            )))))));
    Future<Uint8List> pixels() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1.25);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    await tester.pumpWidget(surface(false));
    final before = await tester.runAsync(pixels);
    await tester.pumpWidget(surface(true));
    final after = await tester.runAsync(pixels);
    var changed = 0;
    for (var i = 0; i < before!.length; i++) {
      if (before[i] != after![i]) changed++;
    }
    expect(changed, 0,
        reason:
            'Completing the animation must not switch glyph rasterization paths');
    await tester.pumpWidget(surface(true, scale: .9999999999));
    final almostRest = await tester.runAsync(pixels);
    await tester.pumpWidget(surface(true));
    final rest = await tester.runAsync(pixels);
    expect(rest, orderedEquals(almostRest!),
        reason: 'Reaching the identity scale must not snap the glyph origin');
  });
}
