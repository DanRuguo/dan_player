import 'package:desktop_lyric/font_policy.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:dan_player/app_preference.dart';

import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/multi_selection_range.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_horizontal_wheel_region.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/component/playlist_folder_export_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/now_playing_page/component/segment_loop_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/page/now_playing_page/component/queue_upcoming_preview.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/play_service/queue_duration_summary.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_selection.dart';
import 'package:dan_player/play_service/queue_order.dart';
import 'package:dan_player/play_service/queue_album_layout.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView(
      {super.key,
      this.showTitle = true,
      this.immersive = false,
      this.shrinkWrap = false,
      this.showUpcomingPreviewAllowed = false,
      this.onOpenDetails,
      this.playbackService,
      this.pickM3uFile,
      this.pickFolderDirectory});

  final bool showTitle;
  final bool immersive;
  final bool shrinkWrap;

  /// Only the lyrics page opts in. Queue dialogs keep their editing space
  /// regardless of the user's lyrics-page preview preference.
  final bool showUpcomingPreviewAllowed;
  final ValueChanged<Audio>? onOpenDetails;

  /// Keeps the production view on the singleton while allowing its shared
  /// presentation to be exercised without creating a native audio device.
  @visibleForTesting
  final PlaybackService? playbackService;

  @visibleForTesting
  final FutureOr<String?> Function(String suggestedName)? pickM3uFile;

  @visibleForTesting
  final FutureOr<String?> Function()? pickFolderDirectory;

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  late PlaybackService playbackService;
  late final ScrollController scrollController;
  final _toolbarScroll = ScrollController();
  final _headerScroll = ScrollController();
  final _searchSummaryKey = GlobalKey();
  int? _lastIndex;
  double _rowHeight = 0;
  int _alignmentGeneration = 0;
  bool _savingQueue = false;
  bool _exportingQueue = false;
  bool _selectionBusy = false;
  final _selection = QueueSelection();
  final _searchController = TextEditingController();
  String _query = '';
  List<Audio>? _filteredQueue;
  List<int> _filteredIndices = const [];
  List<Audio>? _searchQueue;
  int _searchRevision = -1;
  QueueSearchIndex? _queueSearch;
  int _searchGeneration = 0;
  bool _searchPending = false;
  bool? _alignmentAfterSearch;
  bool _groupAlbums = false;
  final _collapsedAlbums = <int>{};
  List<Audio>? _albumQueue;
  int _albumRevision = -1;
  List<QueueAlbumBlock> _albumBlocks = const [];
  List<int>? _rowIndices;
  List<QueueAlbumRow> _rows = const [];

  List<QueueAlbumBlock> _blocks(List<Audio> queue) {
    if (!identical(queue, _albumQueue) ||
        _albumRevision != AudioLibrary.sortRevision) {
      _albumQueue = queue;
      _albumRevision = AudioLibrary.sortRevision;
      _albumBlocks = queueAlbumBlocks(queue, playbackService.queueOccurrenceId);
      _collapsedAlbums.retainAll(_albumBlocks.map((block) => block.id));
      _rowIndices = null;
    }
    return _albumBlocks;
  }

  List<QueueAlbumRow> _displayRows(List<Audio> queue, List<int> visible) {
    final blocks = _groupAlbums ? _blocks(queue) : const <QueueAlbumBlock>[];
    if (!identical(visible, _rowIndices)) {
      _rowIndices = visible;
      _rows = queueAlbumRows(visible, blocks, _collapsedAlbums,
          grouping: _groupAlbums, searching: _query.isNotEmpty);
    }
    return _rows;
  }

  bool _expandIndex(int index) {
    if (!_groupAlbums) return false;
    for (final block in _blocks(playbackService.playlist.value)) {
      if (block.contains(index) && _collapsedAlbums.remove(block.id)) {
        _rowIndices = null;
        return true;
      }
    }
    return false;
  }

  void _locateOccurrence(int occurrence) {
    if (!mounted) return;
    final queue = playbackService.playlist.value;
    final index = _occurrenceIndex(occurrence, 0, queue.length);
    if (index < 0) return;
    if (_query.isNotEmpty) {
      _searchController.clear();
      _updateQuery('');
    }
    setState(() {
      _expandIndex(index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(queue, playbackService.playlist.value)) {
        _alignToIndex(index, animate: true);
      }
    });
  }

  int _occurrenceIndex(int occurrence, int start, int end) {
    for (var i = start; i < end; i++) {
      if (playbackService.queueOccurrenceId(i) == occurrence) return i;
    }
    return -1;
  }

  void _alignToIndex(int index, {required bool animate}) {
    if (!scrollController.hasClients) return;
    final queue = playbackService.playlist.value;
    final row = _displayRows(queue, _visibleIndices(queue))
        .indexWhere((row) => row.queueIndex == index);
    if (row < 0) return;
    final target = _alignmentOffset(row);
    if (animate && AppMotion.enabled(context, MotionKind.feedback)) {
      unawaited(scrollController.animateTo(target,
          duration: AppMotion.standard, curve: AppMotion.standardCurve));
    } else {
      scrollController.jumpTo(target);
    }
  }

  Widget _albumHeader(QueueAlbumBlock block, int currentIndex) {
    final collapsed = _collapsedAlbums.contains(block.id);
    final scheme = Theme.of(context).colorScheme;
    final owner = block.owner == '未知专辑艺术家' ? ui(block.owner) : block.owner;
    final label = '${block.title} · $owner · ${ui('{0} 首歌曲', [block.count])}';
    final isCurrent = block.contains(currentIndex);
    final stopTarget = playbackService.queueStopBoundary.target;
    final stopsHere = stopTarget != null &&
        _occurrenceIndex(stopTarget, block.start, block.end) >= 0;
    return Semantics(
        button: true,
        toggled: !collapsed,
        child: Tooltip(
            message: label,
            child: Material(
                color: scheme.surfaceContainerHighest
                    .withValues(alpha: widget.immersive ? .35 : .7),
                borderRadius: AppShape.controlRadius,
                child: AppItemInkWell(
                    key: ValueKey('queue-album-${block.id}'),
                    borderRadius: AppShape.controlRadius,
                    onTap: () => setState(() {
                          if (!_collapsedAlbums.add(block.id))
                            _collapsedAlbums.remove(block.id);
                          _rowIndices = null;
                        }),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(children: [
                          AnimatedRotation(
                              turns: collapsed ? -.25 : 0,
                              duration: AppMotion.duration(context,
                                  MotionKind.feedback, AppMotion.quick),
                              child: Icon(Icons.expand_more,
                                  color: scheme.primary)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(block.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                Text('$owner · ${ui('{0} 首歌曲', [block.count])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ])),
                          if (isCurrent)
                            Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Symbols.equalizer,
                                    size: 18, color: scheme.primary)),
                          if (stopsHere)
                            Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Tooltip(
                                    message: ui('播完此条后停止'),
                                    child: Icon(Symbols.stop_circle,
                                        size: 18, color: scheme.primary))),
                        ]))))));
  }

  List<int> _visibleIndices(List<Audio> queue) {
    if (!identical(queue, _searchQueue) ||
        _searchRevision != AudioLibrary.searchRevision) {
      _searchQueue = queue;
      _searchRevision = AudioLibrary.searchRevision;
      _queueSearch = null;
      _filteredQueue = null;
      ++_searchGeneration;
      _searchPending = false;
    }
    if (identical(queue, _filteredQueue)) return _filteredIndices;
    _filteredQueue = queue;
    if (_query.isEmpty) {
      return _filteredIndices = List<int>.generate(queue.length, (i) => i);
    }
    if (queue.length > 128) {
      final generation = ++_searchGeneration;
      _searchPending = true;
      _filteredIndices = const [];
      unawaited(_filterLargeQueue(queue, _query, _searchRevision, generation));
      return _filteredIndices;
    }
    return _filteredIndices =
        (_queueSearch ??= QueueSearchIndex(queue)).matchingIndices(_query);
  }

  Future<void> _filterLargeQueue(
      List<Audio> queue, String query, int revision, int generation) async {
    bool cancelled() =>
        !mounted ||
        generation != _searchGeneration ||
        !identical(queue, playbackService.playlist.value) ||
        revision != AudioLibrary.searchRevision ||
        query != _query;
    final index = _queueSearch ??
        await QueueSearchIndex.build(queue, shouldCancel: cancelled);
    if (index == null || cancelled()) return;
    _queueSearch = index;
    final indices =
        await index.matchingIndicesAsync(query, shouldCancel: cancelled);
    if (indices == null || cancelled()) return;
    setState(() {
      _filteredIndices = indices;
      _searchPending = false;
    });
    final align = _alignmentAfterSearch;
    _alignmentAfterSearch = null;
    if (align != null) _scheduleAlignment(animate: align, force: true);
  }

  void _updateQuery(String value) {
    setState(() {
      ++_searchGeneration;
      _searchPending = false;
      _alignmentAfterSearch = null;
      _query = value.trim();
      _filteredQueue = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scrollController.hasClients) scrollController.jumpTo(0);
      final target = _searchSummaryKey.currentContext?.findRenderObject();
      if (_query.isNotEmpty && _headerScroll.hasClients && target != null) {
        unawaited(_headerScroll.position.ensureVisible(target,
            alignment: 1,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd));
      }
    });
  }

  void _locateCurrent() {
    if (_query.isNotEmpty) {
      _searchController.clear();
      _updateQuery('');
    }
    setState(() {
      _expandIndex(playbackService.playlistIndex);
    });
    _scheduleAlignment(force: true);
  }

  void _focusHeaderControl(FocusNode node,
      {ScrollPositionAlignmentPolicy? alignmentPolicy,
      double? alignment,
      Duration? duration,
      Curve? curve}) {
    node.requestFocus();
    final target = node.context;
    if (target == null) return;
    // Returning from the search field can move upward and rightward together.
    // Check both edges so one traversal direction cannot hide the other axis.
    for (final policy in [
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ]) {
      unawaited(Scrollable.ensureVisible(target, alignmentPolicy: policy));
    }
  }

  void _deduplicateQueue() {
    final removed = playbackService.deduplicateQueue();
    showAppNotice(
        ui(removed == 0 ? '队列中没有重复歌曲' : '已移除 {0} 个重复项，可撤销整理', [removed]),
        context: context,
        kind: removed == 0 ? AppNoticeKind.info : AppNoticeKind.success);
  }

  void _trimQueue(bool before) {
    final stopTarget = playbackService.queueStopBoundary.target;
    final removed = playbackService.trimQueue(before: before);
    if (removed > 0 &&
        stopTarget != null &&
        !playbackService.queueStopBoundary.active) {
      showAppNotice(
          ui(
              playbackService.canUndoQueueEdit
                  ? '已移除 {0} 个队列项，停止目标已取消；撤销不会恢复停止目标'
                  : '已移除 {0} 个队列项，停止目标已取消；队列过大，无法撤销',
              [removed]),
          context: context,
          kind: AppNoticeKind.info);
      return;
    }
    if (removed > 0 && !playbackService.canUndoQueueEdit) return;
    showAppNotice(
        ui(removed == 0 ? '队列顺序无需改变' : '已移除 {0} 个队列项，可撤销整理', [removed]),
        context: context,
        kind: removed == 0 ? AppNoticeKind.info : AppNoticeKind.success);
  }

  void _orderUpcoming({AudioSortField? field, bool reverse = false}) {
    final changed =
        playbackService.orderUpcomingQueue(field: field, reverse: reverse);
    if (changed && !playbackService.canUndoQueueEdit) return;
    showAppNotice(ui(changed ? '已整理待播歌曲，可撤销整理' : '队列顺序无需改变'),
        context: context,
        kind: changed ? AppNoticeKind.success : AppNoticeKind.info);
  }

  void _arrangeUpcoming(UpcomingQueueOrder order) {
    final changed = playbackService.arrangeUpcomingQueue(order);
    if (changed && !playbackService.canUndoQueueEdit) return;
    showAppNotice(ui(changed ? '已整理待播歌曲，可撤销整理' : '队列顺序无需改变'),
        context: context,
        kind: changed ? AppNoticeKind.success : AppNoticeKind.info);
  }

  Widget _menuLabel(String text, {double? maxWidth}) => ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: math.min(maxWidth ?? 360,
              (MediaQuery.sizeOf(context).width - 128).clamp(80.0, 360.0))),
      child: Text(ui(text), softWrap: true));

  VoidCallback _queueMenuAction(List<Audio> queue, VoidCallback action) {
    final owner = playbackService;
    return () {
      // Native MenuItemButton closes before dispatching on the next frame.
      // A replacement queue or player retires the menu's original action.
      if (mounted &&
          identical(owner, playbackService) &&
          identical(queue, owner.playlist.value)) {
        action();
      }
    };
  }

  Widget _organizeMenu(List<Audio> queue, int current) {
    final editable = playbackService.canEditQueue && current >= 0;
    final hasUpcoming = editable && queue.length - current - 1 > 1;
    return AppMenuAnchor(
        menuChildren: [
          MenuItemButton(
              key: const ValueKey('queue-trim-before'),
              onPressed: editable && current > 0
                  ? _queueMenuAction(queue, () => _trimQueue(true))
                  : null,
              leadingIcon: const Icon(Symbols.playlist_remove),
              child: _menuLabel('移除当前歌曲之前的队列项')),
          MenuItemButton(
              key: const ValueKey('queue-trim-after'),
              onPressed: editable && current < queue.length - 1
                  ? _queueMenuAction(queue, () => _trimQueue(false))
                  : null,
              leadingIcon: const Icon(Symbols.playlist_remove),
              child: _menuLabel('移除当前歌曲之后的队列项')),
          const Divider(),
          for (final arrangement in [false, true])
            AppSubmenuButton(
              key: ValueKey('queue-extra-${arrangement ? 'arrange' : 'sort'}'),
              leadingIcon: Icon(arrangement ? Symbols.shuffle : Symbols.sort),
              menuStyle: const MenuStyle(
                  maximumSize: WidgetStatePropertyAll(
                      Size(appSortMenuMaxWidth, double.infinity))),
              menuChildren: [
                if (!arrangement) ...[
                  for (final option in const [
                    (AudioSortField.name, '待播歌曲按名称排序'),
                    (AudioSortField.artist, '待播歌曲按艺术家排序'),
                    (AudioSortField.album, '待播歌曲按专辑排序'),
                    (AudioSortField.duration, '待播歌曲按时长排序'),
                  ])
                    MenuItemButton(
                        key: ValueKey('queue-sort-${option.$1.name}'),
                        onPressed: hasUpcoming
                            ? _queueMenuAction(
                                queue, () => _orderUpcoming(field: option.$1))
                            : null,
                        leadingIcon: const Icon(Symbols.sort),
                        child: _menuLabel(option.$2,
                            maxWidth: appSortMenuLabelMaxWidth)),
                  const Divider(),
                ],
                for (final order in UpcomingQueueOrder.values
                    .where((order) => order.arrangement == arrangement))
                  MenuItemButton(
                    key: ValueKey('queue-order-${order.name}'),
                    onPressed: hasUpcoming
                        ? _queueMenuAction(queue, () => _arrangeUpcoming(order))
                        : null,
                    leadingIcon:
                        Icon(arrangement ? Symbols.shuffle : Symbols.sort),
                    child: Tooltip(
                      message: ui(order == UpcomingQueueOrder.added
                          ? '本地使用文件创建时间；联网使用加入乐库时间。'
                          : audioSortMissingValueNote),
                      child: _menuLabel(order.label,
                          maxWidth: appSortMenuLabelMaxWidth),
                    ),
                  ),
                if (!arrangement) ...[
                  const Divider(),
                  MenuItemButton(
                      key: const ValueKey('queue-reverse-upcoming'),
                      onPressed: hasUpcoming
                          ? _queueMenuAction(
                              queue, () => _orderUpcoming(reverse: true))
                          : null,
                      leadingIcon: const Icon(Symbols.swap_vert),
                      child: _menuLabel('反转待播歌曲顺序',
                          maxWidth: appSortMenuLabelMaxWidth)),
                ],
              ],
              child: _menuLabel(arrangement ? '待播洗牌与编排' : '待播排序'),
            ),
        ],
        builder: (context, controller, child) => IconButton(
            key: const ValueKey('queue-organize'),
            tooltip: widget.showTitle
                ? ui('整理队列（保留当前播放，可撤销）')
                : '${ui('整理队列（保留当前播放，可撤销）')}\n'
                    '${current < 0 ? 0 : current + 1} / ${queue.length} · '
                    '${_queueDurationTooltip(queue, current)}',
            onPressed: editable
                ? () =>
                    controller.isOpen ? controller.close() : controller.open()
                : null,
            icon: const Icon(Symbols.sort)));
  }

  KeyEventResult _queueShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (_selection.enabled && event.logicalKey == LogicalKeyboardKey.escape) {
      _selection.exit();
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) return KeyEventResult.ignored;
    final redo = event.logicalKey == LogicalKeyboardKey.keyY ||
        event.logicalKey == LogicalKeyboardKey.keyZ &&
            HardwareKeyboard.instance.isShiftPressed;
    final undo = event.logicalKey == LogicalKeyboardKey.keyZ && !redo;
    if (!undo && !redo) return KeyEventResult.ignored;
    if (redo
        ? playbackService.canRedoQueueEdit
        : playbackService.canUndoQueueEdit) {
      redo ? playbackService.redoQueueEdit() : playbackService.undoQueueEdit();
    } else {
      showAppNotice(ui(playbackService.queueHistoryReason(redo: redo)),
          context: context, kind: AppNoticeKind.warning);
    }
    return KeyEventResult.handled;
  }

  Future<void> _saveQueue(
      {bool searchResults = false, List<Audio>? selected}) async {
    if (_savingQueue || playbackService.playlist.value.isEmpty) return;
    final queue = playbackService.playlist.value;
    // Capture occurrences before opening the name form. A queue replacement or
    // filter change while the form is open must not change what this click saves.
    final snapshot = selected ??
        (searchResults
            ? [for (final index in _visibleIndices(queue)) queue[index]]
            : List<Audio>.from(queue));
    if (snapshot.isEmpty) return;
    final initialName = selected != null
        ? ui('队列所选歌曲')
        : searchResults
            ? ui('搜索结果 {0}', [_query.characters.take(80).toString()])
            : ui('播放队列 {0}',
                [DateTime.now().toIso8601String().substring(0, 10)]);
    setState(() => _savingQueue = true);
    var created = false;
    try {
      final name = await showPlaylistNameDialog(context,
          title: ui(selected != null
              ? '将所选保存为新歌单'
              : searchResults
                  ? '将搜索结果保存为歌单'
                  : '将队列保存为歌单'),
          confirmLabel: ui('保存'),
          initialName: initialName);
      if (name == null || !mounted) return;
      playlistTree.createPlaylistFromAudios(name, snapshot);
      created = true;
      await savePlaylistUiChanges();
      if (mounted) {
        showAppNotice(ui('已保存 {0} 首歌曲到“{1}”', [snapshot.length, name]),
            context: context, kind: AppNoticeKind.success);
      }
    } catch (error, trace) {
      LOGGER.e('[queue] save playlist failed: $error', stackTrace: trace);
      if (mounted) {
        showAppNotice(
            ui(created ? '歌单已创建，但保存失败；请在歌单页重试保存' : '无法保存队列为歌单：{0}', [error]),
            context: context,
            kind: AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _savingQueue = false);
    }
  }

  Future<void> _exportQueue(
      {bool searchResults = false,
      bool musicFolder = false,
      List<Audio>? selected}) async {
    if (_exportingQueue) return;
    final queue = playbackService.playlist.value;
    final snapshot = selected ??
        (searchResults
            ? [for (final index in _visibleIndices(queue)) queue[index]]
            : List<Audio>.from(queue));
    if (snapshot.isEmpty) return;
    final name = selected != null
        ? ui('队列所选歌曲')
        : searchResults
            ? ui('搜索结果 {0}', [_query.characters.take(80).toString()])
            : ui('播放队列 {0}',
                [DateTime.now().toIso8601String().substring(0, 10)]);
    setState(() => _exportingQueue = true);
    try {
      // The shared exporter captures metadata and paths synchronously before
      // its first dialog/await; the clicked projection and repeats stay fixed.
      if (musicFolder) {
        await exportMusicFolder(context, snapshot,
            name: name, pickDirectory: widget.pickFolderDirectory);
      } else {
        await exportM3uPlaylist(context, snapshot,
            name: name, pickFile: widget.pickM3uFile);
      }
    } finally {
      if (mounted) setState(() => _exportingQueue = false);
    }
  }

  List<int> _queueOccurrenceIds(List<Audio> queue) => [
        for (var i = 0; i < queue.length; i++)
          if (playbackService.queueOccurrenceId(i) case final int id) id,
      ];

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSelection(int index, List<Audio> queue, List<int> visibleIds) {
    if (!identical(queue, playbackService.playlist.value)) return;
    final id = playbackService.queueOccurrenceId(index);
    if (id != null) {
      _selection.toggle(id, visibleIds,
          extend: HardwareKeyboard.instance.isShiftPressed);
    }
  }

  Future<void> _saveSelected(List<Audio> snapshot) async {
    if (_selectionBusy || snapshot.isEmpty) return;
    setState(() => _selectionBusy = true);
    try {
      await showAddAudiosToPlaylistDialog(context, snapshot);
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Widget _selectionToolbar(
      List<Audio> queue, List<int> visibleIds, int current) {
    final allIds = _queueOccurrenceIds(queue);
    final selectedIds = _selection.ordered(allIds);
    final selectedSet = selectedIds.toSet();
    final selected = <Audio>[
      for (var i = 0; i < queue.length; i++)
        if (selectedSet.contains(playbackService.queueOccurrenceId(i)))
          queue[i],
    ];
    final hidden =
        selectedIds.length - visibleIds.where(selectedSet.contains).length;
    final revision = _selection.revision;
    final hasCurrent =
        selectedSet.contains(playbackService.queueOccurrenceId(current));
    final editable =
        selected.length > (hasCurrent ? 1 : 0) && playbackService.canEditQueue;
    bool stillCurrent() =>
        mounted &&
        identical(queue, playbackService.playlist.value) &&
        revision == _selection.revision;
    VoidCallback guarded(VoidCallback action) => () {
          if (stillCurrent()) action();
        };
    VoidCallback? range(MultiSelectRange kind) =>
        _selection.canSelectRange(visibleIds, kind)
            ? guarded(() => _selection.selectRange(visibleIds, kind))
            : null;
    Widget action(String id, String label, IconData icon, VoidCallback run,
            {bool enabled = true}) =>
        MenuItemButton(
            key: ValueKey('queue-selection-$id'),
            onPressed: enabled ? guarded(run) : null,
            leadingIcon: Icon(icon),
            child: _menuLabel(label));
    void edit(QueueBatchAction action) =>
        playbackService.editQueueOccurrences(selectedIds,
            action: action, expectedQueue: queue);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Tooltip(
            message: ui('点击勾选，Shift+点击连续选择；隐藏的已选歌曲仍参与操作'),
            child: Text(
                hidden > 0
                    ? ui('已选 {0} 首，其中 {1} 首未显示', [selected.length, hidden])
                    : ui('已选 {0} 首', [selected.length]),
                key: const ValueKey('queue-selection-summary'),
                style: Theme.of(context).textTheme.labelLarge)),
        if (hasCurrent)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(ui('移动或移除时保留正在播放的歌曲；保存和导出包含它。'),
                  style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 4),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppMenuAnchor(
                  crossAxisUnconstrained: false,
                  menuChildren: [
                    action('move-next', '移到下一首', Symbols.playlist_play,
                        () => edit(QueueBatchAction.moveNext),
                        enabled: editable && current >= 0),
                    action('move-last', '移到队尾', Symbols.queue_music,
                        () => edit(QueueBatchAction.moveLast),
                        enabled: editable),
                    action('remove', '从播放队列移除', Symbols.playlist_remove,
                        () => edit(QueueBatchAction.remove),
                        enabled: editable),
                    const Divider(),
                    action(
                        'save-playlist',
                        '将所选保存为新歌单',
                        Symbols.playlist_add,
                        () =>
                            unawaited(_saveQueue(selected: List.of(selected))),
                        enabled: selected.isNotEmpty && !_savingQueue),
                    action('playlist', '加入歌单…', Symbols.playlist_add,
                        () => unawaited(_saveSelected(List.of(selected))),
                        enabled: selected.isNotEmpty && !_selectionBusy),
                    action(
                        'export-m3u',
                        '导出所选为 M3U8…',
                        Symbols.save_alt,
                        () => unawaited(
                            _exportQueue(selected: List.of(selected))),
                        enabled: selected.isNotEmpty && !_exportingQueue),
                    action(
                        'export-folder',
                        '导出所选音乐文件夹…',
                        Symbols.folder_copy,
                        () => unawaited(_exportQueue(
                            selected: List.of(selected), musicFolder: true)),
                        enabled: selected.isNotEmpty && !_exportingQueue),
                  ],
                  builder: (context, controller, _) => FilledButton.tonal(
                      key: const ValueKey('queue-selection-actions'),
                      onPressed: selected.isEmpty
                          ? null
                          : () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                      style: appToolbarControlStyle(context,
                          primary: true, tonal: true),
                      child: AppToolbarLabel(
                          label: ui('处理所选'), icon: Symbols.playlist_play))),
              SelectionRangeMenuButton(
                  onBetween: range(MultiSelectRange.between),
                  onAbove: range(MultiSelectRange.above),
                  onBelow: range(MultiSelectRange.below)),
              IconButton.filledTonal(
                  key: const ValueKey('queue-selection-toggle-all'),
                  tooltip: ui(visibleIds.isNotEmpty &&
                          selectedSet.containsAll(visibleIds)
                      ? '取消全选当前结果'
                      : '全选当前结果'),
                  onPressed: visibleIds.isEmpty
                      ? null
                      : guarded(() => _selection.toggleAll(visibleIds)),
                  style: appToolbarControlStyle(context,
                      primary: true, tonal: true, iconOnly: true),
                  icon: Icon(visibleIds.isNotEmpty &&
                          selectedSet.containsAll(visibleIds)
                      ? Symbols.deselect
                      : Symbols.select_all)),
              IconButton(
                  key: const ValueKey('queue-selection-invert'),
                  tooltip: ui('反选当前列表'),
                  onPressed: visibleIds.isEmpty
                      ? null
                      : guarded(() => _selection.invert(visibleIds)),
                  style: appToolbarControlStyle(context, iconOnly: true),
                  icon: const Icon(Symbols.select_check_box)),
              IconButton(
                  key: const ValueKey('queue-selection-clear'),
                  tooltip: ui('取消全部选择'),
                  onPressed: selected.isEmpty ? null : _selection.clear,
                  style: appToolbarControlStyle(context, iconOnly: true),
                  icon: const Icon(Symbols.deselect)),
              IconButton(
                  key: const ValueKey('queue-selection-exit'),
                  tooltip: ui('退出多选'),
                  onPressed: _selection.exit,
                  style: appToolbarControlStyle(context, iconOnly: true),
                  icon: const Icon(Symbols.close)),
            ]),
      ]),
    );
  }

  Widget _exportMenu(List<Audio> queue, List<int> visibleIndices) =>
      AppMenuAnchor(
        menuChildren: [
          MenuItemButton(
            key: const ValueKey('queue-export-m3u-all'),
            onPressed: queue.isEmpty || _exportingQueue
                ? null
                : _queueMenuAction(queue, _exportQueue),
            leadingIcon: const Icon(Symbols.save_alt),
            child: _menuLabel('导出队列为 M3U8'),
          ),
          if (_query.isNotEmpty)
            MenuItemButton(
              key: const ValueKey('queue-export-m3u-search'),
              onPressed: visibleIndices.isEmpty || _exportingQueue
                  ? null
                  : _queueMenuAction(
                      queue, () => _exportQueue(searchResults: true)),
              leadingIcon: const Icon(Symbols.filter_alt),
              child: _menuLabel('导出搜索结果为 M3U8'),
            ),
          MenuItemButton(
            key: const ValueKey('queue-export-folder-all'),
            onPressed: queue.isEmpty || _exportingQueue
                ? null
                : _queueMenuAction(
                    queue, () => _exportQueue(musicFolder: true)),
            leadingIcon: const Icon(Symbols.folder_copy),
            child: _menuLabel('导出队列音乐文件夹'),
          ),
          if (_query.isNotEmpty)
            MenuItemButton(
              key: const ValueKey('queue-export-folder-search'),
              onPressed: visibleIndices.isEmpty || _exportingQueue
                  ? null
                  : _queueMenuAction(
                      queue,
                      () =>
                          _exportQueue(searchResults: true, musicFolder: true)),
              leadingIcon: const Icon(Symbols.folder_copy),
              child: _menuLabel('导出搜索结果音乐文件夹'),
            ),
        ],
        builder: (context, controller, _) => IconButton(
          key: const ValueKey('queue-export-m3u'),
          tooltip: ui('导出队列或搜索结果'),
          onPressed: queue.isEmpty || _exportingQueue
              ? null
              : () =>
                  controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Symbols.save_alt),
        ),
      );

  PlaybackService _resolvePlaybackService() =>
      widget.playbackService ?? PlayService.instance.playbackService;

  double _alignmentOffset(int index) {
    if (!scrollController.hasClients || index < 0) return 0;
    final position = scrollController.position;
    final centered = index * _rowHeight -
        (position.viewportDimension - _rowHeight).clamp(0.0, double.infinity) /
            2;
    return centered.clamp(0.0, position.maxScrollExtent);
  }

  void _scheduleAlignment({bool animate = true, bool force = false}) {
    final queue = playbackService.playlist.value;
    final index = queue.isEmpty ? -1 : playbackService.playlistIndex;
    if (!force && _lastIndex == index) return;
    _lastIndex = index;
    // An explicit locate can clear the search after a playback notification
    // already queued alignment. Run the latest request after that search reset;
    // an earlier callback must neither swallow it nor move the new results.
    final generation = ++_alignmentGeneration;
    final alignmentQuery = _query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _alignmentGeneration ||
          alignmentQuery != _query) return;
      if (_searchPending) {
        _alignmentAfterSearch = animate;
        return;
      }
      if (!scrollController.hasClients) return;
      final latestQueue = playbackService.playlist.value;
      if (latestQueue.isEmpty) return;
      _alignToIndex(playbackService.playlistIndex, animate: animate);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final measured = scaler.scale(textTheme.bodyLarge?.fontSize ?? 16) * 1.35 +
        scaler.scale(textTheme.bodyMedium?.fontSize ?? 14) * 1.35 +
        34;
    final next = measured < 72 ? 72.0 : measured;
    if (_rowHeight == next) return;
    _rowHeight = next;
    _scheduleAlignment(animate: false, force: true);
  }

  void _toNowPlaying() {
    if (playbackService.playlistIndex != _lastIndex &&
        _expandIndex(playbackService.playlistIndex) &&
        mounted) setState(() {});
    _scheduleAlignment();
  }

  void _onQueueChanged() {
    _selection.retain(_queueOccurrenceIds(playbackService.playlist.value));
    ++_searchGeneration;
    _searchPending = false;
    _alignmentAfterSearch = null;
    _searchQueue = null;
    _filteredQueue = null;
    _scheduleAlignment();
  }

  @override
  void initState() {
    super.initState();
    playbackService = _resolvePlaybackService();
    _lastIndex = playbackService.playlist.value.isEmpty
        ? -1
        : playbackService.playlistIndex;
    scrollController = ScrollController();
    _selection.addListener(_selectionChanged);
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_onQueueChanged);
  }

  @override
  void didUpdateWidget(covariant CurrentPlaylistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _resolvePlaybackService();
    if (identical(next, playbackService)) return;
    _selection.exit();
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_onQueueChanged);
    playbackService = next;
    _albumQueue = null;
    _collapsedAlbums.clear();
    _rowIndices = null;
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_onQueueChanged);
    ++_searchGeneration;
    _searchPending = false;
    _alignmentAfterSearch = null;
    _searchQueue = null;
    _filteredQueue = null;
    _scheduleAlignment(animate: false, force: true);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      autofocus: true,
      onKeyEvent: _queueShortcut,
      child: Material(
        type: MaterialType.transparency,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            playbackService,
            playbackService.playlist,
            playbackService.resolvingAudioPath,
            playbackService.isChangingOutput,
            playbackService.segmentLoop,
            playbackService.playMode,
            playbackService.queueStopBoundary,
            OnlineLibrary.instance,
            AudioLibrary.changes,
            AppPreference.instance.showQueueUpcoming,
          ]),
          builder: (context, _) {
            final queue = playbackService.playlist.value;
            final visibleIndices = _visibleIndices(queue);
            final displayRows = _displayRows(queue, visibleIndices);
            final visibleIds = <int>[
              for (final row in displayRows)
                if (row.queueIndex case final int index)
                  if (playbackService.queueOccurrenceId(index)
                      case final int id)
                    id,
            ];
            final searchSummary = _searchPending
                ? ui('正在搜索队列…')
                : ui('找到 {0} / {1} 首 · 搜索不改变队列',
                    [visibleIndices.length, queue.length]);
            final nowPlaying = playbackService.nowPlaying;
            final candidateIndex = playbackService.playlistIndex;
            final currentIndex = nowPlaying != null &&
                    candidateIndex >= 0 &&
                    candidateIndex < queue.length &&
                    queue[candidateIndex].path == nowPlaying.path
                ? candidateIndex
                : -1;
            final header = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showTitle)
                  _PlaylistHeader(
                    count: queue.length,
                    queue: queue,
                    immersive: widget.immersive,
                    currentIndex: currentIndex,
                  ),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _QueueToolbarRail(
                        controller: _toolbarScroll,
                        suppressStretch: widget.immersive,
                        child: Row(spacing: 4, children: [
                          IconButton(
                              key: const ValueKey('queue-selection-enter'),
                              tooltip: ui('多选整理队列'),
                              isSelected: _selection.enabled,
                              onPressed: queue.isEmpty
                                  ? null
                                  : () => _selection.enabled
                                      ? _selection.exit()
                                      : _selection.enter(),
                              icon: const Icon(Symbols.checklist)),
                          _organizeMenu(queue, currentIndex),
                          IconButton(
                              key: const ValueKey('queue-group-albums'),
                              tooltip: ui(_groupAlbums ? '显示逐首队列' : '按专辑折叠队列'),
                              isSelected: _groupAlbums,
                              onPressed: queue.isEmpty
                                  ? null
                                  : () => setState(() {
                                        _groupAlbums = !_groupAlbums;
                                        _rowIndices = null;
                                        _scheduleAlignment(
                                            animate: false, force: true);
                                      }),
                              icon: const Icon(Icons.album_outlined),
                              selectedIcon: const Icon(Icons.album)),
                          IconButton(
                              tooltip: ui('收听会话'),
                              onPressed: () =>
                                  showNamedQueues(context, playbackService),
                              icon: const Icon(Symbols.save)),
                          IconButton(
                              key: const ValueKey('queue-locate-current'),
                              tooltip: ui('定位当前歌曲'),
                              onPressed:
                                  currentIndex < 0 ? null : _locateCurrent,
                              icon: const Icon(Symbols.my_location)),
                          IconButton(
                              key: const ValueKey('queue-save-playlist'),
                              tooltip: ui('将队列保存为歌单'),
                              onPressed: queue.isEmpty || _savingQueue
                                  ? null
                                  : _saveQueue,
                              icon: const Icon(Symbols.playlist_add)),
                          _exportMenu(queue, visibleIndices),
                          IconButton(
                              key: const ValueKey('queue-keep-current'),
                              tooltip: ui('仅保留当前歌曲'),
                              onPressed: currentIndex < 0 ||
                                      queue.length <= 1 ||
                                      !playbackService.canEditQueue
                                  ? null
                                  : playbackService.keepOnlyCurrentQueueItem,
                              icon: const Icon(Symbols.playlist_remove)),
                          IconButton(
                              key: const ValueKey('queue-deduplicate'),
                              tooltip: ui('移除重复歌曲（保留当前播放，可撤销）'),
                              onPressed: queue.length < 2 ||
                                      !playbackService.canEditQueue
                                  ? null
                                  : _deduplicateQueue,
                              icon: const Icon(Symbols.layers_clear)),
                          IconButton(
                              key: const ValueKey('queue-undo-edit'),
                              tooltip: ui(playbackService.canUndoQueueEdit
                                  ? '撤销队列整理 · Ctrl+Z'
                                  : playbackService.queueHistoryReason()),
                              onPressed: playbackService.canUndoQueueEdit
                                  ? playbackService.undoQueueEdit
                                  : null,
                              icon: const Icon(Symbols.undo)),
                          IconButton(
                              key: const ValueKey('queue-redo-edit'),
                              tooltip: ui(playbackService.canRedoQueueEdit
                                  ? '重做队列整理 · Ctrl+Y / Ctrl+Shift+Z'
                                  : playbackService.queueHistoryReason(
                                      redo: true)),
                              onPressed: playbackService.canRedoQueueEdit
                                  ? playbackService.redoQueueEdit
                                  : null,
                              icon: const Icon(Symbols.redo)),
                          IconButton(
                              key: const ValueKey('queue-stop-after-round'),
                              tooltip: ui(
                                  playbackService.queueStopBlockedReason ??
                                      '播完当前队列后停止'),
                              onPressed: queue.isEmpty ||
                                      playbackService.queueStopBlockedReason !=
                                          null
                                  ? null
                                  : playbackService.stopAfterQueueRound,
                              icon: const Icon(Symbols.stop_circle)),
                          IconButton(
                            tooltip: ui('A-B 片段循环'),
                            key: const ValueKey('queue-segment-loop'),
                            onPressed: () =>
                                showSegmentLoopDialog(context, playbackService),
                            icon: Icon(playbackService.segmentLoop.enabled
                                ? Symbols.repeat_on
                                : Symbols.repeat),
                          ),
                        ]))),
                QueueStopStatus(playbackService: playbackService),
                if (widget.showUpcomingPreviewAllowed &&
                    !_selection.enabled &&
                    queue.isNotEmpty &&
                    AppPreference.instance.showQueueUpcoming.value)
                  QueueUpcomingPreview(
                      playbackService: playbackService,
                      onLocate: _locateOccurrence),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: TextField(
                    key: const ValueKey('queue-search'),
                    controller: _searchController,
                    maxLength: 160,
                    onChanged: _updateQuery,
                    decoration: InputDecoration(
                      hintText: ui('搜索队列：歌曲、歌手或专辑'),
                      hintMaxLines: 1,
                      counterText: '',
                      isDense: true,
                      filled: !widget.immersive,
                      enabledBorder: widget.immersive ? InputBorder.none : null,
                      focusedBorder: widget.immersive ? InputBorder.none : null,
                      fillColor: scheme.surfaceContainerLow,
                      prefixIcon: Tooltip(
                        message: ui('支持拼音、首字母、重音与全角匹配，以及英文拼写容错；多个词需同时匹配。'),
                        child: Icon(Symbols.search, color: scheme.primary),
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('queue-clear-search'),
                              tooltip: ui('清除搜索'),
                              onPressed: () {
                                _searchController.clear();
                                _updateQuery('');
                              },
                              icon: const Icon(Symbols.close)),
                      border: OutlineInputBorder(
                          borderRadius: AppShape.controlRadius,
                          borderSide: BorderSide(color: scheme.outlineVariant)),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Row(children: [
                        Expanded(
                            child: Tooltip(
                                key: _searchSummaryKey,
                                message: searchSummary,
                                child: Text(searchSummary,
                                    key: const ValueKey('queue-search-count'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall))),
                        IconButton(
                            key: const ValueKey('queue-save-search-playlist'),
                            tooltip: ui('将搜索结果保存为歌单'),
                            onPressed: visibleIndices.isEmpty || _savingQueue
                                ? null
                                : () => _saveQueue(searchResults: true),
                            icon: const Icon(Symbols.playlist_add)),
                      ])),
                if (_selection.enabled)
                  _selectionToolbar(queue, visibleIds, currentIndex),
              ],
            );
            final songs = Container(
              margin: EdgeInsets.fromLTRB(
                  widget.showTitle ? 8 : 0, 4, widget.showTitle ? 8 : 0, 0),
              decoration: BoxDecoration(
                color: widget.immersive
                    ? Colors.transparent
                    : scheme.surfaceContainerLow.withValues(alpha: .78),
                borderRadius: AppShape.surfaceRadius,
                border: Border.all(
                  color: widget.immersive
                      ? Colors.transparent
                      : scheme.outlineVariant.withValues(alpha: .52),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: queue.isEmpty
                  ? const _EmptyPlaylistView()
                  : visibleIndices.isEmpty
                      ? Center(
                          heightFactor: 1,
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  ui(_searchPending ? '正在搜索队列…' : '队列中没有匹配的歌曲'),
                                  textAlign: TextAlign.center)))
                      : _QueueScrollbar(
                          controller: scrollController,
                          suppressStretch: widget.immersive,
                          child: ListView.builder(
                            shrinkWrap: widget.shrinkWrap,
                            key: const ValueKey('current-playlist-list'),
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: _QueueScrollbar.edgeInset,
                                vertical: 6),
                            itemCount: displayRows.length,
                            itemExtent: _rowHeight,
                            itemBuilder: (context, rowIndex) {
                              final row = displayRows[rowIndex];
                              if (row.block != null)
                                return _albumHeader(row.block!, currentIndex);
                              final index = row.queueIndex!;
                              return _PlaylistViewItem(
                                key: ValueKey((
                                  'queue-occurrence',
                                  playbackService.queueOccurrenceId(index)
                                )),
                                queue: queue,
                                immersive: widget.immersive,
                                item: queue[index],
                                index: index,
                                current: index == currentIndex,
                                playbackService: playbackService,
                                onOpenDetails: widget.onOpenDetails,
                                selecting: _selection.enabled,
                                selected: _selection.contains(
                                    playbackService.queueOccurrenceId(index)),
                                onToggleSelection: () =>
                                    _toggleSelection(index, queue, visibleIds),
                                onStartSelection: () {
                                  if (!mounted ||
                                      !identical(queue,
                                          playbackService.playlist.value))
                                    return;
                                  _selection.enter(
                                      playbackService.queueOccurrenceId(index));
                                },
                              );
                            },
                          ),
                        ),
            );
            Widget body(Widget top) => Column(
                  mainAxisSize:
                      widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(
                            requestFocusCallback: _focusHeaderControl),
                        child: top),
                    Flexible(
                        fit: widget.shrinkWrap ? FlexFit.loose : FlexFit.tight,
                        child: songs),
                  ],
                );
            // AlertDialog measures the shrink-wrapped presentation intrinsically.
            // Only the bounded player view needs a separate short-height rail.
            if (widget.shrinkWrap) return body(header);
            return LayoutBuilder(builder: (context, constraints) {
              if (!constraints.hasBoundedHeight) return body(header);
              final reserve = math.min(_rowHeight, constraints.maxHeight * .4);
              return body(ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight:
                          math.max(0.0, constraints.maxHeight - reserve)),
                  child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false, overscroll: false),
                      child: AppScrollbar(
                          controller: _headerScroll,
                          child: SingleChildScrollView(
                              key: const ValueKey('queue-header-scroll'),
                              controller: _headerScroll,
                              primary: false,
                              child: header)))));
            });
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_searchGeneration;
    _selection.dispose();
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_onQueueChanged);
    _searchController.dispose();
    _headerScroll.dispose();
    _toolbarScroll.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

