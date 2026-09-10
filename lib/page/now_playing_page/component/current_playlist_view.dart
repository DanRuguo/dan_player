import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/now_playing_page/component/segment_loop_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/library/audio_library.dart';
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
      this.onOpenDetails,
      this.playbackService});

  final bool showTitle;
  final bool immersive;
  final bool shrinkWrap;
  final ValueChanged<Audio>? onOpenDetails;

  /// Keeps the production view on the singleton while allowing its shared
  /// presentation to be exercised without creating a native audio device.
  @visibleForTesting
  final PlaybackService? playbackService;

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  late PlaybackService playbackService;
  late final ScrollController scrollController;
  int? _lastIndex;
  double _rowHeight = 0;
  bool _alignQueued = false;
  bool _savingQueue = false;
  final _searchController = TextEditingController();
  String _query = '';
  List<Audio>? _filteredQueue;
  List<int> _filteredIndices = const [];

  List<int> _visibleIndices(List<Audio> queue) {
    if (identical(queue, _filteredQueue)) return _filteredIndices;
    _filteredQueue = queue;
    final words = _query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    return _filteredIndices = [
      for (var i = 0; i < queue.length; i++)
        if (words.isEmpty ||
            words.every(('${queue[i].displayTitle}\n${queue[i].artist}\n'
                    '${queue[i].album}')
                .toLowerCase()
                .contains))
          i,
    ];
  }

  void _updateQuery(String value) {
    setState(() {
      _query = value.trim();
      _filteredQueue = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scrollController.hasClients) scrollController.jumpTo(0);
    });
  }

  void _locateCurrent() {
    if (_query.isNotEmpty) {
      _searchController.clear();
      _updateQuery('');
    }
    _scheduleAlignment(force: true);
  }

  void _deduplicateQueue() {
    final removed = playbackService.deduplicateQueue();
    showTextOnSnackBar(removed == 0 ? '队列中没有重复歌曲' : '已移除 {0} 个重复项，可撤销整理',
        arguments: [removed], context: context);
  }

  KeyEventResult _queueShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
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
      showTextOnSnackBar(playbackService.queueHistoryReason(redo: redo),
          context: context);
    }
    return KeyEventResult.handled;
  }

  Future<void> _saveQueue() async {
    if (_savingQueue || playbackService.playlist.value.isEmpty) return;
    final snapshot = List<Audio>.from(playbackService.playlist.value);
    setState(() => _savingQueue = true);
    var created = false;
    try {
      final name = await showPlaylistNameDialog(context,
          title: ui('将队列保存为歌单'),
          confirmLabel: ui('保存'),
          initialName: ui(
              '播放队列 {0}', [DateTime.now().toIso8601String().substring(0, 10)]));
      if (name == null || !mounted) return;
      playlistTree.createPlaylistFromAudios(name, snapshot);
      created = true;
      await savePlaylistUiChanges();
      if (mounted) {
        showTextOnSnackBar('已保存 {0} 首歌曲到“{1}”',
            arguments: [snapshot.length, name], context: context);
      }
    } catch (error, trace) {
      LOGGER.e('[queue] save playlist failed: $error', stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar(created ? '歌单已创建，但保存失败；请在歌单页重试保存' : '无法保存队列为歌单：{0}',
            arguments: [error], context: context);
      }
    } finally {
      if (mounted) setState(() => _savingQueue = false);
    }
  }

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
    if (_alignQueued) return;
    _alignQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignQueued = false;
      if (!mounted || !scrollController.hasClients) return;
      final latestQueue = playbackService.playlist.value;
      if (latestQueue.isEmpty) return;
      final visibleIndex =
          _visibleIndices(latestQueue).indexOf(playbackService.playlistIndex);
      if (visibleIndex < 0) return;
      final target = _alignmentOffset(visibleIndex);
      final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (animate && !reduced) {
        scrollController.animateTo(
          target,
          duration: AppMotion.standard,
          curve: AppMotion.standardCurve,
        );
      } else {
        scrollController.jumpTo(target);
      }
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

  void _toNowPlaying() => _scheduleAlignment();

  void _onQueueChanged() {
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
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_onQueueChanged);
  }

  @override
  void didUpdateWidget(covariant CurrentPlaylistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _resolvePlaybackService();
    if (identical(next, playbackService)) return;
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_onQueueChanged);
    playbackService = next;
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_onQueueChanged);
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
          ]),
          builder: (context, _) {
            final queue = playbackService.playlist.value;
            final visibleIndices = _visibleIndices(queue);
            final nowPlaying = playbackService.nowPlaying;
            final candidateIndex = playbackService.playlistIndex;
            final currentIndex = nowPlaying != null &&
                    candidateIndex >= 0 &&
                    candidateIndex < queue.length &&
                    queue[candidateIndex].path == nowPlaying.path
                ? candidateIndex
                : -1;
            return Column(
              mainAxisSize:
                  widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showTitle)
                  _PlaylistHeader(
                    count: queue.length,
                    immersive: widget.immersive,
                    currentIndex: currentIndex,
                  ),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(spacing: 4, children: [
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
                          Tooltip(
                              message: ui('A-B 片段循环'),
                              child: TextButton.icon(
                                  key: const ValueKey('queue-segment-loop'),
                                  onPressed: () => showSegmentLoopDialog(
                                      context, playbackService),
                                  icon: Icon(playbackService.segmentLoop.enabled
                                      ? Symbols.repeat_on
                                      : Symbols.repeat),
                                  label: const Text('A-B'))),
                        ]))),
                QueueStopStatus(playbackService: playbackService),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: TextField(
                    key: const ValueKey('queue-search'),
                    controller: _searchController,
                    maxLength: 160,
                    onChanged: _updateQuery,
                    decoration: InputDecoration(
                      hintText: ui('搜索队列：歌曲、歌手或专辑'),
                      counterText: '',
                      isDense: true,
                      filled: !widget.immersive,
                      enabledBorder: widget.immersive ? InputBorder.none : null,
                      focusedBorder: widget.immersive ? InputBorder.none : null,
                      fillColor: scheme.surfaceContainerLow,
                      prefixIcon: Icon(Symbols.search, color: scheme.primary),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                          ui('找到 {0} / {1} 首 · 搜索不改变队列',
                              [visibleIndices.length, queue.length]),
                          key: const ValueKey('queue-search-count'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall)),
                Flexible(
                  fit: widget.shrinkWrap ? FlexFit.loose : FlexFit.tight,
                  child: Container(
                    margin: EdgeInsets.fromLTRB(widget.showTitle ? 8 : 0, 4,
                        widget.showTitle ? 8 : 0, 0),
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
                                    child: Text(ui('队列中没有匹配的歌曲'),
                                        textAlign: TextAlign.center)))
                            : _QueueScrollbar(
                                controller: scrollController,
                                child: ListView.builder(
                                  shrinkWrap: widget.shrinkWrap,
                                  key: const ValueKey('current-playlist-list'),
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: _QueueScrollbar.edgeInset,
                                      vertical: 6),
                                  itemCount: visibleIndices.length,
                                  itemExtent: _rowHeight,
                                  itemBuilder: (context, index) =>
                                      _PlaylistViewItem(
                                    key: ValueKey(visibleIndices[index]),
                                    queue: queue,
                                    immersive: widget.immersive,
                                    item: queue[visibleIndices[index]],
                                    index: visibleIndices[index],
                                    current:
                                        visibleIndices[index] == currentIndex,
                                    playbackService: playbackService,
                                    onOpenDetails: widget.onOpenDetails,
                                  ),
                                ),
                              ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_onQueueChanged);
    _searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

