import 'dart:async';
import 'package:dan_player/component/now_playing_bar_metrics.dart';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/adaptive_grid_drag.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playlist_cover.dart';
import 'package:dan_player/component/playlist_circle_tile.dart';
import 'package:dan_player/component/playlist_header.dart';
import 'package:dan_player/component/playlist_create_dialog.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/component/cue_import_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:dan_player/component/playlist_drag_data.dart';
import 'package:desktop_lyric/ui_language.dart';

typedef PlaylistTrackBuilder = Widget Function(
  BuildContext context,
  Audio audio,
  VoidCallback onPlay,
  Widget actions,
);

class PlaylistBrowser extends StatefulWidget {
  const PlaylistBrowser({
    super.key,
    this.initialPlaylist,
    this.tree,
    this.persist,
    this.onNavigate,
    this.onPlay,
    this.trackBuilder,
    this.library,
    this.pickImage,
    this.initialContentView = ContentView.list,
    this.onContentViewChanged,
    this.initialView,
    this.onViewChanged,
    this.onOpenAlbums,
    this.albumCount = 0,
  });

  final Playlist? initialPlaylist;
  final PlaylistTree? tree;
  final Future<void> Function()? persist;
  final void Function(Playlist?)? onNavigate;
  final void Function(int, List<Audio>)? onPlay;

  /// Pure tests replace only the song presentation, avoiding native artwork
  /// reads/BASS while exercising the real tree navigation and queue mapping.
  final PlaylistTrackBuilder? trackBuilder;
  final List<Audio>? library;
  final PlaylistImagePicker? pickImage;
  final ContentView initialContentView;
  final ValueChanged<ContentView>? onContentViewChanged;
  final PlaylistViewMode? initialView;
  final ValueChanged<PlaylistViewMode>? onViewChanged;
  final VoidCallback? onOpenAlbums;
  final int albumCount;

  @override
  State<PlaylistBrowser> createState() => _PlaylistBrowserState();
}

class _PlaylistBrowserState extends State<PlaylistBrowser> {
  late Playlist? _current = widget.initialPlaylist;
  bool _busy = false;
  String? _draggingId;
  PlaylistTree? _cachedTree;
  final _selectedEntries = <String>{};
  bool _selecting = false;
  late PlaylistViewMode _view = widget.initialView ??
      PlaylistViewMode.resolve(null, legacy: widget.initialContentView.name);
  final Map<String, String> _testSortModes = {};
  final _reorderController = PlaylistReorderController();
  final _warningScrollController = ScrollController();

  Map<String, String> get _sortModes => widget.tree == null
      ? AppPreference.instance.unifiedPlaylistSortModes
      : _testSortModes;

  String _sortKey(Playlist? parent) =>
      parent == null ? 'root' : 'playlist:${parent.id}';

