import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/lyric_glyph_morph.dart';
import 'package:desktop_lyric/lyric_ruby.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart' show sizePlaylistFeature;

// The user's recorded sentence, including its second-row Han readings.
const _recordedText = '足が立つこの大地 櫻舞う';
const _recordedSpans = [
  JapaneseLyricReadingSpan(start: 0, end: 1, text: 'あし'),
  JapaneseLyricReadingSpan(start: 2, end: 3, text: 'た'),
  JapaneseLyricReadingSpan(start: 6, end: 8, text: 'だいち'),
  JapaneseLyricReadingSpan(start: 9, end: 10, text: 'さくら'),
  JapaneseLyricReadingSpan(start: 10, end: 11, text: 'ま'),
];

class _Word extends SyncLyricWord {
  _Word(int index, String text)
      : super(Duration(milliseconds: index * 350),
            const Duration(milliseconds: 1000), text);
}

class _Line extends SyncLyricLine {
  _Line(String text, {bool grouped = false})
      : super(
            Duration.zero,
            const Duration(seconds: 8),
            grouped
                ? [_Word(0, text)]
                : [for (final (i, c) in text.characters.indexed) _Word(i, c)],
            '我们所立足的这片大地 此刻樱花乱舞');
}

typedef _Consumer = ({RenderCustomPaint render, LyricGlyphMorphConsumer ink});

_Consumer _presented(WidgetTester tester, String text) {
  final painters = <_Consumer>[];
  for (final element in find.byType(CustomPaint).evaluate()) {
    final render = element.renderObject! as RenderCustomPaint;
    final ink = render.painter;
    if (ink is! PlainLyricWordFollowPainter &&
        ink is! LyricWordHighlightPainter) {
      continue;
    }
    final consumer = ink as LyricGlyphMorphConsumer;
    if (consumer.glyphParagraph.text!.toPlainText() == text) {
      painters.add((render: render, ink: consumer));
    }
  }
  final moving = painters.where((p) => p.ink.glyphMorph != null).toList();
  if (moving.isNotEmpty) {
    expect(moving, hasLength(1));
    return moving.single;
  }
  expect(painters, hasLength(1));
  return painters.single;
}

LyricRubyLayout _ruby(_Consumer p) => switch (p.ink) {
      LyricWordHighlightPainter() =>
        (p.ink as LyricWordHighlightPainter).rubyLayout!,
      _ => (p.ink as PlainLyricWordFollowPainter).ruby!,
    };

double _visibility(_Consumer p) => switch (p.ink) {
      LyricWordHighlightPainter() =>
        (p.ink as LyricWordHighlightPainter).rubyVisibility,
      _ => (p.ink as PlainLyricWordFollowPainter).rubyVisibility,
    };

/// The native source line boundary owns a reading's first fragment. The
/// reading stays complete; selecting a provider's whole multi-row word would
/// attach it to the union of unrelated glyphs on the preceding row.
List<Rect> _attachedReadings(_Consumer p) {
  final ruby = _ruby(p), paragraph = p.ink.glyphParagraph;
  final morph = p.ink.glyphMorph;
  return [
    for (final glyph in ruby.glyphs)
      () {
        final range =
            paragraph.getLineBoundary(TextPosition(offset: glyph.span.start));
        var bounds = morph?.geometry.bounds(glyph.span.start,
            math.min(glyph.span.end, range.end), morph.progress);
        if (p.ink case final LyricWordHighlightPainter timed
            when timed.movingWordCount > 0) {
          // This fixture supplies one native CJK cluster per authored word.
          // Public word effects supply the existing media-time pose; native
          // selection gives its original pivot, while morph gives the current
          // primary pivot. The reading is still painted by its native font.
          Rect? presented;
          var start = 0;
          for (final (index, word) in timed.line.words.indexed) {
            final end = start + word.content.length;
            final fragmentStart = math.max(start, glyph.span.start);
            final fragmentEnd =
                math.min(end, math.min(glyph.span.end, range.end));
            if (fragmentStart < fragmentEnd) {
              final native = paragraph.getBoxesForSelection(TextSelection(
                  baseOffset: fragmentStart, extentOffset: fragmentEnd));
              Rect? part;
              for (final box in native) {
                part = part == null
                    ? box.toRect()
                    : part.expandToInclude(box.toRect());
              }
              if (part != null) {
                var current = morph?.geometry
                        .bounds(fragmentStart, fragmentEnd, morph.progress) ??
                    part;
                final wordBoxes = paragraph.getBoxesForSelection(
                    TextSelection(baseOffset: start, extentOffset: end),
                    boxHeightStyle:
                        drawing.BoxHeightStyle.includeLineSpacingMiddle);
                final raw = LyricWordEffects.timedPose(
                    elapsedMilliseconds:
                        (timed.position - word.start).inMicroseconds / 1000,
                    durationMilliseconds: word.length.inMilliseconds,
                    fontSize: timed.paintedFontSize,
                    phraseEnd: index == timed.line.words.length - 1);
                if (raw.lift > .001 &&
                    wordBoxes.length == 1 &&
                    word.content.trim().isNotEmpty) {
                  final wholeWord =
                      morph?.geometry.bounds(start, end, morph.progress) ??
                          wordBoxes.single.toRect();
                  final pivot = wholeWord.center.dy;
                  final scaleY = 1 + (raw.scale - 1) * timed.activation;
                  final lift = raw.lift * timed.activation;
                  current = Rect.fromLTRB(
                      current.left,
                      pivot - lift + (current.top - pivot) * scaleY,
                      current.right,
                      pivot - lift + (current.bottom - pivot) * scaleY);
                }
                presented = presented == null
                    ? current
                    : presented.expandToInclude(current);
              }
            }
            start = end;
          }
          bounds = presented;
        }
        final displacement = bounds == null
            ? Offset.zero
            : Offset(bounds.center.dx - glyph.source.center.dx,
                bounds.top - glyph.source.top);
        return (glyph.offset & glyph.painter.size).shift(p.ink.glyphInkOffset +
            displacement +
            Offset(0, ruby.leadingForGlyph(glyph) * _visibility(p)));
      }(),
  ];
}

