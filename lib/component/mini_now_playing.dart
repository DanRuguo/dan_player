import 'package:dan_player/component/app_dialog_content.dart';
import 'dart:math' as math;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/now_playing_bar_controls.dart';
import 'package:dan_player/component/now_playing_bar_row.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/component/next_play_animation.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/seven_tone_spectrum.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class MiniNowPlaying extends StatelessWidget {
  const MiniNowPlaying({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ResponsiveBuilder(builder: (context, screenType) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8.0,
            0,
            8.0,
            screenType == ScreenType.small ? 8.0 : 32.0,
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 640.0;
            final width = screenType == ScreenType.small
                ? availableWidth
                : availableWidth < 640.0
                    ? availableWidth
                    : 640.0;

            return SizedBox(
              height: NowPlayingBarMetrics.height(context),
              width: width,
              child: FrostedSurface(
                borderRadius: AppShape.surfaceRadius,
                blur: 22.0,
                child: LayoutBuilder(builder: (context, constraints) {
                  final playback = PlayService.instance.playbackService;
                  final lyrics = PlayService.instance.lyricService;
                  return ListenableBuilder(
                    listenable: Listenable.merge(
                        [playback, playback.isBuffering, lyrics]),
                    child: const _NowPlayingForeground(),
                    builder: (context, child) => RectangleProgressIndicator(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      initialPosition: playback.position,
                      trackIdentity: (
                        playback.nowPlaying?.path,
                        lyrics.currLyricFuture
                      ),
                      onSeek: playback.nowPlaying == null ||
                              playback.isBuffering.value
                          ? null
                          : playback.seek,
                      child: child!,
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      );
    });
  }
}

class _NowPlayingForeground extends StatefulWidget {
  const _NowPlayingForeground();

  @override
  State<_NowPlayingForeground> createState() => _NowPlayingForegroundState();
}

class _NowPlayingForegroundState extends State<_NowPlayingForeground> {
  bool _queueOpen = false;

  Future<void> _openQueue() async {
    if (_queueOpen) return;
    _queueOpen = true;
    try {
      final selected = await showAppDialog<Audio>(
          context: context,
          dialogBottomInset: 16,
          builder: (context) {
            final size = MediaQuery.sizeOf(context);
            final contentWidth =
                math.min(520.0, math.max(160.0, size.width - 88));
            final contentHeight =
                math.min(440.0, math.max(160.0, size.height - 220));
            return AlertDialog(
              key: const ValueKey('current-playlist-dialog'),
              insetPadding: const EdgeInsets.all(16),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              title: const _QueueDialogTitle(),
              content: AppDialogContent(
                width: contentWidth,
                maxHeight: contentHeight,
                child: CurrentPlaylistView(
                  showTitle: false,
                  shrinkWrap: true,
                  onOpenDetails: (audio) => Navigator.pop(context, audio),
                ),
              ),
              actions: [
                TextButton.icon(
                  key: const ValueKey('close-current-playlist'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close),
                  label: Text(ui('关闭')),
                )
              ],
            );
          });
      if (mounted && selected != null) {
        context.push(app_paths.AUDIO_DETAIL_PAGE, extra: selected);
      }
    } finally {
      _queueOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    const borderRadius = AppShape.surfaceRadius;

    return Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: () => context.push(app_paths.NOW_PLAYING_PAGE),
        borderRadius: borderRadius,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return scheme.primary.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withValues(alpha: 0.06);
          }
          if (states.contains(WidgetState.focused)) {
            return scheme.primary.withValues(alpha: 0.08);
          }
          return null;
        }),
        child: ListenableBuilder(
          listenable: PlayService.instance.playbackService,
          builder: (context, _) {
            final playbackService = PlayService.instance.playbackService;
            final nowPlaying = playbackService.nowPlaying;
            return NowPlayingBarRow(
              leading: _NowPlayingCover(nowPlaying: nowPlaying),
              title: nowPlaying?.displayTitle ?? 'Dan Player',
              subtitle: nowPlaying == null
                  ? 'Enjoy music'
                  : '${nowPlaying.artist} - ${nowPlaying.album}',
              identity: nowPlaying?.path ?? 'idle',
              spectrum: nowPlaying == null
                  ? null
                  : _NowPlayingSpectrum(color: scheme.primary),
              controlsBuilder: (showQueue) => ValueListenableBuilder<bool>(
                valueListenable: playbackService.isBuffering,
                builder: (context, isBuffering, _) => StreamBuilder(
                  stream: playbackService.playerStateStream,
                  initialData: playbackService.playerState,
                  builder: (context, snapshot) {
                    late void Function() onPressed;
                    if (snapshot.data! == PlayerState.playing) {
                      onPressed = playbackService.pause;
                    } else if (snapshot.data! == PlayerState.completed) {
                      onPressed = playbackService.playAgain;
                    } else {
                      onPressed = playbackService.start;
                    }

                    final isPlaying = snapshot.data! == PlayerState.playing;

                    return NowPlayingBarControls(
                      isPlaying: isPlaying,
                      isBuffering: isBuffering,
                      showQueue: showQueue,
                      onPrevious:
                          nowPlaying == null ? null : playbackService.lastAudio,
                      onPlayPause: nowPlaying == null ? null : onPressed,
                      onNext:
                          nowPlaying == null ? null : playbackService.nextAudio,
                      onQueue: _openQueue,
                      queueTargetKey: NextPlayAnimation.targetKey,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QueueDialogTitle extends StatelessWidget {
  const _QueueDialogTitle();

  @override
  Widget build(BuildContext context) {
    final playback = PlayService.instance.playbackService;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder<List<Audio>>(
      valueListenable: playback.playlist,
      builder: (context, queue, _) => AppDialogTitle(
        ui('播放列表'),
        style: theme.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .82),
            borderRadius: AppShape.controlRadius,
          ),
          child: Icon(Symbols.queue_music,
              size: 22, color: scheme.onPrimaryContainer),
        ),
        trailing: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: .72),
            borderRadius: AppShape.controlRadius,
          ),
          alignment: Alignment.center,
          child: Text(
            '${queue.length}',
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingSpectrum extends StatelessWidget {
  const _NowPlayingSpectrum({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playbackService = PlayService.instance.playbackService;
    return StreamBuilder<PlayerState>(
      stream: playbackService.playerStateStream,
      initialData: playbackService.playerState,
      builder: (context, stateSnapshot) {
        final isPlaying = stateSnapshot.data == PlayerState.playing;
        return StreamBuilder<List<double>>(
          stream: playbackService.spectrumStream,
          initialData: playbackService.spectrumLevels,
          builder: (context, spectrumSnapshot) => SevenToneSpectrum(
            levels: isPlaying
                ? spectrumSnapshot.data ?? playbackService.spectrumLevels
                : const [0, 0, 0, 0, 0, 0, 0],
            color: color,
          ),
        );
      },
    );
  }
}

class _NowPlayingCover extends StatelessWidget {
  const _NowPlayingCover({required this.nowPlaying});

  final Audio? nowPlaying;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    if (nowPlaying == null) {
      return const AnimatedSwitcher(
        duration: AppMotion.standard,
        child: _CoverPlaceholder(key: ValueKey("idle-cover")),
      );
    }

    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation.drive(
            Tween<double>(begin: 0.96, end: 1.0),
          ),
          child: child,
        ),
      ),
      child: ClipRRect(
        key: ValueKey('cover-${nowPlaying!.path}'),
        borderRadius: AppShape.smallRadius,
        child: AudioArtwork(
          audio: nowPlaying!,
          size: 52,
          placeholder: const _CoverPlaceholder(),
          loading: const _CoverLoading(),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return _CoverFrame(
      child: Icon(
        Symbols.broken_image,
        size: 28.0,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _CoverLoading extends StatelessWidget {
  const _CoverLoading();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return const _CoverFrame(
      child: SizedBox(
        width: 20.0,
        height: 20.0,
        child: CircularProgressIndicator(strokeWidth: 2.0),
      ),
    );
  }
}

class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52.0,
      height: 52.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: AppShape.smallRadius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
