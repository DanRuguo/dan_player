import 'component/sleep_timer_submenu.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'package:dan_player/component/app_playback_mode_controls.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/component/online_source_display.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/page/now_playing_page/component/equalizer_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/playback_bookmarks_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/detail_transport_button.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

part 'small_page.dart';
part 'large_page.dart';

enum NowPlayingViewMode {
  onlyMain,
  withLyric,
  withPlaylist;

  static NowPlayingViewMode? fromString(String nowPlayingViewMode) {
    for (var value in NowPlayingViewMode.values) {
      if (value.name == nowPlayingViewMode) return value;
    }
    return null;
  }
}

final NOW_PLAYING_VIEW_MODE = ValueNotifier(
  AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode,
);

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // One cached, configurable layer covers both title bar and body.
        // Cover changes repaint this layer, not the complete lyric/player UI.
        const SceneBackground(scene: BackgroundScene.nowPlaying),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const PreferredSize(
            preferredSize: Size.fromHeight(56.0),
            child: TitleBarSurface(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    NavBackBtn(),
                    Expanded(child: DragToMoveArea(child: SizedBox.expand())),
                    WindowControlls(),
                  ],
                ),
              ),
            ),
          ),
          body: ChangeNotifierProvider.value(
            value: PlayService.instance.playbackService,
            builder: (context, _) {
              return ResponsiveBuilder2(builder: (context, screenType) {
                switch (screenType) {
                  case ScreenType.small:
                    return const _NowPlayingPage_Small();
                  case ScreenType.medium:
                  case ScreenType.large:
                    return const _NowPlayingPage_Large();
                }
              });
            },
          ),
        ),
      ],
    );
  }
}

class _NowPlayingMoreAction extends StatelessWidget {
  const _NowPlayingMoreAction();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playbackService = context.watch<PlaybackService>();
    final nowPlaying = playbackService.nowPlaying;
    final onlinePlaying = nowPlaying?.isOnline == true ? nowPlaying : null;
    final localPlaying = nowPlaying?.isLocal == true ? nowPlaying : null;
    final onlineSourceLabel = onlinePlaying == null
        ? null
        : onlineSourceDisplayLabel(
            provider: onlinePlaying.onlineProvider,
            fallback: onlinePlaying.sourceLabel,
          );
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: OnlineLibrary.instance,
      builder: (context, _) => MenuAnchor(
          menuChildren: [
            MenuItemButton(
                onPressed: () => showPreciseSeek(context, playbackService),
                leadingIcon: const Icon(Symbols.schedule),
                child: Text(ui('精确定位'))),
            MenuItemButton(
              onPressed: () => showEqualizerDialog(context),
              leadingIcon: const Icon(Symbols.equalizer),
              child: Text(ui("均衡器")),
            ),
            const SleepTimerSubmenu(),
            if (localPlaying != null)
              MenuItemButton(
                onPressed: () =>
                    showPlaybackBookmarksDialog(context, playbackService),
                leadingIcon: const Icon(Symbols.bookmarks),
                child: Text(ui('播放书签')),
              ),
            if (nowPlaying != null) const Divider(),
            if (onlinePlaying != null)
              MenuItemButton(
                onPressed: null,
                leadingIcon: const Icon(Symbols.cloud),
                child: Text(ui("来源：{0}", [onlineSourceLabel])),
              ),
            if (nowPlaying != null)
              MenuItemButton(
                onPressed: () => showSongCommentsDialog(context, nowPlaying),
                leadingIcon: const Icon(Symbols.chat_bubble_outline),
                child: Text(ui("歌曲评论")),
              ),
            if (onlinePlaying != null)
              MenuItemButton(
                onPressed: () async {
                  try {
                    if (OnlineLibrary.instance.contains(onlinePlaying)) {
                      await OnlineLibrary.instance.remove(onlinePlaying);
                      showTextOnSnackBar("已从总乐库移除");
                    } else {
                      await OnlineLibrary.instance.add(onlinePlaying);
                      showTextOnSnackBar("已加入总乐库");
                    }
                  } catch (error, stackTrace) {
                    LOGGER.e("[online library] $error", stackTrace: stackTrace);
                    showTextOnSnackBar("更新总乐库失败：{0}", arguments: [error]);
                  }
                },
                leadingIcon: const Icon(Symbols.library_add),
                child: Text(
                  OnlineLibrary.instance.contains(onlinePlaying)
                      ? ui("从总乐库移除")
                      : ui("加入总乐库"),
                ),
              ),
            if (onlinePlaying != null &&
                !OnlineMusicService.instance.canDownload(onlinePlaying))
              MenuItemButton(
                onPressed: null,
                leadingIcon: const Icon(Symbols.download),
                child: Text(
                  ui("下载不可用：{0}", [
                    ui(OnlineMusicService.instance
                            .downloadUnavailableReason(onlinePlaying) ??
                        "当前来源不支持下载")
                  ]),
                ),
              ),
            if (localPlaying != null)
              for (final artistName in localPlaying.splitedArtists)
                MenuItemButton(
                  onPressed: () {
                    final Artist? artist =
                        AudioLibrary.instance.artistCollection[artistName];
                    if (artist == null) return;
                    context.pushReplacement(
                      app_paths.ARTIST_DETAIL_PAGE,
                      extra: artist,
                    );
                  },
                  leadingIcon: const Icon(Symbols.artist),
                  child: Text(
                    artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            if (localPlaying != null)
              MenuItemButton(
                onPressed: () {
                  final album = MusicCategories.albumGroupFor(
                    localPlaying,
                    AudioLibrary.instance.audioCollection,
                  );
                  context.pushReplacement(
                    album.location,
                    extra: album,
                  );
                },
                leadingIcon: const Icon(Symbols.album),
                child: Text(
                  localPlaying.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (nowPlaying != null)
              MenuItemButton(
                onPressed: () {
                  context.pushReplacement(
                    app_paths.AUDIO_DETAIL_PAGE,
                    extra: nowPlaying,
                  );
                },
                leadingIcon: const Icon(Symbols.info),
                child: Text(ui("详细信息")),
              ),
          ],
          builder: (context, controller, _) => IconButton(
                tooltip: ui("更多"),
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                icon: const Icon(Symbols.more_vert),
                color: scheme.primary,
              )),
    );
  }
}

class _NowPlayingCommentsAction extends StatelessWidget {
  const _NowPlayingCommentsAction();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final audio = context.watch<PlaybackService>().nowPlaying;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('now-playing-comments'),
      tooltip: audio?.isLocal == true && !SongCommentsService.canRead(audio!)
          ? ui("歌曲评论 · 需要先关联平台歌曲")
          : ui("歌曲评论"),
      onPressed:
          audio == null ? null : () => showSongCommentsDialog(context, audio),
      color: scheme.primary,
      icon: const Icon(Symbols.chat_bubble_outline),
    );
  }
}

