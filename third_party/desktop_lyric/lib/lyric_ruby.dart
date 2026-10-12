import 'dart:math' as math;
import 'dart:ui' as drawing;

import 'package:flutter/material.dart';

import 'font_policy.dart';

/// Display-only readings reference the unchanged source's UTF-16 positions.
abstract interface class LyricRubySpan {
  int get start;
  int get end;
  String get text;
}

/// Owned by one fixed primary paragraph. Width changes reuse its natural
/// reading shapes; only a genuinely different fragment fit needs a new shape.
class LyricRubyShaping {
  LyricRubyShaping({
    required List<LyricRubySpan> spans,
    required TextStyle style,
    required AppFontPolicy policy,
    required TextDirection direction,
    required TextScaler scaler,
    required Locale? locale,
    required bool vertical,
  }) : _shapes = [
          for (final span in spans)
            _RubyShape(
                span.text, style, policy, direction, scaler, locale, vertical)
        ];

  final List<_RubyShape> _shapes;

  void dispose() {
    for (final shape in _shapes) {
      shape.dispose();
    }
  }
}

class _RubyShape {
  _RubyShape(String text, this.style, this.policy, this.direction, this.scaler,
      this.locale, this.vertical)
      : text = vertical ? text.characters.join('\n') : text {
    natural = _shape((style.fontSize ?? 14) * .45);
  }
  final String text;
  final TextStyle style;
  final AppFontPolicy policy;
  final TextDirection direction;
  final TextScaler scaler;
  final Locale? locale;
  final bool vertical;
  late final TextPainter natural;
  TextPainter? _fitted;
  double? _fitSize;
  double? _fitWidth;

  TextPainter _shape(double size) => TextPainter(
        text: appFontSpan(text,
            style: style.copyWith(
                fontSize: size,
                color: Colors.white,
                height: 1,
                letterSpacing: 0,
                shadows: const []),
            policy: policy),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
      )..layout();

  TextPainter fit(double available) {
    final originalSize = (style.fontSize ?? 14) * .45;
    final originalExtent = vertical ? natural.height : natural.width;
    if (available <= 0 || originalExtent <= available) return natural;
    final size =
        math.max(originalSize / 2, originalSize * available / originalExtent);
    // At the readable lower bound, a long horizontal pronunciation wraps
    // inside its own Han fragment. Retain at most one fitted shape per span.
    final fitWidth = !vertical && size == originalSize / 2
        ? math.max(1.0, available)
        : double.infinity;
    if (_fitted == null || _fitSize != size || _fitWidth != fitWidth) {
      _fitted?.dispose();
      _fitted = _shape(size);
      if (fitWidth.isFinite) _fitted!.layout(maxWidth: fitWidth);
      _fitSize = size;
      _fitWidth = fitWidth;
    }
    return _fitted!;
  }

  void dispose() {
    natural.dispose();
    _fitted?.dispose();
  }
}

/// A shaped reading and the first actual source fragment that owns it.
class LyricRubyGlyph {
  LyricRubyGlyph(this.span, this.painter, this.source, this.offset,
      this.lineWidth, this.sourceInkTop, this.row);
  final LyricRubySpan span;
  final TextPainter painter;
  final Rect source;
  final Offset offset;
  final double lineWidth;
  final double sourceInkTop;

  /// The native paragraph line containing the unchanged UTF-16 source start.
  /// Font-run selection boxes can extend above another line's metric boundary.
  final int row;
  double followPhase = 1;
  List<({int index, Rect bounds, double phase})> motionParts = const [];
}

