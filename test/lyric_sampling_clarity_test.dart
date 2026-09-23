import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fractional lyric sampling retains small glyph edge contrast',
      (tester) async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    const source = Text('ここにいるよ 奇迹 lyrics',
        style: TextStyle(
            fontFamily: danEmbeddedFontFamily,
            fontSize: 29.48,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: Colors.white));
    Widget surface(int mode) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                    width: 550,
                    height: 120,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 20.5, top: 25.5),
                        child: switch (mode) {
                          0 => source,
                          1 => Transform.translate(
                              offset: const Offset(-.5, -.5),
                              child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.compose(
                                      outer: ui.ImageFilter.blur(
                                          sigmaX: .1, sigmaY: .1),
                                      inner: ui.ImageFilter.matrix(
                                          Matrix4.translationValues(.5, .5, 0)
                                              .storage,
                                          filterQuality: ui.FilterQuality.low)),
                                  child: source)),
                          _ => const LyricFractionalFilter(
                              sigma: .1, dpr: 1, child: source),
                        })))));
    Future<({double contrast, double mass})> measure() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final rgba =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        var energy = 0.0, gradient = 0.0, mass = 0.0;
        for (var y = 1; y < image.height - 1; y++) {
          for (var x = 1; x < image.width - 1; x++) {
            final index = (y * image.width + x) * 4 + 3;
            final alpha = rgba[index].toDouble();
            final dx = alpha - rgba[index - 4];
            final dy = alpha - rgba[index - image.width * 4];
            gradient += dx * dx + dy * dy;
            energy += alpha * alpha;
            mass += alpha;
          }
        }
        return (contrast: gradient / energy, mass: mass);
      } finally {
        image.dispose();
      }
    }

    final results = <({double contrast, double mass})>[];
    for (var mode = 0; mode < 3; mode++) {
      await tester.pumpWidget(surface(mode));
      await tester.pumpAndSettle();
      results.add((await tester.runAsync(measure))!);
    }
    final [vector, previous, current] = results;
    // Normalize by alpha energy: changing opacity alone cannot pass this
    // check. Half-pixel translation is the old bilinear path's worst case.
    expect(current.contrast, greaterThan(previous.contrast * 1.20));
    expect(current.contrast, greaterThan(vector.contrast * .80));
    expect(current.contrast, lessThan(vector.contrast * 1.15),
        reason: 'Do not replace softness with aliased or sharpened glyphs');
    expect(current.mass / previous.mass, inInclusiveRange(.90, 1.10),
        reason: 'Improved edges must retain the original stroke weight');
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
