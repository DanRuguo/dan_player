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

  testWidgets('layer and child origins stay zero under nonzero layout offset',
      (tester) async {
    final filterKey = GlobalKey();
    final childKey = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 21.25, top: 30.4),
          child: LyricFractionalFilter(
            key: filterKey,
            sigma: 1.2,
            dpr: 1.25,
            child: RepaintBoundary(
              key: childKey,
              child: const SizedBox(width: 120, height: 40),
            ),
          ),
        ),
      ),
    ));
    final row = filterKey.currentContext!.findRenderObject()! as RenderBox;
    final source = childKey.currentContext!.findRenderObject()! as RenderBox;
    final outer = row.debugLayer! as TransformLayer;
    final filter = outer.firstChild! as ImageFilterLayer;
    final child = filter.firstChild! as OffsetLayer;
    expect(row.isRepaintBoundary, isFalse);
    expect(outer.offset, Offset.zero);
    expect(filter.offset, Offset.zero);
    expect(child.offset, Offset.zero);
    expect(source.localToGlobal(Offset.zero), const Offset(21.25, 30.4));
    final fraction = lyricFilterRemainder(row.getTransformTo(null), 1.25);
    expect(outer.transform![12] + fraction.dx, closeTo(21.25, 1e-9));
    expect(outer.transform![13] + fraction.dy, closeTo(30.4, 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll, blur, DPI and zero-crossing updates retain source cache',
      (tester) async {
    final filterKey = GlobalKey();
    final sourceKey = GlobalKey();
    final counter = _PaintCounter();
    final source = RepaintBoundary(
      key: sourceKey,
      child: SizedBox(
          width: 120, height: 40, child: CustomPaint(painter: counter)),
    );
    Widget surface(double offset, double sigma, double dpr) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(0, offset),
              child: LyricFractionalFilter(
                key: filterKey,
                sigma: sigma,
                dpr: dpr,
                child: source,
              ),
            ),
          ),
        );
    await tester.pumpWidget(surface(20, 0, 1));
    final row = filterKey.currentContext!.findRenderObject()!;
    final outer = row.debugLayer! as TransformLayer;
    final initialFilter = outer.firstChild! as ImageFilterLayer;
    final initialSource = sourceKey.currentContext!.findRenderObject()!;
    final paints = counter.paints;
    for (final args in [(20.4, 1.2, 1.25), (21.0, .0, 1.0), (21.6, 2.4, 2.0)]) {
      await tester.pumpWidget(surface(args.$1, args.$2, args.$3));
      expect(row.debugLayer, same(outer));
      expect(outer.firstChild, same(initialFilter));
      expect(sourceKey.currentContext!.findRenderObject(), same(initialSource));
      expect(counter.paints, paints,
          reason: 'Moving/filtering a row must not repaint its cached source');
      expect(initialFilter.offset, Offset.zero);
    }
    await tester.pumpWidget(surface(20, 0, 1));
    expect(
        initialFilter.imageFilter,
        ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(sigmaX: .1, sigmaY: .1),
            inner: ui.ImageFilter.matrix(Matrix4.identity().storage,
                filterQuality: ui.FilterQuality.low)),
        reason: 'An exact integer endpoint retains the clear filter path');
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
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
      final row = filterKey.currentContext!.findRenderObject()!;
      expect(row.debugLayer, enabled ? isA<TransformLayer>() : isNull);
      expect(sourceKey.currentContext!.findRenderObject(), same(source));
      expect(tester.getTopLeft(find.byKey(sourceKey)), origin);
      await tester.tap(find.byKey(sourceKey));
      await tester.pump();
    }
    expect(taps, 3);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('axis scale compensates in local units and rotation falls back',
      (tester) async {
    final key = GlobalKey();
    Widget surface(Matrix4 matrix) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform(
              transform: matrix,
              child: LyricFractionalFilter(
                key: key,
                sigma: 0,
                dpr: 1.5,
                child: const SizedBox(width: 80, height: 30),
              ),
            ),
          ),
        );
    final matrix = Matrix4.translationValues(30.23, 21.36, 0)
      ..scaleByDouble(.75, 1.25, 1, 1);
    await tester.pumpWidget(surface(matrix));
    final row = key.currentContext!.findRenderObject()!;
    final outer = row.debugLayer! as TransformLayer;
    final fraction = lyricFilterRemainder(row.getTransformTo(null), 1.5);
    expect(outer.transform![12], closeTo(-fraction.dx, 1e-9));
    expect(outer.transform![13], closeTo(-fraction.dy, 1e-9));
    await tester.pumpWidget(surface(Matrix4.rotationZ(math.pi / 12)));
    final filter = outer.firstChild! as ImageFilterLayer;
    expect(outer.transform, Matrix4.identity());
    expect(
        filter.imageFilter,
        ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(sigmaX: .1, sigmaY: .1),
            inner: ui.ImageFilter.matrix(Matrix4.identity().storage,
                filterQuality: ui.FilterQuality.low)));
    expect(tester.takeException(), isNull);
  });
}
