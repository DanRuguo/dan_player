import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_preview.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart' show capturePlaylistFeature;

Future<List<int>> _rgba(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData(
                format: drawing.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList(growable: false);
      } finally {
        image.dispose();
      }
    }))!;

double _inkCenter(List<int> pixels, int width) {
  var weight = 0.0, position = 0.0;
  for (var offset = 0; offset < pixels.length; offset += 4) {
    final ink =
        (765 - pixels[offset] - pixels[offset + 1] - pixels[offset + 2]) *
            pixels[offset + 3] /
            255;
    weight += ink;
    position += (offset ~/ 4 % width) * ink;
  }
  expect(weight, greaterThan(10000),
      reason: 'Actual glyph ink must be present');
  return position / weight;
}

List<TextPainter> _mainPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<PlainLyricWordFollowPainter>()
    .map((painter) => painter.text)
    .toList();

DesktopLyricTextPainter _previewPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<DesktopLyricTextPainter>()
    .single;

Widget _host(Widget child, {bool layout = true, bool reduced = false}) =>
    MaterialApp(
      theme: ThemeData(
          fontFamily: AppFontPolicy.defaults().uiFamily,
          fontFamilyFallback: AppFontPolicy.defaults().fallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: AppFontScope(
        policy: AppFontPolicy.defaults(),
        child: MotionPreferencesScope(
          preferences: MotionPreferences(
              disabled: layout ? const {} : {MotionKind.layout}),
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  testWidgets('spacing in one lyric line changes actual ink from early frames',
      (tester) async {
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance)
      ..lyricTextAlign = LyricTextAlign.left;
    final position = ValueNotifier(Duration.zero);
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(position.dispose);
    final line = LrcLine(Duration.zero, '音乐伴每一天', isBlank: false);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(ChangeNotifierProvider.value(
      value: controller,
      child: RepaintBoundary(
        key: boundary,
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: 600,
            child: LyricViewTile(
                line: line,
                position: position,
                opacity: 1,
                distance: 0,
                reducedMotion: false),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(boundary));
    final before = await _rgba(tester, boundary);
    final sourceElement = find.byType(CustomPaint).evaluate().singleWhere(
        (element) => (element.widget as CustomPaint).painter
            is PlainLyricWordFollowPainter);
    final source = (sourceElement.widget as CustomPaint).painter!
        as PlainLyricWordFollowPainter;
    final paragraph = source.text;
    final nativeInput = (
      text: paragraph.text!.toPlainText(),
      width: paragraph.width,
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.ellipsis,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    );
    final baseStyle = paragraph.text!.style!;
    final policy = AppFontScope.of(sourceElement);
    final boundaryRender =
        boundary.currentContext!.findRenderObject()! as RenderBox;
    final sourceTransform =
        sourceElement.renderObject!.getTransformTo(boundaryRender).storage;
    final sourceInkOffset = source.inkOffset;
    const requestedDelta = 8.0;

    // Shape an independent native paragraph in this fixture only. It never
    // supplies the production animation's endpoints or paints through its
    // glyph-morph implementation. Prove the captured style/origin at t=0 before
    // using it to check the intermediate and final raster.
    Future<List<int>> nativeRgba(double progress) async {
      final reference = TextPainter(
        text: appFontSpan(nativeInput.text,
            style: baseStyle.copyWith(
                letterSpacing:
                    (baseStyle.letterSpacing ?? 0) + requestedDelta * progress),
            policy: policy),
        textAlign: nativeInput.textAlign,
        textDirection: nativeInput.textDirection,
        textScaler: nativeInput.textScaler,
        locale: nativeInput.locale,
        strutStyle: nativeInput.strutStyle,
        maxLines: nativeInput.maxLines,
        ellipsis: nativeInput.ellipsis,
        textWidthBasis: nativeInput.textWidthBasis,
        textHeightBehavior: nativeInput.textHeightBehavior,
      )..layout(minWidth: nativeInput.width, maxWidth: nativeInput.width);
      try {
        return (await tester.runAsync(() async {
          final recorder = drawing.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(Colors.white, BlendMode.src)
            ..clipRect(Offset.zero & size, doAntiAlias: false)
            ..transform(sourceTransform)
            ..translate(sourceInkOffset.dx, sourceInkOffset.dy);
          reference.paint(canvas, Offset.zero);
          final picture = recorder.endRecording();
          final image =
              picture.toImageSync(size.width.round(), size.height.round());
          try {
            return (await image.toByteData(
                    format: drawing.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List()
                .toList(growable: false);
          } finally {
            image.dispose();
            picture.dispose();
          }
        }))!;
      } finally {
        reference.dispose();
      }
    }

    double progressAt(Duration elapsed) => LyricMotion.curve.transform(
        elapsed.inMicroseconds / LyricMotion.lineDuration.inMicroseconds);
    expect(await nativeRgba(0), before,
        reason: 'The independent paragraph must first reproduce the exact '
            'original font, shaping, paint origin and glyph pixels');
    await capturePlaylistFeature(
        tester, boundary, 'spacing-visible-main-start');
    controller.setLyricLetterSpacing(requestedDelta);
    await tester.pump();
    final zero = await _rgba(tester, boundary);
    expect(zero, before,
        reason: 'Zero progress preserves the exact existing glyph raster');
    final endpoints = _mainPainters(tester);
    expect(endpoints, hasLength(2));
    expect(endpoints.first.computeLineMetrics(), hasLength(1));
    expect(endpoints.last.computeLineMetrics(), hasLength(1));
    await tester.pump(const Duration(milliseconds: 16));
    final early = await _rgba(tester, boundary);
    expect(early, isNot(before),
        reason: 'A spacing-only change must not reuse the font-size late '
            'handoff that leaves the old glyphs completely static');
    expect(tester.getSize(find.byKey(boundary)), size);
    expect(_mainPainters(tester), endpoints);
    final startX = _inkCenter(before, size.width.round());
    final earlyX = _inkCenter(early, size.width.round());
    expect(earlyX, greaterThan(startX),
        reason: 'The actual native glyph motion must already move right; a '
            'fixed .2px floor at 16ms exceeds this font\'s native interpolation');
    final nativeEarly =
        await nativeRgba(progressAt(const Duration(milliseconds: 16)));
    expect(early, nativeEarly,
        reason: 'The 16ms visible frame follows independent native tracking');
    await capturePlaylistFeature(tester, boundary, 'spacing-visible-main-mid');
    await tester.pump(const Duration(milliseconds: 16));
    final middle = await _rgba(tester, boundary);
    final middleX = _inkCenter(middle, size.width.round());
    await capturePlaylistFeature(tester, boundary, 'spacing-native-32');
    final nativeMiddle =
        await nativeRgba(progressAt(const Duration(milliseconds: 32)));
    final nativeMiddleX = _inkCenter(nativeMiddle, size.width.round());
    // This font's independent native raster moves about .048px at 16ms and
    // .611px at 32ms with the original curve. Keep the .2px movement requirement
    // at 32ms; exact native pixels above catch an earlier atlas-raster jump.
    expect(nativeMiddleX, greaterThan(startX + .2));
    expect(middleX, greaterThan(startX + .2));
    expect(middle, isNot(before));
    expect(middle, nativeMiddle);
    expect(tester.getSize(find.byKey(boundary)), size);
    expect(_mainPainters(tester), endpoints);

    final nearElapsed = LyricMotion.lineDuration -
        const Duration(milliseconds: 1);
    await tester.pump(nearElapsed - const Duration(milliseconds: 32));
    final nearEnd = await _rgba(tester, boundary);
    await capturePlaylistFeature(tester, boundary, 'spacing-native-near');
    expect(_mainPainters(tester), endpoints);
    final nativeNear = await nativeRgba(progressAt(nearElapsed));
    await tester.pump(const Duration(milliseconds: 1));
    final after = await _rgba(tester, boundary);
    final endX = _inkCenter(after, size.width.round());
    expect(earlyX, lessThan(endX - .2));
    expect(middleX, lessThan(endX - .2));
    final nativeEnd = await nativeRgba(1);
    final nearX = _inkCenter(nearEnd, size.width.round());
    final nativeNearX = _inkCenter(nativeNear, size.width.round());
    expect(nearX, greaterThan(middleX));
    expect(endX, greaterThanOrEqualTo(nearX),
        reason: 'The final native handoff must continue the requested direction');
    // Replaying the retained native picture under an external translation can
    // differ from internal TextPainter tracking by a subpixel at 479ms. Bound
    // both the native-reference error and the final handoff in physical pixels
    // of this 1x capture; the completed paragraph must still be byte-exact.
    expect((nearX - nativeNearX).abs(), lessThan(.5));
    expect((endX - nearX).abs(), lessThan(.5));
    expect(after, nativeEnd,
        reason: 'The completed handoff matches the exact requested native '
            'paragraph, with no missing glyph or approximate raster left over');
    expect(_mainPainters(tester), hasLength(1));
    await tester.pumpAndSettle();
    expect(await _rgba(tester, boundary), after);
    expect(tester.binding.transientCallbackCount, 0);
    await capturePlaylistFeature(tester, boundary, 'spacing-visible-main-end');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  if (onlyRender) return;

  testWidgets(
      'isolated spacing draft preview paints finite retarget and cancel',
      (tester) async {
    final value = ValueNotifier(0.0);
    addTearDown(value.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
      key: boundary,
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: 500,
          child: ValueListenableBuilder(
            valueListenable: value,
            builder: (_, current, __) => LyricLetterSpacingPreview(
                value: current, text: 'Music every day'),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final before = await _rgba(tester, boundary);
    value.value = 6;
    await tester.pump();
    final target = _previewPainter(tester).cachedShapingIdentities;
    await tester.pump(const Duration(milliseconds: 16));
    expect(await _rgba(tester, boundary), isNot(before));
    expect(_previewPainter(tester).cachedShapingIdentities, target);
    expect(_previewPainter(tester).layoutProgress, greaterThan(0));
    expect(_previewPainter(tester).layoutProgress, lessThan(1));
    value.value = 8;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    value.value = 0;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_previewPainter(tester).retainsPreviousLayout, isFalse);
    expect(await _rgba(tester, boundary), before);
    expect(_previewPainter(tester).clock.playing, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final gate in ['layout', 'reduced', 'hidden']) {
    testWidgets('spacing draft preview stops immediately for $gate',
        (tester) async {
      var spacing = 0.0;
      Widget host(bool stop) => _host(
          SizedBox(
            width: 500,
            child: LyricLetterSpacingPreview(
                value: spacing,
                text: 'Music every day',
                visible: gate != 'hidden' || !stop),
          ),
          layout: gate != 'layout' || !stop,
          reduced: gate == 'reduced' && stop);
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      spacing = 8;
      await tester.pumpWidget(host(false));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_previewPainter(tester).retainsPreviousLayout, isTrue);
      await tester.pumpWidget(host(true));
      await tester.pump();
      expect(_previewPainter(tester).retainsPreviousLayout, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
