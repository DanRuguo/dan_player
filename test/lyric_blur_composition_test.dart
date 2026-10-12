import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _background = Color(0xff627172);
const _foreground = Color(0xffe6f1d8);
const _scale = .6613333333333333;
final _policy = AppFontPolicy.defaults();

String get _renderDirectory =>
    Platform.environment['DAN_LYRIC_BLUR_RENDER_DIR'] ??
    const String.fromEnvironment('DAN_LYRIC_BLUR_RENDER_DIR');

class _Capture {
  const _Capture(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width, height;

  int contrast(int x, int y) {
    final index = (y * width + x) * 4;
    return (rgba[index] - 0x62).abs() +
        (rgba[index + 1] - 0x71).abs() +
        (rgba[index + 2] - 0x72).abs();
  }

  int mass(Rect bounds) {
    var result = 0;
    for (var y = bounds.top.floor().clamp(0, height);
        y < bounds.bottom.ceil().clamp(0, height);
        y++) {
      for (var x = bounds.left.floor().clamp(0, width);
          x < bounds.right.ceil().clamp(0, width);
          x++) {
        result += contrast(x, y);
      }
    }
    return result;
  }

  Offset center(Rect bounds) {
    var mass = 0.0, xMoment = 0.0, yMoment = 0.0;
    for (var y = bounds.top.floor().clamp(0, height);
        y < bounds.bottom.ceil().clamp(0, height);
        y++) {
      for (var x = bounds.left.floor().clamp(0, width);
          x < bounds.right.ceil().clamp(0, width);
          x++) {
        final weight = contrast(x, y).toDouble();
        mass += weight;
        xMoment += (x + .5) * weight;
        yMoment += (y + .5) * weight;
      }
    }
    expect(mass, greaterThan(0));
    return Offset(xMoment / mass, yMoment / mass);
  }
}

Future<_Capture> _capture(
    WidgetTester tester, GlobalKey key, String name,
    {double pixelRatio = 1}) async {
  return (await tester.runAsync(() async {
    final box =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = Uint8List.fromList(data!.buffer.asUint8List());
      if (_renderDirectory.isNotEmpty) {
        final directory = Directory(_renderDirectory).absolute;
        expect(
            directory.path.replaceAll('\\', '/'), contains('/tool/qa-local/'));
        await directory.create(recursive: true);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
      return _Capture(rgba, image.width, image.height);
    } finally {
      image.dispose();
    }
  }))!;
}

Finder _paragraph(GlobalKey key) => find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate((widget) =>
          widget is CustomPaint &&
          widget.painter is PlainLyricWordFollowPainter),
    );

PlainLyricWordFollowPainter _painter(WidgetTester tester, GlobalKey key) =>
    tester.widget<CustomPaint>(_paragraph(key)).painter!
        as PlainLyricWordFollowPainter;

class _Surface {
  _Surface({required this.text, required this.width, this.outerX = 7.936,
    this.dpr = 1});
  final String text;
  final double width, outerX, dpr;
  final boundary = GlobalKey();
  final source = GlobalKey();
  var taps = 0;

