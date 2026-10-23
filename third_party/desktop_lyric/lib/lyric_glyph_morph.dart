import 'dart:ui' as drawing;

import 'package:flutter/material.dart';

/// A paragraph's existing painter keeps owning colour, playback and emphasis.
/// Its parent supplies only finite, already-shaped spacing geometry.
abstract interface class LyricGlyphMorphConsumer {
  TextPainter get glyphParagraph;
  Object get glyphLayoutIdentity;
  double get glyphPixelRatio;
  Offset get glyphInkOffset;
  LyricGlyphMorphFrame? get glyphMorph;
  set glyphMorph(LyricGlyphMorphFrame? value);
}

class LyricGlyphMorphFrame {
  const LyricGlyphMorphFrame(this.geometry, this.progress);
  final LyricGlyphMorph geometry;
  final double progress;
}

/// One already shaped cluster. Its source pixels remain unchanged as its
/// cached paragraph geometry moves; source offsets always refer to the author.
class LyricGlyphCell {
  LyricGlyphCell(this.start, this.end, this.source, this.from, this.to,
      {required this.coloured,
      this.fromOpacity = 1,
      this.toOpacity = 1,
      _LyricGlyphAtlas? atlas})
      : _atlas = atlas;
  final int start, end;
  final Rect source;
  final Rect from, to;
  final bool coloured;
  final double fromOpacity, toOpacity;
  final _LyricGlyphAtlas? _atlas;
  late final Rect sourceClip;
  Rect at(double progress) => Rect.lerp(from, to, progress)!;
  double opacityAt(double progress) =>
      fromOpacity + (toOpacity - fromOpacity) * progress;
}

/// A finite paragraph geometry transition. The paragraph is recorded once.
/// Raster tiles are bounded and created only for cells actually painted in the
/// current clip, never once per glyph and never by reshaping on motion frames.
/// The owning lyric's existing presentation clock supplies [progress].
class LyricGlyphMorph {
  LyricGlyphMorph(
      {required TextPainter from,
      required TextPainter to,
      Offset targetOffset = Offset.zero,
      double alignmentX = -1,
      double pixelRatio = 1})
      : _atlas = _LyricGlyphAtlas(from, pixelRatio),
        _completeSource = false,
        fromSize = from.size,
        toSize = to.size {
    cells = _cells(from, to, targetOffset, alignmentX);
    _completeSource = _coversText(cells, from.text!.toPlainText());
    _addRevealed(to, targetOffset, alignmentX);
  }

  LyricGlyphMorph.retarget(
      LyricGlyphMorph previous, TextPainter target, double presentedProgress,
      {Offset targetOffset = Offset.zero,
      Offset fromOffset = Offset.zero,
      double alignmentX = -1})
      : _atlas = previous._atlas.retain(),
        _revealAtlas = previous._revealAtlas?.retain(),
        _completeSource = previous._completeSource,
        fromSize =
            Size.lerp(previous.fromSize, previous.toSize, presentedProgress)!,
        toSize = target.size {
    cells = _retargetCells(previous, target, presentedProgress, targetOffset,
        fromOffset, alignmentX);
    _addRevealed(target, targetOffset, alignmentX);
  }

  static List<LyricGlyphCell> _retargetCells(
      LyricGlyphMorph previous,
      TextPainter target,
      double progress,
      Offset targetOffset,
      Offset fromOffset,
      double alignmentX) {
    final lines = target.computeLineMetrics();
    return [
      for (final cell in previous.cells)
        () {
          final presented = cell.at(progress).shift(fromOffset);
          final destination =
              _placedSelection(target, cell.start, cell.end, alignmentX, lines);
          final visible = destination != null && !destination.isEmpty;
          return LyricGlyphCell(cell.start, cell.end, cell.source, presented,
              visible ? destination.shift(targetOffset) : presented,
              coloured: cell.coloured,
              fromOpacity: cell.opacityAt(progress),
              toOpacity: visible ? 1 : 0,
              atlas: cell._atlas)
            ..sourceClip = cell.sourceClip;
        }()
    ];
  }

