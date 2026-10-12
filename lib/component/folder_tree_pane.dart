import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:desktop_lyric/ui_language.dart';

import '../library/audio_library.dart';
import '../library/folder_tree.dart';
import 'app_content_scrollbar.dart';
import 'app_entrance.dart';
import 'now_playing_bar_metrics.dart';
import 'playlist_tree_pane.dart';

const folderTreeToggleSlotWidth = 36.0;
const folderTreeContentInset = 12.0 + folderTreeToggleSlotWidth;

/// Like the playlist tree, deep paths share a smaller step instead of losing
/// content width one indentation level at a time.
double folderTreeIndentStep(double width, int maximumDepth) =>
    math.min(20.0, width * .18 / math.max(1, maximumDepth));

typedef FolderTreeFolderBuilder = Widget Function(
    BuildContext context, FolderTreeNode node);
typedef FolderTreeSongBuilder = Widget Function(BuildContext context,
    FolderTreeNode node, Audio audio, int index, double coverSize);

/// One vertical, lazy viewport. Each song row follows normal row-major grid
/// order, and folder expansion never mounts every descendant song at once.
class FolderTreePane extends StatefulWidget {
  const FolderTreePane({
    super.key,
    required this.tree,
    required this.expanded,
    required this.songsByFolder,
    required this.folderBuilder,
    required this.songBuilder,
    required this.footer,
    this.controller,
    this.sortingFolders = const {},
  });

  final FolderTree tree;
  final Set<String> expanded;
  final Map<String, List<Audio>> songsByFolder;
  final FolderTreeFolderBuilder folderBuilder;
  final FolderTreeSongBuilder songBuilder;
  final Widget footer;
  final ScrollController? controller;
  final Set<String> sortingFolders;

  @override
  State<FolderTreePane> createState() => _FolderTreePaneState();
}

class _FolderTreePaneState extends State<FolderTreePane> {
  FolderTree? _tree;
  Set<String> _expanded = {}, _sorting = {};
  Map<String, List<Audio>> _sources = {};
  double? _width;
  _FolderTreeRows? _rows;

  _FolderTreeRows _project(double width) {
    if (_rows != null &&
        identical(_tree, widget.tree) &&
        _width == width &&
        setEquals(_expanded, widget.expanded) &&
        setEquals(_sorting, widget.sortingFolders) &&
        _sources.length == widget.songsByFolder.length &&
        _sources.entries.every((entry) =>
            identical(entry.value, widget.songsByFolder[entry.key]))) {
      return _rows!;
    }
    _tree = widget.tree;
    _width = width;
    _expanded = Set.of(widget.expanded);
    _sorting = Set.of(widget.sortingFolders);
    _sources = Map.of(widget.songsByFolder);
    return _rows = _FolderTreeRows(widget.tree.visibleSections(widget.expanded),
        _expanded, _sources, _sorting, width,
        previous: _rows);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppContentScrollbar(
        controller: widget.controller,
        builder: (context, scrollController) =>
            LayoutBuilder(builder: (context, bounds) {
              final rows = _project(bounds.maxWidth);
              final step = rows.step;
              return ListView.builder(
                key: const PageStorageKey('folder-tree-viewport'),
                controller: scrollController,
                // A dense cover grid multiplies the generic 250 px overscan
                // by every column. Retain one actual song row per side so a
                // cold expansion starts artwork only just beyond the viewport.
                scrollCacheExtent: rows.songCacheExtent == null
                    ? null
                    : ScrollCacheExtent.pixels(rows.songCacheExtent!),
                padding: EdgeInsets.only(
                    bottom: NowPlayingBarMetrics.reservedSpace(context)),
                itemCount: rows.length + 1,
                findChildIndexCallback: rows.indexOf,
                itemBuilder: (context, index) {
                  if (index == rows.length) {
                    return KeyedSubtree(
                        key: const ValueKey('folder-tree-cache'),
                        child: widget.footer);
                  }
                  final row = rows[index];
                  final rowKey = row.key;
                  rows.remember(rowKey, row);
                  final node = row.node;
                  final nextDepth =
                      index + 1 < rows.length ? rows[index + 1].visualDepth : 0;
                  Widget guided(Widget child) => CustomPaint(
                      key: rowKey,
                      painter: _FolderTreeLines(
                          depth: row.visualDepth,
                          step: step,
                          content: row.first != null ||
                              row.group != null ||
                              row.loading,
                          last: nextDepth < row.visualDepth,
                          direction: Directionality.of(context),
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: .65)),
                      child: child);
                  if (row.group case final group?) {
                    return guided(Padding(
                        padding: EdgeInsetsDirectional.only(
                            start: (node.depth + 1) * step +
                                folderTreeContentInset,
                            end: 8,
                            top: 2,
                            bottom: 6),
                        child: Semantics(
                            header: true,
                            child: Text(
                                ui(group == _FolderTreeGroup.songs
                                    ? '本文件夹歌曲'
                                    : '子文件夹'),
                                key: ValueKey(
                                    'folder-tree-group-${group.name}-${node.id}'),
                                softWrap: true,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)))));
                  }
                  if (row.loading) {
                    return guided(Padding(
                        padding: EdgeInsetsDirectional.only(
                            start: (node.depth + 1) * step +
                                folderTreeContentInset,
                            end: 8),
                        child: SizedBox(
                            height: row.coverSize! + 14,
                            child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(ui('正在排序歌曲…'),
                                    key: ValueKey(
                                        'folder-tree-sorting-${node.id}'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium)))));
                  }
                  if (row.first == null) {
                    return guided(Padding(
                      padding:
                          EdgeInsetsDirectional.only(start: node.depth * step),
                      child: AppEntrance(
                          identity: ('folder-tree-header', node.id),
                          order: index,
                          child: widget.folderBuilder(context, node)),
                    ));
                  }
                  return guided(Padding(
                    padding: EdgeInsetsDirectional.only(
                        start: (node.depth + 1) * step + folderTreeContentInset,
                        end: 8,
                        bottom: 8),
                    child: Row(children: [
                      for (var column = 0; column < row.columns!; column++) ...[
                        if (column > 0) const SizedBox(width: 8),
                        SizedBox.square(
                          dimension: row.coverSize! + 6,
                          child: row.first! + column < row.songs!.length
                              ? widget.songBuilder(
                                  context,
                                  node,
                                  row.songs![row.first! + column],
                                  row.first! + column,
                                  row.coverSize!)
                              : null,
                        ),
                      ],
                    ]),
                  ));
                },
              );
            }));
  }
}