  PlaylistSortMode _sortMode(Playlist? parent) {
    final saved = _sortModes[_sortKey(parent)];
    return PlaylistSortMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => PlaylistSortMode.custom,
    );
  }

  bool get _readBlocked => widget.tree == null && playlistsReadBlocked;
  bool get _editingBlocked => _busy || _readBlocked;

  PlaylistTree get _tree {
    if (widget.tree != null) return widget.tree!;
    if (_cachedTree == null || !identical(_cachedTree!.roots, PLAYLISTS)) {
      _cachedTree = playlistTree;
    }
    return _cachedTree!;
  }

  @override
  void didUpdateWidget(covariant PlaylistBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlaylist?.id != widget.initialPlaylist?.id) {
      _reorderController.cancel();
      _current = widget.initialPlaylist;
      _clearSelection();
    }
    if (oldWidget.initialView != widget.initialView ||
        oldWidget.initialContentView != widget.initialContentView) {
      _reorderController.cancel();
      _view = widget.initialView ??
          PlaylistViewMode.resolve(null,
              legacy: widget.initialContentView.name);
    }
  }

  @override
  void dispose() {
    _reorderController.dispose();
    _warningScrollController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    showTextOnSnackBar(text, context: context);
  }

  void _navigate(Playlist? playlist) {
    _reorderController.cancel();
    _clearSelection();
    final callback = widget.onNavigate;
    if (callback != null) {
      callback(playlist);
    } else {
      setState(() => _current = playlist);
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedEntries.clear();
      _selecting = false;
    });
  }

  bool _isSelected(_PlaylistRowData row) => _selectedEntries.contains(row.id);

  void _startSelection([_PlaylistRowData? row]) {
    _reorderController.cancel();
    setState(() {
      if (row != null) _selectedEntries.add(row.id);
      _selecting = true;
    });
  }

  void _toggleSelection(_PlaylistRowData row) {
    setState(() {
      if (!_selectedEntries.remove(row.id)) _selectedEntries.add(row.id);
    });
  }

  void _selectAll(List<_PlaylistRowData> rows) {
    setState(() => _selectedEntries.addAll(rows.map((row) => row.id)));
  }

  void _invertSelection(List<_PlaylistRowData> rows) {
    setState(() {
      for (final row in rows) {
        if (!_selectedEntries.remove(row.id)) _selectedEntries.add(row.id);
      }
    });
  }

  List<Audio> _selectedAudios(List<_PlaylistRowData> rows) => [
        for (final row in rows.where(_isSelected))
          if (row.audio != null)
            row.audio!
          else if (row.playlist != null)
            ..._orderedOccurrences(row.playlist!).map((entry) => entry.audio),
      ];

  Future<void> _importM3u() async {
    if (_editingBlocked) return;
    final imported = await importM3uPlaylist(context,
        library:
            List.of(widget.library ?? AudioLibrary.instance.audioCollection));
    if (imported == null || !mounted || _editingBlocked) return;
    Playlist? created;
    await _edit(() => created =
        _tree.createPlaylistFromAudios(imported.name, imported.audios));
    if (mounted && created != null) _navigate(created);
  }

  Future<void> _importCue() async {
    if (_editingBlocked) return;
    final imported = await importCuePlaylist(context,
        library:
            List.of(widget.library ?? AudioLibrary.instance.audioCollection));
    if (imported == null || !mounted || _editingBlocked) return;
    Playlist? created;
    await _edit(() => created =
        _tree.createPlaylistFromAudios(imported.name, imported.audios));
    if (mounted && created != null) _navigate(created);
  }

  Future<bool> _edit(VoidCallback mutation) async {
    if (_busy) return false;
    if (_readBlocked) {
      _message(ui("歌单读取尚未完成，请先修复数据文件并重新读取；原文件没有改动。"));
      return false;
    }
    try {
      mutation();
    } catch (error) {
      _message(ui("无法更改歌单：{0}", [error]));
      return false;
    }
    try {
      // Publish the already-applied order once. Writes are snapshot-queued by
      // storage, so a slow disk must not disable every handle/button or make
      // a second drag lose its input while the preceding save finishes.
      await savePlaylistUiChanges(persist: widget.persist);
      return true;
    } catch (error) {
      if (playlistUiSaveError.value != null) {
        _message(ui("更改已保留在当前会话，但保存失败；可在页面上重试。"));
      }
      return false;
    }
  }

  Future<void> _retrySave() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await savePlaylistUiChanges(persist: widget.persist);
    } catch (error) {
      _message(ui("保存仍未成功：{0}", [error]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(Playlist? parent) async {
    final details = await showAppDialog<NewPlaylistDetails>(
      context: context,
      builder: (_) => PlaylistCreateDialog(
        title: parent == null ? ui("新建歌单") : ui("新建子歌单"),
        library: widget.library,
        pickImage: widget.pickImage,
      ),
    );
    if (details == null || !mounted) return;
    await _edit(() {
      final playlist = _tree.createPlaylist(details.name,
          parent: parent, imagePath: details.imagePath);
      _tree.addAudios(playlist, details.audios);
    });
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await showPlaylistNameDialog(
      context,
      title: ui("重命名歌单"),
      initialName: playlist.name,
      confirmLabel: ui("保存"),
    );
    if (name == null || !mounted) return;
    await _edit(() => _tree.rename(playlist, name));
  }

  Future<void> _addSongs(Playlist playlist) async {
    final selected = await showPlaylistSongPicker(
      context,
      existingPaths: {
        for (final entry in playlist.entries)
          if (entry.audio != null) entry.audio!.path,
      },
      library: widget.library,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _edit(() => _tree.addAudios(playlist, selected));
  }

  Future<void> _editSongs(Playlist playlist) async {
    final selected = await showPlaylistSongPicker(
      context,
      existingPaths: const {},
      selectedAudios: [
        for (final entry in playlist.entries)
          if (entry.audio != null) entry.audio!,
      ],
      replaceSelection: true,
      library: widget.library,
    );
    if (selected == null || !mounted) return;
    await _edit(() => _tree.setDirectAudios(playlist, selected));
  }

  Future<void> _changeCover(Playlist playlist) async {
    try {
      final path = await (widget.pickImage ?? pickPlaylistImage)();
      if (!mounted || path == null) return;
      await _edit(() => _tree.setImagePath(playlist, path));
    } catch (error) {
      _message(ui("无法选择歌单封面：{0}", [error]));
    }
  }

  void _play(List<Audio> queue, [int index = 0]) {
    if (queue.isEmpty || index < 0 || index >= queue.length) {
      _message(ui("这个歌单还没有可播放的歌曲。"));
      return;
    }
    final snapshot = List<Audio>.unmodifiable(queue);
    final callback = widget.onPlay;
    if (callback != null) {
      callback(index, snapshot);
    } else {
      PlayService.instance.playbackService.play(index, snapshot);
    }
  }

  Future<void> _remove(_PlaylistRowData row, Playlist? parent) async {
    final folder = row.playlist;
    final descendants = folder == null
        ? 0
        : _tree.allPlaylists
            .where((item) =>
                item.id != folder.id &&
                item.pathFromRoot.any((ancestor) => ancestor.id == folder.id))
            .length;
    final songs = folder?.flattenAudios().length ?? 1;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppDialogTitle(folder == null ? ui("移除歌曲引用？") : ui("删除歌单？")),
        content: Text(folder == null
            ? ui("仅从当前歌单移除“{0}”。不会删除磁盘音乐或总乐库中的歌曲。", [row.label])
            : ui("删除“{0}”及其 {1} 个子歌单、{2} 个歌曲引用？\n\n不会删除磁盘音乐或总乐库中的歌曲。",
                [row.label, descendants, songs])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(ui("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(folder == null ? ui("移除") : ui("删除歌单")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _edit(() => _tree.removeEntry(parent: parent, entryId: row.id));
  }

  Future<void> _removeSelected(Playlist? parent) async {
    final selected = _rows(parent).where(_isSelected).toList(growable: false);
    if (selected.isEmpty || _editingBlocked) return;
    final folders = selected.where((row) => row.playlist != null).length;
    final songReferences = selected.fold<int>(
      0,
      (count, row) => count + (row.playlist?.flattenAudios().length ?? 1),
    );
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppDialogTitle(ui("移除所选项目？")),
        content: Text(ui(
            "移除所选 {0} 个项目，其中包含 {1} 个歌单及其全部子歌单、{2} 个歌曲引用。\n\n不会删除磁盘音乐或总乐库中的歌曲。",
            [selected.length, folders, songReferences])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(ui("取消")),
          ),
          FilledButton(
            key: const ValueKey('playlist-confirm-remove-selected'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(ui("移除所选")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _edit(() {
      _tree.removeEntries(
        parent: parent,
        entryIds: selected.map((row) => row.id),
      );
      _clearSelection();
    });
  }

  Future<void> _chooseDestination(
      _PlaylistRowData row, Playlist? sourceParent) async {
    final destination = await showPlaylistDestinationDialog(
      context,
      tree: _tree,
      title: ui("将“{0}”移动到", [row.label]),
      allowRoot: row.playlist != null,
      disabledReason: (target) => _tree.moveError(
        sourceParent: sourceParent,
        entryId: row.id,
        targetParent: target,
      ),
    );
    if (destination == null || !mounted) return;
    await _move(
      PlaylistDragData(
        entryId: row.id,
        sourceParent: sourceParent,
        label: row.label,
      ),
      destination.playlist,
    );
  }

  Future<void> _move(PlaylistDragData data, Playlist? target,
      {int? index}) async {
    await _edit(() => _tree.moveEntry(
          sourceParent: data.sourceParent,
          entryId: data.entryId,
          targetParent: target,
          index: index,
        ));
  }

  Future<void> _nudge(_PlaylistRowData row, Playlist? parent, int index) async {
    if (_sortMode(parent) != PlaylistSortMode.custom) return;
    await _move(
      PlaylistDragData(
        entryId: row.id,
        sourceParent: parent,
        label: row.label,
      ),
      parent,
      index: index,
    );
  }

  List<_PlaylistRowData> _customRows(Playlist? parent) => parent == null
      ? [
          for (final root in _tree.allPlaylists)
            if (root.parent == null)
              _PlaylistRowData(id: root.id, playlist: root),
        ]
      : [
          for (final entry in parent.entries)
            _PlaylistRowData(
              id: entry.id,
              audio: entry.audio,
              playlist: entry.childPlaylist,
            ),
        ];

  List<_PlaylistRowData> _rows(Playlist? parent) {
    final sorted = _customRows(parent);
    final method = _sortMode(parent);
    if (method == PlaylistSortMode.custom) return sorted;
    final positions = {
      for (var index = 0; index < sorted.length; index++)
        sorted[index].id: index,
    };
    final field = method.audioField;
    final direction = method.direction!;
    sorted.sort((a, b) {
      // Display ordering never mutates the tree's mixed song/folder order.
      // Folders without a song-specific tag are unknown, not fake artists or
      // albums; unknowns stay last in either direction and ties remain stable.
      final result = switch (field) {
        AudioSortField.name =>
          compareSortText(a.label, b.label, direction: direction),
        AudioSortField.added => compareSortNumbers(
            a.createdAt > 0 ? a.createdAt : null,
            b.createdAt > 0 ? b.createdAt : null,
            direction: direction,
          ),
        AudioSortField.modified => compareSortNumbers(
            a.modifiedAt > 0 ? a.modifiedAt : null,
            b.modifiedAt > 0 ? b.modifiedAt : null,
            direction: direction,
          ),
        null =>
          compareSortNumbers(a.songCount, b.songCount, direction: direction),
        _ => compareAudioSort(a.audio, b.audio, field, direction: direction),
      };
      return result == 0
          ? positions[a.id]!.compareTo(positions[b.id]!)
          : result;
    });
    return sorted;
  }

  void _sort(Playlist? parent, PlaylistSortMode method) {
    _reorderController.cancel();
    setState(() => _sortModes[_sortKey(parent)] = method.name);
  }

  List<PlaylistAudioOccurrence> _orderedOccurrences(Playlist? parent) {
    final result = <PlaylistAudioOccurrence>[];
    final visited = <String>{};
    void append(Playlist? level, int depth) {
      if (depth > PlaylistTree.maxDepth ||
          (level != null && !visited.add(level.id))) {
        throw FormatException(ui("歌单关系包含循环或超过最大层数"));
      }
      for (final row in _rows(level)) {
        if (row.audio != null && level != null) {
          result.add(PlaylistAudioOccurrence(
              entryId: row.id, audio: row.audio!, playlist: level));
        } else if (row.playlist != null) {
          append(row.playlist, depth + 1);
        }
      }
    }

    append(parent, 0);
    return result;
  }

  List<Widget> _menuItems(
      _PlaylistRowData row, Playlist? parent, int index, int count) {
    final folder = row.playlist;
    final canMoveOut =
        parent != null && (parent.parent != null || folder != null);
    return [
      if (folder != null) ...[
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_open),
          onPressed: () => _navigate(folder),
          child: Text(ui("打开歌单")),
        ),
        MenuItemButton(
          leadingIcon: const AppActionIcon(AppActionGlyph.play, size: 20),
          onPressed: () => _play(
              _orderedOccurrences(folder).map((entry) => entry.audio).toList()),
          child: Text(ui("播放歌单（含子歌单）")),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder_outlined),
          onPressed: _editingBlocked ? null : () => _create(folder),
          child: Text(ui("新建子歌单")),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: _editingBlocked ? null : () => _rename(folder),
          child: Text(ui("重命名")),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.playlist_add_check),
          onPressed: _editingBlocked ? null : () => _editSongs(folder),
          child: Text(ui("更改所选歌曲")),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.image_outlined),
          onPressed: _editingBlocked ? null : () => _changeCover(folder),
          child: Text(ui("更改歌单封面")),
        ),
        if (folder.imagePath != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.hide_image_outlined),
            onPressed: _editingBlocked
                ? null
                : () => _edit(() => _tree.setImagePath(folder, null)),
            child: Text(ui("恢复默认封面")),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.checklist),
          onPressed: _editingBlocked ? null : () => _startSelection(row),
          child: Text(ui("多选")),
        ),
      ],
      MenuItemButton(
        leadingIcon: const Icon(Icons.arrow_upward),
        onPressed: _editingBlocked ||
                _sortMode(parent) != PlaylistSortMode.custom ||
                index == 0
            ? null
            : () => _nudge(row, parent, index - 1),
        child: Text(ui("上移（Alt + ↑）")),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.arrow_downward),
        onPressed: _editingBlocked ||
                _sortMode(parent) != PlaylistSortMode.custom ||
                index >= count - 1
            ? null
            : () => _nudge(row, parent, index + 1),
        child: Text(ui("下移（Alt + ↓）")),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.drive_file_move_outline),
        onPressed:
            _editingBlocked ? null : () => _chooseDestination(row, parent),
        child: Text(ui("移动到…")),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
        onPressed: _editingBlocked || !canMoveOut
            ? null
            : () => _move(
                  PlaylistDragData(
                    entryId: row.id,
                    sourceParent: parent,
                    label: row.label,
                  ),
                  parent.parent,
                ),
        child: Text(ui("移到上一级")),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.delete_outline),
        onPressed: _editingBlocked ? null : () => _remove(row, parent),
        child: Text(folder == null ? ui("从当前歌单移除") : ui("删除歌单…")),
      ),
    ];
  }

  int _dropIndex(PlaylistDragData data, Playlist? parent,
      List<_PlaylistRowData> rows, int slot) {
    if (data.sourceParent?.id != parent?.id) return slot;
    final oldIndex = rows.indexWhere((row) => row.id == data.entryId);
    return oldIndex >= 0 && oldIndex < slot ? slot - 1 : slot;
  }

  Widget _dropGap(Playlist? parent, List<_PlaylistRowData> rows, int slot,
      {bool grid = false}) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<PlaylistDragData>(
      key: ValueKey('playlist-drop-slot-${parent?.id ?? 'root'}-$slot'),
      onWillAcceptWithDetails: (details) =>
          !_editingBlocked &&
          !_selecting &&
          _tree.moveError(
                sourceParent: details.data.sourceParent,
                entryId: details.data.entryId,
                targetParent: parent,
                index: _dropIndex(details.data, parent, rows, slot),
              ) ==
              null,
      onAcceptWithDetails: (details) => unawaited(_move(
        details.data,
        parent,
        index: _dropIndex(details.data, parent, rows, slot),
      )),
      builder: (context, candidates, rejected) {
        final color = candidates.isNotEmpty
            ? scheme.primary
            : rejected.isNotEmpty
                ? scheme.error
                : Colors.transparent;
        if (grid) {
          return SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppShape.smallRadius,
                  ),
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: 10,
          child: Center(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppShape.smallRadius,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _folderTarget({
    required Playlist? target,
    required Widget child,
    required String targetKey,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PlaylistReorderDropZone(
      controller: _reorderController,
      id: targetKey,
      canDrop: (data) =>
          !_editingBlocked &&
          !_selecting &&
          _tree.moveError(
                sourceParent: data.sourceParent,
                entryId: data.entryId,
                targetParent: target,
              ) ==
              null,
      rejectionReason: (data) => _tree.moveError(
        sourceParent: data.sourceParent,
        entryId: data.entryId,
        targetParent: target,
      ),
      onDrop: (data) => unawaited(_move(data, target)),
      child: DragTarget<PlaylistDragData>(
        key: ValueKey(targetKey),
        onWillAcceptWithDetails: (details) =>
            !_editingBlocked &&
            !_selecting &&
            _tree.moveError(
                  sourceParent: details.data.sourceParent,
                  entryId: details.data.entryId,
                  targetParent: target,
                ) ==
                null,
        onAcceptWithDetails: (details) =>
            unawaited(_move(details.data, target)),
        builder: (context, candidates, rejected) {
          final rejectedData =
              rejected.whereType<PlaylistDragData>().firstOrNull;
          final reason = rejectedData == null
              ? null
              : _tree.moveError(
                  sourceParent: rejectedData.sourceParent,
                  entryId: rejectedData.entryId,
                  targetParent: target,
                );
          final active = candidates.isNotEmpty || rejected.isNotEmpty;
          return Material(
            animationDuration: Duration.zero,
            color: candidates.isNotEmpty
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : rejected.isNotEmpty
                    ? scheme.errorContainer.withValues(alpha: 0.5)
                    : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: AppShape.controlRadius,
              side: BorderSide(
                color: active
                    ? rejected.isNotEmpty
                        ? scheme.error
                        : scheme.primary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                child,
                if (active)
                  Positioned(
                    right: 4,
                    bottom: 0,
                    left: 4,
                    child: IgnorePointer(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          reason ??
                              (candidates.isNotEmpty ? ui("松开移入") : ui("不能移入")),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                reason == null ? scheme.primary : scheme.error,
                            backgroundColor: scheme.surface,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dragHandle(
      _PlaylistRowData row, Playlist? parent, int index, Widget menuButton) {
    if (_selecting || _sortMode(parent) != PlaylistSortMode.custom) {
      return menuButton;
    }
    if (_view == PlaylistViewMode.list) {
      return PlaylistReorderHandle(
        key: ValueKey('playlist-drag-${row.id}'),
        controller: _reorderController,
        index: index,
        enabled: !_editingBlocked,
        child: menuButton,
      );
    }
    return _freeGridDragSource(
      key: ValueKey('playlist-drag-${row.id}'),
      row: row,
      parent: parent,
      child: menuButton,
    );
  }

  Widget _gridIdentityDragSource(
      _PlaylistRowData row, Playlist? parent, Widget child) {
    if (_selecting ||
        _editingBlocked ||
        _sortMode(parent) != PlaylistSortMode.custom ||
        _view == PlaylistViewMode.list) {
      return child;
    }
    return _freeGridDragSource(
      key: ValueKey('playlist-card-drag-${row.id}'),
      row: row,
      parent: parent,
      child: child,
    );
  }

  Widget _freeGridDragSource({
    required Key key,
    required _PlaylistRowData row,
    required Playlist? parent,
    required Widget child,
  }) =>
      Builder(
        builder: (context) => AdaptiveGridDragSource<PlaylistDragData>(
          dragKey: key,
          data: PlaylistDragData(
            entryId: row.id,
            sourceParent: parent,
            label: row.label,
          ),
          maxSimultaneousDrags: _editingBlocked ? 0 : 1,
          onDragStarted: () {
            Focus.of(context).requestFocus();
            setState(() => _draggingId = row.id);
          },
          onDragEnd: (_) {
            if (mounted) setState(() => _draggingId = null);
          },
          feedback: Material(
            elevation: 8,
            shape: AppShape.surface,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        row.playlist == null ? Icons.music_note : Icons.folder),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(row.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: child,
          ),
        ),
      );

  Widget _row(Playlist? parent, _PlaylistRowData row, int index, int count,
      List<Audio> queue, Map<String, int> queueIndices,
      {PlaylistCircleGeometry? circleGeometry}) {
    final scheme = Theme.of(context).colorScheme;
    final folder = row.playlist;
    final folderSongCount = folder?.flattenAudios().length ?? 0;
    final compact = UiLayoutScope.of(context).compactPlaylists;
    final menuItems = _menuItems(row, parent, index, count);
    return AppEntrance(
      key: ValueKey(('playlist-entry', row.id)),
      identity: ('playlist-entry', row.id),
      order: index,
      child: MenuAnchor(
        useRootOverlay: true,
        menuChildren: menuItems,
        builder: (context, controller, _) {
          final menuButton = AppIconActionButton(
            key: ValueKey('playlist-menu-${row.id}'),
            tooltip: _sortMode(parent) == PlaylistSortMode.custom && !_selecting
                ? ui("拖动排序 · 点按打开菜单")
                : ui("歌单项目操作（切到自定义可拖动）"),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            selected: controller.isOpen,
            glyph: AppActionGlyph.moreVertical,
          );
          final rowAction = _dragHandle(row, parent, index, menuButton);
          final audio = row.audio;
          final queueIndex = queueIndices[row.id] ?? -1;
          Widget wrapGridIdentity(Widget child) {
            final draggable = _gridIdentityDragSource(row, parent, child);
            return folder == null
                ? draggable
                : _folderTarget(
                    target: folder,
                    targetKey: 'playlist-drop-folder-${folder.id}',
                    child: draggable,
                  );
          }

          final Widget content;
          if (_view == PlaylistViewMode.circular) {
            final details = folder == null
                ? '${audio?.artist ?? ''}\n${audio?.album ?? ''}'
                : [
                    ui("{0} 个直接项目 · {1} 首歌曲（含子歌单）",
                        [folder.entries.length, folderSongCount]),
                    if (folder.modifiedAt > 0)
                      ui('更新于 {0}', [
                        DateTime.fromMillisecondsSinceEpoch(folder.modifiedAt)
                            .toIso8601String()
                            .substring(0, 10)
                      ]),
                  ].join('\n');
            void play() {
              if (folder != null) {
                _play(_orderedOccurrences(folder)
                    .map((entry) => entry.audio)
                    .toList());
              } else if (audio != null && queueIndex >= 0) {
                _play(queue, queueIndex);
              }
            }

            content = InkWell(
              key: ValueKey('playlist-circle-open-${row.id}'),
              borderRadius: AppShape.controlRadius,
              onTap: () => _selecting
                  ? _toggleSelection(row)
                  : folder != null
                      ? _navigate(folder)
                      : play(),
              onSecondaryTapDown: (details) =>
                  controller.open(position: details.localPosition),
              onLongPress: () => controller.open(),
              child: PlaylistCircleTile(
                key: ValueKey('playlist-circle-${row.id}'),
                entryId: row.id,
                title: row.label,
                details: details,
                geometry: circleGeometry!,
                artworkBuilder: (size) => folder != null
                    ? PlaylistCover(
                        playlist: folder,
                        size: size,
                        loadSongArtwork: widget.trackBuilder == null,
                      )
                    : AudioArtwork(
                        audio: audio!,
                        size: size,
                        loadArtwork: widget.trackBuilder == null
                            ? null
                            : (_, __) async => null,
                        placeholder: ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                                child: Icon(Icons.music_note,
                                    size: size * .45, color: scheme.primary)))),
                contentWrapper: wrapGridIdentity,
                actions:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppIconActionButton(
                    key: ValueKey('playlist-play-${row.id}'),
                    tooltip: folder == null ? ui('播放歌曲') : ui("播放此歌单（含子歌单）"),
                    onPressed: _selecting ||
                            (folder == null
                                ? queueIndex < 0
                                : folderSongCount == 0)
                        ? null
                        : play,
                    glyph: AppActionGlyph.play,
                  ),
                  rowAction,
                ]),
              ),
            );
          } else if (audio != null && queueIndex >= 0) {
            final track = widget.trackBuilder?.call(
                    context,
                    audio,
                    () => _selecting
                        ? _toggleSelection(row)
                        : _play(queue, queueIndex),
                    rowAction) ??
                AudioTile(
                  key: ValueKey('playlist-audio-${row.id}'),
                  audioIndex: queueIndex,
                  playlist: queue,
                  action: rowAction,
                  selection: AudioTileSelection(
                    enabled: _selecting,
                    selected: _isSelected(row),
                    onToggle: () => _toggleSelection(row),
                    onStart: () => _startSelection(row),
                  ),
                  additionalMenuItems: menuItems,
                );
            content = _view == PlaylistViewMode.grid
                ? widget.trackBuilder != null
                    ? wrapGridIdentity(track)
                    : MusicGridReorderScope(
                        dragSourceBuilder: (_, __, ___, child) =>
                            wrapGridIdentity(child),
                        child: track,
                      )
                : track;
          } else {
            content = InkWell(
              key: ValueKey('playlist-open-${row.id}'),
              borderRadius: AppShape.controlRadius,
              onTap: folder == null
                  ? null
                  : () =>
                      _selecting ? _toggleSelection(row) : _navigate(folder),
              onSecondaryTapDown: (details) =>
                  controller.open(position: details.localPosition),
              onLongPress: () => controller.open(),
              child: _view == PlaylistViewMode.grid
                  ? MusicGridTileBody(
                      title: row.label,
                      tooltip: folder == null
                          ? row.label
                          : ui("{0} · {1} 首歌曲（含子歌单）",
                              [row.label, folderSongCount]),
                      artwork: folder == null
                          ? const Icon(Icons.music_note_outlined)
                          : PlaylistCover(
                              playlist: folder,
                              loadSongArtwork: widget.trackBuilder == null,
                            ),
                      contentWrapper: wrapGridIdentity,
                      action: rowAction,
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: compact ? 6 : 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: folder == null
                                ? Text(row.label)
                                : _folderTarget(
                                    target: folder,
                                    targetKey:
                                        'playlist-drop-folder-${folder.id}',
                                    child: Row(
                                      children: [
                                        PlaylistCover(
                                          playlist: folder,
                                          loadSongArtwork:
                                              widget.trackBuilder == null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(row.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                              Text(
                                                ui(
                                                    "{0} 个直接项目 · {1} 首歌曲（含子歌单）",
                                                    [
                                                      folder.entries.length,
                                                      folderSongCount
                                                    ]),
                                                maxLines: compact ? 1 : 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          AppIconActionButton(
                            key: ValueKey('playlist-play-${row.id}'),
                            tooltip: ui("播放此歌单（含子歌单）"),
                            onPressed: folder == null ||
                                    _selecting ||
                                    folderSongCount == 0
                                ? null
                                : () => _play(_orderedOccurrences(folder)
                                    .map((entry) => entry.audio)
                                    .toList()),
                            glyph: AppActionGlyph.play,
                          ),
                          rowAction,
                        ],
                      ),
                    ),
            );
          }
          final line = Focus(
            key: ValueKey('playlist-focus-${row.id}'),
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent || _editingBlocked) {
                return KeyEventResult.ignored;
              }
              final keyboard = HardwareKeyboard.instance;
              if (_selecting && event.logicalKey == LogicalKeyboardKey.escape) {
                _clearSelection();
                return KeyEventResult.handled;
              }
              if (_selecting && event.logicalKey == LogicalKeyboardKey.delete) {
                unawaited(_removeSelected(parent));
                return KeyEventResult.handled;
              }
              if (keyboard.isAltPressed &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (index > 0) {
                  unawaited(_nudge(row, parent, index - 1));
                }
                return KeyEventResult.handled;
              }
              if (keyboard.isAltPressed &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (index < count - 1) {
                  unawaited(_nudge(row, parent, index + 1));
                }
                return KeyEventResult.handled;
              }
              if ((keyboard.isShiftPressed &&
                      event.logicalKey == LogicalKeyboardKey.f10) ||
                  event.logicalKey == LogicalKeyboardKey.contextMenu) {
                controller.open();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.f2 && folder != null) {
                unawaited(_rename(folder));
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.delete) {
                unawaited(_remove(row, parent));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Material(
              animationDuration: Duration.zero,
              color: _selecting && _isSelected(row)
                  ? scheme.secondaryContainer.withValues(alpha: 0.4)
                  : _draggingId == row.id
                      ? scheme.primaryContainer.withValues(alpha: 0.2)
                      : compact && folder != null
                          ? scheme.surfaceContainerLow
                          : Colors.transparent,
              borderRadius: AppShape.controlRadius,
              child: Row(
                children: [
                  if (_selecting)
                    Checkbox(
                      key: ValueKey('playlist-select-${row.id}'),
                      value: _isSelected(row),
                      onChanged:
                          _editingBlocked ? null : (_) => _toggleSelection(row),
                      semanticLabel: ui("选择{0}", [row.label]),
                    ),
                  Expanded(child: content),
                ],
              ),
            ),
          );
          return compact && folder != null && _view == PlaylistViewMode.list
              ? Padding(padding: const EdgeInsets.only(bottom: 4), child: line)
              : line;
        },
      ),
    );
  }

  Widget _breadcrumbs(Playlist? current) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _folderTarget(
              target: null,
              targetKey: 'playlist-breadcrumb-drop-root',
              child: TextButton.icon(
                key: const ValueKey('playlist-breadcrumb-root'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onPressed: current == null ? null : () => _navigate(null),
                icon: const Icon(Icons.library_music_outlined),
                label: Text(ui("全部歌单")),
              ),
            ),
            if (current != null)
              for (final ancestor in current.pathFromRoot) ...[
                const Icon(Icons.chevron_right, size: 18),
                _folderTarget(
                  target: ancestor,
                  targetKey: 'playlist-breadcrumb-drop-${ancestor.id}',
                  child: Tooltip(
                    message: ancestor.name,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton(
                        key: ValueKey('playlist-breadcrumb-${ancestor.id}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          visualDensity: VisualDensity.standard,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                        onPressed: ancestor.id == current.id
                            ? null
                            : () => _navigate(ancestor),
                        child: Text(ancestor.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ),
              ],
          ],
        ),
      );

  Widget _headerActions(Playlist? current, List<_PlaylistRowData> rows,
          int selectedCount, List<Audio> queue) =>
      PlaylistToolbar(
        alignment: current == null ? WrapAlignment.end : WrapAlignment.start,
        isRoot: current == null,
        selecting: _selecting,
        selectedCount: selectedCount,
        hasItems: rows.isNotEmpty,
        canPlay: queue.isNotEmpty,
        editingEnabled: !_editingBlocked,
        sortMode: _sortMode(current),
        view: _view,
        onCreate: () => unawaited(_create(current)),
        onImportM3u: _importM3u,
        onImportCue: _importCue,
        onOpenSmartPlaylists: () => unawaited(showSmartPlaylists(context,
            library: () =>
                widget.library ?? AudioLibrary.instance.audioCollection,
            libraryChanges: AudioLibrary.changes)),
        onExportM3u: current == null
            ? null
            : () => unawaited(
                exportM3uPlaylist(context, List.of(queue), name: current.name)),
        selectionTools: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                  key: const ValueKey('playlist-play-selected'),
                  onPressed: selectedCount > 0
                      ? () => _play(_selectedAudios(rows))
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(ui('播放所选'))),
              AudioSelectionMenu(
                  selected: _selectedAudios(rows),
                  onInvert: () => _invertSelection(rows),
                  onExport: (audios) => exportM3uPlaylist(context, audios,
                      name: current?.name ?? 'Dan Player')),
            ]),
        onAddSongs:
            current == null ? null : () => unawaited(_addSongs(current)),
        onStartSelection: _startSelection,
        onEndSelection: _clearSelection,
        onSelectAll: () => _selectAll(rows),
        onRemoveSelected: () => unawaited(_removeSelected(current)),
        onSortChanged: (mode) => _sort(current, mode),
        onViewChanged: (view) {
          if (_view == view) return;
          _reorderController.cancel();
          setState(() => _view = view);
          widget.onViewChanged?.call(view);
          if (view != PlaylistViewMode.circular) {
            widget.onContentViewChanged?.call(view == PlaylistViewMode.list
                ? ContentView.list
                : ContentView.table);
          }
        },
        onRename: current == null ? null : () => unawaited(_rename(current)),
        onEditSongs:
            current == null ? null : () => unawaited(_editSongs(current)),
        onChangeCover:
            current == null ? null : () => unawaited(_changeCover(current)),
        onResetCover: current?.imagePath == null
            ? null
            : () => unawaited(_edit(() => _tree.setImagePath(current!, null))),
        onOpenAlbums: current == null ? widget.onOpenAlbums : null,
        albumCount: widget.albumCount,
        onHelp: _showHelp,
      );

  void _showHelp() {
    showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppDialogTitle(ui("歌单操作")),
        content: SingleChildScrollView(
          child: Text(
            ui("自定义排序：拖动歌曲或子歌单右侧的三个点，其他行会连续让位；点按三个点、右键或长按行可打开菜单。\n\n拖到子歌单的封面/名称区域并稍作停留，高亮后松开即可移入；也可通过菜单“移动到…”选择目标。\n\n名称等排序仅改变显示和播放次序，不覆盖自定义顺序；切回“自定义”即可继续拖动。\n\n顺序播放会按各层次序进入子歌单，播完再返回父歌单。Alt + ↑ / ↓ 可在自定义模式调序，Shift + F10 打开菜单。"),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ui("知道了")),
          ),
        ],
      ),
    );
  }

  Future<void> _retryStorageRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await readPlaylists();
      if (!playlistsReadBlocked) playlistUiSaveError.value = null;
      playlistUiRevision.value++;
      if (playlistStorageWarning == null) _message(ui("歌单已重新读取"));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _storageWarning() => ValueListenableBuilder<bool>(
        valueListenable: playlistUiSaving,
        builder: (context, saving, _) => _storageWarningContent(saving),
      );

  Widget _storageWarningContent(bool saving) {
    final warning = widget.tree == null ? playlistStorageWarning : null;
    // A normal queued write has a pending snapshot too. It is not a read/save
    // failure and must not flash an error banner during every successful drag.
    // The dedicated save-error banner owns explicit UI write failures.
    if (warning == null ||
        (!_readBlocked && (saving || playlistUiSaveError.value != null))) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      shape: AppShape.control,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(warning, maxLines: 4, overflow: TextOverflow.ellipsis),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('playlist-retry-storage'),
                onPressed: _busy
                    ? null
                    : playlistsHaveUnsavedChanges
                        ? _retrySave
                        : _retryStorageRead,
                icon: const Icon(Icons.refresh),
                label:
                    Text(playlistsHaveUnsavedChanges ? ui("重试保存") : ui("重新读取")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveWarning() => ValueListenableBuilder<String?>(
        valueListenable: playlistUiSaveError,
        builder: (context, error, _) => error == null || _readBlocked
            ? const SizedBox.shrink()
            : AppEntrance(
                identity: 'playlist-save-warning',
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  shape: AppShape.control,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(ui("歌单更改尚未保存；当前会话仍保留更改。\n{0}", [error]),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const ValueKey('playlist-retry-save'),
                            onPressed: _busy ? null : _retrySave,
                            icon: const Icon(Icons.refresh),
                            label: Text(ui("重试保存")),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );

  Widget _warningsViewport(BuildContext context, double availableHeight) =>
      ConstrainedBox(
        // The page's identity header has its own bounded viewport. Even when
        // it reaches that limit, an I/O failure must not consume the remaining
        // song list: long warnings and their retry controls scroll locally.
        key: const ValueKey('playlist-warning-viewport'),
        constraints: BoxConstraints(maxHeight: availableHeight * .4),
        child: Scrollbar(
          controller: _warningScrollController,
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey('playlist-warning-scroll'),
              controller: _warningScrollController,
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_saveWarning(), _storageWarning()],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<int>(
      valueListenable: playlistUiRevision,
      builder: (context, _, __) {
        final current =
            _current == null ? null : _tree.findPlaylist(_current!.id);
        final rows = _rows(current);
        final selectedCount = rows.where(_isSelected).length;
        final occurrences = _orderedOccurrences(current);
        final queue = [for (final item in occurrences) item.audio];
        final circleGeometry = _view == PlaylistViewMode.circular
            ? PlaylistCircleGeometry.measure(context)
            : null;
        final indices = {
          for (var i = 0; i < occurrences.length; i++)
            occurrences[i].entryId: i,
        };
        final gridChildIndices = _view != PlaylistViewMode.list
            ? <Key, int>{
                for (var i = 0; i < rows.length; i++)
                  ValueKey(('playlist-grid-entry', rows[i].id)): i,
                ValueKey(
                        'playlist-drop-slot-${current?.id ?? 'root'}-${rows.length}'):
                    rows.length,
              }
            : const <Key, int>{};
        final subtitle = current == null
            ? ui("{0} 个顶层歌单 · {1} 首歌曲引用", [rows.length, queue.length])
            : ui("{0} 个直接项目 · {1} 首歌曲（含子歌单）", [rows.length, queue.length]);
        final headerActions =
            _headerActions(current, rows, selectedCount, queue);
        return PageScaffold(
          title: current?.name ?? ui("歌单"),
          subtitle: subtitle,
          actions: const [],
          responsiveActions: current == null ? headerActions : null,
          headerPadding: current == null
              ? EdgeInsets.all(
                  UiLayoutScope.of(context).compactPlaylists ? 8 : 16)
              : EdgeInsets.fromLTRB(
                  8, 0, 8, UiLayoutScope.of(context).compactPlaylists ? 8 : 12),
          header: current == null
              ? null
              : PlaylistHeader(
                  compact: UiLayoutScope.of(context).compactPlaylists,
                  key: ValueKey(('playlist-header', current.id)),
                  title: current.name,
                  subtitle: subtitle,
                  coverBuilder: (size) => PlaylistCover(
                    playlist: current,
                    size: size,
                    loadSongArtwork: widget.trackBuilder == null,
                  ),
                  breadcrumbs: _breadcrumbs(current),
                  actions: headerActions,
                ),
          body: LayoutBuilder(
            builder: (context, constraints) => Column(
              key: const ValueKey('playlist-browser-body'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _warningsViewport(context, constraints.maxHeight),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: rows.isEmpty
                        ? _folderTarget(
                            target: current,
                            targetKey: 'playlist-empty-drop',
                            child: SizedBox.expand(
                              child: Center(
                                child: AppEntrance(
                                  identity: 'playlist-empty',
                                  order: 2,
                                  child: Text(ui("这里还没有项目。可以新建子歌单、添加歌曲或拖入歌单。")),
                                ),
                              ),
                            ),
                          )
                        : _view != PlaylistViewMode.list
                            ? MusicGridScope(
                                child: AppContentScrollbar(
                                  key: ValueKey((
                                    'playlist-grid-scroll',
                                    current?.id,
                                    _view
                                  )),
                                  builder: (context, controller) =>
                                      GridEdgeAutoScrollRegion(
                                    controller: controller,
                                    child: GridView.builder(
                                      controller: controller,
                                      key: PageStorageKey(
                                          'playlist-${_view.name}-${current?.id ?? 'root'}'),
                                      padding: EdgeInsets.only(
                                          bottom: NowPlayingBarMetrics
                                              .reservedSpace(context)),
                                      gridDelegate:
                                          _view == PlaylistViewMode.circular
                                              ? CompactMusicGridDelegate(
                                                  mainAxisExtent:
                                                      circleGeometry!.extent,
                                                  minimumTileWidth:
                                                      PlaylistCircleTile
                                                          .minimumWidth,
                                                  spacing: 12)
                                              : CompactMusicGridDelegate.of(
                                                  context),
                                      itemCount: rows.length +
                                          (_draggingId == null ? 0 : 1),
                                      findChildIndexCallback: (key) =>
                                          gridChildIndices[key],
                                      itemBuilder: (context, index) => index ==
                                              rows.length
                                          ? _dropGap(current, rows, rows.length,
                                              grid: true)
                                          : Stack(
                                              key: ValueKey((
                                                'playlist-grid-entry',
                                                rows[index].id
                                              )),
                                              fit: StackFit.expand,
                                              children: [
                                                _row(
                                                    current,
                                                    rows[index],
                                                    index,
                                                    rows.length,
                                                    queue,
                                                    indices,
                                                    circleGeometry:
                                                        circleGeometry),
                                                // Reading order advances across
                                                // a grid row, so the leading
                                                // edge is the unambiguous
                                                // "insert before" target.
                                                PositionedDirectional(
                                                  top: 0,
                                                  bottom: 0,
                                                  start: 0,
                                                  width: 36,
                                                  child: IgnorePointer(
                                                    ignoring:
                                                        _draggingId == null,
                                                    child: _dropGap(
                                                        current, rows, index,
                                                        grid: true),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              )
                            : PlaylistReorderSurface(
                                key: PageStorageKey(
                                    'playlist-contents-${current?.id ?? 'root'}'),
                                controller: _reorderController,
                                enabled: !_editingBlocked &&
                                    !_selecting &&
                                    _sortMode(current) ==
                                        PlaylistSortMode.custom,
                                padding: EdgeInsets.only(
                                    bottom: NowPlayingBarMetrics.reservedSpace(
                                        context)),
                                items: [
                                  for (final row in rows)
                                    PlaylistDragData(
                                      entryId: row.id,
                                      sourceParent: current,
                                      label: row.label,
                                    ),
                                ],
                                onReorder: (data, correctedIndex) => unawaited(
                                    _move(data, current,
                                        index: correctedIndex)),
                                itemBuilder: (context, index) => _row(
                                  current,
                                  rows[index],
                                  index,
                                  rows.length,
                                  queue,
                                  indices,
                                ),
                              ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A disposable view projection of a model relationship, not a second model.
class _PlaylistRowData {
  const _PlaylistRowData({required this.id, this.audio, this.playlist});
  final String id;
  final Audio? audio;
  final Playlist? playlist;
  String get label => audio?.displayTitle ?? playlist?.name ?? ui("不可用的项目");
  int get createdAt =>
      audio == null ? playlist?.createdAt ?? 0 : audio!.created * 1000;
  int get modifiedAt =>
      audio == null ? playlist?.modifiedAt ?? 0 : audio!.modified * 1000;
  int get songCount => playlist?.flattenAudios().length ?? 1;
}