/// Replay the unchanged real primary painter and real, already-shaped native
/// reading paragraphs. Only their attachment and finite tint-layer coverage
/// are supplied independently. No raster tolerance or filter is introduced.
class _AttachedRubyReference extends CustomPainter {
  _AttachedRubyReference(this.source, this.readings);
  final _Consumer source;
  final List<Rect> readings;
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    final ruby = _ruby(source);
    final retained = List<LyricRubyGlyph>.of(ruby.glyphs);
    final baseBounds = ruby.paintBounds.inflate(ruby.extent * 2 + 24);
    ruby.glyphs.clear();
    try {
      (source.ink as CustomPainter).paint(canvas, size);
    } finally {
      ruby.glyphs.addAll(retained);
    }
    final origin = source.ink.glyphInkOffset;
    final local = readings.map((r) => r.shift(-origin)).toList();
    var coverage = baseBounds;
    for (final rect in local) {
      coverage = coverage.expandToInclude(rect);
    }
    final tint = switch (source.ink) {
      LyricWordHighlightPainter() =>
        (source.ink as LyricWordHighlightPainter).playedColor,
      _ => (source.ink as PlainLyricWordFollowPainter).color ?? ruby.color,
    };
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.saveLayer(
        coverage,
        Paint()
          ..colorFilter = ColorFilter.mode(
              tint.withValues(alpha: tint.a * _visibility(source)),
              BlendMode.srcIn));
    for (final (index, glyph) in retained.indexed) {
      glyph.painter.paint(canvas, local[index].topLeft);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AttachedRubyReference oldDelegate) => true;
}

Future<({Uint8List rgba, Uint8List png})> _pixels(
        WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final rgba =
            await image.toByteData(format: drawing.ImageByteFormat.rawRgba);
        final png = await image.toByteData(format: drawing.ImageByteFormat.png);
        return (
          rgba: Uint8List.fromList(
              rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes)),
          png: Uint8List.fromList(
              png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))
        );
      } finally {
        image.dispose();
      }
    }))!;

