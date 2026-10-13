import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart' as language;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _maximumSigma = 8.0;

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
                                sigmaX: _maximumSigma, sigmaY: _maximumSigma),
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
  final resolved = filter.filterConfig
      .resolve(ImageFilterContext(bounds: Offset.zero & filter.size));
  final dynamic gaussian = filter.enabled ? filter.layer!.filter : resolved;
  final x = gaussian.sigmaX as double;
  final y = gaussian.sigmaY as double;
  final mode = gaussian.tileMode as ui.TileMode?;
  expect(y, x);
  expect(gaussian.bounds, isNull,
      reason: 'The static Gaussian samples the source; its output clips own '
          'the clear boundary instead of bounding away the input halo');
  expect(gaussian, ui.ImageFilter.blur(sigmaX: x, sigmaY: y, tileMode: mode),
      reason: 'The actual painted layer resolves the independent Gaussian '
          'kernel sigma=($x,$y)');
  return x;
}

void _expectPhysicalKernels(
    Iterable<RenderBackdropFilter> filters, double dpr) {
  for (final filter in filters) {
    expect(filter.enabled, _paintedSigma(filter) * dpr >= .1,
        reason: 'Only effective physical Gaussian kernels enter composition');
    if (filter.enabled) {
      expect(filter.layer, isA<BackdropFilterLayer>());
      expect(filter.layer!.filter, isNotNull,
          reason:
              'Every enabled Gaussian is present in the actual painted layer');
    }
  }
}

