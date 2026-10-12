import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, sizePlaylistFeature;

const _red = Color(0xffad2453), _blue = Color(0xff1746ad);
const _tolerance = .05;
const _emojiFamily = 'DanNativeReplayEmoji';

class _Panel {
  _Panel(String text,
      {Color color = _blue,
      LyricTextAlign alignment = LyricTextAlign.left,
      this.direction = TextDirection.ltr,
      double width = 640,
      this.height = 240})
      : line = LrcLine(Duration.zero, text, isBlank: false),
        color = ValueNotifier(color),
        width = ValueNotifier(width) {
    controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance,
        japaneseReadings: japaneseReadings,
        persistAppearance: () async {})
      ..lyricFontSize = 32
      ..lyricTextAlign = alignment;
  }

  final LrcLine line;
  final TextDirection direction;
  final double height;
  final boundary = GlobalKey();
  final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
  final japaneseReadings = ValueNotifier(const JapaneseReadingPreferences());
  final position = ValueNotifier(const Duration(seconds: 20));
  final enabled = ValueNotifier(true);
  final ValueNotifier<Color> color;
  final ValueNotifier<double> width;
  late final LyricViewController controller;

  void dispose() {
    controller.dispose();
    appearance.dispose();
    japaneseReadings.dispose();
    position.dispose();
    color.dispose();
    width.dispose();
    enabled.dispose();
  }

  Widget build() => ChangeNotifierProvider.value(
        value: controller,
        child: ValueListenableBuilder<Color>(
          valueListenable: color,
          builder: (context, tint, _) => Theme(
            // Compare paint colours immediately, without a second theme clock.
            data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context)
                    .colorScheme
                    .copyWith(primary: tint, onSecondaryContainer: tint)),
            child: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (_, visible, __) => TickerMode(
                enabled: visible,
                child: ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (_, value, __) => Directionality(
                    textDirection: direction,
                    child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                        width: value,
                        height: height,
                        child: Material(
                          color: Colors.white,
                          child: ClipRect(
                            child: SingleChildScrollView(
                              primary: false,
                              child: LyricViewTile(
                                line: line,
                                position: position,
                                opacity: 1,
                                distance: 0,
                                reducedMotion: false,
                              ),
                            ),
                          ),
                        ),
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

Widget _host(List<_Panel> panels, {AppFontPolicy? fontPolicy}) {
  final policy = fontPolicy ?? AppFontPolicy.defaults();
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ThemeData(
        fontFamily: policy.uiFamily,
        fontFamilyFallback: policy.fallback,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    home: AppFontScope(
      policy: policy,
      child: MotionPreferencesScope(
        preferences: const MotionPreferences(),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topLeft,
            // Both independently shaped rows have exactly the same viewport
            // origin, clipping and sampling phase. Capture their own boundaries.
            child: Stack(
              alignment: Alignment.topLeft,
              children: [for (final panel in panels) panel.build()],
            ),
          ),
        ),
      ),
    ),
  );
}

typedef _Consumer = ({
  PlainLyricWordFollowPainter painter,
  RenderCustomPaint box
});

List<_Consumer> _consumers(_Panel panel) => [
      for (final element in find
          .descendant(
              of: find.byKey(panel.boundary),
              matching: find.byType(CustomPaint))
          .evaluate())
        if ((element.widget as CustomPaint).painter
            case final PlainLyricWordFollowPainter painter)
          if (painter.text.text!.toPlainText() == panel.line.content)
            (painter: painter, box: element.renderObject! as RenderCustomPaint),
    ];

_Consumer _presented(_Panel panel) {
  final consumers = _consumers(panel);
  final moving = consumers.where((entry) => entry.painter.glyphMorph != null);
  if (moving.isNotEmpty) return moving.single;
  expect(consumers, hasLength(1),
      reason: 'Idle releases the outgoing endpoint');
  return consumers.single;
}

List<Rect> _glyphRects(_Panel panel) {
  final consumer = _presented(panel);
  final frame = consumer.painter.glyphMorph;
  final boundary =
      panel.boundary.currentContext!.findRenderObject()! as RenderBox;
  final transform = consumer.box.getTransformTo(boundary);
  final result = <Rect>[];
  var start = 0;
  for (final cluster in panel.line.content.characters) {
    final end = start + cluster.length;
    final boxes = frame == null
        ? consumer.painter.text
            .getBoxesForSelection(
                TextSelection(baseOffset: start, extentOffset: end))
            .map((box) => box.toRect())
        : frame.geometry.boxes(start, end, frame.progress);
    for (final box in boxes) {
      result.add(MatrixUtils.transformRect(
          transform, box.shift(consumer.painter.inkOffset)));
    }
    start = end;
  }
  return result;
}

void _sameRects(List<Rect> actual, List<Rect> expected, String reason) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < actual.length; index++) {
    for (final (a, e) in [
      (actual[index].left, expected[index].left),
      (actual[index].top, expected[index].top),
      (actual[index].right, expected[index].right),
      (actual[index].bottom, expected[index].bottom),
    ]) {
      expect(a, closeTo(e, _tolerance), reason: '$reason glyph $index');
    }
  }
}

