import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, sizePlaylistFeature;

const _inkColor = Color(0xff075a44);
const _spacingText = '音楽伴毎一天';

class _Word extends SyncLyricWord {
  _Word(String text, int start, int length)
      : super(Duration(milliseconds: start), Duration(milliseconds: length),
            text);
}

class _Line extends SyncLyricLine {
  _Line(List<SyncLyricWord> words)
      : super(Duration.zero, const Duration(seconds: 12), words);
}

class _Document extends Lyric {
  _Document(super.lines);
}

Widget _host(Widget child, {AppFontPolicy? fontPolicy}) {
  final policy = fontPolicy ?? AppFontPolicy.defaults();
  final scheme = ColorScheme.fromSeed(seedColor: _inkColor)
      .copyWith(primary: _inkColor, onSecondaryContainer: _inkColor);
  return MaterialApp(
      theme: ThemeData(
          fontFamily: policy.uiFamily,
          fontFamilyFallback: policy.fallback,
          colorScheme: scheme),
      home: AppFontScope(
          policy: policy,
          child: Scaffold(
              backgroundColor: Colors.white, body: Center(child: child))));
}

typedef _Raster = ({int width, int height, Uint8List rgba});

Future<_Raster> _rgba(WidgetTester tester, GlobalKey boundary) async =>
    (await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (
          width: image.width,
          height: image.height,
          rgba: Uint8List.fromList(
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List())
        );
      } finally {
        image.dispose();
      }
    }))!;

int _solidInk(_Raster pixels) {
  var count = 0;
  for (var i = 0; i < pixels.rgba.length; i += 4) {
    if ((pixels.rgba[i] - 7).abs() <= 2 &&
        (pixels.rgba[i + 1] - 90).abs() <= 2 &&
        (pixels.rgba[i + 2] - 68).abs() <= 2 &&
        pixels.rgba[i + 3] >= 253) {
      count++;
    }
  }
  return count;
}

double _inkX(_Raster pixels) {
  var weight = 0.0, position = 0.0;
  for (var i = 0; i < pixels.rgba.length; i += 4) {
    final ink = 765 - pixels.rgba[i] - pixels.rgba[i + 1] - pixels.rgba[i + 2];
    weight += ink;
    position += (i ~/ 4 % pixels.width) * ink;
  }
  expect(weight, greaterThan(10000), reason: 'Real font ink is present');
  return position / weight;
}

List<({Finder finder, TextPainter text, Offset ink, Object layout})> _main(
    WidgetTester tester, String text,
    {Finder? within}) {
  final result =
      <({Finder finder, TextPainter text, Offset ink, Object layout})>[];
  final paints = within == null
      ? find.byType(CustomPaint)
      : find.descendant(of: within, matching: find.byType(CustomPaint));
  for (final element in paints.evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter is PlainLyricWordFollowPainter &&
        painter.text.text!.toPlainText() == text) {
      result.add((
        finder: find.byWidget(element.widget),
        text: painter.text,
        ink: painter.inkOffset,
        layout: painter.layoutIdentity!
      ));
    } else if (painter is LyricWordHighlightPainter &&
        painter.text.text!.toPlainText() == text) {
      result.add((
        finder: find.byWidget(element.widget),
        text: painter.text,
        ink: painter.inkOffset,
        layout: painter.layoutIdentity
      ));
    }
  }
  return result;
}

DesktopLyricTextPainter _desktop(WidgetTester tester, {Finder? within}) =>
    tester
        .widgetList<CustomPaint>(within == null
            ? find.byType(CustomPaint)
            : find.descendant(of: within, matching: find.byType(CustomPaint)))
        .map((widget) => widget.painter)
        .whereType<DesktopLyricTextPainter>()
        .single;

void _checkColor(_Raster start, _Raster middle, String frame) {
  final reference = _solidInk(start);
  expect(reference, greaterThan(200), reason: 'The source has opaque stems');
  expect(_solidInk(middle), greaterThan(reference * .8),
      reason: '$frame must move opaque glyphs instead of fading the whole '
          'paragraph into a different colour');
}

List<int> _region(_Raster pixels, Rect bounds) => [
      for (var y = bounds.top.ceil().clamp(0, pixels.height);
          y < bounds.bottom.floor().clamp(0, pixels.height);
          y++)
        for (var x = bounds.left.ceil().clamp(0, pixels.width);
            x < bounds.right.floor().clamp(0, pixels.width);
            x++)
          ...pixels.rgba.sublist(
              (y * pixels.width + x) * 4, (y * pixels.width + x) * 4 + 4)
    ];

Rect _coreInkBounds(_Raster pixels, Rect bounds, Color ink) {
  // The retained white viewport and fixed unplayed colour identify coverage
  // independently from the existing low-alpha glow. Inspect the actual dense
  // strokes; a glow's one-channel colour change is not a glyph displacement.
  final fullContrast = (765 - (ink.r + ink.g + ink.b) * 255) * ink.a;
  expect(fullContrast, greaterThan(0));
  var left = pixels.width, top = pixels.height, right = -1, bottom = -1;
  var count = 0;
  for (var y = bounds.top.ceil().clamp(0, pixels.height);
      y < bounds.bottom.floor().clamp(0, pixels.height);
      y++) {
    for (var x = bounds.left.ceil().clamp(0, pixels.width);
        x < bounds.right.floor().clamp(0, pixels.width);
        x++) {
      final offset = (y * pixels.width + x) * 4;
      final coverage = (765 -
              pixels.rgba[offset] -
              pixels.rgba[offset + 1] -
              pixels.rgba[offset + 2]) /
          fullContrast;
      if (coverage < .75) continue;
      count++;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(count, greaterThan(100),
      reason: 'The real phase==1 glyph must retain visible dense strokes');
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

void _expectSameInkRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, .05), reason: reason);
  expect(actual.top, closeTo(expected.top, .05), reason: reason);
  expect(actual.right, closeTo(expected.right, .05), reason: reason);
  expect(actual.bottom, closeTo(expected.bottom, .05), reason: reason);
}

