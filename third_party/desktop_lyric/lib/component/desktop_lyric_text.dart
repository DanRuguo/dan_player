import 'dart:math' as math;

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// A whole Unicode grapheme or a vertical display unit, never a partial UTF-16
/// code unit. Original string offsets let timed words and painted units share
/// one stable layout.
class DesktopLyricGlyph {
  const DesktopLyricGlyph(this.text, this.start, this.end,
      {this.horizontal = false});
  final String text;
  final int start;
  final int end;

  /// Foreign words stay upright on one row in a vertical lyric column. CJK
  /// graphemes and emoji keep the traditional top-to-bottom progression.
  final bool horizontal;
}

List<DesktopLyricGlyph> desktopLyricGlyphs(String text) {
  var offset = 0;
  return [
    for (final grapheme in text.characters)
      DesktopLyricGlyph(grapheme, offset, offset += grapheme.length)
  ];
}

bool _isVerticalCjk(int rune) =>
    (rune >= 0x1100 && rune <= 0x11ff) || // Hangul Jamo
    (rune >= 0x2e80 && rune <= 0x303f) || // CJK radicals/punctuation
    (rune >= 0x3040 && rune <= 0x30ff) || // Hiragana/Katakana
    (rune >= 0x3100 && rune <= 0x31bf) || // Bopomofo
    (rune >= 0x31f0 && rune <= 0x31ff) || // Katakana extensions
    (rune >= 0x3400 && rune <= 0x4dbf) || // CJK Extension A
    (rune >= 0x4e00 && rune <= 0x9fff) || // Unified ideographs
    (rune >= 0xa960 && rune <= 0xa97f) || // Hangul Jamo Extended-A
    (rune >= 0xac00 && rune <= 0xd7ff) || // Hangul syllables/Jamo B
    (rune >= 0xf900 && rune <= 0xfaff) || // Compatibility ideographs
    (rune >= 0xff66 && rune <= 0xff9d) || // Half-width Katakana
    (rune >= 0x20000 && rune <= 0x323af); // Supplementary CJK

bool _isStandalonePictograph(DesktopLyricGlyph glyph) {
  final rune = glyph.text.runes.first;
  return (rune >= 0x1f000 && rune <= 0x1faff) ||
      (rune >= 0x2600 && rune <= 0x27bf) ||
      glyph.text.contains('\u20e3');
}

bool _isVerticalSeparator(DesktopLyricGlyph glyph) => glyph.text.trim().isEmpty;

/// Segments a vertical lyric into readable rows.
///
/// CJK text and emoji retain one grapheme per row. Other space-delimited text
/// stays in one upright row, so `can't`, `mother-in-law`, abbreviations,
/// numbers and their adjacent punctuation are never split into letters.
List<DesktopLyricGlyph> desktopLyricVerticalUnits(String text) {
  final graphemes = desktopLyricGlyphs(text);
  final units = <DesktopLyricGlyph>[];
  var index = 0;
  while (index < graphemes.length) {
    final current = graphemes[index];
    if (_isVerticalSeparator(current)) {
      index += 1;
      continue;
    }
    if (_isVerticalCjk(current.text.runes.first) ||
        _isStandalonePictograph(current)) {
      units.add(current);
      index += 1;
      continue;
    }

    final first = index;
    index += 1;
    while (index < graphemes.length) {
      final next = graphemes[index];
      if (_isVerticalSeparator(next) ||
          _isVerticalCjk(next.text.runes.first) ||
          _isStandalonePictograph(next)) {
        break;
      }
      index += 1;
    }
    units.add(DesktopLyricGlyph(
      graphemes.sublist(first, index).map((glyph) => glyph.text).join(),
      graphemes[first].start,
      graphemes[index - 1].end,
      horizontal: true,
    ));
  }
  return units;
}

/// Cached horizontal paragraph or upright grapheme column. Clock ticks repaint
/// only; no word/glyph widget layout is performed at playback frequency.
class DesktopLyricText extends StatefulWidget {
  const DesktopLyricText(
      {super.key,
      required this.text,
      required this.clock,
      required this.style,
      required this.playedColor,
      required this.unplayedColor,
      this.strokeColor,
      this.words = const [],
      this.vertical = false,
      this.maxVerticalUnitWidth,
      this.maxHorizontalWidth,
      this.reducedMotion = false});