Future<void> _checkInk(WidgetTester tester, GlobalKey boundary,
    _Consumer source, String sample) async {
  final expectedRects = _attachedReadings(source);
  final actual = await _pixels(tester, boundary);
  final reference = _AttachedRubyReference(source, expectedRects);
  late ({Uint8List rgba, Uint8List png}) expected;
  final original = source.render.painter;
  try {
    source.render.painter = reference;
    tester.binding.rootPipelineOwner.flushCompositingBits();
    tester.binding.rootPipelineOwner.flushPaint();
    expected = await _pixels(tester, boundary);
    expect(reference.paints, greaterThan(0));
    expect(source.render.painter, same(reference));
  } finally {
    source.render.painter = original;
    tester.binding.rootPipelineOwner.flushCompositingBits();
    tester.binding.rootPipelineOwner.flushPaint();
  }
  final output = Platform.environment['DAN_RUBY_SPACING_RENDER_DIR'];
  if (output != null && output.isNotEmpty) {
    final workspace = Platform.environment['DAN_PLAYER_WORKSPACE'] ??
        Directory.current.parent.path;
    final allowed =
        path.join(workspace, 'tool', 'qa-local', 'global-opt-oct12');
    expect(path.isWithin(allowed, path.absolute(output)), isTrue);
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File(path.join(output, '$sample-actual.png'))
          .writeAsBytes(actual.png);
      await File(path.join(output, '$sample-reference.png'))
          .writeAsBytes(expected.png);
    });
  }
  expect(actual.rgba.length, expected.rgba.length);
  var attachmentDiagnostic = '';
  if (source.ink is LyricWordHighlightPainter) {
    final rects = (source.ink as LyricWordHighlightPainter).paintedRubyBounds;
    final coverage = _ruby(source)
        .paintBounds
        .inflate(_ruby(source).extent * 2 + 24)
        .shift(source.ink.glyphInkOffset);
    attachmentDiagnostic = [
      for (var i = 0; i < expectedRects.length; i++)
        '${_ruby(source).glyphs[i].span.text}: '
            'positionDelta=${rects[i].topLeft - expectedRects[i].topLeft}, '
            'outsideOldLayer=${!coverage.contains(expectedRects[i].topLeft) || !coverage.contains(expectedRects[i].bottomRight)}'
    ].join('; ');
  }
  var differencePixels = 0, maximumDelta = 0;
  for (var offset = 0; offset < actual.rgba.length; offset += 4) {
    var differs = false;
    for (var channel = 0; channel < 4; channel++) {
      final delta =
          (actual.rgba[offset + channel] - expected.rgba[offset + channel])
              .abs();
      maximumDelta = math.max(maximumDelta, delta);
      differs |= delta != 0;
    }
    if (differs) differencePixels++;
  }
  expect(differencePixels, 0,
      reason: '$sample: native reading pixels must remain at their attached '
          'source fragment and inside the tint layer; max RGBA delta '
          '$maximumDelta, differing pixels $differencePixels. '
          '$attachmentDiagnostic');
  if (source.ink is LyricWordHighlightPainter) {
    final actualRects =
        (source.ink as LyricWordHighlightPainter).paintedRubyBounds;
    for (var index = 0; index < expectedRects.length; index++) {
      final a = actualRects[index], e = expectedRects[index];
      expect(a.left, closeTo(e.left, .05));
      expect(a.top, closeTo(e.top, .05));
      expect(a.right, closeTo(e.right, .05));
      expect(a.bottom, closeTo(e.bottom, .05));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  for (final kind in ['sync', 'plain', 'timed', 'groupedSync', 'activeSync']) {
    testWidgets('second-row ruby survives spacing handoff $kind',
        (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 600);
      final grouped = kind == 'groupedSync';
      final active = kind == 'activeSync';
      final text = grouped ? '夜空 e\u0301 航海' : _recordedText;
      final spans = grouped
          ? const [JapaneseLyricReadingSpan(start: 6, end: 8, text: 'こうかい')]
          : _recordedSpans;
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults.copyWith(
          lyricLetterSpacing: grouped ? 0 : 12, showJapaneseReading: true));
      final japanese = ValueNotifier(const JapaneseReadingPreferences());
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance,
          japaneseReadings: japanese,
          persistAppearance: () async {})
        ..lyricFontSize = grouped ? 22 : 32
        ..lyricTextAlign = LyricTextAlign.left;
      final expectedPosition = active
          ? const Duration(milliseconds: 3650)
          : const Duration(seconds: 20);
      final position = ValueNotifier(expectedPosition);
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(japanese.dispose);
      addTearDown(position.dispose);
      final LyricLine line = kind == 'sync' || grouped || active
          ? _Line(text, grouped: grouped)
          : LrcLine(Duration.zero, text,
              isBlank: false,
              length:
                  kind == 'timed' ? const Duration(seconds: 8) : Duration.zero);
      line.japaneseReadingSpans = spans;
      line.japaneseReading = spans.map((span) => span.text).join(' ');
      final boundary = GlobalKey();
      final policy = AppFontPolicy.defaults();
      await tester.pumpWidget(MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
              fontFamily: policy.uiFamily,
              fontFamilyFallback: policy.fallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          home: AppFontScope(
              policy: policy,
              child: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: ChangeNotifierProvider.value(
                          value: controller,
                          child: RepaintBoundary(
                              key: boundary,
                              child: SizedBox(
                                  width: grouped ? 140 : 620,
                                  height: 320,
                                  child: Material(
                                      color: Colors.white,
                                      child: LyricViewTile(
                                          line: line,
                                          position: position,
                                          opacity: 1,
                                          distance: 0,
                                          reducedMotion: false))))))))));
      await tester.pumpAndSettle();
      final before = _presented(tester, text);
      expect(before.ink.glyphParagraph.computeLineMetrics(), hasLength(2));
      expect(_ruby(before).glyphs.last.row, 1);
      if (active) {
        final timed = before.ink as LyricWordHighlightPainter;
        expect(timed.movingWordCount, greaterThan(0));
        if (timed.follow != null) expect(timed.follow!.clock.value, 1);
      }
      await _checkInk(tester, boundary, before, '$kind-static');
      controller.setLyricLetterSpacing(grouped ? 8 : 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));
      final middle = _presented(tester, text);
      expect(middle.ink.glyphMorph, isNotNull);
      expect(middle.ink.glyphMorph!.progress, inExclusiveRange(0, 1));
      await _checkInk(tester, boundary, middle, '$kind-96ms');
      await tester.pump(const Duration(milliseconds: 96));
      await _checkInk(
          tester, boundary, _presented(tester, text), '$kind-192ms');
      await tester.pumpAndSettle();
      final settled = _presented(tester, text);
      expect(settled.ink.glyphMorph, isNull);
      if (!grouped) {
        expect(settled.ink.glyphParagraph.computeLineMetrics(), hasLength(1));
      }
      await _checkInk(tester, boundary, settled, '$kind-settled');
      expect(position.value, expectedPosition);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