/// Geometry is computed at paragraph layout, never on a media-clock repaint.
/// A word split across lines keeps its complete pronunciation on its first
/// fragment; arbitrary divisions of a word's reading would invent phonetics.
class LyricRubyLayout {
  LyricRubyLayout({
    TextPainter? primary,
    required List<LyricRubySpan> spans,
    required TextStyle style,
    required AppFontPolicy policy,
    required TextDirection direction,
    required TextScaler scaler,
    required Locale? locale,
    required double width,
    this.vertical = false,
    this.primaryInset = 0,
    LyricRubyShaping? shaping,
    List<({int start, int end, Rect bounds})>? verticalUnits,
  }) {
    _shaping = shaping ??
        LyricRubyShaping(
            spans: spans,
            style: style,
            policy: policy,
            direction: direction,
            scaler: scaler,
            locale: locale,
            vertical: vertical);
    _ownsShaping = shaping == null;
    color = style.color ?? Colors.black;
    final fontSize = scaler.scale(style.fontSize ?? 14);
    gap = fontSize * .06;
    extent = vertical ? fontSize * .51 : 0;
    final metrics = vertical
        ? const <drawing.LineMetrics>[]
        : primary!.computeLineMetrics();
    final sourceLength = vertical ? null : primary!.text!.toPlainText().length;
    if (!vertical) {
      _lines = metrics;
      _rowRanges = _paragraphRows(primary!, metrics.length);
    }
    for (final (index, span) in spans.indexed) {
      if (span.start < 0 ||
          span.end <= span.start ||
          span.text.isEmpty ||
          (sourceLength != null && span.end > sourceLength)) {
        continue;
      }
      Rect? source;
      var row = 0;
      if (vertical) {
        for (final unit
            in verticalUnits ?? const <({int start, int end, Rect bounds})>[]) {
          if (unit.end <= span.start || unit.start >= span.end) continue;
          source = source == null
              ? unit.bounds
              : source.expandToInclude(unit.bounds);
        }
      } else {
        row = _rowForOffset(span.start);
        final range = _rowRanges[row];
        final boxes = primary!.getBoxesForSelection(TextSelection(
            baseOffset: span.start,
            extentOffset: math.min(span.end, range.end)));
        if (boxes.isEmpty) continue;
        for (final box in boxes) {
          source = source == null
              ? box.toRect()
              : source.expandToInclude(box.toRect());
        }
      }
      if (source == null || source.isEmpty) continue;
      final sourceBounds = source;
      final available =
          vertical ? sourceBounds.height : math.min(width, sourceBounds.width);
      final painter = _shaping!._shapes[index].fit(available);
      double sourceTop = sourceBounds.top;
      double lineWidth = sourceBounds.width;
      if (!vertical && metrics.isNotEmpty) {
        final line = metrics[row];
        // Font ascent includes room for accents and other scripts; with CJK
        // fonts it can sit an entire reading row above the visible Han. Keep
        // the attachment on the Han em square, independently of the wrapped
        // paragraph's extra line-height budget.
        sourceTop = sourceBounds.center.dy -
            math.min(sourceBounds.height, fontSize) / 2 +
            gap / 2;
        lineWidth = line.width;
      }
      final offset = vertical
          ? Offset(sourceBounds.right + gap,
              sourceBounds.center.dy - painter.height / 2)
          : Offset(
              (sourceBounds.center.dx - painter.width / 2)
                  .clamp(0.0, math.max(0.0, width - painter.width)),
              sourceTop - painter.height - gap);
      // Top padding belongs only to readings above the first native row.
      // Later rows reserve their own leading below, without changing the
      // primary's font metrics or introducing a blank first reading row.
      extent = math.max(
          extent, vertical ? painter.width + gap : math.max(0.0, -offset.dy));
      glyphs.add(LyricRubyGlyph(
          span, painter, sourceBounds, offset, lineWidth, sourceTop, row));
    }
    if (!vertical) {
      var leading = 0.0;
      for (var row = 0; row < metrics.length; row++) {
        var extra = 0.0;
        if (row > 0) {
          final previous = metrics[row - 1];
          for (final glyph in glyphs) {
            if (glyph.row != row) continue;
            extra = math.max(extra,
                previous.baseline + previous.descent + gap - glyph.offset.dy);
          }
        }
        leading += extra;
        _leading.add(leading);
      }
    }
  }

  final bool vertical;

  /// Extra native ink margin belongs to visible readings, not ordinary text.
  final double primaryInset;
  late final Color color;
  final glyphs = <LyricRubyGlyph>[];
  late final double gap;
  late double extent;
  LyricRubyShaping? _shaping;
  bool _ownsShaping = false;
  List<drawing.LineMetrics> _lines = const [];
  List<TextRange> _rowRanges = const [];
  final _leading = <double>[];
  double get extraLeading => _leading.isEmpty ? 0 : _leading.last;

  double insetAt(double visibility) =>
      (extent + (!vertical && glyphs.isNotEmpty ? primaryInset : 0)) *
      visibility;

  static List<TextRange> _paragraphRows(TextPainter paragraph, int count) {
    final text = paragraph.text!.toPlainText();
    final rows = <TextRange>[];
    var offset = 0;
    for (var row = 0; row < count; row++) {
      final range = paragraph.getLineBoundary(TextPosition(offset: offset));
      rows.add(range);
      offset = range.end;
      if (offset < text.length) {
        final code = text.codeUnitAt(offset);
        if (code == 13 &&
            offset + 1 < text.length &&
            text.codeUnitAt(offset + 1) == 10) {
          offset += 2;
        } else if (code == 10 ||
            code == 13 ||
            code == 0x2028 ||
            code == 0x2029) {
          offset++;
        }
      }
    }
    return List.unmodifiable(rows);
  }

