import 'dart:math' as math;
import 'package:dan_player/category_presentation.dart';
import 'package:flutter/rendering.dart';

/// Stable first-fit packing. Coordinates are cells, independent of DPI. Only
/// geometry is precomputed; SliverGrid still builds visible covers lazily.
class CategoryTilePlacement {
  const CategoryTilePlacement(
      this.index, this.column, this.row, this.columns, this.rows);
  final int index, column, row, columns, rows;
}

List<CategoryTilePlacement> packCategoryTiles(
    List<CategoryTileSize> sizes, int columns,
    {bool fillGaps = true,
    List<CategoryTilePlacement>? previous,
    int? resizedIndex}) {
  assert(columns > 0);
  final occupied = <int>[];
  final result = <CategoryTilePlacement>[];
  final old = {
    for (final tile in previous ?? <CategoryTilePlacement>[]) tile.index: tile
  };
  bool place(int index, int cell) {
    final x = cell % columns, y = cell ~/ columns;
    final width = math.min(columns, sizes[index].columns),
        height = sizes[index].rows;
    if (x + width > columns) return false;
    while (occupied.length < y + height) {
      occupied.add(0);
    }
    final mask = ((1 << width) - 1) << x;
    for (var dy = 0; dy < height; dy++) {
      if (occupied[y + dy] & mask != 0) return false;
    }
    for (var dy = 0; dy < height; dy++) {
      occupied[y + dy] |= mask;
    }
    result.add(CategoryTilePlacement(index, x, y, width, height));
    return true;
  }

  final reserved = <int>{};
  if (!fillGaps && old.isNotEmpty) {
    // The resized tile owns its origin. Reserve unaffected tiles before
    // finding destinations for collisions; a shrink never collapses holes.
    final priority = [
      if (resizedIndex != null) resizedIndex,
      for (var i = 0; i < sizes.length; i++)
        if (i != resizedIndex) i
    ];
    for (final index in priority) {
      final tile = old[index];
      if (tile != null && place(index, tile.row * columns + tile.column))
        reserved.add(index);
    }
  }
  var cursor = 0;
  final starts = <(int, int), int>{};
  for (var index = 0; index < sizes.length; index++) {
    if (reserved.contains(index)) continue;
    final width = math.min(columns, sizes[index].columns);
    final height = sizes[index].rows;
    final prior = old[index];
    var cell = fillGaps
        ? starts[(width, height)] ?? 0
        : prior == null
            ? cursor
            : prior.row * columns + prior.column;
    while (true) {
      final x = cell % columns;
      if (x + width > columns) {
        cell += columns - x;
        continue;
      }
      if (place(index, cell)) {
        cursor = cell + width;
        starts[(width, height)] = cell + 1;
        break;
      }
      cell++;
    }
  }
  // A sliver's child indices must follow increasing scroll offsets. Preserve
  // the user's order separately from this spatial projection.
  result.sort((a, b) =>
      a.row != b.row ? a.row.compareTo(b.row) : a.column.compareTo(b.column));
  return result;
}

class CategoryTileGridDelegate extends SliverGridDelegate {
  CategoryTileGridDelegate(this.tiles, this.unit, this.gap, {this.rowHeight})
      : maxEndRows = _prefixEnds(tiles);
  final List<int> maxEndRows;
  static List<int> _prefixEnds(List<CategoryTilePlacement> tiles) {
    var end = 0;
    return [
      for (final tile in tiles) end = math.max(end, tile.row + tile.rows)
    ];
  }

  final List<CategoryTilePlacement> tiles;
  final double unit, gap;
  final double? rowHeight;
  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _TileLayout(
      tiles,
      maxEndRows,
      unit,
      rowHeight ?? unit,
      gap,
      constraints.crossAxisExtent,
      axisDirectionIsReversed(constraints.crossAxisDirection));
  @override
  bool shouldRelayout(CategoryTileGridDelegate old) =>
      tiles != old.tiles ||
      unit != old.unit ||
      gap != old.gap ||
      rowHeight != old.rowHeight;
}

class _TileLayout extends SliverGridLayout {
  _TileLayout(this.tiles, this.maxEndRows, this.unit, this.rowHeight, this.gap,
      this.width, this.reverse);
  final List<CategoryTilePlacement> tiles;
  final List<int> maxEndRows;
  final double unit, rowHeight, gap, width;
  final bool reverse;
  double get stride => rowHeight + gap;
  @override
  int getMinChildIndexForScrollOffset(double offset) {
    var low = 0, high = tiles.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (maxEndRows[mid] * stride - gap <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return math.min(low, math.max(0, tiles.length - 1));
  }

  @override
  int getMaxChildIndexForScrollOffset(double offset) {
    var low = 0, high = tiles.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (tiles[mid].row * stride < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return math.max(0, low - 1);
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final t = tiles[index];
    final extent = t.columns * (unit + gap) - gap;
    return SliverGridGeometry(
        scrollOffset: t.row * stride,
        crossAxisOffset: reverse
            ? width - t.column * (unit + gap) - extent
            : t.column * (unit + gap),
        mainAxisExtent: t.rows * stride - gap,
        crossAxisExtent: extent);
  }

  @override
  double computeMaxScrollOffset(int childCount) =>
      tiles.isEmpty ? 0 : maxEndRows.last * stride - gap;
}
