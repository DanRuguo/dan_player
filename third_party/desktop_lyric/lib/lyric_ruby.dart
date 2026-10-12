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
  final _rasters = <TextPainter, Map<double, _RubyRaster>>{};

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
      _releaseRasters(_fitted);
      _fitted?.dispose();
      _fitted = _shape(size);
      if (fitWidth.isFinite) _fitted!.layout(maxWidth: fitWidth);
      _fitSize = size;
      _fitWidth = fitWidth;
    }
    return _fitted!;
  }

  _RubyRaster? rasterFor(TextPainter painter, double ratio, double padding) {
    final cached = _rasters[painter]?[ratio];
    if (cached != null && cached.padding >= padding) {
      final scales = _rasters[painter]!;
      scales.remove(ratio);
      scales[ratio] = cached;
      cached.touch();
      return cached;
    }
    cached?.dispose();
    final bounds = (Offset.zero & painter.size).inflate(padding);
    final pixelWidth = bounds.width * ratio;
    final pixelHeight = bounds.height * ratio;
    if (!pixelWidth.isFinite ||
        !pixelHeight.isFinite ||
        pixelWidth <= 0 ||
        pixelHeight <= 0 ||
        pixelWidth > 4096 ||
        pixelHeight > 4096) {
      return null;
    }
    final width = pixelWidth.ceil(), height = pixelHeight.ceil();
    if (width * height > _RubyRaster.maximumImagePixels) return null;
    final recorder = drawing.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..translate(-bounds.left, -bounds.top);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    drawing.Image image;
    try {
      image = picture.toImageSync(width, height);
    } catch (_) {
      return null;
    } finally {
      picture.dispose();
    }
    final scales = _rasters.putIfAbsent(painter, () => {});
    late final _RubyRaster raster;
    raster = _RubyRaster(
        image,
        // Only allocation rounds up. Keep the native origin and texel scale;
        // stretching the ceil-sized image back to bounds would move its ink.
        Rect.fromLTWH(bounds.left, bounds.top, width / ratio, height / ratio),
        padding, () {
      if (identical(scales[ratio], raster)) scales.remove(ratio);
      if (scales.isEmpty && identical(_rasters[painter], scales)) {
        _rasters.remove(painter);
      }
    });
    scales[ratio] = raster;
    while (scales.length > 2) {
      scales.values.first.dispose();
    }
    raster.register();
    return raster;
  }

  void _releaseRasters(TextPainter? painter) {
    if (painter == null) return;
    final scales = _rasters.remove(painter);
    for (final raster in scales?.values.toList() ?? const <_RubyRaster>[]) {
      raster.dispose();
    }
  }

  void dispose() {
    for (final painter in _rasters.keys.toList()) {
      _releaseRasters(painter);
    }
    natural.dispose();
    _fitted?.dispose();
  }
}

/// Reuse the player's white-mask image/tint path without a nested saveLayer.
/// Font shapes own entries; one global LRU also bounds long lyric documents.
class _RubyRaster {
  _RubyRaster(this.image, this.bounds, this.padding, this._onDispose);

  static const maximumImagePixels = 1024 * 1024;
  static const maximumPixels = 4 * 1024 * 1024;
  static const maximumEntries = 96;
  static final _lru = <_RubyRaster, bool>{};
  static int _pixels = 0;

  final drawing.Image image;
  final Rect bounds;
  final double padding;
  final VoidCallback _onDispose;
  bool _disposed = false;
  int get pixels => image.width * image.height;

  void register() {
    _pixels += pixels;
    _lru[this] = true;
    while (_lru.length > maximumEntries || _pixels > maximumPixels) {
      _lru.keys.first.dispose();
    }
  }

  void touch() {
    if (_lru.remove(this) != null) _lru[this] = true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_lru.remove(this) != null) _pixels -= pixels;
    _onDispose();
    image.dispose();
  }
}

/// A shaped reading and the first actual source fragment that owns it.
class LyricRubyGlyph {
  LyricRubyGlyph(this.span, this.painter, this.source, this.offset,
      this.lineWidth, this.sourceInkTop, this.row,
      {int? sourceEnd})
      : sourceStart = span.start,
        sourceEnd = sourceEnd ?? span.end;
  final LyricRubySpan span;