/// Wheel input is redirected only while the pointer is over this independent
/// toolbar. The song list keeps its vertical scrolling and touch gestures.
class _QueueToolbarRail extends StatelessWidget {
  const _QueueToolbarRail(
      {required this.controller,
      required this.suppressStretch,
      required this.child});
  final ScrollController controller;
  final bool suppressStretch;
  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
      child: AppHorizontalWheelRegion(
          controller: controller,
          child: ScrollConfiguration(
              behavior: suppressStretch
                  ? const DanPlayerScrollBehavior().copyWith(overscroll: false)
                  : const DanPlayerScrollBehavior(),
              child: AppScrollbar(
                  controller: controller,
                  child: SingleChildScrollView(
                      key: const ValueKey('queue-toolbar-scroll'),
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: child)))));
}

String _queueDurationTooltip(List<Audio> queue, int current) {
  final total = QueueDurationSummary.of(queue);
  final upcoming =
      QueueDurationSummary.of(current < 0 ? queue : queue.skip(current + 1));
  final label = current < 0
      ? ui('队列时长 {0}', [total.clock])
      : ui('队列时长 {0} · 待播 {1}', [total.clock, upcoming.clock]);
  return total.unknownCount == 0
      ? label
      : '$label · ${ui('另有 {0} 首时长未知', [total.unknownCount])}';
}