void _expectBackdropAncestors(List<RenderBackdropFilter> filters) {
  for (final filter in filters.where((filter) => filter.enabled)) {
    expect(filter.layer, isNotNull,
        reason: 'An enabled local blur owns its actual painted layer');
    for (Layer? ancestor = filter.layer!.parent;
        ancestor != null;
        ancestor = ancestor.parent) {
      expect(ancestor, isNot(isA<ShaderMaskLayer>()),
          reason: 'A ShaderMask ancestor isolates the local glass from the '
              'composited lyric/background and changes live raster caching');
    }
  }
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

class _ColourBackground extends CustomPainter {
  const _ColourBackground();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0.0; y < size.height; y += 4) {
      for (var x = 0.0; x < size.width; x += 4) {
        paint.color = ((x ~/ 4 + y ~/ 4) % 2 == 0)
            ? const Color(0xffe03030)
            : const Color(0xff2060e8);
        canvas.drawRect(Rect.fromLTWH(x, y, 4, 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ColourBackground oldDelegate) => false;
}

/// The real source-future consumer sits above a separate colourful player
/// background. Empty probes lie in the blur bands and outside lyric ink.
class _ContentSurface {
  final boundary = GlobalKey();
  final contentKey = GlobalKey();
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
  final positions = StreamController<double>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  Future<Lyric?>? future;
  Object source = Object();

  Widget host({bool backgroundOnly = false, double opacity = 1}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 420,
                height: 480,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _ColourBackground()),
                    if (!backgroundOnly)
                      Opacity(
                        opacity: opacity,
                        child: ChangeNotifierProvider.value(
                          value: settings,
                          child: VerticalLyricContent(
                            key: contentKey,
                            lyricFuture: future,
                            sourceIdentity: source,
                            positionStream: positions.stream,
                            readPosition: () => 12,
                            onSeek: (_) => fail('No seek is requested'),
                            hidden: hidden,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  List<RenderBackdropFilter> filters(WidgetTester tester) => tester
      .renderObjectList<RenderBackdropFilter>(find.descendant(
          of: find.byKey(contentKey), matching: find.byType(BackdropFilter)))
      .toList(growable: false);

  void dispose() {
    settings.dispose();
    positions.close();
    hidden.dispose();
  }
}

void _expectUnchangedBackground(
    _Pixels actual, _Pixels background, String phase) {
  expect((actual.width, actual.height), (background.width, background.height));
  for (var offset = 3; offset < actual.bytes.length; offset += 4) {
    if (actual.bytes[offset] != 255) {
      fail('$phase erased the opaque player background at '
          '(${offset ~/ 4 % actual.width},${offset ~/ 4 ~/ actual.width})');
    }
  }
  // Local glass deliberately filters everything below its top/bottom bands,
  // including the checker background. Bare-background equality inside those
  // bands incorrectly required the old shader isolation. The clear centre
  // must remain exact; narrow side probes avoid source glyphs in every state.
  for (final row in [const (210, 216), const (250, 256)]) {
    for (var y = row.$1; y < row.$2; y++) {
      for (var x = 4; x < 8; x++) {
        final offset = (y * actual.width + x) * 4;
        for (var channel = 0; channel < 4; channel++) {
          expect(actual.bytes[offset + channel],
              background.bytes[offset + channel],
              reason: '$phase: clear centre background at ($x,$y) '
                  'channel=$channel must remain unchanged');
        }
      }
    }
  }
}

void _expectRetainedMask(
    WidgetTester tester,
    _ContentSurface surface,
    List<RenderBackdropFilter> original,
    List<BackdropFilterLayer?> layers,
    String phase) {
  final current = surface.filters(tester);
  expect(current, hasLength(24), reason: '$phase keeps one fixed mask');
  _expectBackdropAncestors(current);
  for (var index = 0; index < 24; index++) {
    expect(current[index], same(original[index]),
        reason: '$phase retains native band render ownership');
    expect(current[index].layer, same(layers[index]),
        reason: '$phase retains the painted native backdrop layer');
  }
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
      expect(filters, hasLength(24));
      _expectBackdropAncestors(filters);
      _expectPhysicalKernels(filters, dpr);
      for (final band in [filters.take(12), filters.skip(12)]) {
        final sigma = band.map(_paintedSigma).toList();
        expect(sigma.first, greaterThan(0));
        for (var index = 1; index < sigma.length; index++) {
          expect(sigma[index], greaterThan(sigma[index - 1]));
        }
        expect(sigma.last, inExclusiveRange(7.9, _maximumSigma),
            reason: 'The full band gradually approaches the stronger maximum');
      }
      await _finish(tester);
    });
  }

  for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('physically ineffective blur preserves clear pixels at ${dpr}x',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(640 * dpr, 480 * dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final surface = _Surface(tester);
      addTearDown(surface.reading.dispose);
      await tester.pumpWidget(surface.host(enabled: false));
      final clear = await _capture(tester, surface.boundary, dpr: dpr);
      await tester.pumpWidget(surface.host());
      final original = surface.filters(tester);
      expect(original, hasLength(24));
      _expectPhysicalKernels(original, dpr);
      _expectBackdropAncestors(original);

      // A native Gaussian smaller than .1 physical pixels can become an
      // identity/empty pass. Omit it before composition instead of replacing
      // the backdrop or painting the same translucent ink a second time.
      surface.reading.value = .099 / (_maximumSigma * dpr);
      await tester.pump();
      final current = surface.filters(tester);
      expect(current, hasLength(24));
      for (var index = 0; index < current.length; index++) {
        expect(current[index], same(original[index]),
            reason: 'Near-zero hover retains the fixed band ownership');
        expect(current[index].enabled, isFalse,
            reason: 'No ineffective native kernel enters composition');
      }
      expect((await _capture(tester, surface.boundary, dpr: dpr)).bytes,
          orderedEquals(clear.bytes),
          reason: 'An omitted physical kernel keeps the complete clear image');
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
    expect(filters, hasLength(24));
    _expectPhysicalKernels(filters, tester.view.devicePixelRatio);
    expect(positions.hasListener, isTrue);
    await tester.pumpAndSettle();
    await _finish(tester);
  });

  testWidgets(
      'source changes retain one mask over a colourful player background',
      (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = _ContentSurface();
    addTearDown(surface.dispose);
    await tester.pumpWidget(surface.host(backgroundOnly: true));
    final background = await _capture(tester, surface.boundary);
    surface.future = Future<Lyric?>.value(_Lyrics());
    await tester.pumpWidget(surface.host());
    await tester.pumpAndSettle();
    final filters = surface.filters(tester);
    expect(filters, hasLength(24));
    final layers = [for (final filter in filters) filter.layer];

    // A full-opacity FadeTransition can elide its temporary buffer. The
    // player's actual source consumer must retain the same backdrop scope.
    for (final opacity in [254 / 255, 1.0]) {
      await tester.pumpWidget(surface.host(opacity: opacity));
      _expectRetainedMask(
          tester, surface, filters, layers, 'ancestor opacity=$opacity');
      _expectUnchangedBackground(await _capture(tester, surface.boundary),
          background, 'ancestor opacity=$opacity');
    }

    Future<void> sample(String phase) async {
      var previous = 0;
      for (final elapsed in [16, 159, 160, 161, 319, 320]) {
        await tester.pump(Duration(milliseconds: elapsed - previous));
        previous = elapsed;
        _expectRetainedMask(
            tester, surface, filters, layers, '$phase at ${elapsed}ms');
        _expectUnchangedBackground(await _capture(tester, surface.boundary),
            background, '$phase at ${elapsed}ms');
      }
    }

    final pending = Completer<Lyric?>();
    surface.future = pending.future;
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    await sample('A to pending');
    pending.complete(_Lyrics());
    await tester.pump();
    await sample('pending to B');

    surface.future = Future<Lyric?>.value(null);
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    await sample('B to empty lyric result');
    surface.future = null;
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    await sample('empty result to no lyric source');

    // Live frames subscribe in the engine's error Zone. An error Future
    // created in the guarded test Zone cannot deliver onError across it.
    // Create and complete this real failure in the same frame Zone as the
    // FutureBuilder, without suppressing or replacing its error result.
    for (final outcome in [
      (StateError('fixture lookup failed'), '歌词加载失败，请切换来源或重试'),
      (const InstrumentalLyric(), InstrumentalLyric.message),
    ]) {
      late final Completer<Lyric?> failed;
      tester.binding.addPostFrameCallback((_) => failed = Completer<Lyric?>());
      tester.binding.scheduleFrame();
      await tester.pump();
      surface.future = failed.future;
      surface.source = Object();
      await tester.pumpWidget(surface.host());
      await tester.pump();
      tester.binding
          .addPostFrameCallback((_) => failed.completeError(outcome.$1));
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(find.text(language.ui(outcome.$2)), findsOneWidget,
          reason: 'The real lookup outcome must display its own presentation');
      await sample('lookup outcome: ${outcome.$2}');
    }
    await _finish(tester);
  });

  testWidgets(
      'rapid sources ignore late results and release document manual mode',
      (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = _ContentSurface();
    addTearDown(surface.dispose);
    await tester.pumpWidget(surface.host(backgroundOnly: true));
    final background = await _capture(tester, surface.boundary);
    surface.future = Future<Lyric?>.value(_Lyrics());
    await tester.pumpWidget(surface.host());
    await tester.pumpAndSettle();
    final filters = surface.filters(tester);
    expect(filters, hasLength(24));

    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(find.byKey(surface.contentKey)),
        scrollDelta: const Offset(0, 72)));
    await tester.pump();
    expect(
        tester
            .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
            .enabled,
        isFalse,
        reason: 'Actual manual scrolling disables the fixed blur');
    final manual = surface.filters(tester);
    for (var index = 0; index < 24; index++) {
      expect(manual[index], same(filters[index]));
      expect(manual[index].enabled, isFalse);
    }
    _expectUnchangedBackground(
        await _capture(tester, surface.boundary), background, 'manual reading');

    final pending = Completer<Lyric?>();
    surface.future = pending.future;
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    await tester.pump(const Duration(milliseconds: 16));
    final mask =
        tester.widget<LyricViewportBlur>(find.byType(LyricViewportBlur));
    expect(mask.enabled, isTrue,
        reason:
            'The new source cannot inherit the outgoing document manual mode');
    final current = surface.filters(tester);
    for (var index = 0; index < 24; index++) {
      expect(current[index], same(filters[index]));
    }
    // Enabling after deliberate manual-disable owns fresh native layers;
    // future changes from this point must keep that exact ownership.
    final layers = [for (final filter in current) filter.layer];
    final destination = _Lyrics();
    surface.future = Future<Lyric?>.value(destination);
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    await tester.pump(const Duration(milliseconds: 16));
    final late = _Lyrics();
    pending.complete(late);
    await tester.pump();
    var previous = 16;
    for (final elapsed in [16, 80, 159, 160, 161, 239, 319, 320]) {
      await tester.pump(Duration(milliseconds: elapsed - previous));
      previous = elapsed;
      _expectRetainedMask(tester, surface, filters, layers,
          'rapid replacement at ${elapsed}ms');
      _expectUnchangedBackground(await _capture(tester, surface.boundary),
          background, 'rapid replacement at ${elapsed}ms');
      expect(
          find.byWidgetPredicate((widget) =>
              widget is VerticalLyricScrollView &&
              identical(widget.lyric, late)),
          findsNothing,
          reason: 'An obsolete lookup cannot publish its lyric or blur owner');
    }
    expect(
        find.byWidgetPredicate((widget) =>
            widget is VerticalLyricScrollView &&
            identical(widget.lyric, destination)),
        findsOneWidget);
    expect(
        tester
            .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
            .reading,
        same(mask.reading),
        reason: 'Rapid source replacement keeps the original reading clock');

    // A derived lookup for this same authored source retains its live scroll
    // view and manual mode while pending. Its terminal empty result releases
    // only that document ownership, leaving the host mask/clock in place.
    final heldScroll = find.byWidgetPredicate((widget) =>
        widget is VerticalLyricScrollView &&
        identical(widget.lyric, destination));
    final heldState = tester.state(heldScroll);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(find.byKey(surface.contentKey)),
        scrollDelta: const Offset(0, 72)));
    await tester.pump();
    expect(
        tester
            .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
            .enabled,
        isFalse);
    final sameOwner = surface.source;
    final sameSourcePending = Completer<Lyric?>();
    surface.future = sameSourcePending.future;
    await tester.pumpWidget(surface.host());
    for (final duration in [16, 143, 161]) {
      await tester.pump(Duration(milliseconds: duration));
      expect(surface.source, same(sameOwner));
      expect(tester.state(heldScroll), same(heldState));
      final waitingMask =
          tester.widget<LyricViewportBlur>(find.byType(LyricViewportBlur));
      expect(waitingMask.enabled, isFalse,
          reason: 'A pending same-source projection preserves manual reading');
      expect(waitingMask.reading, same(mask.reading));
      final waitingFilters = surface.filters(tester);
      expect(waitingFilters, hasLength(24));
      for (var index = 0; index < 24; index++) {
        expect(waitingFilters[index], same(filters[index]));
        expect(waitingFilters[index].enabled, isFalse);
      }
      _expectUnchangedBackground(await _capture(tester, surface.boundary),
          background, 'same-source manual pending');
    }
    sameSourcePending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text(language.ui('无歌词')), findsOneWidget,
        reason:
            'The completed null lookup reaches the real terminal presentation');
    // The child commits its terminal snapshot before the deferred host
    // notification can rebuild the already-built outer mask.
    await tester.pump();
    final terminalMask =
        tester.widget<LyricViewportBlur>(find.byType(LyricViewportBlur));
    expect(terminalMask.enabled, isTrue,
        reason: 'A terminal empty source cannot keep an obsolete manual owner');
    expect(terminalMask.reading, same(mask.reading));
    final terminalFilters = surface.filters(tester);
    expect(terminalFilters, hasLength(24));
    for (var index = 0; index < 24; index++) {
      expect(terminalFilters[index], same(filters[index]));
    }
    _expectPhysicalKernels(terminalFilters, tester.view.devicePixelRatio);
    _expectUnchangedBackground(await _capture(tester, surface.boundary),
        background, 'same-source terminal empty');
    await tester.pumpAndSettle();
    await _finish(tester);
  });

  testWidgets(
      'hover continues across sources and hiding preserves its blur pose',
      (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = _ContentSurface();
    addTearDown(surface.dispose);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 550));
    addTearDown(mouse.removePointer);
    await tester.pumpWidget(surface.host(backgroundOnly: true));
    final background = await _capture(tester, surface.boundary);
    surface.future = Future<Lyric?>.value(_Lyrics());
    await tester.pumpWidget(surface.host());
    await tester.pumpAndSettle();
    final filters = surface.filters(tester);
    final layers = [for (final filter in filters) filter.layer];
    final reading = tester
        .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
        .reading;
    expect(reading.value, 1);
    await mouse.moveTo(tester.getCenter(find.byKey(surface.contentKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final partial = reading.value;
    expect(partial, inExclusiveRange(0.0, 1.0));

    final pending = Completer<Lyric?>();
    surface.future = pending.future;
    surface.source = Object();
    await tester.pumpWidget(surface.host());
    expect(
        tester
            .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
            .reading,
        same(reading));
    expect(reading.value, partial,
        reason: 'The source switch cannot restart the in-flight hover clock');
    pending.complete(_Lyrics());
    await tester.pump();
    expect(reading.value, partial);
    await tester.pump(const Duration(milliseconds: 20));
    final beforeHidden = reading.value;
    expect(beforeHidden, greaterThan(0));
    expect(beforeHidden, lessThan(partial),
        reason:
            'The original hover keeps advancing through loading/source arrival');
    _expectRetainedMask(
        tester, surface, filters, layers, 'source arrived mid-hover');
    _expectUnchangedBackground(await _capture(tester, surface.boundary),
        background, 'source arrived mid-hover');

    surface.hidden.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(reading.value, beforeHidden,
        reason: 'A hidden window freezes its already-painted fixed mask');
    _expectRetainedMask(tester, surface, filters, layers, 'hidden hover');
    expect(tester.binding.transientCallbackCount, 0);
    surface.hidden.value = false;
    await tester.pump();
    expect(reading.value, beforeHidden,
        reason: 'The first restored frame reuses the held blur pose');
    expect(
        tester
            .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
            .reading,
        same(reading));
    await tester.pump(const Duration(milliseconds: 120));
    expect(reading.value, 0);
    expect(surface.filters(tester).every((filter) => !filter.enabled), isTrue);
    _expectUnchangedBackground(await _capture(tester, surface.boundary),
        background, 'completed hover after restore');
    await mouse.moveTo(const Offset(600, 550));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(reading.value, 1);
    _expectPhysicalKernels(
        surface.filters(tester), tester.view.devicePixelRatio);
    await tester.pumpAndSettle();
    await _finish(tester);
  });
}
