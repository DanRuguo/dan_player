import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Pixels {
  const _Pixels(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;

  int ink(int x, int y) => 255 - bytes[(y * width + x) * 4];

  Uint8List rows(int first, int end) =>
      Uint8List.sublistView(bytes, first * width * 4, end * width * 4);
}

Future<_Pixels> _capture(WidgetTester tester, GlobalKey boundary,
        {double dpr = 1}) async =>
    (await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: dpr);
      try {
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return _Pixels(Uint8List.fromList(bytes!.buffer.asUint8List()),
            image.width, image.height);
      } finally {
        image.dispose();
      }
    }))!;

/// Native, narrow ink strokes give each Gaussian a known sharp source. This
/// stays independent of lyric font shaping and of the production blur ramp.
class _Strokes extends CustomPainter {
  const _Strokes({this.opaque = true});
  final bool opaque;

  @override
  void paint(Canvas canvas, Size size) {
    if (opaque) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }
    final ink = Paint()..color = Colors.black;
    for (var x = 20.0; x < size.width - 10; x += 20) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), ink);
    }
  }

  @override
  bool shouldRepaint(_Strokes oldDelegate) => opaque != oldDelegate.opaque;
}

class _Surface {
  _Surface(WidgetTester tester)
      : reading = AnimationController(vsync: tester, value: 1);

  final boundary = GlobalKey();
  final viewport = GlobalKey();
  final AnimationController reading;

  Widget host({
    bool enabled = true,
    bool opaqueSource = true,
    double opacity = 1,
    double top = .25,
    double bottom = .25,
    Size size = const Size(240, 240),
    bool gaussianReference = false,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox.fromSize(
              size: size,
              child: ColoredBox(
                color: Colors.white,
                child: Opacity(
                  opacity: opacity,
                  child: gaussianReference
                      ? ClipRect(
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                                sigmaX: LyricMotion.blurForDistance(2),
                                sigmaY: LyricMotion.blurForDistance(2)),
                            child: CustomPaint(
                                painter: _Strokes(opaque: opaqueSource)),
                          ),
                        )
                      : LyricViewportBlur(
                          key: viewport,
                          enabled: enabled,
                          topFraction: top,
                          bottomFraction: bottom,
                          reading: reading,
                          child: CustomPaint(
                              painter: _Strokes(opaque: opaqueSource)),
                        ),
                ),
              ),
            ),
          ),
        ),
      );

  List<RenderBackdropFilter> filters(WidgetTester tester) => tester
      .renderObjectList<RenderBackdropFilter>(find.descendant(
        of: find.byKey(viewport),
        matching: find.byType(BackdropFilter),
      ))
      .toList();
}

double _paintedSigma(RenderBackdropFilter filter) {
  // These are public getters on this SDK's resolved Gaussian object. Profile
  // can omit dart:ui toString implementations, so text is not a kernel API.
  final dynamic gaussian = filter.layer!.filter;
  final x = gaussian.sigmaX as double;
  final y = gaussian.sigmaY as double;
  final mode = gaussian.tileMode as ui.TileMode?;
  expect(y, x);
  expect(gaussian.bounds, isNull,
      reason: 'The static Gaussian samples the source; its output clips own '
          'the clear boundary instead of bounding away the input halo');
  expect(filter.layer!.filter,
      ui.ImageFilter.blur(sigmaX: x, sigmaY: y, tileMode: mode),
      reason: 'The actual painted layer resolves the independent Gaussian '
          'kernel sigma=($x,$y)');
  return x;
}

double _variance(_Pixels pixels, int start, int end, int y) {
  var mass = 0.0, moment = 0.0, squareMoment = 0.0;
  for (var x = start; x < end; x++) {
    final ink = pixels.ink(x, y).toDouble();
    mass += ink;
    moment += ink * x;
    squareMoment += ink * x * x;
  }
  expect(mass, greaterThan(0), reason: 'The original ink is still visible');
  final center = moment / mass;
  return squareMoment / mass - center * center;
}