class _DesktopLyricSwitch extends StatelessWidget {
  const _DesktopLyricSwitch();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: PlayService.instance.desktopLyricService,
      builder: (context, _) {
        final desktopLyricService = PlayService.instance.desktopLyricService;
        final tooltip = switch (desktopLyricService.state) {
          DesktopLyricState.stopped => ui("开启桌面歌词"),
          DesktopLyricState.starting => ui("正在启动桌面歌词"),
          DesktopLyricState.running when desktopLyricService.isLocked =>
            ui("桌面歌词已锁定；点击解锁"),
          DesktopLyricState.running => ui("关闭桌面歌词"),
          DesktopLyricState.recovering => ui("桌面歌词异常，正在恢复"),
          DesktopLyricState.failed => ui("桌面歌词启动失败；点击重试"),
        };
        final onPressed = switch (desktopLyricService.state) {
          DesktopLyricState.starting || DesktopLyricState.recovering => null,
          DesktopLyricState.running when desktopLyricService.isLocked =>
            desktopLyricService.sendUnlockMessage,
          DesktopLyricState.running => desktopLyricService.killDesktopLyric,
          DesktopLyricState.stopped ||
          DesktopLyricState.failed =>
            desktopLyricService.startDesktopLyric,
        };

        return IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: desktopLyricService.isStarting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Icon(
                  desktopLyricService.state == DesktopLyricState.failed
                      ? Symbols.error
                      : desktopLyricService.isLocked
                          ? Symbols.lock
                          : Symbols.toast,
                  fill: desktopLyricService.isRunning ? 1 : 0,
                ),
          color: scheme.primary,
        );
      },
    );
  }
}

class _NowPlayingVolDspSlider extends StatefulWidget {
  const _NowPlayingVolDspSlider();

  @override
  State<_NowPlayingVolDspSlider> createState() =>
      _NowPlayingVolDspSliderState();
}

class _NowPlayingVolDspSliderState extends State<_NowPlayingVolDspSlider> {
  final playbackService = PlayService.instance.playbackService;
  final dragVolDsp = ValueNotifier(
    AppPreference.instance.playbackPref.volumeDsp,
  );
  bool isDragging = false;