  /// UTF-16 bounds of the native first fragment carrying the full reading.
  final int sourceStart, sourceEnd;
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
  _RubyShape? _rasterSource;
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
      var sourceEnd = span.end;
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
        sourceEnd = math.min(span.end, range.end);
        final boxes = primary!.getBoxesForSelection(
            TextSelection(baseOffset: span.start, extentOffset: sourceEnd));
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
          span, painter, sourceBounds, offset, lineWidth, sourceTop, row,
          sourceEnd: sourceEnd)
        .._rasterSource = _shaping!._shapes[index]);
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
          target.row,
          sourceEnd:
              retainSourcePainter ? previous.sourceEnd : target.sourceEnd)
        .._rasterSource = retainSourcePainter
            ? previous._rasterSource
            : target._rasterSource);
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

  /// Sampling parents may opt into cached native white snapshots with their
  /// real device/sample scale. Null and excessive allocations retain native
  /// paragraph painting; tint, visibility and displacement never reshape text.
  void paint(Canvas canvas,
      {Offset Function(LyricRubyGlyph)? displacement,
      void Function(Canvas, LyricRubyGlyph)? transform,
      Color? tint,
      double visibility = 1,
      double? rasterScale}) {
    if (visibility <= 0) return;
    if (glyphs.isEmpty) return;
    final offsets = displacement == null
        ? null
        : [
            for (final glyph in glyphs)
              glyph.offset +
                  Offset(0, leadingForGlyph(glyph) * visibility) +
                  displacement(glyph)
          ];
    final color = (tint ?? this.color)
        .withValues(alpha: (tint ?? this.color).a * visibility);
    if (rasterScale != null &&
        rasterScale.isFinite &&
        rasterScale > 0 &&
        _paintRasters(
            canvas, rasterScale, color, offsets, transform, visibility)) {
      return;
    }
    var coverage = paintBounds;
    if (offsets != null) {
      for (var index = 0; index < glyphs.length; index++) {
        coverage = coverage
            .expandToInclude(offsets[index] & glyphs[index].painter.size);
      }
    }
    // Tint one small cached reading layer, rather than rebuilding paragraphs
    // as the lyric's active/theme colour changes on presentation frames.
    canvas.saveLayer(coverage.inflate(extent * 2 + 24),
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn));
    for (final (index, glyph) in glyphs.indexed) {
      canvas.save();
      transform?.call(canvas, glyph);
      glyph.painter.paint(
          canvas,
          offsets?[index] ??
              glyph.offset + Offset(0, leadingForGlyph(glyph) * visibility));
      canvas.restore();
    }
    canvas.restore();
  }

  bool _paintRasters(
      Canvas canvas,
      double ratio,
      Color color,
      List<Offset>? offsets,
      void Function(Canvas, LyricRubyGlyph)? transform,
      double visibility) {
    if (glyphs.length > _RubyRaster.maximumEntries) return false;
    final snapshots = <({drawing.Image image, Rect bounds})>[];
    var pixels = 0;
    try {
      for (final glyph in glyphs) {
        final raster = glyph._rasterSource
            ?.rasterFor(glyph.painter, ratio, extent * 2 + 24);
        if (raster == null) return false;
        pixels += raster.pixels;
        if (pixels > _RubyRaster.maximumPixels) return false;
        // Pin this frame's handles while later entries may evict from the LRU.
        snapshots.add((image: raster.image.clone(), bounds: raster.bounds));
      }
      final paint = Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
      for (final (index, glyph) in glyphs.indexed) {
        final snapshot = snapshots[index];
        final offset = offsets?[index] ??
            glyph.offset + Offset(0, leadingForGlyph(glyph) * visibility);
        canvas.save();
        try {
          transform?.call(canvas, glyph);
          canvas.drawImageRect(
              snapshot.image,
              Rect.fromLTWH(0, 0, snapshot.image.width.toDouble(),
                  snapshot.image.height.toDouble()),
              snapshot.bounds.shift(offset),
              paint);
        } finally {
          canvas.restore();
        }
      }
      return true;
    } finally {
      for (final snapshot in snapshots) {
        snapshot.image.dispose();
      }
    }
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