  final String text;
  final PlaybackClock clock;
  final TextStyle style;
  final Color playedColor;
  final Color unplayedColor;
  final Color? strokeColor;
  final List<DesktopLyricWord> words;
  final bool vertical;
  final double? maxVerticalUnitWidth;

  /// Bounded single-line mode shares the same timed-word painter. Flutter's
  /// paragraph ellipsis excludes hidden glyphs from the existing word boxes.
  final double? maxHorizontalWidth;
  final bool reducedMotion;

  @override
  State<DesktopLyricText> createState() => _DesktopLyricTextState();
}

class _DesktopLyricTextState extends State<DesktopLyricText> {
  Object? _identity;
  Object? _shapeIdentity;
  _DesktopLyricTextShaping? _shaping;
  _DesktopLyricTextLayout? _layout;
  bool _reduced = true;
  int _wordEndMilliseconds = 0;

  @override
  void initState() {
    super.initState();
    _attachClock();
  }

  void _attachClock() {
    if (widget.words.isNotEmpty) {
      widget.clock.addListener(_syncSamplingDemand);
    }
  }

  @override
  void didUpdateWidget(DesktopLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock) ||
        !identical(oldWidget.words, widget.words)) {
      if (oldWidget.words.isNotEmpty) {
        oldWidget.clock.removeListener(_syncSamplingDemand);
      }
      oldWidget.clock.setVisualSamplingDemand(this, false);
      _attachClock();
    }
  }

  void _syncSamplingDemand() {
    widget.clock.setVisualSamplingDemand(
        this,
        !_reduced &&
            widget.words.isNotEmpty &&
            widget.clock.positionMilliseconds < _wordEndMilliseconds);
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final fontPolicy = AppFontScope.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final reducedMotion = widget.reducedMotion ||
        !AppMotion.enabled(context, MotionKind.lyrics) ||
        !TickerMode.valuesOf(context).enabled;
    _reduced = reducedMotion;
    // TextPainter does not inherit the app's font as Text does. Merge the real
    // desktop typography before caching so CJK/fallback fonts stay identical.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final shapeIdentity = (
      widget.text,
      widget.words,
      widget.vertical,
      !widget.vertical &&
          widget.maxHorizontalWidth != null &&
          widget.maxHorizontalWidth!.isFinite,
      style,
      widget.playedColor,
      widget.unplayedColor,
      widget.strokeColor,
      direction,
      scaler,
      locale,
      fontPolicy
    );
    final identity = (
      shapeIdentity,
      widget.maxVerticalUnitWidth,
      widget.maxHorizontalWidth,
    );
    if (_identity != identity) {
      if (_shapeIdentity != shapeIdentity) {
        _shaping?.dispose();
        _shaping = _DesktopLyricTextShaping(
            text: widget.text,
            words: widget.words,
            vertical: widget.vertical,
            bounded: !widget.vertical &&
                widget.maxHorizontalWidth != null &&
                widget.maxHorizontalWidth!.isFinite,
            style: style,
            playedColor: widget.playedColor,
            unplayedColor: widget.unplayedColor,
            strokeColor: widget.strokeColor,
            direction: direction,
            scaler: scaler,
            locale: locale,
            fontPolicy: fontPolicy);
        _shapeIdentity = shapeIdentity;
      }
      _layout = _DesktopLyricTextLayout(
          shaping: _shaping!,
          maxVerticalUnitWidth: widget.maxVerticalUnitWidth,
          maxHorizontalWidth: widget.maxHorizontalWidth);
      _identity = identity;
      // A bounded paragraph can omit trailing authored words entirely. Only
      // words with visible shaped boxes can keep its sampler alive. Recompute
      // after every width/font/direction/mode layout, including restored glyphs.
      _wordEndMilliseconds = 0;
      for (var index = 0; index < _layout!.words.length; index++) {
        if (_layout!.wordExtents[index] <= 0) continue;
        final word = _layout!.words[index];
        _wordEndMilliseconds = math.max(_wordEndMilliseconds,
            word.startMilliseconds + math.max(0, word.lengthMilliseconds));
      }
    }
    _syncSamplingDemand();
    return SizedBox.fromSize(
      size: _layout!.size,
      child: RepaintBoundary(
          child: CustomPaint(
        painter: DesktopLyricTextPainter._(
            layout: _layout!,
            clock: widget.clock,
            reducedMotion: reducedMotion),
        isComplex: true,
        willChange: widget.words.isNotEmpty && !reducedMotion,
      )),
    );
  }

  @override
  void dispose() {
    widget.clock.setVisualSamplingDemand(this, false);
    if (widget.words.isNotEmpty) {
      widget.clock.removeListener(_syncSamplingDemand);
    }
    _shaping?.dispose();
    super.dispose();
  }
}

