import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Global queue modes, independent of the page's contents. These controls never
/// start playback or replace the queue. A native player is not created by build.
class AppPlaybackModeControls extends StatelessWidget {
  const AppPlaybackModeControls({
    super.key,
    this.playbackService,
    this.plain = false,
  });

  final PlaybackService? playbackService;

  /// Lyrics use independent transparent buttons; library headers stay joined.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final service = playbackService;
    if (service != null) return _connected(service);
    return PlaybackReadyBuilder(
      readyBuilder: (_) => _connected(PlayService.instance.playbackService),
      waitingBuilder: (_) => _ModeButtons(plain: plain),
    );
  }

  Widget _connected(PlaybackService service) => ListenableBuilder(
        listenable: Listenable.merge([service.shuffle, service.playMode]),
        builder: (_, __) => _ModeButtons(
          plain: plain,
          shuffle: service.shuffle.value,
          mode: service.playMode.value,
          onShuffle: () => service.useShuffle(!service.shuffle.value),
          onRepeat: () => service.setPlayMode(switch (service.playMode.value) {
            PlayMode.forward => PlayMode.loop,
            PlayMode.loop => PlayMode.singleLoop,
            PlayMode.singleLoop => PlayMode.forward,
          }),
        ),
      );
}

class _ModeButtons extends StatelessWidget {
  const _ModeButtons({
    this.shuffle = false,
    this.mode = PlayMode.forward,
    this.onShuffle,
    this.onRepeat,
    this.plain = false,
  });

  final bool shuffle;
  final PlayMode mode;
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeat;
  final bool plain;

  Widget _animatedModeIcon(
    BuildContext context, {
    required IconData icon,
  }) {
    final duration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: const Threshold(1.0),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .86, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Icon(icon, key: ValueKey(icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final shuffleTooltip = ui('随机；现在：{0}', [shuffle ? ui('启用') : ui('禁用')]);
    final repeatTooltip = ui('循环；现在：{0}', [
      switch (mode) {
        PlayMode.forward => ui('循环关闭'),
        PlayMode.loop => ui('列表循环'),
        PlayMode.singleLoop => ui('单曲循环'),
      }
    ]);
    if (plain) {
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        fixedSize: const WidgetStatePropertyAll(Size(44, 44)),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(AppShape.pill),
        side: const WidgetStatePropertyAll(BorderSide.none),
        iconSize: const WidgetStatePropertyAll(24),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: .16);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withValues(alpha: .08);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.primary),
      );
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: const ValueKey('playback-mode-shuffle'),
          tooltip: shuffleTooltip,
          style: style,
          isSelected: shuffle,
          onPressed: onShuffle,
          icon: _animatedModeIcon(
            context,
            icon: shuffle ? Symbols.shuffle_on : Symbols.shuffle,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('playback-mode-repeat'),
          tooltip: repeatTooltip,
          style: style,
          isSelected: mode != PlayMode.forward,
          onPressed: onRepeat,
          icon: _animatedModeIcon(
            context,
            icon: switch (mode) {
              PlayMode.forward => Symbols.repeat,
              PlayMode.loop => Symbols.repeat_on,
              PlayMode.singleLoop => Symbols.repeat_one_on,
            },
          ),
        ),
      ]);
    }
    final height = appToolbarControlHeight(context);
    final innerHeight = math.max(36.0, height - 8);
    final outline =
        scheme.outlineVariant.withValues(alpha: isDark ? .38 : .46);
    final style = appToolbarControlStyle(context, iconOnly: true).copyWith(
      minimumSize: WidgetStatePropertyAll(Size(44, innerHeight)),
      fixedSize: WidgetStatePropertyAll(Size(44, innerHeight)),
      shape: const WidgetStatePropertyAll(AppShape.pill),
      side: const WidgetStatePropertyAll(BorderSide.none),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.selected)) {
          return scheme.primaryContainer;
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.secondaryContainer
              .withValues(alpha: isDark ? .40 : .52);
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.primary),
      iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.primary),
    );
    // Two independent IconButtons inside a unified capsule track retain the
    // selected repeat button's click: toggling a SegmentedButton off would lose
    // the single-loop step.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.pillRadius,
        border: Border.all(color: outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: const ValueKey('playback-mode-shuffle'),
            tooltip: shuffleTooltip,
            style: style,
            isSelected: shuffle,
            onPressed: onShuffle,
            icon: _animatedModeIcon(
              context,
              icon: shuffle ? Symbols.shuffle_on : Symbols.shuffle,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const ValueKey('playback-mode-repeat'),
            tooltip: repeatTooltip,
            style: style,
            isSelected: mode != PlayMode.forward,
            onPressed: onRepeat,
            icon: _animatedModeIcon(
              context,
              icon: mode == PlayMode.singleLoop
                  ? Symbols.repeat_one
                  : Symbols.repeat,
            ),
          ),
        ]),
      ),
    );
  }
}
