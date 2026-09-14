import 'dart:math' as math;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_tile_layout.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Reuses the category packer and lazy sliver layout; playlist relationship IDs
/// and drop callbacks remain owned by PlaylistBrowser.
class PlaylistTileGrid extends StatefulWidget {
  const PlaylistTileGrid({
    super.key,
    required this.ids,
    required this.presentation,
    required this.controller,
    required this.padding,
    required this.itemBuilder,
    required this.onLayoutChanged,
    this.tailBuilder,
  });
  final List<String> ids;
  final CategoryPresentation presentation;
  final ScrollController controller;
  final EdgeInsets padding;
  final Widget Function(BuildContext, int) itemBuilder;
  final WidgetBuilder? tailBuilder;
  final ValueChanged<Map<String, List<int>>> onLayoutChanged;

  @override
  State<PlaylistTileGrid> createState() => _PlaylistTileGridState();
}

class _PlaylistTileGridState extends State<PlaylistTileGrid> {
  List<String> _ids = [];
  List<CategoryTileSize> _sizes = [];
  List<CategoryTilePlacement> _placements = [];
  int _columns = 0;
  bool? _fill;
  bool _linear = false;
  int _revision = 0;

  @override
  Widget build(BuildContext context) =>
      CoverPointerScope(child: LayoutBuilder(builder: (context, box) {
        const gap = 4.0;
        final minimum = math.max(
            116.0, MediaQuery.textScalerOf(context).scale(14) * 2.6 + 52);
        final columns = math.max(1, ((box.maxWidth + gap) / minimum).floor());
        final unit = (box.maxWidth - gap * (columns - 1)) / columns;
        final sizes = [
          for (final id in widget.ids)
            widget.presentation.sizes[id] ?? CategoryTileSize.small
        ];
        final sameIds = listEquals(_ids, widget.ids);
        final resized = sameIds && sizes.length == _sizes.length
            ? sizes.indexed
                .where((entry) => _sizes[entry.$1] != entry.$2)
                .firstOrNull
                ?.$1
            : null;
        if (!sameIds ||
            !listEquals(_sizes, sizes) ||
            columns != _columns ||
            _fill != widget.presentation.autoFill) {
          _linear = _fill != null && _fill != widget.presentation.autoFill;
          final previous = sameIds && columns == _columns
              ? _placements
              : _ids.isEmpty
                  ? [
                      for (var i = 0; i < widget.ids.length; i++)
                        if (widget.presentation.layouts[widget.ids[i]]
                            case final saved?
                            when saved[0] == columns && saved[1] < columns)
                          CategoryTilePlacement(i, saved[1], saved[2],
                              sizes[i].columns, sizes[i].rows)
                    ]
                  : null;
          _placements = packCategoryTiles(sizes, columns,
              fillGaps: widget.presentation.autoFill,
              previous: previous,
              resizedIndex: resized);
          _ids = List.of(widget.ids);
          _sizes = sizes;
          _columns = columns;
          _fill = widget.presentation.autoFill;
          if (!widget.presentation.autoFill) {
            final positions = {
              for (final tile in _placements)
                widget.ids[tile.index]: [columns, tile.column, tile.row]
            };
            if (positions.entries.any((e) =>
                !listEquals(e.value, widget.presentation.layouts[e.key]))) {
              final revision = ++_revision;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && revision == _revision) {
                  widget.onLayoutChanged(positions);
                }
              });
            }
          }
        }
        final placements = [
          ..._placements,
          if (widget.tailBuilder != null)
            CategoryTilePlacement(
                widget.ids.length,
                0,
                _placements.fold<int>(0,
                    (maxRow, tile) => math.max(maxRow, tile.row + tile.rows)),
                1,
                1),
        ];
        final indices = {
          for (var i = 0; i < placements.length; i++)
            ValueKey((
              'playlist-grid-entry',
              placements[i].index < widget.ids.length
                  ? widget.ids[placements[i].index]
                  : 'tail'
            )): i
        };
        return GridView.builder(
          key: PageStorageKey(widget.key),
          controller: widget.controller,
          padding: widget.padding,
          gridDelegate: CategoryTileGridDelegate(placements, unit, gap),
          itemCount: placements.length,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) {
            final tile = placements[index];
            final id = tile.index < widget.ids.length
                ? widget.ids[tile.index]
                : 'tail';
            return CategoryTileMotion(
              key: ValueKey(('playlist-grid-entry', id)),
              rect: Rect.fromLTWH(
                  tile.column * (unit + gap),
                  tile.row * (unit + gap),
                  tile.columns * (unit + gap) - gap,
                  tile.rows * (unit + gap) - gap),
              linear: _linear,
              child: tile.index == widget.ids.length
                  ? widget.tailBuilder!(context)
                  : widget.itemBuilder(context, tile.index),
            );
          },
        );
      }));
}
