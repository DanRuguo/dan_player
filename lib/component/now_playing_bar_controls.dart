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
      this.queueExpanded = false,
      this.onPrevious,
      this.onPlayPause,
      this.onNext,
      this.onQueue,
      this.queueTargetKey});

  final bool isPlaying;
  final bool isBuffering;
  final bool showQueue;
  final bool queueExpanded;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onQueue;
  final Key? queueTargetKey;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final style = IconButton.styleFrom(
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
      foregroundColor: scheme.primary,
      shape: AppShape.pill,
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
      const SizedBox(width: 2),
      _TactilePlayPauseButton(
        key: const ValueKey('bar-play-pause'),
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        reduceMotion: reduce,
        tooltip: isBuffering
            ? ui('正在获取播放地址')
            : isPlaying
                ? ui('暂停')
                : ui('播放'),
        onPressed: isBuffering ? null : onPlayPause,
        style: style.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(50, 42)),
            fixedSize: const WidgetStatePropertyAll(Size(50, 42)),
            shape: const WidgetStatePropertyAll(AppShape.pill),
            side: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? BorderSide.none
                    : BorderSide(color: scheme.primary.withValues(alpha: .20))),
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .12)
                    : scheme.primaryContainer.withValues(alpha: .92)),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .38)
                    : scheme.onPrimaryContainer)),
      ),
      const SizedBox(width: 2),
      IconButton(
          key: const ValueKey('bar-next'),
          tooltip: ui('下一首'),
          style: style,
          onPressed: onNext,
          icon: const Icon(Symbols.skip_next)),
      if (showQueue) ...[
        const SizedBox(width: 2),
        KeyedSubtree(
          key: queueTargetKey,
          child: Semantics(
            expanded: queueExpanded,
            child: IconButton(
                key: const ValueKey('bar-queue'),
                tooltip: ui('播放列表'),
                style: queueExpanded
                    ? style.copyWith(
                        backgroundColor: WidgetStatePropertyAll(
                            scheme.secondaryContainer.withValues(alpha: .72)),
                        foregroundColor:
                            WidgetStatePropertyAll(scheme.onSecondaryContainer))
                    : style,
                onPressed: onQueue,
                icon: const Icon(Symbols.queue_music)),
          ),
        ),
      ],
    ]);
  }
}

class _TactilePlayPauseButton extends StatefulWidget {
  const _TactilePlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isBuffering,
    required this.reduceMotion,
    required this.tooltip,
    required this.onPressed,
    required this.style,
  });

  final bool isPlaying;
  final bool isBuffering;
  final bool reduceMotion;
  final String tooltip;
  final VoidCallback? onPressed;
  final ButtonStyle style;

  @override
  State<_TactilePlayPauseButton> createState() =>
      _TactilePlayPauseButtonState();
}

class _TactilePlayPauseButtonState extends State<_TactilePlayPauseButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isBuffering;
    final pressed = enabled && !widget.reduceMotion && _pressed;
    return Listener(
      onPointerDown: enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: pressed ? 0.94 : 1.0,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: IconButton.filled(
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          style: widget.style,
          icon: AnimatedSwitcher(
            duration: widget.reduceMotion ? Duration.zero : AppMotion.quick,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => widget.reduceMotion
                ? child
                : FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.80, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
            child: widget.isBuffering
                ? SizedBox.square(
                    key: const ValueKey('buffering'),
                    dimension: 20,
                    child: widget.reduceMotion
                        ? const Icon(Icons.hourglass_top_rounded, size: 20)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.isPlaying ? Symbols.pause : Symbols.play_arrow,
                    key: ValueKey(widget.isPlaying),
                  ),
          ),
        ),
      ),
    );
  }
}