Future<Uint8List> _rgba(WidgetTester tester, _Panel panel) async =>
    (await tester.runAsync(() async {
      final boundary = panel.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final bytes =
            await image.toByteData(format: drawing.ImageByteFormat.rawRgba);
        return Uint8List.fromList(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

Future<void> _sameInk(
    WidgetTester tester, _Panel actual, _Panel reference, String reason) async {
  expect(await _rgba(tester, actual), await _rgba(tester, reference),
      reason: reason);
}

Future<void> _loadFonts() async {
  await loadLetterSpacingFonts();
  // These read-only fixtures supply actual Arabic/Hebrew and COLR emoji glyphs
  // in the software engine. A missing fixture must fail, not pass with Ahem boxes.
  final windows = Platform.environment['WINDIR'];
  expect(windows, isNotNull,
      reason: 'This native replay fixture requires Windows');
  for (final (family, name) in [
    ('Segoe UI', 'segoeui.ttf'),
    ('Segoe UI Emoji', 'seguiemj.ttf'),
    (_emojiFamily, 'seguiemj.ttf'),
  ]) {
    final font = File('$windows/Fonts/$name');
    expect(await font.exists(), isTrue,
        reason: '$family fixture must be present');
    await (FontLoader(family)
          ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes()))))
        .load();
  }
}

// Observe commands emitted by the actual production painter. No movement,
// grouping, clip partition or paragraph shaping is reproduced in this fixture.
class _ReplayCanvas implements Canvas {
  _ReplayCanvas(this.delegate);
  final Canvas delegate;
  int pictures = 0;
  @override
  void save() => delegate.save();
  @override
  void restore() => delegate.restore();
  @override
  void translate(double dx, double dy) => delegate.translate(dx, dy);
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      delegate.clipPath(path, doAntiAlias: doAntiAlias);
  @override
  Rect getLocalClipBounds() => delegate.getLocalClipBounds();
  @override
  void drawPicture(drawing.Picture picture) {
    pictures++;
    delegate.drawPicture(picture);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected replay operation ${invocation.memberName}');
}

({int cells, int pictures, int sourceUnits, int microseconds}) _replayCost(
    _Panel panel) {
  final consumer = _presented(panel);
  final frame = consumer.painter.glyphMorph;
  expect(frame, isNotNull);
  final boundary =
      panel.boundary.currentContext!.findRenderObject()! as RenderBox;
  final localClip = MatrixUtils.transformRect(
      Matrix4.inverted(consumer.box.getTransformTo(boundary)),
      Offset.zero & boundary.size);
  final recorder = drawing.PictureRecorder();
  final delegate = Canvas(recorder, localClip)
    ..clipRect(localClip, doAntiAlias: false);
  final canvas = _ReplayCanvas(delegate);
  final watch = Stopwatch()..start();
  consumer.painter.paint(canvas, consumer.box.size);
  watch.stop();
  recorder.endRecording().dispose();
  return (
    cells: frame!.geometry.cells.length,
    pictures: canvas.pictures,
    sourceUnits: consumer.painter.text.text!.toPlainText().length,
    microseconds: watch.elapsedMicroseconds,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final (name, text, direction, alignment) in [
    (
      'mixed fonts',
      'office ffi e\u0301 音楽 한글 ★♭',
      TextDirection.ltr,
      LyricTextAlign.left
    ),
    (
      'RTL joining',
      'مرحبا שלום ffi e\u0301 音楽 한글',
      TextDirection.rtl,
      LyricTextAlign.right
    ),
    (
      'COLR emoji',
      '音楽 ❤️ 👨‍👩‍👧‍👦 e\u0301 ★♭',
      TextDirection.ltr,
      LyricTextAlign.left
    ),
  ]) {
    testWidgets(
        'native spacing replay preserves live palette and retarget $name',
        (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 600);
      final changed =
          _Panel(text, color: _red, direction: direction, alignment: alignment);
      final reference =
          _Panel(text, direction: direction, alignment: alignment);
      addTearDown(changed.dispose);
      addTearDown(reference.dispose);
      final defaults = AppFontPolicy.defaults();
      final policy = name != 'COLR emoji'
          ? defaults
          : AppFontPolicy(
              language: defaults.language,
              mixedScripts: defaults.mixedScripts,
              zh: defaults.zh,
              en: defaults.en,
              ja: defaults.ja,
              ko: defaults.ko,
              // Windows has a real monochrome Segoe UI Symbol before Emoji in
              // the production fallback order. The software font manager does
              // not. This fixture specifically tests COLR, so select its loaded
              // unique family ahead of Symbol without changing language faces.
              baseFallback: const AppFontFace(
                  id: 'native-replay-colr-fixture', family: _emojiFamily));
      await tester.pumpWidget(_host([changed, reference], fontPolicy: policy));
      await tester.pumpAndSettle();
      final blueSource = await _rgba(tester, reference);
      if (name == 'COLR emoji') {
        var colouredInk = 0;
        for (var i = 0; i < blueSource.length; i += 4) {
          if (blueSource[i] > blueSource[i + 1] + 40 &&
              blueSource[i] > blueSource[i + 2] + 40) {
            colouredInk++;
          }
        }
        expect(colouredInk, greaterThan(100),
            reason: 'The blue text fixture must contain real red emoji ink');
      }
      changed.controller.setLyricLetterSpacing(8);
      reference.controller.setLyricLetterSpacing(8);
      await tester.pump();
      expect(await _rgba(tester, reference), blueSource,
          reason: 'Entering native replay preserves the exact original raster');
      await tester.pump(const Duration(milliseconds: 96));
      final frame = _presented(changed).painter.glyphMorph;
      expect(frame, isNotNull);
      expect(frame!.progress, inExclusiveRange(0, 1));
      final beforePalette = _glyphRects(changed);
      changed.color.value = _blue;
      await tester.pump();
      _sameRects(_glyphRects(changed), beforePalette,
          'Paint-only palette changes preserve glyph geometry');
      await _sameInk(tester, changed, reference,
          'Dynamic tint equals an independently shaped blue source paragraph');
      await capturePlaylistFeature(
          tester, changed.boundary, 'native-replay-$name-palette');

      final beforeReverse = _glyphRects(changed);
      final reversePixels = await _rgba(tester, changed);
      changed.controller.setLyricLetterSpacing(2);
      reference.controller.setLyricLetterSpacing(2);
      await tester.pump();
      _sameRects(_glyphRects(changed), beforeReverse,
          'Reversal begins at the currently presented viewport glyphs');
      expect(await _rgba(tester, changed), reversePixels,
          reason: 'A retained source does not repaint at a different phase');
      await _sameInk(tester, changed, reference,
          'Palette ownership survives rapid retargeting');
      await tester.pump(const Duration(milliseconds: 48));
      changed.width.value = 360;
      reference.width.value = 360;
      await tester.pump();
      await _sameInk(tester, changed, reference,
          'Resizing retains the original font tree and live colour source');
      await tester
          .pump(LyricMotion.lineDuration + const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(_presented(changed).painter.glyphMorph, isNull);
      expect(_presented(changed).painter.text.text!.toPlainText(), text);
      expect(changed.line.content, text);
      await _sameInk(tester, changed, reference,
          'Both retargeted paragraphs converge to the same native endpoint');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
      'native spacing visible replay groups do not grow with hidden tail',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 600);
    // Both lengths bypass the short-line balance heuristic. They have the same
    // visible prefix, font and native wrapping, with ten times the hidden tail.
    final short = _Panel(List.filled(900, '音').join(), width: 760, height: 220);
    final long = _Panel(List.filled(9000, '音').join(), width: 760, height: 220);
    addTearDown(short.dispose);
    addTearDown(long.dispose);
    await tester.pumpWidget(_host([short, long]));
    await tester.pumpAndSettle();
    await _sameInk(
        tester, short, long, 'The visible native prefixes are identical');
    short.controller.setLyricLetterSpacing(8);
    long.controller.setLyricLetterSpacing(8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    await _sameInk(tester, short, long,
        'Hidden tail does not alter visible source clips or glyph motion');
    final a = _replayCost(short), b = _replayCost(long);
    expect(b.sourceUnits, a.sourceUnits * 10);
    expect(b.cells, greaterThan(a.cells * 9));
    expect(a.pictures, greaterThan(0));
    expect(b.pictures, a.pictures,
        reason: 'Only groups intersecting the real viewport are replayed');
    expect(b.pictures, lessThan(a.cells),
        reason: 'The offscreen paragraph is not replayed once for every cell');
    debugPrint('NATIVE_REPLAY_COST short=$a long=$b '
        'full paragraph replays retain G x N source complexity; '
        'command counts do not prove bounded GPU cost');
    long.enabled.value = false;
    short.enabled.value = false;
    await tester.pump();
    expect(_presented(short).painter.glyphMorph, isNull);
    expect(_presented(long).painter.glyphMorph, isNull);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
