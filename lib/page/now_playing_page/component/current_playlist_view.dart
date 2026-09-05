import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/now_playing_page/component/segment_loop_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView(
      {super.key,
      this.showTitle = true,
      this.onOpenDetails,
      this.playbackService});

  final bool showTitle;
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
      final target = _alignmentOffset(playbackService.playlistIndex);
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

  @override
  void initState() {
    super.initState();
    playbackService = _resolvePlaybackService();
    _lastIndex = playbackService.playlist.value.isEmpty
        ? -1
        : playbackService.playlistIndex;
    scrollController = ScrollController();
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_toNowPlaying);
  }

  @override
  void didUpdateWidget(covariant CurrentPlaylistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _resolvePlaybackService();
    if (identical(next, playbackService)) return;
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_toNowPlaying);
    playbackService = next;
    playbackService.addListener(_toNowPlaying);
    playbackService.playlist.addListener(_toNowPlaying);
    _scheduleAlignment(animate: false, force: true);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          playbackService,
          playbackService.playlist,
          playbackService.resolvingAudioPath,
          playbackService.isChangingOutput,
          playbackService.segmentLoop,
          OnlineLibrary.instance,
        ]),
        builder: (context, _) {
          final queue = playbackService.playlist.value;
          final nowPlaying = playbackService.nowPlaying;
          final candidateIndex = playbackService.playlistIndex;
          final currentIndex = nowPlaying != null &&
                  candidateIndex >= 0 &&
                  candidateIndex < queue.length &&
                  queue[candidateIndex].path == nowPlaying.path
              ? candidateIndex
              : -1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showTitle)
                _PlaylistHeader(
                  count: queue.length,
                  currentIndex: currentIndex,
                ),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                            key: const ValueKey('queue-locate-current'),
                            tooltip: ui('定位当前歌曲'),
                            onPressed: currentIndex < 0
                                ? null
                                : () => _scheduleAlignment(force: true),
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
                            key: const ValueKey('queue-undo-edit'),
                            tooltip: ui('撤销队列整理（最多 10 步；切换歌曲或队列后清空）'),
                            onPressed: playbackService.canUndoQueueEdit
                                ? playbackService.undoQueueEdit
                                : null,
                            icon: const Icon(Symbols.undo)),
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
                      ])),
              Expanded(
                child: Container(
                  margin: EdgeInsets.fromLTRB(
                      widget.showTitle ? 8 : 0, 4, widget.showTitle ? 8 : 0, 0),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: .78),
                    borderRadius: AppShape.surfaceRadius,
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .52),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: queue.isEmpty
                      ? const _EmptyPlaylistView()
                      : AppContentScrollbar(
                          controller: scrollController,
                          builder: (context, controller) => ListView.builder(
                            key: const ValueKey('current-playlist-list'),
                            controller: controller,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            itemCount: queue.length,
                            itemExtent: _rowHeight,
                            itemBuilder: (context, index) => _PlaylistViewItem(
                              item: queue[index],
                              index: index,
                              current: index == currentIndex,
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
    );
  }

  @override
  void dispose() {
    playbackService.removeListener(_toNowPlaying);
    playbackService.playlist.removeListener(_toNowPlaying);
    scrollController.dispose();
    super.dispose();
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({required this.count, required this.currentIndex});

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
              color: scheme.primaryContainer.withValues(alpha: .78),
              borderRadius: AppShape.controlRadius,
            ),
            child: Icon(Symbols.queue_music,
                size: 22, color: scheme.onPrimaryContainer),
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
                    color: scheme.onSurface,
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
    required this.item,
    required this.index,
    required this.current,
    required this.playbackService,
    this.onOpenDetails,
  });

  final Audio item;
  final int index;
  final bool current;
  final PlaybackService playbackService;
  final ValueChanged<Audio>? onOpenDetails;

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
      color: current ? scheme.onPrimaryContainer : scheme.onSurface,
      fontWeight: current ? FontWeight.w700 : FontWeight.w600,
    );
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      color: current
          ? scheme.onPrimaryContainer.withValues(alpha: .78)
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
          onPressed: () => playbackService.playIndexOfPlaylist(index),
          leadingIcon: const Icon(Symbols.play_arrow),
          child: Text(ui("播放")),
        ),
        MenuItemButton(
          onPressed: !current &&
                  playbackService.canEditQueue &&
                  playbackService.nowPlaying != null
              ? () => playbackService.moveQueueItemNext(index)
              : null,
          leadingIcon: const Icon(Symbols.playlist_play),
          child: Text(ui('移到下一首')),
        ),
        MenuItemButton(
          onPressed: !current && playbackService.canEditQueue
              ? () => playbackService.removeQueueItem(index)
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
            end: current
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
            onTap: () => playbackService.playIndexOfPlaylist(index),
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
                                : scheme.onSurfaceVariant,
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
