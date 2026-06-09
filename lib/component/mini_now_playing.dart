import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class MiniNowPlaying extends StatelessWidget {
  const MiniNowPlaying({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
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
              height: 72.0,
              width: width,
              child: FrostedSurface(
                borderRadius: BorderRadius.circular(16.0),
                blur: 22.0,
                child: LayoutBuilder(builder: (context, constraints) {
                  return RectangleProgressIndicator(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    child: const _NowPlayingForeground(),
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

class _NowPlayingForeground extends StatelessWidget {
  const _NowPlayingForeground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const borderRadius = BorderRadius.all(Radius.circular(16.0));

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: ListenableBuilder(
            listenable: PlayService.instance.playbackService,
            builder: (context, _) {
              final playbackService = PlayService.instance.playbackService;
              final nowPlaying = playbackService.nowPlaying;

              return Row(
                children: [
                  _NowPlayingCover(nowPlaying: nowPlaying),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.standard,
                      switchInCurve: AppMotion.standardCurve,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: _fadeSlideTransition,
                      child: Column(
                        key: ValueKey(nowPlaying?.path ?? "idle"),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            nowPlaying != null
                                ? nowPlaying.displayTitle
                                : "Dan Player",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            nowPlaying != null
                                ? "${nowPlaying.artist} - ${nowPlaying.album}"
                                : "Enjoy music",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  StreamBuilder(
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

                      return IconButton.filled(
                        tooltip: isPlaying ? "Pause" : "Play",
                        onPressed: onPressed,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              scheme.primaryContainer.withValues(alpha: 0.86),
                          foregroundColor: scheme.onPrimaryContainer,
                          hoverColor: scheme.primary.withValues(alpha: 0.08),
                          focusColor: scheme.primary.withValues(alpha: 0.10),
                        ),
                        icon: AnimatedSwitcher(
                          duration: AppMotion.quick,
                          switchInCurve: AppMotion.standardCurve,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: animation,
                              child: child,
                            ),
                          ),
                          child: Icon(
                            isPlaying ? Symbols.pause : Symbols.play_arrow,
                            key: ValueKey(isPlaying),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowPlayingCover extends StatelessWidget {
  const _NowPlayingCover({required this.nowPlaying});

  final Audio? nowPlaying;

  @override
  Widget build(BuildContext context) {
    if (nowPlaying == null) {
      return const AnimatedSwitcher(
        duration: AppMotion.standard,
        child: _CoverPlaceholder(key: ValueKey("idle-cover")),
      );
    }

    return FutureBuilder<ImageProvider?>(
      future: nowPlaying!.cover,
      builder: (context, snapshot) {
        final Widget child = switch (snapshot.connectionState) {
          ConnectionState.done => snapshot.data == null
              ? _CoverPlaceholder(key: ValueKey("missing-${nowPlaying!.path}"))
              : _CoverImage(
                  key: ValueKey("cover-${nowPlaying!.path}"),
                  image: snapshot.data!,
                ),
          _ => _CoverLoading(key: ValueKey("loading-${nowPlaying!.path}")),
        };

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
          child: child,
        );
      },
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    super.key,
    required this.image,
  });

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Image(
        image: image,
        width: 52.0,
        height: 52.0,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
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
  const _CoverLoading({super.key});

  @override
  Widget build(BuildContext context) {
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52.0,
      height: 52.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

Widget _fadeSlideTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation.drive(CurveTween(curve: AppMotion.standardCurve)),
    child: SlideTransition(
      position: animation.drive(
        Tween<Offset>(begin: const Offset(0.02, 0.0), end: Offset.zero),
      ),
      child: child,
    ),
  );
}