enum _FolderTreeGroup { songs, subfolders }

class _VisibleFolderRow {
  const _VisibleFolderRow(this.node,
      {this.first,
      this.columns,
      this.coverSize,
      this.songs,
      this.group,
      this.loading = false});
  final FolderTreeNode node;
  final int? first, columns;
  final double? coverSize;
  final List<Audio>? songs;
  final _FolderTreeGroup? group;
  final bool loading;
  int get visualDepth =>
      node.depth + (first != null || group != null || loading ? 1 : 0);
  Key get key => loading
      ? ValueKey('folder-tree-loading-${node.id}')
      : group != null
          ? ValueKey(('folder-tree-group', node.id, group))
          : first == null
              ? ValueKey('folder-tree-row-${node.id}')
              : ValueKey(('folder-tree-songs', node.id, songs![first!].path));
}

/// Store one descriptor per folder/group, rather than materializing every
/// offscreen song row and reading its first song to construct a global key map.
class _FolderTreeRows {
  _FolderTreeRows(List<FolderTreeSection> sections, Set<String> expanded,
      Map<String, List<Audio>> sources, Set<String> sorting, double width,
      {_FolderTreeRows? previous}) {
    final depth = sections.fold<int>(
        1,
        (depth, section) =>
            math.max(depth, section.node.depth + (section.songs ? 1 : 0)));
    step = folderTreeIndentStep(width, depth);
    if (previous != null) _knownRows.addAll(previous._knownRows);
    void add(_VisibleFolderRow row, [int count = 1]) {
      if (count == 0) return;
      final block = _FolderTreeRowBlock(length, count, row);
      _blocks.add(block);
      if (row.first != null) {
        _songBlocks[row.node.id] = block;
      } else {
        _fixedIndices[row.key] = length;
      }
      length += count;
    }

    for (final section in sections) {
      final node = section.node;
      if (!section.songs) {
        add(_VisibleFolderRow(node));
        if (expanded.contains(node.id) &&
            node.folder.audios.isEmpty &&
            node.children.isNotEmpty) {
          add(_VisibleFolderRow(node, group: _FolderTreeGroup.subfolders));
        }
        continue;
      }
      add(_VisibleFolderRow(node, group: _FolderTreeGroup.songs));
      final coverSize = playlistTreeSongCoverSize(parentDepth: node.depth);
      songCacheExtent = math.max(songCacheExtent ?? 0, coverSize + 14);
      if (sorting.contains(node.id)) {
        add(_VisibleFolderRow(node, loading: true, coverSize: coverSize));
      } else {
        final available = math.max(
            1.0, width - (node.depth + 1) * step - folderTreeContentInset - 8);
        final columns =
            math.max(1, ((available + 8) / (coverSize + 14)).floor());
        final songs = sources[node.id] ?? const <Audio>[];
        add(
            _VisibleFolderRow(node,
                first: 0, columns: columns, coverSize: coverSize, songs: songs),
            (songs.length + columns - 1) ~/ columns);
      }
      if (node.children.isNotEmpty) {
        add(_VisibleFolderRow(node, group: _FolderTreeGroup.subfolders));
      }
    }
    _fixedIndices[const ValueKey('folder-tree-cache')] = length;
  }
  late final double step;
  double? songCacheExtent;
  int length = 0;
  final _blocks = <_FolderTreeRowBlock>[];
  final _songBlocks = <String, _FolderTreeRowBlock>{};
  final _fixedIndices = <Key, int>{};
  final _knownRows = <Key, _VisibleFolderRow>{};

