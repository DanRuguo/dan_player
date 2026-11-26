import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Identifies one explicit locate-current-track event for a list page.
typedef LocatedTrackPulse = ({String path, int token});

/// Broadcasts locate-current-track pulses to visible [PlayingAudioListRow]s
/// without forcing list rebuilds or allocating controllers for idle rows.
class LocatedTrackPulseScope extends InheritedWidget {
  const LocatedTrackPulseScope({
    super.key,
    required this.pulse,
    required super.child,
  });

  final ValueListenable<LocatedTrackPulse?> pulse;

  static ValueListenable<LocatedTrackPulse?>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LocatedTrackPulseScope>()
          ?.pulse;

  @override
  bool updateShouldNotify(LocatedTrackPulseScope oldWidget) =>
      !identical(pulse, oldWidget.pulse);
}

/// Opted into by the music and playlist list views only. Playback events change
/// the state layer without rebuilding metadata, menus or decoded artwork.
class PlayingAudioListRow extends StatelessWidget {
  const PlayingAudioListRow({
    super.key,
    required this.audioPath,
    required this.child,
    this.nowPlayingPath,
  });

  final String audioPath;
  final Widget child;

  /// Allows isolated rendering without constructing the native player.
  final ValueListenable<String?>? nowPlayingPath;

  @override
  Widget build(BuildContext context) {
    final source = nowPlayingPath;
    if (source != null) {
      return _CurrentRow(
          audioPath: audioPath,
          source: source,
          isCurrent: () => source.value == audioPath,
          child: child);
    }
    return PlaybackReadyBuilder(
      waitingBuilder: (_) => child,
      readyBuilder: (_) {
        final playback = PlayService.instance.playbackService;
        return _CurrentRow(
            audioPath: audioPath,
            source: playback,
            isCurrent: () => playback.nowPlaying?.path == audioPath,
            child: child);
      },
    );
  }
}

class _CurrentRow extends StatefulWidget {
  const _CurrentRow({
    required this.audioPath,
    required this.source,
    required this.isCurrent,
    required this.child,
  });
  final String audioPath;
  final Listenable source;
  final bool Function() isCurrent;
  final Widget child;

  @override
  State<_CurrentRow> createState() => _CurrentRowState();
}

class _CurrentRowState extends State<_CurrentRow>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _pulseDuration = Duration(milliseconds: 720);

  late bool _current = widget.isCurrent();
  ValueListenable<LocatedTrackPulse?>? _pulseSource;
  AnimationController? _pulseController;
  int _lastPulseToken = -1;
  AppLifecycleState? _lifecycle;

  bool get _hidden =>
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached;

  bool get _platformReducedMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  bool _canPulse(BuildContext context) =>
      !_hidden &&
      TickerMode.valuesOf(context).enabled &&
      AppMotion.enabled(context, MotionKind.feedback) &&
      !_platformReducedMotion;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.source.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPulse = LocatedTrackPulseScope.maybeOf(context);
    if (!identical(_pulseSource, nextPulse)) {
      _pulseSource?.removeListener(_onPulse);
      _pulseSource = nextPulse;
      _pulseSource?.addListener(_onPulse);
      _onPulse();
    }
    if (!_canPulse(context)) _stopPulse();
  }

  void _changed() {
    final current = widget.isCurrent();
    if (current != _current) setState(() => _current = current);
  }

  void _onPulse() {
    if (!mounted) return;
    final event = _pulseSource?.value;
    if (event == null ||
        event.path != widget.audioPath ||
        event.token == _lastPulseToken) {
      return;
    }
    _lastPulseToken = event.token;
    if (!_canPulse(context)) {
      _stopPulse();
      return;
    }
    var created = false;
    final controller = _pulseController ??= () {
      created = true;
      return AnimationController(vsync: this, duration: _pulseDuration);
    }();
    controller.forward(from: 0);
    if (created) setState(() {});
  }

  void _stopPulse() {
    final controller = _pulseController;
    if (controller == null) return;
    if (controller.isAnimating) controller.stop();
    if (controller.value != 1) controller.value = 1;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (_hidden) _stopPulse();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducedMotion) _stopPulse();
  }

  @override
  void didUpdateWidget(_CurrentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_changed);
      widget.source.addListener(_changed);
    }
    if (oldWidget.audioPath != widget.audioPath) {
      _lastPulseToken = -1;
      _stopPulse();
      _onPulse();
    }
    _current = widget.isCurrent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseSource?.removeListener(_onPulse);
    widget.source.removeListener(_changed);
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    const rowRadius = BorderRadius.all(Radius.circular(14));
    final activeBase =
        scheme.primaryContainer.withValues(alpha: isDark ? .24 : .34);
    final activeSide = BorderSide(
      color: scheme.primary.withValues(alpha: isDark ? .26 : .20),
    );
    final controller = _pulseController;
    if (controller == null) {
      return Material(
        color: _current ? activeBase : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: rowRadius,
          side: _current ? activeSide : BorderSide.none,
        ),
        animationDuration:
            AppMotion.duration(context, MotionKind.feedback, AppMotion.quick),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = controller.value.clamp(0.0, 1.0);
        final wave =
            t >= 1 ? 0.0 : math.pow(math.sin(math.pi * t), 2).toDouble();
        final baseColor = _current ? activeBase : Colors.transparent;
        final color = wave > 0
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: .16 * wave),
                baseColor,
              )
            : baseColor;
        final shape = RoundedRectangleBorder(
          borderRadius: rowRadius,
          side: wave > .01
              ? BorderSide(
                  color: scheme.primary.withValues(alpha: .38 * wave),
                  width: 1.2,
                )
              : (_current ? activeSide : BorderSide.none),
        );
        return Material(
          color: color,
          shape: shape,
          animationDuration: wave > 0
              ? Duration.zero
              : AppMotion.duration(
                  context,
                  MotionKind.feedback,
                  AppMotion.quick,
                ),
          child: child,
        );
      },
    );
  }
}