class _GlyphShaping {
  _GlyphShaping(this.glyph, this.base, this.highlight, this.stroke);
  final DesktopLyricGlyph glyph;
  final TextPainter base;
  final TextPainter highlight;
  final TextPainter? stroke;
}

/// Width changes relayout retained horizontal paragraphs or rescale already
/// shaped vertical units. Text, typography and paint changes own their lifetime.
class _DesktopLyricTextShaping {
  _DesktopLyricTextShaping(
      {required this.text,
      required List<DesktopLyricWord> words,
      required this.vertical,
      required bool bounded,
      required TextStyle style,
      required Color playedColor,
      required Color unplayedColor,
      required Color? strokeColor,
      required TextDirection direction,
      required TextScaler scaler,
      required Locale? locale,
      required AppFontPolicy fontPolicy})
      : words = _DesktopLyricTextLayout._shapedWords(text, words) {
    fontSize = scaler.scale(style.fontSize ?? 22);
    TextPainter painter(String text, Color color, {UiLanguage? language}) =>
        TextPainter(
          text: appFontSpan(text,
              style: style.copyWith(color: color),
              policy: fontPolicy,
              language: language),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
          ellipsis: bounded ? '…' : null,
        );
    TextPainter? outline(String text, {UiLanguage? language}) =>
        strokeColor == null
            ? null
            : (TextPainter(
                text: appFontSpan(text,
                    policy: fontPolicy,
                    language: language,
                    style: style.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth =
                            ((style.fontSize ?? 22) * .06).clamp(1.2, 2.4)
                        ..strokeJoin = StrokeJoin.round
                        ..color = strokeColor,
                      shadows: const [],
                    )),
                textDirection: direction,
                textScaler: scaler,
                locale: locale,
                maxLines: 1,
                ellipsis: bounded ? '…' : null,
              ));
    if (!vertical) {
      base = painter(text, unplayedColor);
      highlight = painter(text, playedColor);
      stroke = outline(text);
      return;
    }
    // Resolve script context on the complete original line, then reuse it for
    // upright units. Isolated Han glyphs would otherwise lose adjacent Kana
    // or Hangul context. UTF-16 starts still belong to the authored text.
    final runs = fontPolicy.mixedScripts
        ? appFontRuns(text, fontPolicy.language)
        : const <AppFontRun>[];
    var runIndex = 0;
    var runEnd = runs.isEmpty ? text.length : runs.first.text.length;
    for (final glyph in desktopLyricVerticalUnits(text)) {
      while (runIndex + 1 < runs.length && glyph.start >= runEnd) {
        runIndex++;
        runEnd += runs[runIndex].text.length;
      }
      final language =
          runs.isEmpty ? fontPolicy.language : runs[runIndex].language;
      final display =
          glyph.text == '\n' || glyph.text == '\r\n' ? ' ' : glyph.text;
      final stroke = outline(display, language: language);
      stroke?.layout();
      glyphs.add(_GlyphShaping(
          glyph,
          painter(display, unplayedColor, language: language)..layout(),
          painter(display, playedColor, language: language)..layout(),
          stroke));
    }
  }

  final String text;
  final List<DesktopLyricWord> words;
  final bool vertical;
  late final double fontSize;
  final List<_GlyphShaping> glyphs = [];
  TextPainter? base;
  TextPainter? highlight;
  TextPainter? stroke;

  void dispose() {
    base?.dispose();
    highlight?.dispose();
    stroke?.dispose();
    for (final glyph in glyphs) {
      glyph.base.dispose();
      glyph.highlight.dispose();
      glyph.stroke?.dispose();
    }
  }
}