/// A separately mounted resting native target. It has the final spacing from
/// its first layout and never receives a spacing transition or glyph morph.
/// Only the fixture applies the independently sampled group fade and scale.
class _NativeSpacingReference {
  _NativeSpacingReference(this.line, this.position, this.fontSize,
      {this.whiteBackground = false});
  final LyricLine line;
  final ValueNotifier<Duration> position;
  final double fontSize;
  final bool whiteBackground;
  final spacing = ValueNotifier(0.0), progress = ValueNotifier(1.0);
  final boundary = GlobalKey();
  final _targets = <double, LyricViewController>{};
  final _appearances = <ValueNotifier<DesktopLyricAppearance>>[];

  LyricViewController _target(double value) => _targets.putIfAbsent(value, () {
        final appearance = ValueNotifier(DesktopLyricAppearance.defaults
            .copyWith(lyricLetterSpacing: value));
        _appearances.add(appearance);
        return LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}),
            appearance: appearance,
            persistAppearance: () async {})
          ..lyricFontSize = fontSize
          ..lyricTextAlign = LyricTextAlign.left;
      });

  Widget pane(double width) => RepaintBoundary(
      key: boundary,
      child: ValueListenableBuilder<double>(
          valueListenable: spacing,
          builder: (context, value, _) {
            final target = ChangeNotifierProvider.value(
                value: _target(value),
                child: SizedBox(
                    width: width,
                    child: LyricViewTile(
                        key: ValueKey(('native-spacing-target', value)),
                        line: line,
                        position: position,
                        opacity: 1,
                        distance: 0,
                        reducedMotion: false)));
            final group = ValueListenableBuilder<double>(
                valueListenable: progress,
                child: target,
                builder: (context, progress, child) => Opacity(
                    opacity: progress,
                    child: Transform.scale(
                        scale: .96 + .04 * progress,
                        alignment: Alignment.topLeft,
                        filterQuality: progress < 1 ? FilterQuality.low : null,
                        child: child)));
            return whiteBackground
                ? ColoredBox(color: Colors.white, child: group)
                : group;
          }));

  void target(double value) {
    spacing.value = value;
    progress.value = 0;
  }

  void at(int milliseconds) => progress.value = LyricMotion.curve
      .transform(milliseconds / LyricMotion.spacingDuration.inMilliseconds);

  void dispose() {
    for (final target in _targets.values) {
      target.dispose();
    }
    for (final appearance in _appearances) {
      appearance.dispose();
    }
    spacing.dispose();
    progress.dispose();
  }
}

Future<_Raster> _expectNativeSpacing(WidgetTester tester, GlobalKey actual,
    _NativeSpacingReference reference, String phase) async {
  final pixels = await _rgba(tester, actual);
  final expected = await _rgba(tester, reference.boundary);
  expect((pixels.width, pixels.height), (expected.width, expected.height));
  expect(pixels.rgba.length, expected.rgba.length);
  for (var at = 0; at < pixels.rgba.length; at++) {
    final delta = (pixels.rgba[at] - expected.rgba[at]).abs();
    if (delta > (at % 4 == 3 ? 0 : 2)) {
      fail('$phase differs from the fixed native target at byte $at: '
          '$delta (RGB tolerance 2, alpha exact)');
    }
  }
  return pixels;
}