  final _LyricGlyphAtlas _atlas;
  _LyricGlyphAtlas? _revealAtlas;
  bool _completeSource;
  late List<LyricGlyphCell> cells;
  final Size fromSize, toSize;
  Size get sourceSize => _atlas.size;
  bool _disposed = false;
  Object? _colourLayoutIdentity;
  final _colourSources = <LyricGlyphCell, ({Rect bounds, Rect clip})>{};

  late final bool _hasColourCells = cells.any((cell) => cell.coloured);
  late final bool _hasVisibilityChanges = cells.any((cell) =>
      cell.fromOpacity != 1 || cell.toOpacity != 1 || cell._atlas != null);

  void _addRevealed(TextPainter target, Offset offset, double alignmentX) {
    if (_completeSource) return;
    final targetCells = _cells(target, target, Offset.zero, alignmentX);
    var sourceIndex = 0;
    final missing = <int>{};
    for (final cell in targetCells) {
      while (
          sourceIndex < cells.length && cells[sourceIndex].end <= cell.start) {
        sourceIndex++;
      }
      if (sourceIndex == cells.length || cells[sourceIndex].start > cell.start)
        missing.add(cell.start);
    }
    if (missing.isEmpty) return;
    // One unbounded source owns all newly exposed clusters, even after repeated
    // width edits. Its lazy atlas remains bounded instead of recording a new
    // full paragraph for every small pointer movement.
    final atlas =
        _revealAtlas ??= _LyricGlyphAtlas.unbounded(target, _atlas.ratio);
    final revealed = _cells(atlas.revealSource!, target, offset, alignmentX);
    cells = [
      ...cells,
      for (final cell in revealed)
        if (missing.contains(cell.start) && cell.toOpacity > 0)
          LyricGlyphCell(cell.start, cell.end, cell.source, cell.to, cell.to,
              coloured: cell.coloured, fromOpacity: 0, atlas: atlas)
            ..sourceClip = cell.sourceClip,
    ]..sort((a, b) => a.start.compareTo(b.start));
    _completeSource = _coversText(cells, target.text!.toPlainText());
  }

  static bool _coversText(List<LyricGlyphCell> cells, String text) {
    var index = 0, start = 0;
    for (final cluster in text.characters) {
      final end = start + cluster.length;
      while (index < cells.length && cells[index].end <= start) index++;
      if (cluster.trim().isNotEmpty &&
          (index == cells.length ||
              cells[index].start > start ||
              cells[index].end < end)) return false;
      start = end;
    }
    return true;
  }

  void _syncColourSources(TextPainter paragraph, Object identity) {
    if (!_hasColourCells || _colourLayoutIdentity == identity) return;
    _colourSources.clear();
    final lines = paragraph.computeLineMetrics();
    final rows = <TextRange, List<({LyricGlyphCell cell, Rect bounds})>>{};
    for (final cell in cells) {
      final bounds = _selection(paragraph, cell.start, cell.end);
      if (bounds == null || bounds.isEmpty) continue;
      final range = paragraph.getLineBoundary(TextPosition(offset: cell.start));
      rows.putIfAbsent(range, () => []).add((cell: cell, bounds: bounds));
    }
    for (final row in rows.values) {
      row.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      for (final (index, entry) in row.indexed) {
        if (!entry.cell.coloured) continue;
        final bounds = entry.bounds;
        final line = _lineIndex(lines, bounds);
        _colourSources[entry.cell] = (
          bounds: bounds,
          clip: Rect.fromLTRB(
              index == 0 ? -4 : (row[index - 1].bounds.right + bounds.left) / 2,
              line == 0 ? -4 : lines[line].baseline - lines[line].ascent,
              index == row.length - 1
                  ? paragraph.width + 4
                  : (bounds.right + row[index + 1].bounds.left) / 2,
              line == lines.length - 1
                  ? paragraph.height + 4
                  : lines[line + 1].baseline - lines[line + 1].ascent)
        );
      }
    }
    _colourLayoutIdentity = identity;
  }