  @override
  void dispose() {
    dragVolDsp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      style: const MenuStyle(
        shape: WidgetStatePropertyAll(
          AppShape.control,
        ),
      ),
      menuChildren: [
        SliderTheme(
          data: const SliderThemeData(
            showValueIndicator: ShowValueIndicator.onDrag,
          ),
          child: ValueListenableBuilder(
            valueListenable: dragVolDsp,
            builder: (context, dragVolDspValue, _) => Slider(
              thumbColor: scheme.primary,
              activeColor: scheme.primary,
              inactiveColor: scheme.outline,
              min: 0.0,
              max: 1.0,
              value: isDragging ? dragVolDspValue : playbackService.volumeDsp,
              label: "${(dragVolDspValue * 100).toInt()}",
              onChangeStart: (value) {
                isDragging = true;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChanged: (value) {
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChangeEnd: (value) {
                isDragging = false;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: ui("音量"),
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Symbols.volume_up),
        color: scheme.primary,
      ),
    );
  }
}

/// previous audio, pause/resume, next audio
class _NowPlayingMainControls extends StatelessWidget {
  const _NowPlayingMainControls();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playbackService = PlayService.instance.playbackService;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      DetailTransportButton(
        tooltip: ui("上一曲"),
        onPressed: playbackService.lastAudio,
        icon: Symbols.skip_previous,
      ),
      const SizedBox(width: 16),
      ValueListenableBuilder<bool>(
        valueListenable: playbackService.isBuffering,
        builder: (context, buffering, _) => StreamBuilder(
          stream: playbackService.playerStateStream,
          initialData: playbackService.playerState,
          builder: (context, snapshot) {
            final playerState = snapshot.data!;
            final playing = playerState == PlayerState.playing;
            return DetailTransportButton(
              primary: true,
              buffering: buffering,
              tooltip: buffering
                  ? ui("正在获取播放地址")
                  : playing
                      ? ui("暂停")
                      : ui("播放"),
              onPressed: playing
                  ? playbackService.pause
                  : playerState == PlayerState.completed
                      ? playbackService.playAgain
                      : playbackService.start,
              icon: playing ? Symbols.pause : Symbols.play_arrow,
            );
          },
        ),
      ),
      const SizedBox(width: 16),
      DetailTransportButton(
        tooltip: ui("下一曲"),
        onPressed: playbackService.nextAudio,
        icon: Symbols.skip_next,
      ),
    ]);
  }
}

class _NowPlayingSlider extends StatelessWidget {
  const _NowPlayingSlider();

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackService>();
    return ValueListenableBuilder<bool>(
      valueListenable: playback.isBuffering,
      builder: (context, buffering, _) => DetailProgressSlider(
        positions: playback.positionStream,
        readPosition: () => playback.position,
        duration: playback.length,
        trackIdentity: playback.nowPlaying?.path,
        enabled: playback.nowPlaying != null && !buffering,
        onSeek: playback.seek,
        hidden: DesktopIntegration.instance.isHidden,
      ),
    );
  }
}

/// title, artist, album, cover
class _NowPlayingInfo extends StatefulWidget {
  const _NowPlayingInfo();

  @override
  State<_NowPlayingInfo> createState() => __NowPlayingInfoState();
}

class __NowPlayingInfoState extends State<_NowPlayingInfo> {
  final playbackService = PlayService.instance.playbackService;

  void updateCover() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    playbackService.addListener(updateCover);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final nowPlaying = playbackService.nowPlaying;

    final placeholder = FittedBox(
      child: Icon(
        Symbols.broken_image,
        size: 400.0,
        color: scheme.onSecondaryContainer,
      ),
    );

    const loadingWidget = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(),
      ),
    );

    return Center(
      child: SizedBox(
        width: 400.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nowPlaying == null ? "Dan Player" : nowPlaying.displayTitle,
              maxLines: 1,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              nowPlaying == null
                  ? "Enjoy Music"
                  : "${nowPlaying.artist} - ${nowPlaying.album}",
              maxLines: 1,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: TouchTrackSwipe(
                  onPrevious: playbackService.lastAudio,
                  onNext: playbackService.nextAudio,
                  child: RepaintBoundary(
                    child: nowPlaying == null
                        ? placeholder
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final available =
                                  constraints.biggest.shortestSide;
                              final size = available.isFinite && available > 0
                                  ? available.clamp(1.0, 400.0)
                                  : 400.0;
                              return Center(
                                  child: ClipRRect(
                                borderRadius: AppShape.surfaceRadius,
                                child: AudioArtwork(
                                  audio: nowPlaying,
                                  size: size,
                                  placeholder: placeholder,
                                  loading: loadingWidget,
                                ),
                              ));
                            },
                          ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    playbackService.removeListener(updateCover);
    super.dispose();
  }
}