class _GlyphPaint {
  _GlyphPaint(this.shaping,
      {required this.bounds, required this.paintOffset, required this.scale});
  final _GlyphShaping shaping;
  DesktopLyricGlyph get glyph => shaping.glyph;
  TextPainter get base => shaping.base;
  TextPainter get highlight => shaping.highlight;
  TextPainter? get stroke => shaping.stroke;
  final Rect bounds;
  final Offset paintOffset;
  final double scale;
}

/// Each width owns independent geometry, so replacing a layout never mutates
/// the old painter's boxes or makes shouldRepaint miss a retained paragraph.
class _DesktopLyricTextLayout {
  _DesktopLyricTextLayout(
      {required this.shaping,
      required double? maxVerticalUnitWidth,
      required double? maxHorizontalWidth}) {
    if (!vertical) {
      final width = maxHorizontalWidth == null
          ? double.infinity
          : math.max(0.0, maxHorizontalWidth);
      base!.layout(maxWidth: width);
      highlight!.layout(maxWidth: width);
      stroke?.layout(maxWidth: width);
      size = base!.size;
      var offset = 0;
      for (final word in words) {
        wordBoxes.add(base!
            .getBoxesForSelection(TextSelection(
              baseOffset: offset,
              extentOffset: offset += word.content.length,
            ))
            .map((box) => (
                  rect: box.toRect(),
                  rtl: box.direction == TextDirection.rtl,
                  horizontal: true,
                ))
            .toList(growable: false));
      }
      return;
    }
    final widthLimit = maxVerticalUnitWidth != null &&
            maxVerticalUnitWidth.isFinite &&
            maxVerticalUnitWidth > 0
        ? maxVerticalUnitWidth
        : double.infinity;
    double scaleFor(_GlyphShaping glyph) =>
        glyph.base.width > widthLimit ? widthLimit / glyph.base.width : 1;
    final columnWidth = shaping.glyphs.fold<double>(
        0,
        (maxWidth, glyph) =>
            math.max(maxWidth, glyph.base.width * scaleFor(glyph)));
    var top = 0.0;
    for (final glyph in shaping.glyphs) {
      final scale = scaleFor(glyph);
      final height = math.max(glyph.base.height, fontSize * 1.15);
      glyphs.add(_GlyphPaint(glyph,
          bounds: Rect.fromLTWH(0, top, columnWidth, height),
          paintOffset: Offset((columnWidth - glyph.base.width * scale) / 2,
              top + (height - glyph.base.height * scale) / 2),
          scale: scale));
      top += height;
    }
    size = Size(columnWidth, top);
    var offset = 0;
    for (final word in words) {
      final start = offset.clamp(0, text.length);
      offset += word.content.length;
      final end = offset.clamp(0, text.length);
      final boxes = <({Rect rect, bool rtl, bool horizontal})>[];
      for (final glyph in glyphs) {
        if (glyph.glyph.horizontal) {
          final selectionStart = math.max(start, glyph.glyph.start);
          final selectionEnd = math.min(end, glyph.glyph.end);
          if (selectionStart >= selectionEnd) continue;
          for (final box in glyph.base.getBoxesForSelection(TextSelection(
            baseOffset: selectionStart - glyph.glyph.start,
            extentOffset: selectionEnd - glyph.glyph.start,
          ))) {
            boxes.add((
              rect: Rect.fromLTRB(
                glyph.paintOffset.dx + box.left * glyph.scale,
                glyph.paintOffset.dy + box.top * glyph.scale,
                glyph.paintOffset.dx + box.right * glyph.scale,
                glyph.paintOffset.dy + box.bottom * glyph.scale,
              ),
              rtl: box.direction == TextDirection.rtl,
              horizontal: true,
            ));
          }
        } else if (glyph.glyph.start >= start && glyph.glyph.start < end) {
          boxes.add((rect: glyph.bounds, rtl: false, horizontal: false));
        }
      }
      wordBoxes.add(boxes);
    }
  }