/// Queue rows already leave a small symmetric edge inset. Paint the thumb in
/// that space without reducing the available content width.
class _QueueScrollbar extends StatelessWidget {
  const _QueueScrollbar({required this.controller, required this.child});

  static const edgeInset = 6.0;
  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
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
            controller: controller,
            interactive: true,

            child: child),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader(
      {required this.count,
      required this.currentIndex,
      required this.immersive});
  final bool immersive;

  final int count;
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
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
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
    this.onOpenDetails,
  });

  final Audio item;
  final List<Audio> queue;
  final int index;
  final bool current;
  final bool immersive;
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
      context.push(app_paths.AUDIO_DETAIL_PAGE, extra: item);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
      color: current
          ? (immersive ? scheme.primary : scheme.onPrimaryContainer)
          : scheme.onSurface,
      fontWeight: current ? FontWeight.w700 : FontWeight.w600,
    );
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      color: current
          ? (immersive ? scheme.primary : scheme.onPrimaryContainer)
              .withValues(alpha: .78)
          : scheme.onSurfaceVariant,
    );
    final durationText = Duration(seconds: item.duration).toStringHMMSS();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          onPressed: _playOccurrence,
          leadingIcon: const Icon(Symbols.play_arrow),
          child: Text(ui("播放")),
        ),
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
        if (playbackService.queueOccurrenceId(index) ==
            playbackService.queueStopBoundary.target)
          MenuItemButton(
              onPressed: playbackService.cancelQueueStop,
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
                showTextOnSnackBar("已加入总乐库");
              } catch (error, trace) {
                LOGGER.e('[queue] add online track failed: $error',
                    stackTrace: trace);
                showTextOnSnackBar("加入总乐库失败，请重试");
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
            end: current && !immersive
                ? scheme.primaryContainer.withValues(alpha: .82)
                : Colors.transparent,
          ),
          duration: reduced ? Duration.zero : AppMotion.quick,
          curve: AppMotion.standardCurve,
          builder: (context, color, child) => Material(
            color: color,
            borderRadius: AppShape.controlRadius,
            child: child,
          ),
          child: InkWell(
            key: ValueKey('current-playlist-item-$index'),
            borderRadius: AppShape.controlRadius,
            onTap: _playOccurrence,
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
                            Text(
                              item.displayTitle,
                              key: ValueKey('current-playlist-title-$index'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            const SizedBox(height: 2),
                            Text(
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
                            color: current
                                ? scheme.onPrimaryContainer
                                    .withValues(alpha: .72)
                                : scheme.onSurfaceVariant,
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
