import 'dart:math' as math;

import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
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
  _DesktopLyricTextLayout? _layout;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // TextPainter does not inherit the app's font as Text does. Merge the real
    // desktop typography before caching so CJK/fallback fonts stay identical.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final identity = (
      widget.text,
      widget.words,
      widget.vertical,
      widget.maxVerticalUnitWidth,
      widget.maxHorizontalWidth,
      style,
      widget.playedColor,
      widget.unplayedColor,
      widget.strokeColor,
      direction,
      scaler
    );
    if (_identity != identity) {
      _layout?.dispose();
      _layout = _DesktopLyricTextLayout(
          text: widget.text,
          words: widget.words,
          vertical: widget.vertical,
          maxVerticalUnitWidth: widget.maxVerticalUnitWidth,
          maxHorizontalWidth: widget.maxHorizontalWidth,
          style: style,
          playedColor: widget.playedColor,
          unplayedColor: widget.unplayedColor,
          strokeColor: widget.strokeColor,
          direction: direction,
          scaler: scaler);
      _identity = identity;
    }
    return SizedBox.fromSize(
      size: _layout!.size,
      child: RepaintBoundary(
          child: CustomPaint(
        painter: DesktopLyricTextPainter._(
            layout: _layout!,
            clock: widget.clock,
            reducedMotion: widget.reducedMotion),
        isComplex: true,
        willChange: widget.words.isNotEmpty && !widget.reducedMotion,
      )),
    );
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }
}

class _GlyphPaint {
  _GlyphPaint(this.glyph, this.base, this.highlight, this.stroke);
  final DesktopLyricGlyph glyph;
  final TextPainter base;
  final TextPainter highlight;
  final TextPainter? stroke;
  late Rect bounds;
  late Offset paintOffset;
  double scale = 1;
}

class _DesktopLyricTextLayout {
  _DesktopLyricTextLayout(
      {required String text,
      required this.words,
      required this.vertical,
      required double? maxVerticalUnitWidth,
      required double? maxHorizontalWidth,
      required TextStyle style,
      required Color playedColor,
      required Color unplayedColor,
      required Color? strokeColor,
      required TextDirection direction,
      required TextScaler scaler}) {
    final width = !vertical && maxHorizontalWidth != null
        ? math.max(0.0, maxHorizontalWidth)
        : double.infinity;
    TextPainter painter(String text, Color color) => TextPainter(
          text: TextSpan(text: text, style: style.copyWith(color: color)),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
          ellipsis: width.isFinite ? '…' : null,
        )..layout(maxWidth: width);
    TextPainter? outline(String text) => strokeColor == null
        ? null
        : (TextPainter(
            text: TextSpan(
                text: text,
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
            maxLines: 1,
            ellipsis: width.isFinite ? '…' : null,
          )..layout(maxWidth: width));
    if (!vertical) {
      base = painter(text, unplayedColor);
      highlight = painter(text, playedColor);
      stroke = outline(text);
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
    for (final glyph in desktopLyricVerticalUnits(text)) {
      final display =
          glyph.text == '\n' || glyph.text == '\r\n' ? ' ' : glyph.text;
      glyphs.add(_GlyphPaint(glyph, painter(display, unplayedColor),
          painter(display, playedColor), outline(display)));
    }
    final widthLimit = maxVerticalUnitWidth != null &&
            maxVerticalUnitWidth.isFinite &&
            maxVerticalUnitWidth > 0
        ? maxVerticalUnitWidth
        : double.infinity;
    for (final glyph in glyphs) {
      if (glyph.base.width > widthLimit) {
        glyph.scale = widthLimit / glyph.base.width;
      }
    }
    final columnWidth = glyphs.fold<double>(
        0,
        (maxWidth, glyph) =>
            math.max(maxWidth, glyph.base.width * glyph.scale));
    var top = 0.0;
    for (final glyph in glyphs) {
      final height = math.max(
          glyph.base.height, scaler.scale(style.fontSize ?? 22) * 1.15);
      glyph.bounds = Rect.fromLTWH(0, top, columnWidth, height);
      glyph.paintOffset = Offset(
          (columnWidth - glyph.base.width * glyph.scale) / 2,
          top + (height - glyph.base.height * glyph.scale) / 2);
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
          // Malformed timing may split an emoji across tokens. Paint it once
          // and assign it to the token containing the grapheme's start.
          boxes.add((rect: glyph.bounds, rtl: false, horizontal: false));
        }
      }
      wordBoxes.add(boxes);
    }
  }

  final List<DesktopLyricWord> words;
  final bool vertical;
  final List<_GlyphPaint> glyphs = [];
  TextPainter? base;
  TextPainter? highlight;
  TextPainter? stroke;
  late final Size size;
  final List<List<({Rect rect, bool rtl, bool horizontal})>> wordBoxes = [];

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
    final total = boxes.fold<double>(
        0,
        (sum, box) =>
            sum +
            (vertical && !box.horizontal ? box.rect.height : box.rect.width));
    var remaining = total * progressForWord(index);
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
    final path = Path();
    var hasHighlight = false;
    for (var index = 0; index < _layout.words.length; index++) {
      for (final rect in highlightRectsForWord(index)) {
        path.addRect(rect);
        hasHighlight = true;
      }
    }
    if (!hasHighlight) return;
    canvas.save();
    canvas.clipPath(path);
    _layout.paint(canvas, played: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DesktopLyricTextPainter oldDelegate) =>
      !identical(_layout, oldDelegate._layout) ||
      !identical(clock, oldDelegate.clock) ||
      reducedMotion != oldDelegate.reducedMotion;
}
