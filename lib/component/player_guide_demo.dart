import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/viewport_visibility.dart';
import 'package:dan_player/component/player_guide_playlist_demo.dart';
import 'package:dan_player/component/player_guide_cover_demo.dart';
import 'package:dan_player/component/primary_pointer_input.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum PlayerGuideDemoKind {
  progress,
  lyrics,
  playlists,
  transitions,
  statistics,
  spectrum,
  cover
}

/// Small, local examples: no audio, network, library or preferences are changed.
/// Animations start only after input and finish once; losing visibility settles
/// them immediately instead of retaining an offscreen animation clock.
class PlayerGuideDemo extends StatefulWidget {
  const PlayerGuideDemo(
      {super.key, required this.kind, this.isHidden, this.layoutChanges});
  final PlayerGuideDemoKind kind;
  final ValueListenable<bool>? isHidden;

  /// Layout notifications from the owning guide, without a periodic monitor.
  final Listenable? layoutChanges;

  @override
  State<PlayerGuideDemo> createState() => _PlayerGuideDemoState();
}

class _PlayerGuideDemoState extends State<PlayerGuideDemo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _surface = GlobalKey();
  final _motionGate = ValueNotifier(false);
  late final AnimationController _animation =
      AnimationController(vsync: this, value: _initialValue(widget.kind));
  late ValueListenable<bool> _hidden;
  Set<ScrollPosition> _scrollPositions = {};
  bool _visible = false, _treeVisible = true, _queued = false;
  bool _lifecycleVisible = true;
  bool _changingLine = false;
  int _line = 0;
  late double _target = _initialValue(widget.kind);
  PlaybackTransitionMode _transition = PlaybackTransitionMode.crossfade;
  SpectrumStyle _spectrumStyle = SpectrumStyle.pixel;

  static double _initialValue(PlayerGuideDemoKind kind) => switch (kind) {
        PlayerGuideDemoKind.progress => .32,
        PlayerGuideDemoKind.transitions => 0,
        PlayerGuideDemoKind.spectrum => 0,
        _ => 1,
      };

  static const _lyricLines = ['音乐|点亮|每一天', '下一句|轻轻|向上浮起'];
  // A frozen local example uses the real chart without reading listening data.
  static final _statisticsSnapshot = ListeningTrendsSnapshot.fromDaily(
      capturedAt: DateTime(2026, 10, 7, 12),
      dailyMilliseconds: {
        for (var day = 1; day <= 180; day++)
          listeningDayKey(DateTime(2026, 10, 7 - day)):
              day % 6 == 0 ? 0 : (day % 9 + 1) * 600000,
      });

  MotionKind get _motion => switch (widget.kind) {
        PlayerGuideDemoKind.progress => MotionKind.layout,
        PlayerGuideDemoKind.lyrics => MotionKind.lyrics,
        PlayerGuideDemoKind.playlists => MotionKind.tracking,
        PlayerGuideDemoKind.transitions => MotionKind.layout,
        PlayerGuideDemoKind.statistics => MotionKind.layout,
        PlayerGuideDemoKind.spectrum => MotionKind.feedback,
        PlayerGuideDemoKind.cover => MotionKind.feedback,
      };

  @override
  void initState() {
    super.initState();
    _hidden = widget.isHidden ?? DesktopIntegration.instance.isHidden;
    _hidden.addListener(_applyVisibility);
    widget.layoutChanges?.addListener(_layoutChanged);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleVisible = lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant PlayerGuideDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutChanges != widget.layoutChanges) {
      oldWidget.layoutChanges?.removeListener(_layoutChanged);
      widget.layoutChanges?.addListener(_layoutChanged);
      _layoutChanged();
    }
    if (oldWidget.isHidden != widget.isHidden) {
      _hidden.removeListener(_applyVisibility);
      _hidden = widget.isHidden ?? DesktopIntegration.instance.isHidden;
      _hidden.addListener(_applyVisibility);
    }
    if (oldWidget.kind != widget.kind) {
      _animation.stop();
      _target = _initialValue(widget.kind);
      _animation.value = _target;
      _line = 0;
      _changingLine = false;
    }
    _applyVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final positions = scrollPositionsOf(context);
    for (final position in _scrollPositions.difference(positions)) {
      position.removeListener(_scheduleVisibility);
    }
    for (final position in positions.difference(_scrollPositions)) {
      position.addListener(_scheduleVisibility);
    }
    _scrollPositions = positions;
    _applyVisibility();
    _scheduleVisibility();
  }

  bool get _canAnimate {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return _visible &&
        _treeVisible &&
        _lifecycleVisible &&
        !_hidden.value &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        AppMotion.enabled(context, _motion);
  }

  void _settle() {
    if (!_animation.isAnimating) return;
    _animation.stop();
    _animation.value = _target;
  }

  void _applyVisibility() {
    if (!mounted) return;
    final enabled = _canAnimate;
    if (_motionGate.value != enabled) _motionGate.value = enabled;
    if (!enabled) _settle();
  }

  void _scheduleVisibility() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      _checkViewport();
    });
  }

  void _layoutChanged() {
    _scheduleVisibility();
    // Scroll metrics arrive after the layout frame, possibly its last one.
    // Request only the coalesced check's frame; idle demos own no clock.
    if (mounted) WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkViewport() {
    _visible = intersectsPaintViewport(
        _surface.currentContext?.findRenderObject(),
        MediaQuery.sizeOf(context));
    _applyVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleVisible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _applyVisibility();
  }

  @override
  void didChangeAccessibilityFeatures() => _applyVisibility();

  void _animate(double target, Duration duration) {
    _target = target;
    _checkViewport();
    if (_canAnimate) {
      _animation.animateTo(target,
          duration: duration, curve: AppMotion.standardCurve);
    } else {
      _animation.value = target;
    }
  }

  void _highlight() {
    setState(() => _changingLine = false);
    _animation.value = 0;
    _animate(1, const Duration(milliseconds: 1800));
  }

  void _nextLine() {
    setState(() {
      _changingLine = true;
      _line = 1 - _line;
    });
    _animation.value = 0;
    _animate(1, AppMotion.lyricLine);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final position in _scrollPositions) {
      position.removeListener(_scheduleVisibility);
    }
    _hidden.removeListener(_applyVisibility);
    widget.layoutChanges?.removeListener(_layoutChanged);
    _animation.dispose();
    _motionGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final colors = Theme.of(context).colorScheme;
    _scheduleVisibility();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DecoratedBox(
            key: widget.kind == PlayerGuideDemoKind.playlists ||
                    widget.kind == PlayerGuideDemoKind.cover
                ? null
                : _surface,
            decoration: ShapeDecoration(
                color: colors.surfaceContainerLow,
                shape: AppShape.surface
                    .copyWith(side: BorderSide(color: colors.outlineVariant))),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          ui(switch (widget.kind) {
                            PlayerGuideDemoKind.progress => '试一试：进度定位',
                            PlayerGuideDemoKind.lyrics => '试一试：歌词动效',
                            PlayerGuideDemoKind.playlists => '试一试：歌单视图',
                            PlayerGuideDemoKind.transitions => '试一试：歌曲过渡',
                            PlayerGuideDemoKind.statistics => '试一试：收听趋势',
                            PlayerGuideDemoKind.spectrum => '试一试：频谱动效',
                            PlayerGuideDemoKind.cover => '试一试：封面动效',
                          }),
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                          ui(widget.kind == PlayerGuideDemoKind.statistics
                              ? '这里使用固定示例记录。可以切换范围和曲线，点按日期或用方向键查看；不会读取或保存你的听歌记录。'
                              : '仅本卡片演示，不播放声音、不联网，也不修改曲库或设置。'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      if (widget.kind == PlayerGuideDemoKind.playlists)
                        ValueListenableBuilder(
                            valueListenable: _motionGate,
                            child:
                                PlayerGuidePlaylistDemo(viewportKey: _surface),
                            builder: (context, enabled, child) =>
                                TickerMode(enabled: enabled, child: child!))
                      else if (widget.kind == PlayerGuideDemoKind.transitions)
                        _transitions(context)
                      else if (widget.kind == PlayerGuideDemoKind.statistics)
                        StatisticsListeningTrends(snapshot: _statisticsSnapshot)
                      else if (widget.kind == PlayerGuideDemoKind.spectrum)
                        _spectrum(context)
                      else if (widget.kind == PlayerGuideDemoKind.cover)
                        PlayerGuideCoverDemo(
                            viewportKey: _surface,
                            motionEnabled: _motionGate,
                            isHidden: _hidden)
                      else
                        AnimatedBuilder(
                            animation: _animation,
                            builder: (context, _) =>
                                widget.kind == PlayerGuideDemoKind.progress
                                    ? _progress(context)
                                    : _lyrics(context)),
                    ]))));
  }

  Widget _spectrum(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSegmentedControl<SpectrumStyle>(
          key: const ValueKey('guide-demo-spectrum-style'),
          value: _spectrumStyle,
          options: [
            AppSegmentOption(
                value: SpectrumStyle.rounded,
                label: ui('圆头音柱'),
                icon: Icons.equalizer_rounded),
            AppSegmentOption(
                value: SpectrumStyle.pixel,
                label: ui('像素音柱'),
                icon: Icons.grid_view_rounded),
          ],
          onChanged: (style) => setState(() => _spectrumStyle = style)),
      const SizedBox(height: 12),
      Semantics(
          label: ui('频谱显隐示意'),
          excludeSemantics: true,
          child: RepaintBoundary(
              child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) {
                    final envelope = math.sin(_animation.value * math.pi);
                    return SizedBox(
                        height: 72,
                        child: CustomPaint(
                            painter: FrequencySpectrumPainter(
                                levels: AlwaysStoppedAnimation(
                                    List<double>.generate(
                                        36,
                                        (i) =>
                                            envelope *
                                            envelope *
                                            (.35 +
                                                .65 *
                                                    math
                                                        .sin(i * .4 +
                                                            _animation.value *
                                                                6)
                                                        .abs()),
                                        growable: false)),
                                maximumBars: 36,
                                style: _spectrumStyle,
                                pixelRatio:
                                    MediaQuery.devicePixelRatioOf(context),
                                startColor: colors.primary,
                                endColor: colors.tertiary)));
                  }))),
      const SizedBox(height: 8),
      Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
              key: const ValueKey('guide-demo-spectrum-start'),
              onPressed: () {
                _animation.value = 0;
                _animate(1, const Duration(milliseconds: 1800));
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(ui('演示音柱显隐')))),
    ]);
  }

  String _stamp(double value) {
    final seconds = (value * 180).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _transitions(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSegmentedControl<PlaybackTransitionMode>(
            key: const ValueKey('guide-demo-transition-mode'),
            value: _transition,
            wrapCompactLabel: true,
            semanticLabel: ui('歌曲过渡'),
            options: [
              AppSegmentOption(
                  value: PlaybackTransitionMode.standard,
                  label: ui('常规切换'),
                  icon: Icons.skip_next_outlined),
              AppSegmentOption(
                  value: PlaybackTransitionMode.gapless,
                  label: ui('连续输出'),
                  icon: Icons.link_outlined),
              AppSegmentOption(
                  value: PlaybackTransitionMode.crossfade,
                  label: ui('交叉淡入淡出'),
                  icon: Icons.merge_outlined),
            ],
            onChanged: (mode) {
              _animation.stop();
              setState(() => _transition = mode);
              _target = 0;
              _animation.value = 0;
            }),
        const SizedBox(height: 16),
        AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final progress = _animation.value;
              final overlap = ((progress - .35) / .3).clamp(0.0, 1.0);
              final outgoing = switch (_transition) {
                PlaybackTransitionMode.standard => progress < .45 ? 1.0 : 0.0,
                PlaybackTransitionMode.gapless => progress < .5 ? 1.0 : 0.0,
                PlaybackTransitionMode.crossfade => 1 - overlap,
              };
              final incoming = switch (_transition) {
                PlaybackTransitionMode.standard => progress >= .55 ? 1.0 : 0.0,
                PlaybackTransitionMode.gapless => progress >= .5 ? 1.0 : 0.0,
                PlaybackTransitionMode.crossfade => overlap,
              };
              return Column(children: [
                _transitionTrack(context, '当前歌曲', outgoing, 'current'),
                const SizedBox(height: 12),
                _transitionTrack(context, '下一首歌曲', incoming, 'next'),
              ]);
            }),
        const SizedBox(height: 12),
        Text(ui('音量交接示意；实际效果取决于歌曲与输出设备。'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
                key: const ValueKey('guide-demo-transition-start'),
                onPressed: () {
                  _animation.value = 0;
                  _animate(1, const Duration(milliseconds: 2400));
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(ui('演示歌曲过渡')))),
      ]);

  Widget _transitionTrack(
      BuildContext context, String title, double gain, String id) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(ui(title)),
      const SizedBox(height: 6),
      LinearProgressIndicator(
          key: ValueKey('guide-demo-transition-$id'),
          value: gain,
          minHeight: 10,
          borderRadius: AppShape.controlRadius,
          color: id == 'current' ? colors.primary : colors.tertiary,
          backgroundColor: colors.surfaceContainerHighest,
          semanticsLabel: '${ui(title)} · ${ui('示意音量')}'),
    ]);
  }

  Widget _progress(BuildContext context) => Column(children: [
        Semantics(
            label: ui('演示进度定位'),
            child: PrimaryPointerInput(
                child: Slider(
                    key: const ValueKey('guide-demo-progress-slider'),
                    value: _animation.value,
                    label: _stamp(_animation.value),
                    semanticFormatterCallback: _stamp,
                    onChanged: (value) {
                      _animation.stop();
                      _target = value;
                      _animation.value = value;
                    }))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_stamp(_animation.value),
              key: const ValueKey('guide-demo-progress-time')),
          const Text('3:00'),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
              key: const ValueKey('guide-demo-seek-back'),
              onPressed: () => _animate(
                  (_animation.value - 10 / 180).clamp(0, 1),
                  AppMotion.standard),
              icon: const Icon(Icons.replay_10_outlined, size: 18),
              label: Text(ui('后退 10 秒'))),
          OutlinedButton.icon(
              key: const ValueKey('guide-demo-seek-forward'),
              onPressed: () => _animate(
                  (_animation.value + 10 / 180).clamp(0, 1),
                  AppMotion.standard),
              icon: const Icon(Icons.forward_10_outlined, size: 18),
              label: Text(ui('前进 10 秒'))),
        ]),
      ]);

  Widget _lyricText(BuildContext context, int line, double progress) {
    final words = ui(_lyricLines[line]).split('|');
    final colors = Theme.of(context).colorScheme;
    return Text.rich(
        TextSpan(children: [
          for (var index = 0; index < words.length; index++)
            TextSpan(
                text: '${words[index]}${index + 1 < words.length ? ' ' : ''}',
                style: TextStyle(
                    color: Color.lerp(colors.onSurfaceVariant, colors.primary,
                        (progress * words.length - index).clamp(0, 1)))),
        ]),
        key: ValueKey('guide-demo-lyric-line-$line'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium);
  }

  Widget _lyrics(BuildContext context) {
    final progress = _animation.value;
    final words = ui(_lyricLines[_line]).split('|').join(' ');
    return Column(children: [
      Semantics(
          label: ui('演示歌词：{0}', [words]),
          excludeSemantics: true,
          child: ClipRect(
              child: Stack(alignment: Alignment.center, children: [
            if (_changingLine && progress < 1)
              Opacity(
                  // Retire the old baseline before a multiline arrival reaches it.
                  opacity: 1 - const Interval(0, .6).transform(progress),
                  child: FractionalTranslation(
                      translation: Offset(0, -1.2 * progress),
                      child: _lyricText(context, 1 - _line, 1))),
            Opacity(
                opacity: _changingLine ? progress : 1,
                child: FractionalTranslation(
                    translation:
                        Offset(0, _changingLine ? 1.2 * (1 - progress) : 0),
                    child: _lyricText(
                        context, _line, _changingLine ? 1 : progress))),
          ]))),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
            key: const ValueKey('guide-demo-highlight'),
            onPressed: _highlight,
            icon: const Icon(Icons.format_color_text, size: 18),
            label: Text(ui('演示逐词强调'))),
        OutlinedButton.icon(
            key: const ValueKey('guide-demo-next-line'),
            onPressed: _nextLine,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            label: Text(ui('演示换句'))),
      ]),
    ]);
  }
}