void main({bool onlyRender = false, String onlyCase = ''}) {
  const cases = {
    'spacing keeps real colour emoji alpha and text variation ink',
    'spacing keeps opaque glyph colour and moves early timed=false',
    'spacing keeps opaque glyph colour and moves early timed=true',
    'desktop spacing keeps opaque glyph colour through retarget',
    'playing ruby keeps the main viewport and stationary glyph ink',
    'playing multiline ruby keeps centered and right stationary glyph ink',
    'playing ruby keeps desktop layout and stationary glyph ink',
  };
  if (onlyCase.isNotEmpty && !cases.contains(onlyCase)) {
    throw ArgumentError.value(onlyCase, 'onlyCase', 'Unknown motion case');
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  void motionTest(String name, WidgetTesterCallback body) {
    if (onlyCase.isEmpty || onlyCase == name) testWidgets(name, body);
  }

  motionTest('spacing keeps real colour emoji alpha and text variation ink',
      (tester) async {
    // This actual Windows colour font is read only. Ahem's missing-glyph boxes
    // cannot prove that a coloured glyph keeps its endpoint opacity or hue.
    final emojiFile = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/seguiemj.ttf');
    const emojiFamily = 'DanMotionColourEmoji';
    expect(await tester.runAsync(emojiFile.exists), isTrue);
    await tester.runAsync(() async {
      final bytes = await emojiFile.readAsBytes();
      await (FontLoader(emojiFamily)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    });
    final defaults = AppFontPolicy.defaults();
    final colourPolicy = AppFontPolicy(
        language: defaults.language,
        mixedScripts: defaults.mixedScripts,
        zh: defaults.zh,
        en: defaults.en,
        ja: defaults.ja,
        ko: defaults.ko,
        // The Windows system fallback includes monochrome Segoe UI Symbol
        // before Emoji; the software fixture font manager does not. Select the
        // verified COLR face explicitly for this colour-glyph regression.
        baseFallback:
            const AppFontFace(id: 'motion-colr-fixture', family: emojiFamily));
    sizePlaylistFeature(tester, width: 1000, height: 700);
    const text = '★☆♭ ❤\ufe0e ❤\ufe0f 👨‍👩‍👧‍👦';
    final line = _Line([_Word(text, 9000, 2000)]);
    final position = ValueNotifier(Duration.zero);
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance,
        persistAppearance: () async {})
      ..lyricFontSize = 38
      ..lyricTextAlign = LyricTextAlign.left;
    final reference = _NativeSpacingReference(line, position, 38);
    addTearDown(controller.dispose);
    addTearDown(reference.dispose);
    addTearDown(appearance.dispose);
    addTearDown(position.dispose);
    final boundary = GlobalKey();
    final targetBoundary = reference.boundary;
    final actual = ChangeNotifierProvider.value(
        value: controller,
        child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
                width: 850,
                child: LyricViewTile(
                    line: line,
                    position: position,
                    opacity: 1,
                    distance: 0,
                    reducedMotion: false))));
    await tester.pumpWidget(_host(
        Column(
            mainAxisSize: MainAxisSize.min,
            children: [actual, reference.pane(850)]),
        fontPolicy: colourPolicy));
    await tester.pumpAndSettle();
    Rect crop(GlobalKey key, String cluster) {
      final start = text.indexOf(cluster), end = start + cluster.length;
      expect(start, greaterThanOrEqualTo(0));
      final paragraph = _main(tester, text, within: find.byKey(key)).single;
      final bounds = paragraph.text
          .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end))
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b));
      final render = tester.renderObject<RenderBox>(paragraph.finder);
      return MatrixUtils.transformRect(
          render.getTransformTo(key.currentContext!.findRenderObject()),
          bounds.shift(paragraph.ink));
    }

    ({int alpha, int coloured, int red, Set<int> hues}) ink(
        _Raster pixels, Rect bounds) {
      final region = _region(pixels, bounds);
      var alpha = 0, coloured = 0, red = 0;
      final hues = <int>{};
      for (var i = 0; i < region.length; i += 4) {
        if (region[i + 3] > alpha) alpha = region[i + 3];
        final r = region[i], g = region[i + 1], b = region[i + 2];
        final maximum = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minimum = [r, g, b].reduce((a, b) => a < b ? a : b);
        if (region[i + 3] <= 40 || maximum - minimum <= 25) continue;
        coloured++;
        if (r > g * 1.25 && r > b * 1.25) red++;
        // A green missing-glyph box cannot pass as a multi-colour family.
        if (r > g * 1.2 && r > b * 1.2) hues.add(0);
        if (g > r * 1.2 && g > b * 1.2) hues.add(1);
        if (b > r * 1.2 && b > g * 1.2) hues.add(2);
        if (r > b * 1.2 && g > b * 1.2) hues.add(3);
      }
      return (alpha: alpha, coloured: coloured, red: red, hues: hues);
    }

    void actualColours(String cluster,
        ({int alpha, int coloured, int red, Set<int> hues}) actual) {
      expect(actual.coloured, greaterThan(40));
      if (cluster == '❤\ufe0f') {
        expect(actual.red, greaterThan(40),
            reason: 'The heart must retain real red COLR ink, not lyric tint');
      } else {
        expect(actual.hues.length, greaterThanOrEqualTo(2),
            reason: 'The family must retain distinct actual font colours');
      }
    }

    final originalTracking = _main(tester, text, within: find.byKey(boundary))
        .single
        .text
        .text!
        .style!
        .letterSpacing;
    final from = await _expectNativeSpacing(tester, boundary, reference,
        'original native colour and text-variation source');
    const colouredClusters = ['❤\ufe0f', '👨‍👩‍👧‍👦'];
    const textClusters = ['★', '☆', '♭', '❤\ufe0e'];
    for (final cluster in colouredClusters) {
      actualColours(cluster, ink(from, crop(boundary, cluster)));
    }
    for (final cluster in textClusters) {
      expect(ink(from, crop(boundary, cluster)).alpha, greaterThan(0),
          reason: 'The native text-variation source contains real glyph ink');
    }
    await capturePlaylistFeature(tester, boundary, 'colour-emoji-start');
    for (final spacing in [8.0, 2.0, 6.0, 0.0]) {
      reference.target(spacing);
      controller.setLyricLetterSpacing(spacing);
      await tester.pump();
      final paragraphs = _main(tester, text, within: find.byKey(boundary));
      expect(paragraphs, hasLength(1),
          reason: 'The old spacing disappears; one final target is retained');
      final paragraph = paragraphs.single.text;
      final painter = tester
          .widget<CustomPaint>(paragraphs.single.finder)
          .painter! as LyricWordHighlightPainter;
      expect(painter.glyphMorph, isNull);
      expect(paragraph.text!.style!.letterSpacing,
          spacing == 0 ? originalTracking : (originalTracking ?? 0) + spacing);
      final zero = await _expectNativeSpacing(tester, boundary, reference,
          'new spacing $spacing starts without old emoji ink');
      expect(zero.rgba, everyElement(0),
          reason: 'At zero group opacity no old native glyph is left behind');
      reference.at(90);
      await tester.pump(const Duration(milliseconds: 90));
      final middle = await _expectNativeSpacing(tester, boundary, reference,
          'new spacing $spacing keeps native COLR alpha through the group fade');
      final native = await _rgba(tester, targetBoundary);
      for (final cluster in colouredClusters) {
        final actualInk = ink(middle, crop(boundary, cluster));
        final targetInk = ink(native, crop(targetBoundary, cluster));
        actualColours(cluster, actualInk);
        expect(actualInk.alpha, targetInk.alpha,
            reason: 'Only the shared group opacity changes native COLR alpha');
        expect(actualInk.hues, targetInk.hues);
      }
      for (final cluster in textClusters) {
        final actualInk = ink(middle, crop(boundary, cluster));
        final targetInk = ink(native, crop(targetBoundary, cluster));
        expect(actualInk.alpha, targetInk.alpha);
        expect(actualInk.red, targetInk.red);
        expect(actualInk.hues, targetInk.hues,
            reason: 'Text selectors must retain their real native variant ink');
      }
      expect(_main(tester, text, within: find.byKey(boundary)).single.text,
          same(paragraph),
          reason: 'Motion does not replace the native target');
    }
    reference.progress.value = 1;
    await tester.pumpAndSettle();
    final end = await _expectNativeSpacing(
        tester, boundary, reference, 'final native colour source');
    expect(end.rgba, orderedEquals(from.rgba),
        reason: 'Returning to zero spacing restores the original native alpha');
    expect(position.value, Duration.zero);
    await capturePlaylistFeature(tester, boundary, 'colour-emoji-end');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final timed in [false, true]) {
    motionTest('spacing keeps opaque glyph colour and moves early timed=$timed',
        (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 500);
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance,
          persistAppearance: () async {})
        ..lyricFontSize = 32
        ..lyricTextAlign = LyricTextAlign.left;
      final position = ValueNotifier(const Duration(seconds: 20));
      final LyricLine line = timed
          ? _Line([_Word(_spacingText, 0, 4000)])
          : LrcLine(Duration.zero, _spacingText, isBlank: false);
      final reference =
          _NativeSpacingReference(line, position, 32, whiteBackground: true);
      addTearDown(controller.dispose);
      addTearDown(reference.dispose);
      addTearDown(appearance.dispose);
      addTearDown(position.dispose);
      final boundary = GlobalKey();
      final actual = ChangeNotifierProvider.value(
          value: controller,
          child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                      width: 600,
                      child: LyricViewTile(
                          line: line,
                          position: position,
                          opacity: 1,
                          distance: 0,
                          reducedMotion: false)))));
      await tester.pumpWidget(_host(Column(
          mainAxisSize: MainAxisSize.min,
          children: [actual, reference.pane(600)])));
      await tester.pumpAndSettle();
      final start = await _expectNativeSpacing(
          tester, boundary, reference, 'original native source timed=$timed');
      final originalTracking =
          _main(tester, _spacingText, within: find.byKey(boundary))
                  .single
                  .text
                  .text!
                  .style!
                  .letterSpacing ??
              0;
      expect(_solidInk(start), greaterThan(200));
      await capturePlaylistFeature(
          tester, boundary, 'opaque-main-$timed-start');
      reference.target(8);
      controller.setLyricLetterSpacing(8);
      await tester.pump();
      final target =
          _main(tester, _spacingText, within: find.byKey(boundary)).single;
      final nativeParagraph = target.text;
      expect(nativeParagraph.text!.style!.letterSpacing, originalTracking + 8);
      final zero = await _expectNativeSpacing(
          tester, boundary, reference, 'first new-spacing frame timed=$timed');
      expect(_solidInk(zero), 0,
          reason: 'Old spacing is removed before the final target fades in');
      for (final (elapsed, step) in [(16, 16), (32, 16), (90, 58)]) {
        reference.at(elapsed);
        await tester.pump(Duration(milliseconds: step));
        final pixels = await _expectNativeSpacing(tester, boundary, reference,
            'target native spacing timed=$timed at ${elapsed}ms');
        final next =
            _main(tester, _spacingText, within: find.byKey(boundary)).single;
        expect(next.text, same(nativeParagraph),
            reason: 'The final paragraph is shaped once and reused in motion');
        expect(next.text.text!.style!.letterSpacing, originalTracking + 8);
        expect(_inkX(pixels), greaterThan(_inkX(start) + .2),
            reason: 'Real target ink moves early in the requested direction');
      }
      await capturePlaylistFeature(tester, boundary, 'opaque-main-$timed-mid');
      reference.target(3);
      controller.setLyricLetterSpacing(3);
      await tester.pump();
      await _expectNativeSpacing(tester, boundary, reference,
          'rapid retarget first frame timed=$timed');
      final retarget =
          _main(tester, _spacingText, within: find.byKey(boundary)).single.text;
      expect(retarget.text!.style!.letterSpacing, originalTracking + 3);
      expect(retarget, isNot(same(nativeParagraph)));
      reference.at(40);
      await tester.pump(const Duration(milliseconds: 40));
      await _expectNativeSpacing(
          tester, boundary, reference, 'rapid native target fade timed=$timed');
      reference.progress.value = 1;
      await tester.pumpAndSettle();
      final end = await _expectNativeSpacing(
          tester, boundary, reference, 'final native target timed=$timed');
      _checkColor(start, end, 'final native target');
      expect(
          _main(tester, _spacingText, within: find.byKey(boundary)).single.text,
          same(retarget));
      final endpoint = end.rgba;
      await tester.pump(const Duration(milliseconds: 240));
      expect((await _rgba(tester, boundary)).rgba, orderedEquals(endpoint),
          reason:
              'After the fade the native target keeps every endpoint pixel');
      expect(position.value, const Duration(seconds: 20));
      await capturePlaylistFeature(tester, boundary, 'opaque-main-$timed-end');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  motionTest('desktop spacing keeps opaque glyph colour through retarget',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 500);
    final clock = PlaybackClock(automaticTicks: false);
    addTearDown(clock.dispose);
    final spacing = ValueNotifier(0.0);
    addTearDown(spacing.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: ColoredBox(
            color: Colors.white,
            child: ValueListenableBuilder(
                valueListenable: spacing,
                builder: (_, value, __) => DesktopLyricText(
                    text: _spacingText,
                    clock: clock,
                    verticalLetterSpacing: value,
                    style: TextStyle(fontSize: 48, letterSpacing: value),
                    playedColor: _inkColor,
                    unplayedColor: _inkColor))))));
    await tester.pumpAndSettle();
    final start = await _rgba(tester, boundary);
    await capturePlaylistFeature(tester, boundary, 'opaque-desktop-start');
    spacing.value = 8;
    await tester.pump();
    final target = _desktop(tester).cachedShapingIdentities;
    expect(_desktop(tester).retainsPreviousLayout, isTrue,
        reason: 'Use the real shared spacing input, not a static style change');
    await tester.pump(const Duration(milliseconds: 16));
    final early = await _rgba(tester, boundary);
    // Desktop is centred, so position the actual glyph centres relative to its
    // own changing width rather than the scaffold's centre.
    expect(early.rgba, isNot(start.rgba));
    await tester.pump(const Duration(milliseconds: 74));
    final middle = await _rgba(tester, boundary);
    expect(_desktop(tester).layoutProgress, inExclusiveRange(0, 1));
    await capturePlaylistFeature(tester, boundary, 'opaque-desktop-mid');
    expect(_desktop(tester).cachedShapingIdentities, target);
    _checkColor(start, middle, 'desktop spacing mid-frame');
    spacing.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    _checkColor(start, await _rgba(tester, boundary), 'desktop rapid retarget');
    await tester.pumpAndSettle();
    await capturePlaylistFeature(tester, boundary, 'opaque-desktop-end');
    expect(_desktop(tester).retainsPreviousLayout, isFalse);
    expect(clock.positionMilliseconds, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  motionTest('playing ruby keeps the main viewport and stationary glyph ink',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 700);
    const text = '夜空 航海 終点';
    final line = _Line([
      _Word('夜空 ', 0, 2500),
      _Word('航海 ', 3000, 2500),
      _Word('終点', 9000, 2000)
    ])
      ..japaneseReading = 'よぞら こうかい 終点'
      ..japaneseReadingSpans = const [
        JapaneseLyricReadingSpan(start: 0, end: 2, text: 'よぞら'),
        JapaneseLyricReadingSpan(start: 3, end: 5, text: 'こうかい')
      ];
    final document = _Document([line]);
    final controlDocument = _Document([
      _Line([
        _Word('夜空 ', 0, 2500),
        _Word('航海 ', 3000, 2500),
        _Word('終点', 9000, 2000)
      ])
    ]);
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance)
      ..lyricFontSize = 32
      ..lyricTextAlign = LyricTextAlign.left;
    final positions = StreamController<double>.broadcast(sync: true);
    var seconds = .05;
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(positions.close);
    final boundary = GlobalKey();
    final controlBoundary = GlobalKey();
    Widget pane(Lyric document, GlobalKey key) => RepaintBoundary(
        key: key,
        child: ColoredBox(
            color: Colors.white,
            child: SizedBox(
                width: 600,
                height: 300,
                child: VerticalLyricScrollView(
                    lyric: document,
                    positionStream: positions.stream,
                    readPosition: () => seconds,
                    onSeek: (_) => fail('No seek is requested'),
                    playing: true))));
    await tester.pumpWidget(_host(ChangeNotifierProvider.value(
        value: controller,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          pane(document, boundary),
          pane(controlDocument, controlBoundary),
        ]))));
    // Playback owns its existing presentation sampler. Let finite entrance
    // and scroll motion finish without waiting for live media sampling to stop.
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final original = _main(tester, text, within: find.byKey(boundary)).single;
    final control =
        _main(tester, text, within: find.byKey(controlBoundary)).single;
    final origin = tester.getTopLeft(original.finder);
    final controlOrigin = tester.getTopLeft(control.finder);
    final baseMetrics = original.text
        .computeLineMetrics()
        .map((m) => (m.baseline, m.height))
        .toList();
    expect(control.text.computeLineMetrics().map((m) => (m.baseline, m.height)),
        baseMetrics,
        reason: 'Ruby must leave the original primary baseline and word '
            'emphasis geometry identical to the real no-Ruby consumer');
    final source = original.text
        .getBoxesForSelection(
            const TextSelection(baseOffset: 7, extentOffset: 8))
        .single
        .toRect();
    final crop = source
        .shift(origin - tester.getTopLeft(find.byKey(boundary)) + original.ink);
    final controlSource = control.text
        .getBoxesForSelection(
            const TextSelection(baseOffset: 7, extentOffset: 8))
        .single
        .toRect();
    final controlCrop = controlSource.shift(controlOrigin -
        tester.getTopLeft(find.byKey(controlBoundary)) +
        control.ink);
    // Only 点 is the original phase==1 stationary slot. 終 retains the
    // legitimate original follow effect and cannot be used as a frozen mask.
    final startPixels = await _rgba(tester, boundary);
    final controlStartPixels = await _rgba(tester, controlBoundary);
    final reference = _region(startPixels, crop);
    final controlReference = _region(controlStartPixels, controlCrop);
    List<double> transform(Finder paint, GlobalKey boundary) => tester
        .renderObject<RenderBox>(paint)
        .getTransformTo(boundary.currentContext!.findRenderObject())
        .storage
        .toList(growable: false);
    final originalTransform = transform(original.finder, boundary);
    final controlTransform = transform(control.finder, controlBoundary);
    final originalPainter = tester.widget<CustomPaint>(original.finder).painter!
        as LyricWordHighlightPainter;
    final core = _coreInkBounds(startPixels, crop, originalPainter.baseColor);
    final controlCore = _coreInkBounds(
        controlStartPixels, controlCrop, originalPainter.baseColor);
    Rect actualGlyph(Finder finder, GlobalKey boundary, Rect box, Offset ink) =>
        MatrixUtils.transformRect(
            tester
                .renderObject<RenderBox>(finder)
                .getTransformTo(boundary.currentContext!.findRenderObject()),
            box.shift(ink));
    final originalGlyph =
        actualGlyph(original.finder, boundary, source, original.ink);
    final controlGlyph = actualGlyph(
        control.finder, controlBoundary, controlSource, control.ink);
    debugPrint('playing initial primary colour='
        '${originalPainter.baseColor}/${originalPainter.playedColor} '
        'activation=${originalPainter.activation} '
        'follow=${originalPainter.follow?.clock.value} '
        'transform=$originalTransform control=$controlTransform');
    final changingPixels = <int>{};
    for (final milliseconds in [200, 600, 1200, 2200, 2800, 3200, 3800, 4600]) {
      seconds = milliseconds / 1000;
      positions.add(seconds);
      await tester.pump(const Duration(milliseconds: 16));
      final current = _main(tester, text, within: find.byKey(boundary)).single;
      final controlCurrent =
          _main(tester, text, within: find.byKey(controlBoundary)).single;
      expect(current.text, same(original.text));
      expect(current.layout, same(original.layout));
      expect(
          current.text.computeLineMetrics().map((m) => (m.baseline, m.height)),
          baseMetrics);
      expect(tester.getTopLeft(current.finder), origin,
          reason: 'Media-only samples never move the entire primary paragraph');
      expect(tester.getTopLeft(controlCurrent.finder), controlOrigin);
      final live = tester.widget<CustomPaint>(current.finder).painter!
          as LyricWordHighlightPainter;
      final withoutRuby = tester
          .widget<CustomPaint>(controlCurrent.finder)
          .painter! as LyricWordHighlightPainter;
      expect(live.followWordOffsets, withoutRuby.followWordOffsets);
      expect(live.movingWordLifts, withoutRuby.movingWordLifts,
          reason: 'Adding readings must not alter the existing timed poses');
      final pixels = await _rgba(tester, boundary);
      final controlPixels = await _rgba(tester, controlBoundary);
      await capturePlaylistFeature(
          tester, boundary, 'ruby-playback-main-$milliseconds');
      _diagnoseRegion(reference, _region(pixels, crop), crop, milliseconds);
      _diagnoseRegion(controlReference, _region(controlPixels, controlCrop),
          controlCrop, milliseconds);
      debugPrint('playing primary t=$milliseconds colour='
          '${live.baseColor}/${live.playedColor} activation=${live.activation} '
          'follow=${live.follow?.clock.value} '
          'transform=${transform(current.finder, boundary)} '
          'control=${transform(controlCurrent.finder, controlBoundary)}');
      _expectSameInkRect(
          actualGlyph(current.finder, boundary, source, current.ink),
          originalGlyph,
          'Media cannot move the actual primary glyph geometry');
      _expectSameInkRect(
          actualGlyph(controlCurrent.finder, controlBoundary, controlSource,
              controlCurrent.ink),
          controlGlyph,
          'The original no-Ruby consumer has the same stationary geometry');
      _expectSameInkRect(_coreInkBounds(pixels, crop, live.baseColor), core,
          'The actual stationary glyph strokes remain at identical pixels');
      _expectSameInkRect(
          _coreInkBounds(controlPixels, controlCrop, withoutRuby.baseColor),
          controlCore,
          'The original no-Ruby strokes obey the same viewport contract');
      changingPixels.add(Object.hashAll(pixels.rgba));
    }
    expect(changingPixels.length, greaterThan(3),
        reason: 'The existing highlight/emphasis still animates');
    await capturePlaylistFeature(tester, boundary, 'ruby-playback-main');
    await capturePlaylistFeature(
        tester, controlBoundary, 'ruby-playback-main-control');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  motionTest(
      'playing multiline ruby keeps centered and right stationary glyph ink',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 600);
    const prefix = '夜空の海を渡り続ける\n';
    const suffix = '航海   点';
    const text = '$prefix$suffix';
    const lastOffset = text.length - 1;
    for (final align in [LyricTextAlign.center, LyricTextAlign.right]) {
      final line = _Line([
        _Word(prefix, 9000, 2000),
        _Word('航海   ', 0, 2500),
        _Word('点', 9000, 2000),
      ])
        ..japaneseReading = '夜空の海を渡り続ける こうかい 点'
        ..japaneseReadingSpans = const [
          JapaneseLyricReadingSpan(
              start: prefix.length, end: prefix.length + 2, text: 'こうかい'),
        ];
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance)
        ..lyricFontSize = 32
        ..lyricTextAlign = align;
      final positions = StreamController<double>.broadcast(sync: true);
      var seconds = .05;
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(positions.close);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(ChangeNotifierProvider.value(
          value: controller,
          child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                      width: 600,
                      height: 440,
                      child: VerticalLyricScrollView(
                          lyric: _Document([line]),
                          positionStream: positions.stream,
                          readPosition: () => seconds,
                          onSeek: (_) => fail('No seek is requested'),
                          playing: true)))))));
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final original = _main(tester, text, within: find.byKey(boundary)).single;
      final originalPainter = tester
          .widget<CustomPaint>(original.finder)
          .painter! as LyricWordHighlightPainter;
      final metrics = original.text.computeLineMetrics();
      expect(metrics, hasLength(2));
      expect(metrics.first.width - metrics.last.width, greaterThan(100),
          reason:
              'A short second row has a substantial native alignment shift');
      expect(originalPainter.rubyLayout!.glyphs.single.row, 1,
          reason: 'The moving snapshot belongs to the short second row');
      final source = original.text
          .getBoxesForSelection(const TextSelection(
              baseOffset: lastOffset, extentOffset: text.length))
          .single
          .toRect();
      final lineShift = lyricAlignedOffset(
          original.text.width, metrics.last.width, originalPainter.alignmentX!);
      final local = source.shift(original.ink +
          Offset(lineShift,
              originalPainter.rubyLayout!.leadingForOffset(lastOffset)));
      final paint = tester.renderObject<RenderBox>(original.finder);
      final matrix =
          paint.getTransformTo(boundary.currentContext!.findRenderObject());
      final crop = MatrixUtils.transformRect(matrix, local);
      // Native selection height includes blank leading. The stationary ROI
      // must not accidentally count the legally moving reading above it.
      expect(
          MatrixUtils.transformRect(
                  matrix, originalPainter.paintedRubyBounds.single)
              .inflate(2)
              .overlaps(crop),
          isFalse,
          reason:
              'The actual moving Ruby ink is separated from the last glyph');
      final start = await _rgba(tester, boundary);
      final core = _coreInkBounds(start, crop, originalPainter.baseColor);
      final movingSnapshots = <double>{};
      final changingPixels = <int>{};
      for (final milliseconds in [200, 600, 1200, 2200, 2800, 3200, 4600]) {
        seconds = milliseconds / 1000;
        positions.add(seconds);
        await tester.pump(const Duration(milliseconds: 16));
        final current =
            _main(tester, text, within: find.byKey(boundary)).single;
        final live = tester.widget<CustomPaint>(current.finder).painter!
            as LyricWordHighlightPainter;
        expect(current.text, same(original.text));
        expect(current.layout, same(original.layout));
        expect(live.followWordOffsets.last, 0,
            reason: 'The final glyph is the existing stationary follow slot');
        final currentMatrix = tester
            .renderObject<RenderBox>(current.finder)
            .getTransformTo(boundary.currentContext!.findRenderObject());
        final actual = MatrixUtils.transformRect(currentMatrix, local);
        expect(
            MatrixUtils.transformRect(
                    currentMatrix, live.paintedRubyBounds.single)
                .inflate(2)
                .overlaps(crop),
            isFalse,
            reason: 'Media keeps the real Ruby ink outside the stationary ROI');
        _expectSameInkRect(actual, crop,
            'Media preserves the actual $align multiline glyph geometry');
        final pixels = await _rgba(tester, boundary);
        _expectSameInkRect(_coreInkBounds(pixels, crop, live.baseColor), core,
            'Media preserves the actual $align stationary dense glyph strokes');
        movingSnapshots.add(live.paintedRubyBounds.single.top);
        changingPixels.add(Object.hashAll(pixels.rgba));
      }
      expect(movingSnapshots.length, greaterThan(3),
          reason: 'The real second-row reading snapshot moves with playback');
      expect(changingPixels.length, greaterThan(3),
          reason: 'The original highlight and emphasis still animate');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });

  motionTest('playing ruby keeps desktop layout and stationary glyph ink',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 500);
    var now = 0;
    final clock =
        PlaybackClock(automaticTicks: false, nowMilliseconds: () => now);
    addTearDown(clock.dispose);
    clock.sync(const PlaybackTimelineMessage(1, 0, true));
    const message = LyricLineTimelineMessage(
        sequence: 1,
        lineIndex: 0,
        startMilliseconds: 0,
        lengthMilliseconds: 12000,
        content: '夜空 航海 終点',
        translation: null,
        japaneseReading: 'よぞら こうかい 終点',
        japaneseReadingSpans: [
          DesktopJapaneseReadingSpan(start: 0, end: 2, text: 'よぞら'),
          DesktopJapaneseReadingSpan(start: 3, end: 5, text: 'こうかい')
        ],
        words: [
          DesktopLyricWord(0, 2500, '夜空 '),
          DesktopLyricWord(3000, 2500, '航海 '),
          DesktopLyricWord(9000, 2000, '終点')
        ]);
    final boundary = GlobalKey();
    final controlBoundary = GlobalKey();
    Widget pane(GlobalKey key, bool ruby) => RepaintBoundary(
        key: key,
        child: ColoredBox(
            color: Colors.white,
            child: DesktopLyricLineContent(
                detailedLine: message,
                legacyLine:
                    const LyricLineChangedMessage('', Duration.zero, null),
                clock: clock,
                showJapaneseReading: ruby,
                vertical: false,
                color: _inkColor,
                lyricFontSize: 48)));
    await tester.pumpWidget(_host(Column(
        mainAxisSize: MainAxisSize.min,
        children: [pane(boundary, true), pane(controlBoundary, false)])));
    await tester.pumpAndSettle();
    final original = _desktop(tester, within: find.byKey(boundary));
    final control = _desktop(tester, within: find.byKey(controlBoundary));
    final paintFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && identical(w.painter, original));
    final origin = tester.getTopLeft(paintFinder);
    final controlPaintFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && identical(w.painter, control));
    final controlOrigin = tester.getTopLeft(controlPaintFinder);
    final text =
        original.cachedShapingIdentities.whereType<TextPainter>().first;
    final controlText =
        control.cachedShapingIdentities.whereType<TextPainter>().first;
    expect(controlText.computeLineMetrics().map((m) => (m.baseline, m.height)),
        text.computeLineMetrics().map((m) => (m.baseline, m.height)));
    final source = text
        .getBoxesForSelection(
            const TextSelection(baseOffset: 7, extentOffset: 8))
        .single
        .toRect();
    final crop = source.shift(origin -
        tester.getTopLeft(find.byKey(boundary)) +
        Offset(0, original.rubyLayout!.extent));
    final controlSource = controlText
        .getBoxesForSelection(
            const TextSelection(baseOffset: 7, extentOffset: 8))
        .single
        .toRect();
    final controlCrop = controlSource
        .shift(controlOrigin - tester.getTopLeft(find.byKey(controlBoundary)));
    final reference = _region(await _rgba(tester, boundary), crop);
    final controlReference =
        _region(await _rgba(tester, controlBoundary), controlCrop);
    final changingPixels = <int>{};
    for (final milliseconds in [200, 600, 1200, 2200, 2800, 3200, 3800, 4600]) {
      now = milliseconds;
      clock.sync(PlaybackTimelineMessage(1, milliseconds, true));
      await tester.pump(const Duration(milliseconds: 16));
      final current = _desktop(tester, within: find.byKey(boundary));
      expect(current.layoutCacheIdentity, same(original.layoutCacheIdentity));
      expect(current.cachedShapingIdentities, original.cachedShapingIdentities);
      expect(tester.getTopLeft(paintFinder), origin);
      expect(tester.getTopLeft(controlPaintFinder), controlOrigin);
      final pixels = await _rgba(tester, boundary);
      await capturePlaylistFeature(
          tester, boundary, 'ruby-playback-desktop-$milliseconds');
      _diagnoseRegion(reference, _region(pixels, crop), crop, milliseconds);
      expect(_region(pixels, crop), reference);
      final controlPixels = await _rgba(tester, controlBoundary);
      _diagnoseRegion(controlReference, _region(controlPixels, controlCrop),
          controlCrop, milliseconds);
      expect(_region(controlPixels, controlCrop), controlReference);
      changingPixels.add(Object.hashAll(pixels.rgba));
    }
    expect(changingPixels.length, greaterThan(3),
        reason: 'Word highlighting is still active');
    await capturePlaylistFeature(tester, boundary, 'ruby-playback-desktop');
    await capturePlaylistFeature(
        tester, controlBoundary, 'ruby-playback-desktop-control');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}

void _diagnoseRegion(List<int> before, List<int> after, Rect crop, int time) {
  final width = crop.right.floor() - crop.left.ceil();
  var printed = 0, changed = 0, maximum = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] == after[i]) continue;
    changed++;
    final difference = (before[i] - after[i]).abs();
    if (difference > maximum) maximum = difference;
    if (printed++ < 4) {
      debugPrint('stationary ink t=$time pixel='
          '${crop.left.ceil() + i ~/ 4 % width},'
          '${crop.top.ceil() + i ~/ 4 ~/ width} channel=${i % 4} '
          '${before[i]}→${after[i]} crop=$crop');
    }
  }
  debugPrint(
      'stationary ink t=$time changedChannels=$changed maxDelta=$maximum');
}
