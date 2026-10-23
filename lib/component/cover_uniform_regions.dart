import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Conservative proof that an image sampling region has one premultiplied
/// RGBA value. A query includes whole tiles, so it can miss a smaller uniform
/// region but cannot accept a tile containing different pixels.
class CoverUniformRegions {
  CoverUniformRegions._(this.width, this.height, this._columns, this._colors,
      this._uniform, this.isUniformEntireImage);

  static const tileSize = 16;
  static const maximumPixels = 4000000;

  final int width;
  final int height;
  final int _columns;
  final Uint32List _colors;
  final Uint8List _uniform;
  final bool isUniformEntireImage;

  static bool _validDimensions(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= maximumPixels &&
      height <= maximumPixels &&
      width * height <= maximumPixels;

  /// Reads the actual displayed image. The caller owns request coalescing and
  /// must still match the result to its current frame with [ui.Image.isCloneOf].
  /// No shared image, pixel buffer or index is retained by this helper.
  static Future<CoverUniformRegions?> inspect(ui.Image image) async {
    ui.Image? retained;
    try {
      final width = image.width;
      final height = image.height;
      if (!_validDimensions(width, height) ||
          image.colorSpace != ui.ColorSpace.sRGB) return null;
      retained = image.clone();
      final data =
          await retained.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return await compute(_inspectUniformPixels,
          _UniformPixels(width, height, Uint8List.sublistView(data)),
          debugLabel: 'cover-uniform-regions');
    } catch (_) {
      // Optional work must never interrupt the normal cover rendering path.
      return null;
    } finally {
      retained?.dispose();
    }
  }

  /// Builds an index from exact, row-major, premultiplied RGBA bytes. All four
  /// channels must match; transparent RGB and alpha are never approximated.
  /// Invalid dimensions or a mismatched buffer return null.
  static CoverUniformRegions? fromRGBA(int width, int height, Uint8List rgba) {
    if (!_validDimensions(width, height) || rgba.length != width * height * 4)
      return null;
    final columns = (width + tileSize - 1) ~/ tileSize;
    final rows = (height + tileSize - 1) ~/ tileSize;
    final colors = Uint32List(columns * rows);
    final uniform = Uint8List(columns * rows);
    int? wholeColor;
    var wholeUniform = true;
    for (var tileY = 0; tileY < rows; tileY++) {
      final top = tileY * tileSize;
      final bottom = (top + tileSize).clamp(0, height);
      for (var tileX = 0; tileX < columns; tileX++) {
        final left = tileX * tileSize;
        final right = (left + tileSize).clamp(0, width);
        final first = (top * width + left) * 4;
        final red = rgba[first];
        final green = rgba[first + 1];
        final blue = rgba[first + 2];
        final alpha = rgba[first + 3];
        final color = red | green << 8 | blue << 16 | alpha << 24;
        var same = true;
        for (var y = top; y < bottom && same; y++) {
          for (var x = left; x < right; x++) {
            final at = (y * width + x) * 4;
            if (rgba[at] != red ||
                rgba[at + 1] != green ||
                rgba[at + 2] != blue ||
                rgba[at + 3] != alpha) {
              same = false;
              break;
            }
          }
        }
        final tile = tileY * columns + tileX;
        colors[tile] = color;
        uniform[tile] = same ? 1 : 0;
        wholeColor ??= color;
        if (!same || color != wholeColor) wholeUniform = false;
      }
    }
    return CoverUniformRegions._(
        width, height, columns, colors, uniform, wholeUniform);
  }

  /// Tests a source-image sampling rectangle, including any displacement and
  /// filter margin supplied by the caller. Coordinates outside the image use
  /// its edge tiles, matching TileMode.clamp. Empty or non-finite input is false.
  bool isUniform(ui.Rect pixelRect) {
    if (!pixelRect.left.isFinite ||
        !pixelRect.top.isFinite ||
        !pixelRect.right.isFinite ||
        !pixelRect.bottom.isFinite ||
        pixelRect.isEmpty) return false;
    if (isUniformEntireImage) return true;
    final left =
        pixelRect.left.clamp(0.0, width.toDouble()).floor().clamp(0, width - 1);
    final top = pixelRect.top
        .clamp(0.0, height.toDouble())
        .floor()
        .clamp(0, height - 1);
    final right = (pixelRect.right.clamp(0.0, width.toDouble()).ceil() - 1)
        .clamp(0, width - 1);
    final bottom = (pixelRect.bottom.clamp(0.0, height.toDouble()).ceil() - 1)
        .clamp(0, height - 1);
    final firstColumn = left ~/ tileSize;
    final lastColumn = right ~/ tileSize;
    final firstRow = top ~/ tileSize;
    final lastRow = bottom ~/ tileSize;
    final color = _colors[firstRow * _columns + firstColumn];
    for (var row = firstRow; row <= lastRow; row++) {
      for (var column = firstColumn; column <= lastColumn; column++) {
        final tile = row * _columns + column;
        if (_uniform[tile] == 0 || _colors[tile] != color) return false;
      }
    }
    return true;
  }
}

class _UniformPixels {
  const _UniformPixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

CoverUniformRegions? _inspectUniformPixels(_UniformPixels pixels) =>
    CoverUniformRegions.fromRGBA(pixels.width, pixels.height, pixels.rgba);
