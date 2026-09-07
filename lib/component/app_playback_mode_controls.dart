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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shuffleTooltip = ui('随机；现在：{0}', [shuffle ? ui('启用') : ui('禁用')]);
    final repeatTooltip = ui('循环；现在：{0}', [
      switch (mode) {
        PlayMode.forward => ui('循环关闭'),
        PlayMode.loop => ui('列表循环'),
        PlayMode.singleLoop => ui('单曲循环'),
      }
    ]);
    if (plain) {
      final style = IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        fixedSize: const Size(44, 44),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.primary,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
        side: BorderSide.none,
        iconSize: 24,
      );
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: const ValueKey('playback-mode-shuffle'),
          tooltip: shuffleTooltip,
          style: style,
          isSelected: shuffle,
          onPressed: onShuffle,
          icon: Icon(shuffle ? Symbols.shuffle_on : Symbols.shuffle),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('playback-mode-repeat'),
          tooltip: repeatTooltip,
          style: style,
          isSelected: mode != PlayMode.forward,
          onPressed: onRepeat,
          icon: Icon(switch (mode) {
            PlayMode.forward => Symbols.repeat,
            PlayMode.loop => Symbols.repeat_on,
            PlayMode.singleLoop => Symbols.repeat_one_on,
          }),
        ),
      ]);
    }
    final height = appToolbarControlHeight(context);
    final outline = scheme.outlineVariant.withValues(alpha: .7);
    final style = appToolbarControlStyle(context, iconOnly: true).copyWith(
      fixedSize: WidgetStatePropertyAll(Size(44, height)),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      side: const WidgetStatePropertyAll(BorderSide.none),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.primary),
    );
    // Two independent IconButtons retain the selected repeat button's click:
    // toggling a selected SegmentedButton off would lose the single-loop step.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppShape.controlRadius,
        border: Border.all(color: outline),
      ),
      position: DecorationPosition.foreground,
      child: ClipRRect(
        borderRadius: AppShape.controlRadius,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: const ValueKey('playback-mode-shuffle'),
            tooltip: shuffleTooltip,
            style: style,
            isSelected: shuffle,
            onPressed: onShuffle,
            icon: const Icon(Symbols.shuffle),
          ),
          SizedBox(width: 1, height: height, child: ColoredBox(color: outline)),
          IconButton(
            key: const ValueKey('playback-mode-repeat'),
            tooltip: repeatTooltip,
            style: style,
            isSelected: mode != PlayMode.forward,
            onPressed: onRepeat,
            icon: Icon(mode == PlayMode.singleLoop
                ? Symbols.repeat_one
                : Symbols.repeat),
          ),
        ]),
      ),
    );
  }
}
