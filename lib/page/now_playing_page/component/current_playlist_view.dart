import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView(
      {super.key, this.showTitle = true, this.onOpenDetails});

  final bool showTitle;
  final ValueChanged<Audio>? onOpenDetails;

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  final playbackService = PlayService.instance.playbackService;
  late final ScrollController scrollController;
  int? _lastIndex;
  double _rowHeight = 0;
  bool _alignQueued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final measured = MediaQuery.textScalerOf(context).scale(14) * 2.8 + 16;
    final next = measured < 56 ? 56.0 : measured;
    if (_rowHeight == next) return;
    _rowHeight = next;
    if (_alignQueued) return;
    _alignQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignQueued = false;
      if (!mounted || !scrollController.hasClients) return;
      scrollController.jumpTo((playbackService.playlistIndex * _rowHeight)
          .clamp(0.0, scrollController.position.maxScrollExtent));
    });
  }

  void _toNowPlaying() {
    if (_lastIndex == playbackService.playlistIndex) return;
    _lastIndex = playbackService.playlistIndex;
    if (scrollController.hasClients) {
      scrollController.animateTo(
        (playbackService.playlistIndex * _rowHeight)
            .clamp(0.0, scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _lastIndex = playbackService.playlistIndex;
    scrollController = ScrollController(
      initialScrollOffset: playbackService.playlistIndex * 56.0,
    );
    playbackService.addListener(_toNowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                ui("播放列表"),
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                playbackService,
                playbackService.playlist,
                OnlineLibrary.instance,
              ]),
              builder: (context, _) {
                return AppContentScrollbar(
                  controller: scrollController,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    itemCount: playbackService.playlist.value.length,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, index) {
                      return _PlaylistViewItem(
                          index: index, onOpenDetails: widget.onOpenDetails);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    playbackService.removeListener(_toNowPlaying);
    scrollController.dispose();
    super.dispose();
  }
}

class _PlaylistViewItem extends StatelessWidget {
  const _PlaylistViewItem({required this.index, this.onOpenDetails});

  final int index;
  final ValueChanged<Audio>? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    var playbackService = PlayService.instance.playbackService;
    final item = playbackService.playlist.value[index];
    final scheme = Theme.of(context).colorScheme;
    final current = playbackService.nowPlaying?.path == item.path;
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          onPressed: () => playbackService.playIndexOfPlaylist(index),
          leadingIcon: const Icon(Symbols.play_arrow),
          child: Text(ui("播放")),
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
          onPressed: () {
            if (onOpenDetails != null) {
              onOpenDetails!(item);
            } else {
              context.push(app_paths.AUDIO_DETAIL_PAGE, extra: item);
            }
          },
          leadingIcon: const Icon(Symbols.info),
          child: Text(item.isOnline ? ui("联网歌曲详情") : ui("本地歌曲详情")),
        ),
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: AppShape.controlRadius,
        onTap: () => playbackService.playIndexOfPlaylist(index),
        onSecondaryTapDown: (details) =>
            controller.open(position: details.localPosition),
        onLongPress: () => controller.open(position: const Offset(16, 28)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: DefaultTextStyle(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 14),
            child: Row(
              children: [
                Icon(
                  current
                      ? Symbols.equalizer
                      : item.isOnline
                          ? Symbols.cloud
                          : Symbols.audio_file,
                  size: 20,
                  color: current ? scheme.primary : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.displayTitle,
                        style: TextStyle(
                            fontWeight: current ? FontWeight.w700 : null)),
                    Text("${item.artist} - ${item.album}"),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