  final _DesktopLyricTextShaping shaping;
  String get text => shaping.text;
  List<DesktopLyricWord> get words => shaping.words;
  bool get vertical => shaping.vertical;
  final List<_GlyphPaint> glyphs = [];
  TextPainter? get base => shaping.base;
  TextPainter? get highlight => shaping.highlight;
  TextPainter? get stroke => shaping.stroke;
  late final Size size;
  double get fontSize => shaping.fontSize;
  final List<List<({Rect rect, bool rtl, bool horizontal})>> wordBoxes = [];
  late final List<double> wordExtents = [
    for (final boxes in wordBoxes)
      boxes.fold<double>(
          0,
          (total, box) =>
              total +
              (vertical && !box.horizontal ? box.rect.height : box.rect.width))
  ];
  late final List<double> wordSoftness = [
    for (final extent in wordExtents)
      LyricWordEffects.softEdgeWidth(fontSize: fontSize, extent: extent)
  ];

  /// The owning player's renderer also joins timing fragments that divide one
  /// Unicode grapheme. Keep one mask and the union of its actual timing here;
  /// partial selections have no horizontal boxes and would lose later timing
  /// in vertical mode. This runs only when shaping, never on clock samples.
  static List<DesktopLyricWord> _shapedWords(
      String text, List<DesktopLyricWord> authored) {
    if (authored.isEmpty) return authored;
    final boundaries = <int>{0};
    var endOffset = 0;
    for (final character in text.characters) {
      endOffset += character.length;
      boundaries.add(endOffset);
    }
    final result = <DesktopLyricWord>[];
    var offset = 0;
    for (var index = 0; index < authored.length; index++) {
      final word = authored[index];
      offset += word.content.length;
      int start = word.startMilliseconds;
      int end = start + math.max(0, word.lengthMilliseconds);
      StringBuffer? joined;
      while (offset < text.length &&
          !boundaries.contains(offset) &&
          index + 1 < authored.length) {
        final next = authored[++index];
        joined ??= StringBuffer(word.content);
        joined.write(next.content);
        start = math.min(start, next.startMilliseconds);
        end = math.max(
            end, next.startMilliseconds + math.max(0, next.lengthMilliseconds));
        offset += next.content.length;
      }
      result.add(joined == null
          ? word
          : DesktopLyricWord(start, end - start, joined.toString()));
    }
    return result;
  }