/// Use the backend's independent Gaussian to identify visible halo pixels.
/// A fixed far-away sample can quantize to zero on Windows, especially during
/// an opacity entrance. The complete local distribution must still widen;
/// merely fading the strokes or replacing the band with grey cannot pass.
void _expectDiffusion(_Pixels actual, _Pixels clear, _Pixels gaussian,
    double logicalY, double dpr, String reason) {
  expect(actual.width, clear.width);
  expect(actual.width, gaussian.width);
  expect(actual.height, gaussian.height);
  final y = (logicalY * dpr).floor();
  for (var stroke = 20.0; stroke < actual.width / dpr - 10; stroke += 20) {
    final start = ((stroke - 6) * dpr).floor();
    final end = ((stroke + 8) * dpr).ceil();
    var referenceHalo = 0, actualHalo = 0, peak = 0;
    final actualProfile = <int>[];
    final referenceProfile = <int>[];
    for (var x = start; x < end; x++) {
      final value = actual.ink(x, y);
      actualProfile.add(value);
      referenceProfile.add(gaussian.ink(x, y));
      if (value > peak) peak = value;
      if (clear.ink(x, y) == 0 && gaussian.ink(x, y) > 0) {
        referenceHalo += gaussian.ink(x, y);
        actualHalo += value;
      }
    }
    final diagnostic = '$reason stroke=$stroke DPR=$dpr '
        'actual=$actualProfile Gaussian=$referenceProfile';
    expect(referenceHalo, greaterThan(0),
        reason:
            'The independent native Gaussian has visible diffusion: $diagnostic');
    expect(actualHalo, greaterThan(0),
        reason: 'Actual blur retains native halo ink: $diagnostic');
    expect(_variance(actual, start, end, y),
        greaterThan(_variance(clear, start, end, y)),
        reason: 'Actual ink spreads instead of just fading: $diagnostic');
    expect(peak, greaterThan(actual.ink(start, y)),
        reason:
            'The band retains stroke structure instead of a grey rectangle: $diagnostic');
    expect(peak, greaterThan(actual.ink(end - 1, y)),
        reason:
            'The original stroke remains distinct from its outer halo: $diagnostic');
  }
}

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          for (var index = 0; index < 8; index++)
            LrcLine(Duration(seconds: index * 5), 'Held lyric $index',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

Future<void> _finish(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets(
        'fixed blur preserves the clear centre and increases outward '
        'at ${dpr}x', (tester) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(640 * dpr, 480 * dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final surface = _Surface(tester);
      addTearDown(surface.reading.dispose);
      await tester.pumpWidget(surface.host(enabled: false));
      final clear = await _capture(tester, surface.boundary, dpr: dpr);
      await tester.pumpWidget(surface.host(gaussianReference: true));
      final gaussian = await _capture(tester, surface.boundary, dpr: dpr);

      // Capture the very first enabled frame: no entrance or delayed timer is
      // allowed to postpone the surface filter until a subsequent frame.
      await tester.pumpWidget(surface.host());
      final blurred = await _capture(tester, surface.boundary, dpr: dpr);
      expect(blurred.rows((60 * dpr).ceil(), (180 * dpr).floor()),
          orderedEquals(clear.rows((60 * dpr).ceil(), (180 * dpr).floor())),
          reason: 'No filtered output enters the configured clear centre');

      for (final top in [true, false]) {
        final peaks = <int>[];
        for (var index = 0; index < 6; index++) {
          final y = top ? 55 - index * 10 : 185 + index * 10;
          peaks.add(blurred.ink((40.5 * dpr).floor(), (y * dpr).floor()));
        }
        expect(peaks.last, lessThan(peaks.first),
            reason: 'The actual ink becomes softer towards the outer edge');
        for (var index = 1; index < peaks.length; index++) {
          expect(peaks[index], lessThanOrEqualTo(peaks[index - 1]),
              reason: 'The Gaussian ramp must not sharpen again inside a band');
        }
        final y = top ? 15 : 225;
        _expectDiffusion(blurred, clear, gaussian, y.toDouble(), dpr,
            'The fixed ${top ? 'top' : 'bottom'} band diffuses original ink');
      }
      final filters = surface.filters(tester);
      expect(filters, hasLength(12));
      for (final filter in filters) {
        expect(filter.enabled, isTrue);
        expect(filter.layer, isA<BackdropFilterLayer>());
        expect(filter.layer!.filter, isNotNull,
            reason: 'The rendered layer, rather than a widget-only setting, '
                'must contain its Gaussian');
      }
      for (final band in [filters.take(6), filters.skip(6)]) {
        final sigma = band.map(_paintedSigma).toList();
        expect(sigma.first, greaterThan(0));
        for (var index = 1; index < 4; index++) {
          expect(sigma[index], greaterThan(sigma[index - 1]));
        }
        expect(sigma[4], LyricMotion.blurForDistance(2));
        expect(sigma[5], LyricMotion.blurForDistance(2),
            reason: 'The outer third already reaches the full configured blur');
      }
      await _finish(tester);
    });
  }

  testWidgets('positive blur replaces sharp ink during a transparent entrance',
      (tester) async {
    final surface = _Surface(tester);
    addTearDown(surface.reading.dispose);
    for (final opacity in [.25, .5, .9]) {
      await tester.pumpWidget(
          surface.host(enabled: false, opaqueSource: false, opacity: opacity));
      final clear = await _capture(tester, surface.boundary);
      await tester.pumpWidget(surface.host(
          gaussianReference: true, opaqueSource: false, opacity: opacity));
      final gaussian = await _capture(tester, surface.boundary);
      await tester
          .pumpWidget(surface.host(opaqueSource: false, opacity: opacity));
      final firstFrame = await _capture(tester, surface.boundary);
      final actualCentre = firstFrame.rows(60, 180);
      final clearCentre = clear.rows(60, 180);
      for (var channel = 0; channel < actualCentre.length; channel++) {
        // Introducing the opacity saveLayer may change RGB rounding by one;
        // the accepted rendering contract keeps the alpha and ink geometry.
        expect((actualCentre[channel] - clearCentre[channel]).abs(),
            lessThanOrEqualTo(channel % 4 == 3 ? 0 : 2));
      }
      for (final y in [15, 225]) {
        expect(firstFrame.ink(40, y), lessThan(clear.ink(40, y)),
            reason: 'The sharp stroke must be replaced during the fade, '
                'without waiting for Opacity to reach one');
        _expectDiffusion(firstFrame, clear, gaussian, y.toDouble(), 1,
            'The transparent entrance at opacity=$opacity diffuses its source');
      }
    }
    await _finish(tester);
  });

  testWidgets('reading retraces the viewport and zero blur stays byte exact',
      (tester) async {
    final surface = _Surface(tester);
    addTearDown(surface.reading.dispose);
    await tester.pumpWidget(surface.host(enabled: false));
    final clear = await _capture(tester, surface.boundary);
    await tester.pumpWidget(surface.host());
    final blurred = await _capture(tester, surface.boundary);
    final forward = <double, Uint8List>{};
    for (final value in [.8, .5, .2, .0001, 0.0]) {
      surface.reading.value = value;
      await tester.pump();
      final pixels = await _capture(tester, surface.boundary);
      forward[value] = pixels.bytes;
      for (var alpha = 3; alpha < pixels.bytes.length; alpha += 4) {
        expect(pixels.bytes[alpha], clear.bytes[alpha],
            reason: 'A positive or nearly-zero blur must never erase the '
                'opaque lyric surface (reading=$value, pixel=${alpha ~/ 4})');
      }
      expect(pixels.rows(60, 180), orderedEquals(clear.rows(60, 180)));
    }
    expect(forward[0], orderedEquals(clear.bytes),
        reason: 'Zero sigma restores all original pixels, without grey bands');
    expect(surface.filters(tester).every((filter) => !filter.enabled), isTrue);
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect((await _capture(tester, surface.boundary)).bytes,
          orderedEquals(clear.bytes),
          reason: 'The clear endpoint remains unchanged for the next 240ms');
    }
    for (final value in [.2, .5, .8]) {
      surface.reading.value = value;
      await tester.pump();
      expect((await _capture(tester, surface.boundary)).bytes,
          orderedEquals(forward[value]!),
          reason: 'Equal reading poses retrace every actual viewport pixel');
    }
    surface.reading.value = 1;
    await tester.pump();
    expect((await _capture(tester, surface.boundary)).bytes,
        orderedEquals(blurred.bytes));
    await tester.pumpWidget(surface.host(enabled: false));
    expect((await _capture(tester, surface.boundary)).bytes,
        orderedEquals(clear.bytes));
    await _finish(tester);
  });

  testWidgets('blur follows the remaining lyric height when the spectrum grows',
      (tester) async {
    final surface = _Surface(tester);
    addTearDown(surface.reading.dispose);
    for (final height in [240.0, 180.0, 300.0]) {
      final size = Size(240, height);
      await tester.pumpWidget(surface.host(enabled: false, size: size));
      final clear = await _capture(tester, surface.boundary);
      await tester
          .pumpWidget(surface.host(size: size, gaussianReference: true));
      final gaussian = await _capture(tester, surface.boundary);
      await tester.pumpWidget(surface.host(size: size));
      final blurred = await _capture(tester, surface.boundary);
      expect(blurred.height, height.toInt());
      expect(
          blurred.rows((height * .25).ceil(), (height * .75).floor()),
          orderedEquals(
              clear.rows((height * .25).ceil(), (height * .75).floor())),
          reason: 'The clear centre uses the current lyric viewport height');
      final y = (height * .06).floor();
      expect(blurred.ink(40, y), lessThan(clear.ink(40, y)));
      _expectDiffusion(blurred, clear, gaussian, y.toDouble(), 1,
          'The resized lyric viewport height=$height has actual Gaussian ink');
    }
    await _finish(tester);
  });

  testWidgets(
      'a presented lyric keeps its surface mounted through minimization',
      (tester) async {
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    final hidden = ValueNotifier(false);
    final positions = StreamController<double>.broadcast(sync: true);
    final future = Future<Lyric?>.value(_Lyrics());
    addTearDown(settings.dispose);
    addTearDown(hidden.dispose);
    addTearDown(positions.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 480,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: VerticalLyricContent(
                lyricFuture: future,
                sourceIdentity: future,
                positionStream: positions.stream,
                readPosition: () => 12,
                onSeek: (_) {},
                hidden: hidden,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scroll = find.byType(VerticalLyricScrollView);
    final mounted = tester.state(scroll);
    expect(positions.hasListener, isTrue);
    hidden.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll, findsOneWidget,
        reason: 'Hiding must stop clocks without fading out the mounted lyric');
    expect(tester.state(scroll), same(mounted));
    expect(positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = false;
    await tester.pump();
    expect(tester.state(scroll), same(mounted),
        reason: 'Restoring must reuse the same glyph/cache/scroll ownership');
    final blur =
        tester.widget<LyricViewportBlur>(find.byType(LyricViewportBlur));
    expect(blur.enabled, isTrue,
        reason: 'The restored first frame does not wait for the entry motion');
    expect(blur.reading.value, 1);
    final filters = tester
        .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter));
    expect(filters.where((filter) => filter.enabled), hasLength(12));
    expect(positions.hasListener, isTrue);
    await tester.pumpAndSettle();
    await _finish(tester);
  });
}