/// Queue rows already leave a small symmetric edge inset. Paint the thumb in
/// that space without reducing the available content width.
class _QueueScrollbar extends StatelessWidget {
  const _QueueScrollbar(
      {required this.controller,
      required this.suppressStretch,
      required this.child});

  static const edgeInset = 6.0;
  final ScrollController controller;
  final bool suppressStretch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: !suppressStretch),
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(
          crossAxisMargin: 0,
          mainAxisMargin: edgeInset,
          radius: const Radius.circular(4),
          thickness: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.dragged)
                  ? edgeInset
                  : 4.0),
          thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.dragged)
                  ? scheme.primary.withValues(alpha: .95)
                  : states.contains(WidgetState.hovered)
                      ? scheme.primary.withValues(alpha: .8)
                      : scheme.onSurfaceVariant.withValues(alpha: .5)),
        ),
        child: AppScrollbar(
            controller: controller, interactive: true, child: child),
      ),
    );
  }
}

class _QueueDurationLabel extends StatelessWidget {
  const _QueueDurationLabel(
      {required this.queue, required this.current, required this.status});
  final List<Audio> queue;
  final int current;
  final String status;

  @override
  Widget build(BuildContext context) {
    final total = QueueDurationSummary.of(queue);
    return Tooltip(
        message: _queueDurationTooltip(queue, current),
        child: Text(
            queue.isEmpty
                ? status
                : '$status · ${total.clock}${total.unknownCount > 0 ? ' + ?' : ''}',
            key: const ValueKey('queue-duration-summary'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)));
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader(
      {required this.count,
      required this.queue,
      required this.currentIndex,
      required this.immersive});
  final bool immersive;

  final int count;
  final List<Audio> queue;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = count == 0
        ? ui('尚未选择歌曲')
        : currentIndex < 0
            ? '$count'
            : '${currentIndex + 1} / $count';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: immersive
                  ? Colors.transparent
                  : scheme.primaryContainer.withValues(alpha: .78),
              borderRadius: AppShape.controlRadius,
            ),
            child: Icon(Symbols.queue_music,
                size: 22,
                color: immersive ? scheme.primary : scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ui('播放列表'),
                  key: const ValueKey('current-playlist-heading'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                _QueueDurationLabel(
                    queue: queue, current: currentIndex, status: status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaylistView extends StatelessWidget {
  const _EmptyPlaylistView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      heightFactor: 1,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: .68),
                borderRadius: AppShape.surfaceRadius,
              ),
              child: Icon(Symbols.queue_music,
                  size: 28, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              ui('尚未选择歌曲'),
              key: const ValueKey('current-playlist-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistViewItem extends StatelessWidget {
  const _PlaylistViewItem({
    super.key,
    required this.queue,
    required this.item,
    required this.index,
    required this.current,
    required this.immersive,
    required this.playbackService,
    required this.selecting,
    required this.selected,
    required this.onToggleSelection,
    required this.onStartSelection,
    this.onOpenDetails,
  });

  final Audio item;
  final List<Audio> queue;
  final int index;
  final bool current;
  final bool immersive;
  final bool selecting, selected;
  final VoidCallback onToggleSelection, onStartSelection;
  final PlaybackService playbackService;
  final ValueChanged<Audio>? onOpenDetails;

  // An open menu from an older queue must not operate on a shifted occurrence.
  bool get _stillCurrentQueue =>
      identical(queue, playbackService.playlist.value);

  void _playOccurrence() {
    if (_stillCurrentQueue) playbackService.playIndexOfPlaylist(index);
  }

  void _openDetails(BuildContext context) {
    if (onOpenDetails != null) {
      onOpenDetails!(item);
    } else {
      // Pushing a ShellRoute from its sibling root lyric route would mount the
      // same shell page key twice. Keep detail on the lyric navigator instead.
      final path = GoRouterState.of(context).uri.path;
      context.push(
          path == app_paths.NOW_PLAYING_PAGE ||
                  path.startsWith('${app_paths.NOW_PLAYING_PAGE}/')
              ? '${app_paths.NOW_PLAYING_PAGE}/detail'
              : app_paths.AUDIO_DETAIL_PAGE,
          extra: item);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
      color: selected
          ? scheme.onSecondaryContainer
          : current
              ? (immersive ? scheme.primary : scheme.onPrimaryContainer)
              : scheme.onSurface,
      fontWeight: current ? FontWeight.w700 : FontWeight.w600,
    );
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      color: selected
          ? scheme.onSecondaryContainer.withValues(alpha: .78)
          : current
              ? (immersive ? scheme.primary : scheme.onPrimaryContainer)
                  .withValues(alpha: .78)
              : scheme.onSurfaceVariant,
    );
    final durationText = Duration(seconds: item.duration).toStringHMMSS();
    final stopTarget = playbackService.queueStopBoundary.target;
    final stopCommandRevision =
        playbackService.queueStopBoundary.commandRevision;
    final reduced = !AppMotion.enabled(context, MotionKind.feedback);
    final placeholder = ColoredBox(
      color: current
          ? scheme.primary.withValues(alpha: .08)
          : scheme.surfaceContainerHighest,
      child: Icon(
        item.isOnline ? Symbols.cloud : Symbols.audio_file,
        size: 22,
        color: current ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
    return AppMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          onPressed: _playOccurrence,
          leadingIcon: const Icon(Symbols.play_arrow),
          child: Text(ui("播放")),
        ),
        if (!selecting)
          MenuItemButton(
              key: ValueKey('queue-selection-start-$index'),
              onPressed: onStartSelection,
              leadingIcon: const Icon(Symbols.checklist),
              child: Text(ui('多选整理队列'))),
        MenuItemButton(
          onPressed: !current &&
                  playbackService.canEditQueue &&
                  playbackService.nowPlaying != null
              ? () {
                  if (_stillCurrentQueue) {
                    playbackService.moveQueueItemNext(index);
                  }
                }
              : null,
          leadingIcon: const Icon(Symbols.playlist_play),
          child: Text(ui('移到下一首')),
        ),
        MenuItemButton(
          key: ValueKey('queue-stop-after-item-$index'),
          onPressed: playbackService.queueStopBlockedReason == null
              ? () {
                  if (_stillCurrentQueue) {
                    playbackService.stopAfterQueueItem(index);
                  }
                }
              : null,
          leadingIcon: const Icon(Symbols.stop_circle),
          child: Text(ui('播完此条后停止')),
        ),
        if (stopTarget != null &&
            playbackService.queueOccurrenceId(index) == stopTarget)
          MenuItemButton(
              onPressed: () {
                if (_stillCurrentQueue &&
                    playbackService.queueStopBoundary.target == stopTarget &&
                    playbackService.queueStopBoundary.commandRevision ==
                        stopCommandRevision) {
                  playbackService.cancelQueueStop();
                }
              },
              leadingIcon: const Icon(Symbols.close),
              child: Text(ui('取消停止目标'))),
        MenuItemButton(
          onPressed: !current && playbackService.canEditQueue
              ? () {
                  if (_stillCurrentQueue) {
                    playbackService.removeQueueItem(index);
                  }
                }
              : null,
          leadingIcon: const Icon(Symbols.playlist_remove),
          child: Text(ui(current ? '正在播放的歌曲保留在队列中' : '从播放队列移除')),
        ),
        if (item.isOnline && !OnlineLibrary.instance.contains(item))
          MenuItemButton(
            onPressed: () async {
              try {
                await OnlineLibrary.instance.add(item);
                showAppNotice(ui("已加入总乐库"), kind: AppNoticeKind.success);
              } catch (error, trace) {
                LOGGER.e('[queue] add online track failed: $error',
                    stackTrace: trace);
                showAppNotice(ui("加入总乐库失败，请重试"), kind: AppNoticeKind.error);
              }
            },
            leadingIcon: const Icon(Symbols.library_add),
            child: Text(ui("加入总乐库")),
          ),
        MenuItemButton(
          onPressed: () => _openDetails(context),
          leadingIcon: const Icon(Symbols.info),
          child: Text(item.isOnline ? ui("联网歌曲详情") : ui("本地歌曲详情")),
        ),
      ],
      builder: (context, controller, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: selected
                ? scheme.secondaryContainer.withValues(alpha: .78)
                : current && !immersive
                    ? scheme.primaryContainer.withValues(alpha: .82)
                    : Colors.transparent,
          ),
          duration: reduced ? Duration.zero : AppMotion.quick,
          curve: AppMotion.standardCurve,
          builder: (context, color, child) => Material(
            color: color,
            shape: RoundedRectangleBorder(
                borderRadius: AppShape.controlRadius,
                side: BorderSide(
                    color: selected
                        ? scheme.primary.withValues(alpha: .22)
                        : Colors.transparent)),
            child: child,
          ),
          child: AppItemInkWell(
            key: ValueKey('current-playlist-item-$index'),
            borderRadius: AppShape.controlRadius,
            onTap: selecting ? onToggleSelection : _playOccurrence,
            onSecondaryTapDown: (details) =>
                controller.open(position: details.localPosition),
            onLongPress: () => controller.open(position: const Offset(16, 28)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showDetails = constraints.maxWidth >= 300;
                  final showDuration = constraints.maxWidth >= 380;
                  return Row(
                    children: [
                      if (selecting)
                        SizedBox.square(
                            dimension: 48,
                            child: Center(
                                child: Checkbox(
                                    key: ValueKey('queue-select-$index'),
                                    value: selected,
                                    visualDensity: VisualDensity.standard,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    semanticLabel: item.displayTitle,
                                    onChanged: (_) => onToggleSelection()))),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: AppShape.smallRadius,
                            child: AudioArtwork(
                              audio: item,
                              size: 44,
                              placeholder: placeholder,
                              loading: placeholder,
                            ),
                          ),
                          if (current)
                            PositionedDirectional(
                              end: -4,
                              bottom: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: scheme.primaryContainer, width: 2),
                                ),
                                child: Icon(Symbols.equalizer,
                                    size: 12, color: scheme.onPrimary),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            appFontText(
                              context,
                              item.displayTitle,
                              key: ValueKey('current-playlist-title-$index'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            const SizedBox(height: 2),
                            appFontText(
                              context,
                              "${item.artist} - ${item.album}",
                              key: ValueKey('current-playlist-metadata-$index'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metadataStyle,
                            ),
                          ],
                        ),
                      ),
                      if (showDuration) ...[
                        const SizedBox(width: 10),
                        Text(
                          durationText,
                          maxLines: 1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                : current
                                    ? scheme.onPrimaryContainer
                                    : scheme.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      if (playbackService.queueStopBoundary.active &&
                          playbackService.queueOccurrenceId(index) ==
                              playbackService.queueStopBoundary.target)
                        Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Tooltip(
                                message: ui('播完此条后停止'),
                                child: Icon(Symbols.stop_circle,
                                    size: 18, color: scheme.primary))),
                      if (showDetails) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: item.isOnline ? ui("联网歌曲详情") : ui("本地歌曲详情"),
                          onPressed: () => _openDetails(context),
                          visualDensity: VisualDensity.compact,
                          iconSize: 19,
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(36),
                            fixedSize: const Size.square(36),
                            padding: EdgeInsets.zero,
                            foregroundColor: current
                                ? scheme.onPrimaryContainer
                                : scheme.primary,
                            shape: AppShape.control,
                          ),
                          icon: const Icon(Symbols.info),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
