import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('near-zero lyric blur hands off to clear ink at DPI $dpi',
        (tester) async {
      await (FontLoader(danEmbeddedFontFamily)
            ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
          .load();
      tester.view.devicePixelRatio = dpi;
      tester.view.physicalSize = Size(900 * dpi, 300 * dpi);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundary = GlobalKey();
      const lyric = Text('风吹过街角 Aあ歌词',
          style: TextStyle(
              fontFamily: danEmbeddedFontFamily,
              fontSize: 29.48,
              fontWeight: FontWeight.w800,
              color: Colors.white));
      Widget surface(bool nearZero, double physicalOffset) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                      width: 550,
                      height: 120,
                      child: Padding(
                          padding: const EdgeInsets.only(left: 20, top: 25),
                          child: Transform.translate(
                              offset: Offset(.5 / dpi, physicalOffset / dpi),
                              child: LyricFractionalFilter(
                                  sigma: nearZero ? .000001 : 0,
                                  dpr: dpi,
                                  enabled: true,
                                  repaintToken: (nearZero, physicalOffset),
                                  child: lyric)))))));

      Future<({List<int> alpha, double x, double y, double mass})> capture(
          String stage) async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: dpi);
        try {
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          final alpha = <int>[];
          var mass = 0.0, xMoment = 0.0, yMoment = 0.0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final value = bytes[(y * image.width + x) * 4 + 3];
              alpha.add(value);
              mass += value;
              xMoment += value * x;
              yMoment += value * y;
            }
          }
          final output = Platform.environment['DAN_LYRIC_NEARZERO_RENDER'];
          if (output != null) {
            final file = File('$output/dpi-$dpi-$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
                (await image.toByteData(format: ui.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
          }
          expect(mass, greaterThan(100));
          return (
            alpha: alpha,
            x: xMoment / mass,
            y: yMoment / mass,
            mass: mass
          );
        } finally {
          image.dispose();
        }
      }

      final clearCenters = <({double x, double y})>[];
      for (final offset in [.1, .3, .5, .7, .9]) {
        await tester.pumpWidget(surface(true, offset));
        await tester.pumpAndSettle();
        final near = (await tester.runAsync(() => capture('near-$offset')))!;
        await tester.pumpWidget(surface(false, offset));
        await tester.pumpAndSettle();
        final clear = (await tester.runAsync(() => capture('clear-$offset')))!;
        clearCenters.add((x: clear.x, y: clear.y));
        var difference = 0.0;
        for (var i = 0; i < near.alpha.length; i++) {
          difference += (near.alpha[i] - clear.alpha[i]).abs();
        }
        final normalized = difference / near.mass;
        // This exact frame boundary previously shifted by up to half a pixel
        // and changed 10–17% of ink when zero blur switched to direct paint.
        expect((clear.x - near.x).abs(), lessThan(.08));
        expect((clear.y - near.y).abs(), lessThan(.08));
        expect(normalized, lessThan(.025));
      }
      for (var i = 1; i < clearCenters.length; i++) {
        expect(clearCenters[i].y - clearCenters[i - 1].y,
            inInclusiveRange(.08, .35),
            reason:
                'Slow vertical follow should not stall or jump at DPI $dpi');
      }
    });
  }

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