  _VisibleFolderRow operator [](int index) {
    var low = 0, high = _blocks.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final block = _blocks[middle];
      if (index < block.start) {
        high = middle;
      } else if (index >= block.start + block.count) {
        low = middle + 1;
      } else {
        final row = block.row;
        return row.first == null
            ? row
            : _VisibleFolderRow(row.node,
                first: (index - block.start) * row.columns!,
                columns: row.columns,
                coverSize: row.coverSize,
                songs: row.songs);
      }
    }
    throw RangeError.index(index, _blocks);
  }

  void remember(Key key, _VisibleFolderRow row) {
    if (row.first == null) return;
    _knownRows.remove(key);
    _knownRows[key] = row;
    // Only mounted/recent rows need state retention, not every row ever visited.
    while (_knownRows.length > 1024) {
      _knownRows.remove(_knownRows.keys.first);
    }
  }

  int? indexOf(Key key) {
    if (_fixedIndices[key] case final index?) return index;
    final previous = _knownRows[key];
    if (previous == null) return null;
    final block = _songBlocks[previous.node.id];
    if (block == null) return null;
    final row = block.row;
    var first = previous.first!;
    if (!identical(row.songs, previous.songs)) {
      final sourcePath = previous.songs![first].path;
      first = block.indicesByPath[sourcePath] ?? -1;
    }
    if (first < 0 || first >= row.songs!.length || first % row.columns! != 0) {
      return null;
    }
    return block.start + first ~/ row.columns!;
  }
}

class _FolderTreeRowBlock {
  _FolderTreeRowBlock(this.start, this.count, this.row);
  final int start, count;
  final _VisibleFolderRow row;
  late final indicesByPath = <String, int>{
    for (var i = 0; i < row.songs!.length; i++) row.songs![i].path: i,
  };
}

/// Painted only in the bounded indentation gutter, like the playlist tree.
/// Each direct-song group uses its own parent's rail; ancestor rails continue
/// through nested groups without overlaying folder cards or song artwork.
class _FolderTreeLines extends CustomPainter {
  const _FolderTreeLines(
      {required this.depth,
      required this.step,
      required this.content,
      required this.last,
      required this.direction,
      required this.color});
  final int depth;
  final double step;
  final bool content, last;
  final TextDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth == 0) return;
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x(double start) =>
        direction == TextDirection.ltr ? start : size.width - start;
    for (var level = 0; level < depth; level++) {
      final rail = x((level + .5) * step);
      final end = level == depth - 1 && last ? size.height / 2 : size.height;
      canvas.drawLine(Offset(rail, 0), Offset(rail, end), pen);
    }
    canvas.drawLine(
        Offset(x((depth - .5) * step), size.height / 2),
        Offset(x(depth * step + (content ? folderTreeContentInset : 0)),
            size.height / 2),
        pen);
  }

  @override
  bool shouldRepaint(covariant _FolderTreeLines old) =>
      old.depth != depth ||
      old.step != step ||
      old.content != content ||
      old.last != last ||
      old.direction != direction ||
      old.color != color;
}
