import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

class _PaintCounter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xfffefefe));
  }

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  testWidgets(
      'deblur preserves the horizontal mass of a fractionally scaled row',
      (tester) async {
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final source = Transform.scale(
      scale: .8 * 1.24 / 1.34,
      alignment: Alignment.centerLeft,
      child: const Opacity(
        opacity: .64,
        child: Text('Line 1',
            style: TextStyle(
                fontFamily: danEmbeddedFontFamily,
                fontSize: 29.48,
                color: Color(0xffffffff),
                height: 1.3)),
      ),
    );
    Widget surface(double sigma, bool precision) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 400,
                height: 120,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20.25),
                    child: precision
                        ? LyricFractionalFilter(
                            sigma: sigma, dpr: 1.25, child: source)
                        : ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                                sigmaX: sigma, sigmaY: sigma),
                            child: source),
                  ),
                ),
              ),
            ),
          ),
        );
    Future<double> center() async => (await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.25);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          var mass = 0.0, moment = 0.0;
          for (var i = 0; i < bytes.length; i += 4) {
            final weight = bytes[i + 3];
            mass += weight;
            moment += weight * ((i ~/ 4) % image.width);
          }
          image.dispose();
          return moment / mass;
        }))!;
    for (final precision in [false, true]) {
      final centers = <double>[];
      for (final sigma in [1.2, .5, .1]) {
        await tester.pumpWidget(surface(sigma, precision));
        centers.add(await center());
      }
      for (final center in centers.skip(1)) {
        expect(center, closeTo(centers.first, .05),
            reason: 'Blur strength must not move the sampled text origin');
      }
    }
  });
  test('physical source alignment preserves position across DPI and axis scale',
      () {
    for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
      for (final scale in [.75, 1.0, 1.3, -1.25]) {
        for (final offset in [-100.41, -1.5, -.00001, 0.0, .5, 20.21, 501.37]) {
          final matrix = Matrix4.translationValues(offset, offset + .231, 0)
            ..scaleByDouble(scale, scale * .8, 1, 1);
          final remainder = lyricFilterRemainder(matrix, dpr);
          for (final values in [
            (matrix[12], matrix[0], remainder.dx),
            (matrix[13], matrix[5], remainder.dy),
          ]) {
            final (origin, axisScale, fraction) = values;
            final anchor = (origin - axisScale * fraction) * dpr;
            expect(anchor, closeTo(anchor.roundToDouble(), 1e-9));
            expect(anchor + axisScale * fraction * dpr,
                closeTo(origin * dpr, 1e-9));
            expect((axisScale * fraction * dpr).abs(), lessThanOrEqualTo(.5));
          }
        }
      }
    }
  });

  test('slow positions remain continuous across integer and half-pixel origins',
      () {
    const dpr = 1.25;
    const scale = 1.3;
    var previous = double.negativeInfinity;
    for (var index = 0; index <= 160; index++) {
      final expected = -2.0 + index * .025;
      final matrix = Matrix4.translationValues(0, expected / dpr, 0)
        ..scaleByDouble(1, scale, 1, 1);
      final remainder = lyricFilterRemainder(matrix, dpr).dy;
      // Model the renderer's integer-source path plus sampled fractional shift.
      final actual = (expected - remainder * scale * dpr).roundToDouble() +
          remainder * scale * dpr;
      expect(actual, closeTo(expected, 1e-10));
      expect(actual, greaterThan(previous));
      previous = actual;
    }
    expect(lyricFilterRemainder(Matrix4.identity(), dpr), Offset.zero);
  });

  test('complex or singular transforms leave the original filter geometry', () {
    for (final matrix in [
      Matrix4.rotationZ(.02),
      Matrix4.identity()..setEntry(0, 1, .01),
      Matrix4.identity()..setEntry(3, 1, .01),
      Matrix4.diagonal3Values(0, 1, 1),
      Matrix4.identity()..setEntry(0, 3, double.nan),
    ]) {
      expect(lyricFilterRemainder(matrix, 1.25), Offset.zero);
    }
  });

  testWidgets('scope repaints cached rows without rebuilding or relayout',
      (tester) async {
    final sourceKey = GlobalKey();
    final counter = _PaintCounter();
    var layouts = 0;
    final source = LayoutBuilder(builder: (_, constraints) {
      layouts++;
      return SizedBox(
          key: sourceKey,
          width: 120,
          height: 40,
          child: CustomPaint(painter: counter));
    });
    final leaf =
        RepaintBoundary(child: ScopedLyricFractionalFilter(child: source));
    Widget surface(double offset, double sigma, int tick) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
                offset: Offset(20.25, offset),
                child: LyricFractionalFilterScope(
                    sigma: sigma,
                    dpr: 1.25,
                    enabled: true,
                    repaintToken: tick,
                    child: leaf))));
    await tester.pumpWidget(surface(30.4, .1, 0));
    final render = sourceKey.currentContext!.findRenderObject();
    final layoutCount = layouts;
    var previousPaints = counter.paints;
    for (final step in [(30.7, 1.2, 1), (31.1, .5, 2), (31.4, .1, 3)]) {
      await tester.pumpWidget(surface(step.$1, step.$2, step.$3));
      expect(counter.paints, previousPaints + 1);
      previousPaints = counter.paints;
      expect(layouts, layoutCount);
      expect(sourceKey.currentContext!.findRenderObject(), same(render));
      expect(tester.getTopLeft(find.byKey(sourceKey)), Offset(20.25, step.$1));
    }
    await tester.pump();
    expect(counter.paints, previousPaints);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manual scroll refreshes fractional source without a follow clock',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final counter = _PaintCounter();
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 400,
                height: 160,
                child: SingleChildScrollView(
                    controller: controller,
                    child: SizedBox(
                        height: 1000,
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: LyricFractionalFilterScope(
                                sigma: .1,
                                dpr: 1.25,
                                enabled: true,
                                repaintToken: 0,
                                child: RepaintBoundary(
                                    child: ScopedLyricFractionalFilter(
                                        child: SizedBox(
                                            width: 120,
                                            height: 80,
                                            child: CustomPaint(
                                                painter: counter))))))))))));
    final paints = counter.paints;
    controller.jumpTo(7.5);
    await tester.pump();
    expect(counter.paints, greaterThan(paints));
    final scrollPaints = counter.paints;
    await tester.pump();
    expect(counter.paints, scrollPaints);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disabled filter keeps hit testing and descendant identity',
      (tester) async {
    final filterKey = GlobalKey();
    final sourceKey = GlobalKey();
    var taps = 0;
    Widget surface(bool enabled) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20.35, top: 31.21),
              child: LyricFractionalFilter(
                key: filterKey,
                sigma: 0,
                dpr: 1.25,
                enabled: enabled,
                child: GestureDetector(
                  key: sourceKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(width: 120, height: 40),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(surface(true));
    final source = sourceKey.currentContext!.findRenderObject();
    final origin = tester.getTopLeft(find.byKey(sourceKey));
    for (final enabled in [false, true, false]) {
      await tester.pumpWidget(surface(enabled));

      expect(sourceKey.currentContext!.findRenderObject(), same(source));
      expect(tester.getTopLeft(find.byKey(sourceKey)), origin);
      await tester.tap(find.byKey(sourceKey));
      await tester.pump();
    }
    expect(taps, 3);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('axis scale and rotation keep child layout and paint valid',
      (tester) async {
    final key = GlobalKey();
    final counter = _PaintCounter();
    Widget surface(Matrix4 matrix) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
            alignment: Alignment.topLeft,
            child: Transform(
                transform: matrix,
                child: LyricFractionalFilter(
                    sigma: .1,
                    dpr: 1.5,
                    child: SizedBox(
                        key: key,
                        width: 80,
                        height: 30,
                        child: CustomPaint(painter: counter))))));
    for (final matrix in [
      Matrix4.translationValues(30.23, 21.36, 0)
        ..scaleByDouble(.75, 1.25, 1, 1),
      Matrix4.rotationZ(math.pi / 12)
    ]) {
      await tester.pumpWidget(surface(matrix));
      expect(tester.getSize(find.byKey(key)), const Size(80, 30));
      expect(tester.takeException(), isNull);
    }
    expect(counter.paints, greaterThan(0));
  });
}