  static Rect? _selection(TextPainter text, int start, int end) {
    Rect? bounds;
    for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end))) {
      bounds =
          bounds == null ? box.toRect() : bounds.expandToInclude(box.toRect());
    }
    return bounds;
  }

  static List<LyricGlyphCell> _cells(TextPainter from, TextPainter to,
      Offset targetOffset, double alignmentX) {
    final text = from.text!.toPlainText();
    final lines = from.computeLineMetrics(),
        targetLines = to.computeLineMetrics();
    final result = <LyricGlyphCell>[];
    var start = 0;
    for (final cluster in text.characters) {
      final end = start + cluster.length;
      final source = _selection(from, start, end);
      final target = _placedSelection(to, start, end, alignmentX, targetLines)
          ?.shift(targetOffset);
      final presented = _placedSelection(from, start, end, alignmentX, lines);
      if (source != null && !source.isEmpty) {
        final visible = target != null && !target.isEmpty;
        final destination = visible ? target : presented!;
        final previous = result.isEmpty ? null : result.last;
        // Selection boxes for a ligature can coincide. Keep the entire shaped
        // cluster in one cell instead of drawing or clipping its ink twice.
        if (previous != null &&
            previous.source.overlaps(source) &&
            (previous.source.top - source.top).abs() < .01 &&
            (previous.source.bottom - source.bottom).abs() < .01) {
          result[result.length - 1] = LyricGlyphCell(
              previous.start,
              end,
              previous.source.expandToInclude(source),
              previous.from.expandToInclude(presented!),
              previous.to.expandToInclude(destination),
              coloured: previous.coloured || _coloured(cluster),
              toOpacity: visible ? 1 : 0);
        } else {
          result.add(LyricGlyphCell(
              start, end, source, presented!, destination,
              coloured: _coloured(cluster), toOpacity: visible ? 1 : 0));
        }
      }
      start = end;
    }
    final rows = <int, List<LyricGlyphCell>>{};
    for (final cell in result) {
      final closest = _lineIndex(lines, cell.source);
      rows.putIfAbsent(closest, () => []).add(cell);
    }
    for (final entry in rows.entries) {
      final row = entry.value
        ..sort((a, b) => a.source.left.compareTo(b.source.left));
      final line = entry.key;
      final top = line == 0 ? -4.0 : lines[line].baseline - lines[line].ascent;
      final bottom = line == lines.length - 1
          ? from.height + 4
          : lines[line + 1].baseline - lines[line + 1].ascent;
      for (var cell = 0; cell < row.length; cell++) {
        row[cell].sourceClip = Rect.fromLTRB(
            cell == 0
                ? -4
                : (row[cell - 1].source.right + row[cell].source.left) / 2,
            top,
            cell == row.length - 1
                ? from.width + 4
                : (row[cell].source.right + row[cell + 1].source.left) / 2,
            bottom);
      }
    }
    return List.unmodifiable(result);
  }

  static final _emojiPresentation =
      RegExp(r'\p{Emoji_Presentation}', unicode: true);
  static bool _coloured(String text) =>
      !text.contains('\ufe0e') &&
      (text.contains('\ufe0f') ||
          text.contains('\u20e3') ||
          _emojiPresentation.hasMatch(text));

  static Rect? _placedSelection(TextPainter painter, int start, int end,
      double alignmentX, List<drawing.LineMetrics> lines) {
    final box = _selection(painter, start, end);
    if (box == null || alignmentX <= -1) return box;
    if (lines.isEmpty) return box;
    final line = lines[_lineIndex(lines, box)];
    return box.shift(Offset(
        (painter.width - line.width) * ((alignmentX + 1) / 2).clamp(0.0, 1.0),
        0));
  }

  static int _lineIndex(List<drawing.LineMetrics> lines, Rect box) {
    var low = 0, high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].baseline - lines[middle].ascent < box.top) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return 0;
    if (low == lines.length) return low - 1;
    return (lines[low].baseline - lines[low].ascent - box.top).abs() <
            (lines[low - 1].baseline - lines[low - 1].ascent - box.top).abs()
        ? low
        : low - 1;
  }

  int _firstCell(int start) {
    var low = 0, high = cells.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (cells[middle].end <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  List<Rect> boxes(int start, int end, double progress) => [
        for (var index = _firstCell(start);
            index < cells.length && cells[index].start < end;
            index++)
          if (cells[index].opacityAt(progress) > 0) cells[index].at(progress)
      ];

  Rect? bounds(int start, int end, double progress) {
    Rect? result;
    for (final box in boxes(start, end, progress)) {
      result = result == null ? box : result.expandToInclude(box);
    }
    return result;
  }

  /// Paint one source range as a batch of whole cached clusters. Tinting applies
  /// to monochrome text alone; colourful emoji retains its recorded colours.
  void paint(Canvas canvas,
      {required double progress,
      Color? tint,
      drawing.Shader? shader,
      bool nativeParagraph = false,
      int start = 0,
      int? end,
      void Function(Canvas canvas)? colourPaint,
      TextPainter? colourParagraph,
      Object? colourLayoutIdentity,
      Offset Function(LyricGlyphCell cell, Rect presented)? displacement}) {
    if (_disposed) return;
    if (!_hasVisibilityChanges) {
      _paintCells(canvas, cells, _atlas,
          progress: progress,
          tint: tint,
          shader: shader,
          nativeParagraph: nativeParagraph,
          start: start,
          end: end,
          colourPaint: colourPaint,
          colourParagraph: colourParagraph,
          colourLayoutIdentity: colourLayoutIdentity,
          displacement: displacement);
      return;
    }
    final groups = <(_LyricGlyphAtlas, double), List<LyricGlyphCell>>{};
    for (var index = _firstCell(start);
        index < cells.length && cells[index].start < (end ?? 0x7fffffff);
        index++) {
      final cell = cells[index];
      if (cell.start < start) continue;
      final opacity = cell.opacityAt(progress).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      groups.putIfAbsent((cell._atlas ?? _atlas, opacity), () => []).add(cell);
    }
    for (final entry in groups.entries) {
      final (atlas, opacity) = entry.key;
      if (opacity < 1) {
        Rect? bounds;
        for (final cell in entry.value) {
          final presented = cell.at(progress);
          final shift = presented.topLeft -
              cell.source.topLeft +
              (displacement?.call(cell, presented) ?? Offset.zero);
          // Native replay uses leading edges; atlas replay uses centres.
          // Keep both inside the fade layer so a changing advance cannot
          // clip a stem while its opacity is interpolating.
          final centerShift = presented.center -
              cell.source.center +
              (displacement?.call(cell, presented) ?? Offset.zero);
          final ink = cell.sourceClip
              .shift(shift)
              .expandToInclude(cell.sourceClip.shift(centerShift));
          bounds = bounds == null ? ink : bounds.expandToInclude(ink);
        }
        canvas.saveLayer(bounds?.intersect(canvas.getLocalClipBounds()),
            Paint()..color = Colors.white.withValues(alpha: opacity));
      }
      _paintCells(canvas, entry.value, atlas,
          progress: progress,
          tint: tint,
          shader: shader,
          nativeParagraph: nativeParagraph,
          colourPaint: identical(atlas, _atlas) ? colourPaint : null,
          colourParagraph: identical(atlas, _atlas) ? colourParagraph : null,
          colourLayoutIdentity: colourLayoutIdentity,
          displacement: displacement);
      if (opacity < 1) canvas.restore();
    }
  }

  void _paintCells(
      Canvas canvas, List<LyricGlyphCell> selected, _LyricGlyphAtlas atlas,
      {required double progress,
      Color? tint,
      drawing.Shader? shader,
      required bool nativeParagraph,
      int start = 0,
      int? end,
      void Function(Canvas canvas)? colourPaint,
      TextPainter? colourParagraph,
      Object? colourLayoutIdentity,
      Offset Function(LyricGlyphCell cell, Rect presented)? displacement}) {
    if (nativeParagraph && shader == null && atlas.hasNativeParagraph) {
      // Reuse the native paragraph replay used below for colour glyphs. Plain
      // spacing must keep the same raster source as the resting paragraph.
      final groups = <Offset, Path>{};
      final clip = canvas.getLocalClipBounds();
      for (var index = identical(selected, cells) ? _firstCell(start) : 0;
          index < selected.length &&
              selected[index].start < (end ?? 0x7fffffff);
          index++) {
        final cell = selected[index];
        if (cell.start < start) continue;
        final presented = cell.at(progress);
        // Selection width includes tracking space, not a larger glyph. Its
        // leading visual edge is the translation of the unchanged source ink.
        final movement = presented.topLeft -
            cell.source.topLeft +
            (displacement?.call(cell, presented) ?? Offset.zero);
        final needed = cell.sourceClip.intersect(clip.shift(-movement));
        if (!needed.isEmpty) {
          groups.putIfAbsent(movement, Path.new).addRect(needed);
        }
      }
      if (groups.isEmpty) return;
      final source = atlas.nativePictureFor(tint);
      for (final entry in groups.entries) {
        canvas.save();
        canvas.translate(entry.key.dx, entry.key.dy);
        canvas.clipPath(entry.value, doAntiAlias: false);
        canvas.drawPicture(source);
        canvas.restore();
      }
      return;
    }
    if (colourPaint != null && colourParagraph != null) {
      _syncColourSources(
          colourParagraph, colourLayoutIdentity ?? colourParagraph);
    }
    final clip = canvas.getLocalClipBounds();
    Rect? inkBounds;
    var hasColour = false;
    final colourGroups = <Offset, Path>{};
    final batches = <(int, int),
        ({
      List<Rect> sources,
      List<drawing.RSTransform> poses,
      List<Rect> colouredSources,
      List<drawing.RSTransform> colouredPoses
    })>{};
    for (var index = identical(selected, cells) ? _firstCell(start) : 0;
        index < selected.length && selected[index].start < (end ?? 0x7fffffff);
        index++) {
      final cell = selected[index];
      if (cell.start < start) continue;
      final presented = cell.at(progress);
      final colourSource = colourPaint == null ? null : _colourSources[cell];
      final movement = presented.center -
          (colourSource?.bounds ?? cell.source).center +
          (displacement?.call(cell, presented) ?? Offset.zero);
      final sourceClip = colourSource?.clip ?? cell.sourceClip;
      final needed = sourceClip.intersect(clip.shift(-movement));
      if (needed.isEmpty) continue;
      if (cell.coloured && colourPaint != null) {
        colourGroups.putIfAbsent(movement, Path.new).addRect(needed);
        continue;
      }
      for (final tileKey in atlas.keysFor(needed)) {
        final tileBounds = atlas.boundsFor(tileKey);
        final piece = sourceClip.intersect(tileBounds);
        if (piece.isEmpty) continue;
        inkBounds = inkBounds == null
            ? piece.shift(movement)
            : inkBounds.expandToInclude(piece.shift(movement));
        final batch = batches.putIfAbsent(
            tileKey,
            () => (
                  sources: [],
                  poses: [],
                  colouredSources: [],
                  colouredPoses: []
                ));
        final relative = piece.shift(-tileBounds.topLeft);
        final uv = Rect.fromLTRB(
            relative.left * atlas.ratio,
            relative.top * atlas.ratio,
            relative.right * atlas.ratio,
            relative.bottom * atlas.ratio);
        final pose = drawing.RSTransform(1 / atlas.ratio, 0,
            piece.left + movement.dx, piece.top + movement.dy);
        if (cell.coloured) {
          hasColour = true;
          batch.colouredSources.add(uv);
          batch.colouredPoses.add(pose);
        } else {
          batch.sources.add(uv);
          batch.poses.add(pose);
        }
      }
    }
    if (colourGroups.isNotEmpty) {
      // COLR glyphs can contain several overlapping translucent layers.
      // Replaying the existing native draw preserves their per-layer opacity;
      // flattening white coverage and then tinting cannot recover that alpha.
      // Record once per native ink pass and combine equal cell movements.
      final recorder = drawing.PictureRecorder();
      colourPaint!(Canvas(recorder));
      final colours = recorder.endRecording();
      for (final entry in colourGroups.entries) {
        canvas.save();
        canvas.translate(entry.key.dx, entry.key.dy);
        canvas.clipPath(entry.value, doAntiAlias: false);
        canvas.drawPicture(colours);
        canvas.restore();
      }
      colours.dispose();
    }
    final layerBounds = inkBounds?.intersect(clip);
    if (layerBounds == null || layerBounds.isEmpty) return;
    if (shader != null) canvas.saveLayer(layerBounds, Paint());
    for (final entry in batches.entries) {
      final batch = entry.value;
      if (batch.sources.isEmpty) continue;
      canvas.drawAtlas(
          atlas.tileFor(entry.key).image,
          batch.poses,
          batch.sources,
          null,
          null,
          null,
          atlas.inkPaint(shader == null ? tint : Colors.white));
    }
    if (shader != null) {
      canvas.drawRect(
          layerBounds,
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.srcIn);
      canvas.restore();
    }
    if (shader != null && hasColour) canvas.saveLayer(layerBounds, Paint());
    for (final entry in batches.entries) {
      final batch = entry.value;
      if (batch.colouredSources.isEmpty) continue;
      canvas.drawAtlas(
          atlas.tileFor(entry.key).image,
          batch.colouredPoses,
          batch.colouredSources,
          null,
          null,
          null,
          atlas.colourPaint(shader == null ? tint : Colors.white));
    }
    if (shader != null && hasColour) {
      // A colour glyph keeps its RGB. Playback owns its opacity exactly once,
      // as it does for monochrome coverage; srcIn would erase the glyph colours.
      canvas.drawRect(
          layerBounds,
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.dstIn);
      canvas.restore();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _atlas.release();
    _revealAtlas?.release();
  }
}

class _AtlasTile {
  _AtlasTile(this.image, this.bounds);
  final drawing.Image image;
  final Rect bounds;
}

class _LyricGlyphAtlas {
  factory _LyricGlyphAtlas.unbounded(TextPainter source, double pixelRatio) {
    final painter = TextPainter(
        text: source.text,
        textAlign: source.textAlign,
        textDirection: source.textDirection,
        textScaler: source.textScaler,
        strutStyle: source.strutStyle,
        locale: source.locale,
        maxLines: source.maxLines,
        textWidthBasis: source.textWidthBasis,
        textHeightBehavior: source.textHeightBehavior)
      ..layout();
    return _LyricGlyphAtlas(painter, pixelRatio)..revealSource = painter;
  }

  _LyricGlyphAtlas(TextPainter painter, double pixelRatio)
      : size = painter.size,
        ratio = pixelRatio.clamp(1.0, 3.0),
        _sourceText =
            painter.text is TextSpan ? painter.text as TextSpan : null,
        originalAlpha = painter.text?.style?.color?.a ?? 1 {
    final recorder = drawing.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    picture = recorder.endRecording();
    final align = painter.textAlign;
    final direction = painter.textDirection;
    final scaler = painter.textScaler;
    final strut = painter.strutStyle;
    final locale = painter.locale;
    final maxLines = painter.maxLines;
    final ellipsis = painter.ellipsis;
    final widthBasis = painter.textWidthBasis;
    final heightBehavior = painter.textHeightBehavior;
    _createNativePainter = (text) => TextPainter(
        text: text,
        textAlign: align,
        textDirection: direction,
        textScaler: scaler,
        strutStyle: strut,
        locale: locale,
        maxLines: maxLines,
        ellipsis: ellipsis,
        textWidthBasis: widthBasis,
        textHeightBehavior: heightBehavior);
  }
  final Size size;
  TextPainter? revealSource;
  final double ratio, originalAlpha;
  final TextSpan? _sourceText;
  late final TextPainter Function(TextSpan text) _createNativePainter;
  TextPainter? _nativePainter;
  drawing.Picture? _nativePicture;
  Color? _nativeTint;
  late final drawing.Picture picture;
  final _tiles = <(int, int), _AtlasTile>{};
  int _references = 1, _pixels = 0;
  static const _tilePixels = 512;
  static const _maximumPixels = 4 * 1024 * 1024;

  bool get hasNativeParagraph => _sourceText != null;

  drawing.Picture nativePictureFor(Color? tint) {
    final source = _sourceText!;
    if (tint == null || tint == source.style?.color) return picture;
    if (_nativePicture != null && tint == _nativeTint) return _nativePicture!;
    // Keep the original shaped source through a retarget. Recolouring the
    // current endpoint would otherwise substitute its different tracking or
    // wrapping. The extra painter is created only when its colour changes.
    final text = TextSpan(
        text: source.text,
        children: source.children,
        style: source.style?.copyWith(color: tint),
        locale: source.locale,
        semanticsLabel: source.semanticsLabel,
        spellOut: source.spellOut);
    final painter = _nativePainter ??= _createNativePainter(text);
    painter
      ..text = text
      ..layout(minWidth: size.width, maxWidth: size.width);
    final recorder = drawing.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    _nativePicture?.dispose();
    _nativePicture = recorder.endRecording();
    _nativeTint = tint;
    return _nativePicture!;
  }

  _LyricGlyphAtlas retain() {
    _references++;
    return this;
  }

  Rect boundsFor((int, int) key) {
    final side = _tilePixels / ratio;
    return Rect.fromLTWH(key.$1 * side, key.$2 * side, side, side)
        .intersect(Rect.fromLTRB(-4, -4, size.width + 4, size.height + 4));
  }

  Iterable<(int, int)> keysFor(Rect source) sync* {
    final side = _tilePixels / ratio;
    for (var y = (source.top / side).floor();
        y <= (source.bottom / side).floor();
        y++) {
      for (var x = (source.left / side).floor();
          x <= (source.right / side).floor();
          x++) {
        yield (x, y);
      }
    }
  }

  _AtlasTile tileFor((int, int) key) {
    var tile = _tiles.remove(key);
    if (tile == null) {
      final bounds = boundsFor(key);
      final recorder = drawing.PictureRecorder();
      Canvas(recorder)
        ..scale(ratio)
        ..translate(-bounds.left, -bounds.top)
        ..drawPicture(picture);
      final part = recorder.endRecording();
      final image = part.toImageSync(
          (bounds.width * ratio).ceil(), (bounds.height * ratio).ceil());
      part.dispose();
      tile = _AtlasTile(image, bounds);
      _pixels += image.width * image.height;
    }
    _tiles[key] = tile;
    while (_pixels > _maximumPixels && _tiles.length > 1) {
      final old = _tiles.remove(_tiles.keys.first)!;
      _pixels -= old.image.width * old.image.height;
      old.image.dispose();
    }
    return tile;
  }

  Paint inkPaint(Color? tint) {
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (tint != null) {
      final alpha = originalAlpha > 0 ? tint.a / originalAlpha : 0.0;
      paint.colorFilter = ColorFilter.matrix([
        0,
        0,
        0,
        0,
        tint.r * 255,
        0,
        0,
        0,
        0,
        tint.g * 255,
        0,
        0,
        0,
        0,
        tint.b * 255,
        0,
        0,
        0,
        alpha,
        0,
      ]);
    }
    return paint;
  }

  Paint colourPaint(Color? tint) {
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (tint != null) {
      paint.colorFilter = ColorFilter.matrix([
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        originalAlpha > 0 ? tint.a / originalAlpha : 0,
        0,
      ]);
    }
    return paint;
  }

  void release() {
    if (--_references > 0) return;
    for (final tile in _tiles.values) {
      tile.image.dispose();
    }
    _tiles.clear();
    _nativePicture?.dispose();
    _nativePainter?.dispose();
    revealSource?.dispose();
    picture.dispose();
  }
}
