import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/lyric_ruby.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, sizePlaylistFeature;

const _text = 'with - 日本群星\n(オムニバス)/嶺内\nともみ (岭内智美)';

List<JapaneseLyricReadingSpan> _spans(String text) => [
      for (final (source, reading) in [
        ('日本群星', 'にっぽん ぐん ぼし'),
        ('嶺内', 'みねない'),
        ('岭内智美', 'ともみ'),
      ])
        JapaneseLyricReadingSpan(
            start: text.indexOf(source),
            end: text.indexOf(source) + source.length,
            text: reading),
    ];

class _Word extends SyncLyricWord {
  _Word(String text) : super(Duration.zero, const Duration(seconds: 8), text);
}

class _Line extends SyncLyricLine {
  _Line(String text)
      : super(Duration.zero, const Duration(seconds: 8), [_Word(text)], null);
}

typedef _Raster = ({int width, int height, Uint8List rgba});

Future<_Raster> _raster(WidgetTester tester, TextPainter painter) async =>
    (await tester.runAsync(() async {
      final recorder = drawing.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(painter.width.ceil().clamp(1, 10000),
          painter.height.ceil().clamp(1, 10000));
      try {
        return (
          width: image.width,
          height: image.height,
          rgba:
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List(),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;

// Colour alone isolates this source's ink. The complete paragraph, font runs,
// line breaking and UTF-16 offsets remain identical to the live consumer.
TextPainter _sourcePainter(TextPainter original, LyricRubySpan source) {
  var offset = 0;
  InlineSpan isolate(InlineSpan span) {
    final textSpan = span as TextSpan;
    final text = textSpan.text ?? '';
    final start = offset;
    offset += text.length;
    final left = (source.start - start).clamp(0, text.length);
    final right = (source.end - start).clamp(left, text.length);
    TextStyle ink(bool selected) => (textSpan.style ?? const TextStyle())
        .copyWith(color: selected ? Colors.white : Colors.transparent);
    return TextSpan(style: ink(false), children: [
      if (left > 0) TextSpan(text: text.substring(0, left), style: ink(false)),
      if (right > left)
        TextSpan(text: text.substring(left, right), style: ink(true)),
      if (right < text.length)
        TextSpan(text: text.substring(right), style: ink(false)),
      for (final child in textSpan.children ?? const <InlineSpan>[])
        isolate(child),
    ]);
  }

  final result = TextPainter(
      text: isolate(original.text!),
      textAlign: original.textAlign,
      textDirection: original.textDirection,
      textScaler: original.textScaler,
      maxLines: original.maxLines,
      ellipsis: original.ellipsis,
      locale: original.locale,
      strutStyle: original.strutStyle,
      textWidthBasis: original.textWidthBasis,
      textHeightBehavior: original.textHeightBehavior)
    ..layout(minWidth: original.width, maxWidth: original.width);
  expect(result.text!.toPlainText(), original.text!.toPlainText());
  expect(result.size, original.size);
  expect(
      result.computeLineMetrics().map((line) => (line.baseline, line.height)),
      original.computeLineMetrics().map((line) => (line.baseline, line.height)),
      reason: 'Source isolation must not change the production paragraph');
  return result;
}

Future<_Raster> _paintRaster(
        WidgetTester tester, Size size, void Function(Canvas) paint) async =>
    (await tester.runAsync(() async {
      final recorder = drawing.PictureRecorder();
      paint(Canvas(recorder));
      final picture = recorder.endRecording();
      final image =
          await picture.toImage(size.width.ceil(), size.height.ceil());
      try {
        return (
          width: image.width,
          height: image.height,
          rgba:
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List(),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;

Future<_Raster> _boundaryRaster(
        WidgetTester tester, GlobalKey boundary) async =>
    (await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      try {
        return (
          width: image.width,
          height: image.height,
          rgba:
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List(),
        );
      } finally {
        image.dispose();
      }
    }))!;

Rect _visibleMaskInk(_Raster viewport, _Raster mask, Offset origin, Rect clip) {
  final maskInk = _ink(mask, clip: clip);
  var left = viewport.width, top = viewport.height, right = -1, bottom = -1;
  var expected = 0, found = 0;
  for (var y = maskInk.top.toInt(); y < maskInk.bottom; y++) {
    for (var x = maskInk.left.toInt(); x < maskInk.right; x++) {
      if (mask.rgba[(y * mask.width + x) * 4 + 3] < 24) continue;
      expected++;
      final actualX = (x + origin.dx).round();
      final actualY = (y + origin.dy).round();
      var visible = false;
      // Fractional parent placement can select the adjacent physical pixel.
      // This verifies real viewport ink; it does not replace its coordinates
      // with the raw paragraph's box or the Ruby leading formula.
      for (var dy = -1; dy <= 1 && !visible; dy++) {
        for (var dx = -1; dx <= 1 && !visible; dx++) {
          final px = actualX + dx, py = actualY + dy;
          if (px < 0 ||
              py < 0 ||
              px >= viewport.width ||
              py >= viewport.height) {
            continue;
          }
          visible = viewport.rgba[(py * viewport.width + px) * 4 + 3] >= 24;
        }
      }
      if (!visible) continue;
      found++;
      if (actualX < left) left = actualX;
      if (actualX > right) right = actualX;
      if (actualY < top) top = actualY;
      if (actualY > bottom) bottom = actualY;
    }
  }
  expect(expected, greaterThan(0));
  expect(found / expected, greaterThan(.98),
      reason: 'The separately isolated layer must match the actual consumer '
          'viewport, including its shared primary/Ruby leading');
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

Future<void> _expectFinalPaintedGap(WidgetTester tester, GlobalKey boundary,
    TextPainter primary, LyricRubyLayout ruby, double fontSize) async {
  final widget = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((widget) => switch (widget.painter) {
            PlainLyricWordFollowPainter painter =>
              identical(painter.text, primary),
            LyricWordHighlightPainter painter =>
              identical(painter.text, primary),
            _ => false,
          });
  final paintBox =
      tester.renderObject<RenderCustomPaint>(find.byWidget(widget));
  final viewportBox = boundary.currentContext!.findRenderObject()! as RenderBox;
  final origin = paintBox.localToGlobal(Offset.zero, ancestor: viewportBox);
  final inkOffset = switch (widget.painter) {
    PlainLyricWordFollowPainter painter => painter.inkOffset,
    LyricWordHighlightPainter painter => painter.inkOffset,
    _ => throw StateError('Expected the live primary lyric painter'),
  };
  final viewport = await _boundaryRaster(tester, boundary);
  final readings = await _paintRaster(tester, paintBox.size, (canvas) {
    canvas.translate(inkOffset.dx, inkOffset.dy);
    ruby.paint(canvas, tint: Colors.white);
  });
  for (final glyph in ruby.glyphs) {
    final source = _sourcePainter(primary, glyph.span);
    try {
      final body = await _paintRaster(tester, paintBox.size, (canvas) {
        canvas.translate(inkOffset.dx, inkOffset.dy);
        ruby.paintPrimary(canvas, () => source.paint(canvas, Offset.zero));
      });
      final rowOffset = Offset(0, ruby.leadingForGlyph(glyph));
      final bodyInk = _visibleMaskInk(
          viewport, body, origin, glyph.source.shift(inkOffset + rowOffset));
      final readingInk = _visibleMaskInk(viewport, readings, origin,
          (glyph.offset & glyph.painter.size).shift(inkOffset + rowOffset));
      final gap = bodyInk.top - readingInk.bottom;
      debugPrint('FINAL viewport ruby ${glyph.span.text}: row=${glyph.row} '
          'source=$bodyInk reading=$readingInk gap=$gap font=$fontSize');
      expect(gap, greaterThanOrEqualTo(0),
          reason: 'Final painted reading must not overlap its own Han');
      expect(gap, lessThanOrEqualTo(fontSize * .22),
          reason: 'The real viewport must not retain a blank reading row');
    } finally {
      source.dispose();
    }
  }
}

Rect _ink(_Raster raster, {Rect? clip}) {
  final region = (clip ??
          Rect.fromLTWH(
              0, 0, raster.width.toDouble(), raster.height.toDouble()))
      .intersect(Rect.fromLTWH(
          0, 0, raster.width.toDouble(), raster.height.toDouble()));
  var left = raster.width, top = raster.height, right = -1, bottom = -1;
  for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
    for (var x = region.left.ceil(); x < region.right.floor(); x++) {
      if (raster.rgba[(y * raster.width + x) * 4 + 3] < 24) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left),
      reason: 'The selected real font must provide actual source/reading ink');
  expect(bottom, greaterThanOrEqualTo(top));
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

Widget _host(Widget child) {
  final policy = AppFontPolicy.defaults();
  return MaterialApp(
      theme: ThemeData(
          fontFamily: policy.uiFamily,
          fontFamilyFallback: policy.fallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: AppFontScope(
          policy: policy,
          child: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(24), child: child)))));
}

Future<void> _expectHorizontalVisibleGap(WidgetTester tester,
    TextPainter primary, LyricRubyLayout ruby, double fontSize) async {
  expect(ruby.glyphs, isNotEmpty);
  for (final glyph in ruby.glyphs) {
    final source = _sourcePainter(primary, glyph.span);
    final primaryRaster = await _raster(tester, source);
    source.dispose();
    final primaryInk = _ink(primaryRaster, clip: glyph.source);
    final readingInk = _ink(await _raster(tester, glyph.painter));
    final gap = primaryInk.top - (glyph.offset.dy + readingInk.bottom);
    debugPrint('visible ruby ${glyph.span.text}: source=$primaryInk '
        'reading=${readingInk.shift(glyph.offset)} gap=$gap font=$fontSize '
        'selection=${glyph.source} inkTop=${glyph.sourceInkTop} '
        'lines=${primary.computeLineMetrics().map((line) => (
              line.baseline,
              line.ascent,
              line.descent,
              line.height
            )).toList()}');
    expect(gap, greaterThanOrEqualTo(0),
        reason: 'Reading ink must not overlap its Han source');
    expect(gap, lessThanOrEqualTo(fontSize * .22),
        reason: 'The visible reading must sit near its actual Han ink, '
            'rather than an empty metric row above it');
  }
}

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  for (final face in appBundledFonts) {
    if (onlyRender) break;
    testWidgets('ruby source metrics and visible ink for ${face.id}',
        (tester) async {
      final policy = AppFontPolicy(
          language: UiLanguage.ja,
          mixedScripts: false,
          zh: face,
          en: face,
          ja: face,
          ko: face);
      // The third source in the screenshot is absent from this short probe.
      final spans = _spans('日本群星 嶺内 ともみ')
          .where((span) => span.start >= 0)
          .toList(growable: false);
      final primary = TextPainter(
          text: appFontSpan('日本群星 嶺内 ともみ',
              style: lyricRubyPrimaryStyle(
                  const TextStyle(
                      fontSize: 48, height: 1.3, color: Colors.black),
                  spans),
              policy: policy),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: 600);
      final ruby = LyricRubyLayout(
          primary: primary,
          spans: spans,
          style:
              const TextStyle(fontSize: 48, height: 1.3, color: Colors.black),
          policy: policy,
          direction: TextDirection.ltr,
          locale: null,
          scaler: TextScaler.noScaling,
          width: primary.width);
      addTearDown(primary.dispose);
      addTearDown(ruby.dispose);
      final raster = await _raster(tester, primary);
      final metric = primary.computeLineMetrics().single;
      for (final glyph in ruby.glyphs) {
        final ink = _ink(raster, clip: glyph.source);
        final boxEmTop =
            glyph.source.center.dy - math.min(glyph.source.height, 48) / 2;
        debugPrint('ruby metrics ${face.id} source=${glyph.source} '
            'ink=$ink baseline=${metric.baseline} '
            'ascent=${metric.ascent} unscaledAscent=${metric.unscaledAscent} '
            'descent=${metric.descent} boxEmTop=$boxEmTop '
            'currentTop=${glyph.sourceInkTop}');
      }
      await _expectHorizontalVisibleGap(tester, primary, ruby, 48);
    });
  }

  for (final timed in [false, true]) {
    testWidgets(
        'visible ruby gap in the actual mixed author paragraph timed=$timed',
        (tester) async {
      sizePlaylistFeature(tester, width: 620, height: 1200);
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance)
        ..lyricFontSize = 32
        ..lyricTextAlign = LyricTextAlign.left;
      final position = ValueNotifier(const Duration(seconds: 20));
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(position.dispose);
      final LyricLine line =
          timed ? _Line(_text) : LrcLine(Duration.zero, _text, isBlank: false);
      line
        ..romanization = 'with nihon gunsei / mineuchi tomomi'
        ..japaneseReading = 'with - にっぽん ぐん ぼし / みねない ともみ'
        ..japaneseReadingSpans = _spans(_text);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(ChangeNotifierProvider.value(
          value: controller,
          child: RepaintBoundary(
              key: boundary,
              child: LyricViewTile(
                  line: line,
                  position: position,
                  opacity: 1,
                  distance: 0,
                  reducedMotion: true)))));
      await tester.pumpAndSettle();
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter);
      final (primary, ruby) = timed
          ? (() {
              final paint =
                  paints.whereType<LyricWordHighlightPainter>().single;
              return (paint.text, paint.rubyLayout!);
            })()
          : (() {
              final paint = paints
                  .whereType<PlainLyricWordFollowPainter>()
                  .firstWhere((paint) => paint.ruby != null);
              return (paint.text, paint.ruby!);
            })();
      expect(primary.computeLineMetrics().length, greaterThanOrEqualTo(3));
      await capturePlaylistFeature(
          tester, boundary, 'mixed-author-${timed ? 'qrc' : 'plain'}');
      await _expectHorizontalVisibleGap(tester, primary, ruby, 48);
      await _expectFinalPaintedGap(tester, boundary, primary, ruby, 48);
      expect(primary.text!.toPlainText(), _text);
      expect(line.romanization, 'with nihon gunsei / mineuchi tomomi');
      if (line is SyncLyricLine) {
        expect(line.words.single.content, _text);
        expect(line.words.single.start, Duration.zero);
        expect(line.words.single.length, const Duration(seconds: 8));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visible ruby gap in the desktop mixed author paragraph',
      (tester) async {
    sizePlaylistFeature(tester, width: 1800, height: 400);
    final clock = PlaybackClock(automaticTicks: false);
    addTearDown(clock.dispose);
    final text = _text.replaceAll('\n', ' / ');
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: DesktopLyricText(
            text: text,
            clock: clock,
            style: const TextStyle(fontSize: 48, height: 1.3),
            playedColor: Colors.teal,
            unplayedColor: Colors.teal,
            rubySpans: _spans(text),
            reducedMotion: true))));
    await tester.pumpAndSettle();
    final paint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<DesktopLyricTextPainter>()
        .single;
    final primary =
        paint.cachedShapingIdentities.whereType<TextPainter>().first;
    await capturePlaylistFeature(tester, boundary, 'mixed-author-desktop');
    await _expectHorizontalVisibleGap(tester, primary, paint.rubyLayout!, 48);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