  // A separate cached pass under both fills. Word clipping never cuts an
  // outline in half and no paragraphs are laid out on playback clock ticks.
  void paintStroke(Canvas canvas) {
    if (!vertical) {
      stroke?.paint(canvas, Offset.zero);
      return;
    }
    for (final glyph in glyphs) {
      if (glyph.stroke == null) continue;
      canvas.save();
      canvas.translate(glyph.paintOffset.dx, glyph.paintOffset.dy);
      canvas.scale(glyph.scale, glyph.scale);
      glyph.stroke!.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  void paint(Canvas canvas, {required bool played}) {
    if (!vertical) {
      (played ? highlight : base)!.paint(canvas, Offset.zero);
      return;
    }
    for (final glyph in glyphs) {
      final painter = played ? glyph.highlight : glyph.base;
      canvas.save();
      canvas.translate(glyph.paintOffset.dx, glyph.paintOffset.dy);
      canvas.scale(glyph.scale, glyph.scale);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }
}

class DesktopLyricTextPainter extends CustomPainter {
  DesktopLyricTextPainter._(
      {required _DesktopLyricTextLayout layout,
      required this.clock,
      required this.reducedMotion})
      : _layout = layout,
        super(
            repaint: layout.words.isNotEmpty && !reducedMotion ? clock : null);

  final _DesktopLyricTextLayout _layout;
  final PlaybackClock clock;
  final bool reducedMotion;

  bool get vertical => _layout.vertical;
  @visibleForTesting
  Object get layoutCacheIdentity => _layout;

  /// Opaque diagnostic identities; read only from resize regressions, never
  /// from the playback sampling or painting path.
  @visibleForTesting
  List<Object> get cachedShapingIdentities => List<Object>.unmodifiable([
        if (_layout.base != null) _layout.base!,
        if (_layout.highlight != null) _layout.highlight!,
        if (_layout.stroke != null) _layout.stroke!,
        for (final glyph in _layout.glyphs) ...[
          glyph.base,
          glyph.highlight,
          if (glyph.stroke != null) glyph.stroke!,
        ],
      ]);
  @visibleForTesting
  int get cachedStrokePainterCount => _layout.vertical
      ? _layout.glyphs.where((glyph) => glyph.stroke != null).length
      : (_layout.stroke == null ? 0 : 1);
  List<DesktopLyricGlyph> get glyphs =>
      List.unmodifiable(_layout.glyphs.map((glyph) => glyph.glyph));

  double progressForWord(int index) {
    final word = _layout.words[index];
    final elapsed = clock.positionMilliseconds - word.startMilliseconds;
    return word.lengthMilliseconds <= 0
        ? (elapsed >= 0 ? 1 : 0)
        : (elapsed / word.lengthMilliseconds).clamp(0.0, 1.0);
  }

  List<Rect> highlightRectsForWord(int index) {
    final boxes = _layout.wordBoxes[index];
    var remaining = _layout.wordExtents[index] * progressForWord(index);
    final result = <Rect>[];
    for (final box in boxes) {
      if (remaining <= 0) break;
      final fillVertically = vertical && !box.horizontal;
      final amount = math.min(
          remaining, fillVertically ? box.rect.height : box.rect.width);
      remaining -= amount;
      result.add(fillVertically
          ? Rect.fromLTRB(box.rect.left, box.rect.top, box.rect.right,
              box.rect.top + amount)
          : box.rtl
              ? Rect.fromLTRB(box.rect.right - amount, box.rect.top,
                  box.rect.right, box.rect.bottom)
              : Rect.fromLTRB(box.rect.left, box.rect.top,
                  box.rect.left + amount, box.rect.bottom));
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layout.paintStroke(canvas);
    if (_layout.words.isEmpty || reducedMotion) {
      _layout.paint(canvas, played: true);
      return;
    }
    _layout.paint(canvas, played: false);
    final completed = Path();
    var hasCompleted = false;
    final active = <({
      Rect bounds,
      int word,
      double progress,
      double offset,
      bool reverse,
      bool vertical,
    })>[];
    for (var index = 0; index < _layout.words.length; index++) {
      final progress = progressForWord(index);
      if (progress <= 0) continue;
      final extent = _layout.wordExtents[index];
      if (extent <= 0) continue;
      final edges = LyricWordEffects.revealEdges(
          progress: progress,
          extent: extent,
          softness: _layout.wordSoftness[index]);
      var offset = 0.0;
      for (final box in _layout.wordBoxes[index]) {
        final vertical = _layout.vertical && !box.horizontal;
        final end = offset + (vertical ? box.rect.height : box.rect.width);
        if (progress >= 1 || edges.start >= end) {
          completed.addRect(box.rect);
          hasCompleted = true;
        } else if (edges.end > offset && !box.rect.isEmpty) {
          active.add((
            bounds: box.rect,
            word: index,
            progress: progress,
            offset: offset,
            reverse: box.rtl,
            vertical: vertical,
          ));
        }
        offset = end;
      }
    }
    if (hasCompleted) {
      canvas.save();
      canvas.clipPath(completed);
      _layout.paint(canvas, played: true);
      canvas.restore();
    }
    // Only unfinished word fragments need an alpha mask. Completed text is
    // one cached pass; the outline remains a single untouched pass beneath.
    // Bounds stay local to each shaped fragment, including vertical foreign
    // words and RTL runs, rather than allocating a window-sized layer.
    for (final fragment in active) {
      canvas.save();
      canvas.clipRect(fragment.bounds);
      canvas.saveLayer(fragment.bounds, Paint());
      _layout.paint(canvas, played: true);
      canvas.drawRect(
          fragment.bounds,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = LyricWordEffects.revealShader(
                bounds: fragment.bounds,
                progress: fragment.progress,
                extent: _layout.wordExtents[fragment.word],
                offset: fragment.offset,
                softness: _layout.wordSoftness[fragment.word],
                reverse: fragment.reverse,
                vertical: fragment.vertical));
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(DesktopLyricTextPainter oldDelegate) =>
      !identical(_layout, oldDelegate._layout) ||
      !identical(clock, oldDelegate.clock) ||
      reducedMotion != oldDelegate.reducedMotion;
}