  int _rowForOffset(int offset) {
    var low = 0, high = _rowRanges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_rowRanges[middle].start <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.max(0, low - 1);
  }

  double leadingForOffset(int offset) =>
      _leading.isEmpty ? 0 : _leading[_rowForOffset(offset)];

  double leadingForGlyph(LyricRubyGlyph glyph) =>
      _leading.isEmpty ? 0 : _leading[glyph.row];

  /// Optional readings reserve their own leading, leaving the original
  /// paragraph metrics and word-emphasis pivots completely unchanged.
  void paintPrimary(Canvas canvas, VoidCallback paint,
      {double visibility = 1}) {
    if (visibility <= 0 || extraLeading == 0) {
      paint();
      return;
    }
    for (var row = 0; row < _lines.length; row++) {
      final top = row == 0 ? -100.0 : _lines[row].baseline - _lines[row].ascent;
      final bottom = row + 1 == _lines.length
          ? double.infinity
          : _lines[row + 1].baseline - _lines[row + 1].ascent;
      canvas.save();
      canvas.translate(0, _leading[row] * visibility);
      canvas.clipRect(
          Rect.fromLTRB(
              -100000, top, 100000, bottom.isFinite ? bottom : 100000),
          doAntiAlias: false);
      paint();
      canvas.restore();
    }
  }

  LyricRubyLayout.interpolate(
      LyricRubyLayout from, LyricRubyLayout to, double progress,
      {bool retainSourcePainter = false})
      : vertical = to.vertical,
        primaryInset = from.primaryInset +
            (to.primaryInset - from.primaryInset) * progress {
    color = to.color;
    gap = from.gap + (to.gap - from.gap) * progress;
    extent = from.extent + (to.extent - from.extent) * progress;
    for (var index = 0; index < to.glyphs.length; index++) {
      final target = to.glyphs[index];
      final previous = index < from.glyphs.length ? from.glyphs[index] : target;
      glyphs.add(LyricRubyGlyph(
          target.span,
          retainSourcePainter ? previous.painter : target.painter,
          Rect.lerp(previous.source, target.source, progress)!,
          Offset.lerp(previous.offset, target.offset, progress)!,
          previous.lineWidth +
              (target.lineWidth - previous.lineWidth) * progress,
          previous.sourceInkTop +
              (target.sourceInkTop - previous.sourceInkTop) * progress,
          target.row));
    }
    _lines = to._lines;
    _rowRanges = to._rowRanges;
    for (var row = 0; row < to._leading.length; row++) {
      final start = row < from._leading.length ? from._leading[row] : 0.0;
      _leading.add(start + (to._leading[row] - start) * progress);
    }
  }

  late final Rect paintBounds = glyphs.fold<Rect?>(
          null,
          (bounds, glyph) => bounds == null
              ? (glyph.offset + Offset(0, leadingForGlyph(glyph))) &
                  glyph.painter.size
              : bounds.expandToInclude(
                  (glyph.offset + Offset(0, leadingForGlyph(glyph))) &
                      glyph.painter.size)) ??
      Rect.zero;

  void paint(Canvas canvas,
      {Offset Function(LyricRubyGlyph)? displacement,
      void Function(Canvas, LyricRubyGlyph)? transform,
      Color? tint,
      double visibility = 1}) {
    if (visibility <= 0) return;
    if (glyphs.isEmpty) return;
    // Tint one small cached reading layer, rather than rebuilding paragraphs
    // as the lyric's active/theme colour changes on presentation frames.
    canvas.saveLayer(
        paintBounds.inflate(extent * 2 + 24),
        Paint()
          ..colorFilter = ColorFilter.mode(
              (tint ?? color).withValues(alpha: (tint ?? color).a * visibility),
              BlendMode.srcIn));
    for (final glyph in glyphs) {
      canvas.save();
      transform?.call(canvas, glyph);
      glyph.painter.paint(
          canvas,
          glyph.offset +
              Offset(0, leadingForGlyph(glyph) * visibility) +
              (displacement?.call(glyph) ?? Offset.zero));
      canvas.restore();
    }
    canvas.restore();
  }

  void bindMotion(
      {double Function(LyricRubySpan)? phaseFor,
      List<({int index, Rect bounds, double phase})> Function(LyricRubyGlyph)?
          partsFor}) {
    for (final glyph in glyphs) {
      glyph.followPhase = phaseFor?.call(glyph.span) ?? 1;
      glyph.motionParts = partsFor?.call(glyph) ?? const [];
    }
  }

  void dispose() {
    if (_ownsShaping) _shaping?.dispose();
  }
}

/// Reserve space between wrapped primary rows without changing source text.
TextStyle lyricRubyPrimaryStyle(TextStyle style, List<LyricRubySpan> spans) =>
    style;
