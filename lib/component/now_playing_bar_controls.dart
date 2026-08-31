import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The floating bar uses the same playback callbacks as the full/mini player.
/// No native service is initialized by this presentation-only widget.
class NowPlayingBarControls extends StatelessWidget {
  const NowPlayingBarControls(
      {super.key,
      required this.isPlaying,
      this.isBuffering = false,
      this.showQueue = true,
      this.onPrevious,
      this.onPlayPause,
      this.onNext,
      this.onQueue});

  final bool isPlaying;
  final bool isBuffering;
  final bool showQueue;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final style = IconButton.styleFrom(
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
      foregroundColor: scheme.primary,
      shape: AppShape.control,
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final reduce = appToolbarReduceMotion(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          key: const ValueKey('bar-previous'),
          tooltip: ui('上一首'),
          style: style,
          onPressed: onPrevious,
          icon: const Icon(Symbols.skip_previous)),
      IconButton.filled(
        key: const ValueKey('bar-play-pause'),
        tooltip: isBuffering
            ? ui('正在获取播放地址')
            : isPlaying
                ? ui('暂停')
                : ui('播放'),
        onPressed: isBuffering ? null : onPlayPause,
        style: style.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .12)
                    : scheme.primaryContainer.withValues(alpha: .86)),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .38)
                    : scheme.onPrimaryContainer)),
        icon: AnimatedSwitcher(
            duration: reduce ? Duration.zero : AppMotion.quick,
            child: isBuffering
                ? const SizedBox.square(
                    key: ValueKey('buffering'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(isPlaying ? Symbols.pause : Symbols.play_arrow,
                    key: ValueKey(isPlaying))),
      ),
      IconButton(
          key: const ValueKey('bar-next'),
          tooltip: ui('下一首'),
          style: style,
          onPressed: onNext,
          icon: const Icon(Symbols.skip_next)),
      if (showQueue)
        IconButton(
            key: const ValueKey('bar-queue'),
            tooltip: ui('播放列表'),
            style: style,
            onPressed: onQueue,
            icon: const Icon(Symbols.queue_music)),
    ]);
  }
}