  Widget build(double sigma, {bool reference = false}) {
    final paragraph = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => taps++,
      child: BalancedLyricText(
        text,
        key: source,
        wordFollow: true,
        textAlign: TextAlign.left,
        style: const TextStyle(
          fontSize: 28,
          height: 1.35,
          color: _foreground,
        ),
      ),
    );
    // The reference uses Flutter's ordinary Gaussian layer and the unchanged
    // clear sampler. It neither reproduces the production compose expression
    // nor records a second version of the cached paragraph's paint method.
    Widget filtered = LyricFractionalFilter(
      sigma: reference ? 0 : sigma,
      dpr: dpr,
      child: paragraph,
    );
    if (reference && sigma > 0) {
      filtered = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: math.max(.1, sigma) * 1.5,
          sigmaY: math.max(.1, sigma) * 1.5,
        ),
        child: filtered,
      );
    }
    return MaterialApp(
      theme: ThemeData(
        fontFamily: _policy.uiFamily,
        fontFamilyFallback: _policy.fallback,
      ),
      home: AppFontScope(
        policy: _policy,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 900,
              height: 450,
              child: Material(
                color: _background,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding:
                        EdgeInsets.only(left: outerX, top: 161.3003737117513),
                    child: Transform.scale(
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(width: width, child: filtered),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect selection(WidgetTester tester, int start, int end) {
    final painter = _painter(tester, source);
    final boxes = painter.text.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end));
    expect(boxes, isNotEmpty);
    final sourceBox = tester.renderObject<RenderBox>(_paragraph(source));
    final viewport = boundary.currentContext!.findRenderObject()! as RenderBox;
    final transform = sourceBox.getTransformTo(viewport);
    return boxes
        .map((box) => MatrixUtils.transformRect(
            transform, box.toRect().shift(painter.inkOffset)))
        .reduce((a, b) => a.expandToInclude(b));
  }
}

void _equalGaussian(_Capture actual, _Capture reference, Rect source,
    double sigma, String reason) {
  expect(actual.width, reference.width);
  expect(actual.height, reference.height);
  // A source-adjacent Gaussian must retain the same native edge diffusion,
  // including outside the tight paragraph bounds. Comparing only the source
  // box misses the vertical straight edges seen on the Windows composition.
  final bounds = source.inflate(sigma * 6);
  var changed = 0, maximum = 0;
  for (var y = bounds.top.floor().clamp(0, actual.height);
      y < bounds.bottom.ceil().clamp(0, actual.height);
      y++) {
    for (var x = bounds.left.floor().clamp(0, actual.width);
        x < bounds.right.ceil().clamp(0, actual.width);
        x++) {
      final index = (y * actual.width + x) * 4;
      for (var channel = 0; channel < 4; channel++) {
        final delta =
            (actual.rgba[index + channel] - reference.rgba[index + channel])
                .abs();
        if (delta != 0) changed++;
        maximum = math.max(maximum, delta);
      }
    }
  }
  debugPrint('LYRIC_BLUR $reason sigma=$sigma changed=$changed max=$maximum '
      'actualMass=${actual.mass(bounds)} referenceMass=${reference.mass(bounds)}');
  expect(actual.mass(bounds), greaterThan(0),
      reason: 'The original glyphs exist');
  expect(reference.mass(bounds), greaterThan(0));
  expect(changed, 0, reason: reason);
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
  setUpAll(() => ensureAppFontsLoaded(_policy));

  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets('blur and deblur keep the same ink origin at ${dpr}x',
        (tester) async {
      tester.view.physicalSize = Size(900 * dpr, 450 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final surface = _Surface(text: 'makka na fuusen Aeiou xyz', width: 880,
          dpr: dpr);
      const strengths = [0.0, .01, .05, .1, .25, .5, 1.0, 2.0, 4.0];
      final outward = <double, _Capture>{};
      Offset? origin;
      Object? layout;
      Rect? bounds;
      for (final sigma in [...strengths, ...strengths.reversed]) {
        await tester.pumpWidget(surface.build(sigma));
        await tester.pump();
        layout ??= _painter(tester, surface.source).layoutIdentity;
        expect(_painter(tester, surface.source).layoutIdentity, layout);
        bounds ??= surface.selection(tester, 0, surface.text.length).inflate(32);
        final capture = await _capture(tester, surface.boundary,
            'origin-$dpr-$sigma-${outward.containsKey(sigma) ? "reverse" : "forward"}',
            pixelRatio: dpr);
        final physicalBounds = Rect.fromLTRB(bounds.left * dpr,
            bounds.top * dpr, bounds.right * dpr, bounds.bottom * dpr);
        final center = capture.center(physicalBounds);
        origin ??= center;
        debugPrint('LYRIC_BLUR_ORIGIN dpr=$dpr sigma=$sigma '
            'dx=${(center.dx - origin.dx).toStringAsFixed(6)} '
            'dy=${(center.dy - origin.dy).toStringAsFixed(6)}');
        expect((center - origin).distance, lessThan(.25),
            reason: 'Blur changes edge diffusion, never the physical ink origin');
        final forward = outward[sigma];
        if (forward != null) {
          expect(capture.rgba, orderedEquals(forward.rgba),
              reason: 'Reversing blur must retrace the same pixels at each strength');
        } else {
          outward[sigma] = capture;
        }
      }
      await _finish(tester);
    });
  }

  testWidgets('fractional lyric blur preserves natural Latin edge diffusion',
      (tester) async {
    tester.view.physicalSize = const Size(900, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = _Surface(text: 'makka na fuusen Aeiou xyz', width: 880);
    for (final sigma in [2.0, 4.0]) {
      await tester.pumpWidget(surface.build(sigma));
      await tester.pump();
      final painter = _painter(tester, surface.source);
      final paragraph = painter.text;
      final identity = painter.layoutIdentity;
      expect(paragraph.text!.toPlainText(), surface.text);
      expect(paragraph.computeLineMetrics(), hasLength(1));
      final source = surface.selection(tester, 0, surface.text.length);
      final tail = surface.selection(
          tester, surface.text.length - 3, surface.text.length);
      final actual =
          await _capture(tester, surface.boundary, 'latin-$sigma-actual');
      await tester.pumpWidget(surface.build(sigma, reference: true));
      await tester.pump();
      expect(_painter(tester, surface.source).text, same(paragraph));
      expect(_painter(tester, surface.source).layoutIdentity, equals(identity));
      expect(surface.selection(tester, 0, surface.text.length), source);
      final reference = await _capture(
          tester, surface.boundary, 'latin-$sigma-native-gaussian');
      expect(actual.mass(tail), greaterThan(0));
      _equalGaussian(actual, reference, source, sigma,
          'The whole Latin source and the final xyz retain the native Gaussian');
    }
    await _finish(tester);
  });

  testWidgets(
      'fractional lyric blur keeps mixed wrapped tail glyphs at window edge',
      (tester) async {
    tester.view.physicalSize = const Size(900, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final surface = _Surface(
      text: '青い空 Aeiou xyz\n小さな風船 한글 끝',
      width: 340,
      outerX: 620.25,
    );
    const sigma = 2.0;
    await tester.pumpWidget(surface.build(sigma));
    await tester.pump();
    final painter = _painter(tester, surface.source);
    final paragraph = painter.text;
    final identity = painter.layoutIdentity;
    expect(paragraph.text!.toPlainText(), surface.text);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.computeLineMetrics().length, greaterThanOrEqualTo(2));
    final source = surface.selection(tester, 0, surface.text.length);
    final tail =
        surface.selection(tester, surface.text.length - 1, surface.text.length);
    expect(tail.right, lessThan(900 - sigma * 6));
    final actual =
        await _capture(tester, surface.boundary, 'mixed-edge-actual');
    await tester.pumpWidget(surface.build(sigma, reference: true));
    await tester.pump();
    expect(_painter(tester, surface.source).text, same(paragraph));
    expect(_painter(tester, surface.source).layoutIdentity, equals(identity));
    expect(
        surface.selection(tester, surface.text.length - 1, surface.text.length),
        tail);
    final reference =
        await _capture(tester, surface.boundary, 'mixed-edge-native-gaussian');
    expect(actual.mass(tail), greaterThan(0),
        reason: 'The Korean final glyph remains painted');
    _equalGaussian(actual, reference, source, sigma,
        'Wrapped mixed font source remains complete near the right viewport edge');
    await _finish(tester);
  });

  testWidgets(
      'fractional lyric deblur retains paragraph hit semantics and clear pixels',
      (tester) async {
    tester.view.physicalSize = const Size(900, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      final surface = _Surface(text: 'Aeiou 風船 한글 xyz', width: 800);
      await tester.pumpWidget(surface.build(0));
      await tester.pump();
      final paragraphElement = tester.element(_paragraph(surface.source));
      final render = paragraphElement.renderObject;
      final painter = _painter(tester, surface.source);
      final paragraph = painter.text;
      final identity = painter.layoutIdentity;
      final source = surface.selection(tester, 0, surface.text.length);
      final clear =
          await _capture(tester, surface.boundary, 'deblur-original-clear');
      for (final sigma in [4.0, 2.0, .5, 0.0]) {
        await tester.pumpWidget(surface.build(sigma));
        await tester.pump();
        expect(
            tester.element(_paragraph(surface.source)), same(paragraphElement));
        expect(paragraphElement.renderObject, same(render));
        expect(_painter(tester, surface.source).text, same(paragraph));
        expect(
            _painter(tester, surface.source).layoutIdentity, equals(identity));
        expect(surface.selection(tester, 0, surface.text.length), source);
        expect(find.bySemanticsLabel(surface.text), findsOneWidget);
        await tester.tapAt(tester.getCenter(_paragraph(surface.source)));
        await tester.pump();
        expect(surface.taps, [4.0, 2.0, .5, 0.0].indexOf(sigma) + 1);
        final actual =
            await _capture(tester, surface.boundary, 'deblur-$sigma-actual');
        if (sigma == 0) {
          expect(actual.rgba, clear.rgba,
              reason:
                  'Returning to clear must retain the original sampling bytes');
        } else {
          await tester.pumpWidget(surface.build(sigma, reference: true));
          await tester.pump();
          final reference = await _capture(
              tester, surface.boundary, 'deblur-$sigma-native-gaussian');
          _equalGaussian(actual, reference, source, sigma,
              'Focus deblur retains the same paragraph and native Gaussian');
          await tester.pumpWidget(surface.build(sigma));
          await tester.pump();
          // The global-key source survives reparenting into the independent
          // reference, and the actual focus updates retain its own next element.
          expect(_painter(tester, surface.source).text, same(paragraph));
        }
        expect(tester.binding.transientCallbackCount, 0);
      }
      await _finish(tester);
    } finally {
      semantics.dispose();
    }
  });
}
