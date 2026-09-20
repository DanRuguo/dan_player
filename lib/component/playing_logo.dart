import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/player_logo.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A passive title-bar decoration: never initializes playback or reads audio.
class PlayingLogo extends StatelessWidget {
  const PlayingLogo({super.key});
  @override
  Widget build(BuildContext context) {
    const icon = PlayerLogo();
    return PlaybackReadyBuilder(
      waitingBuilder: (_) => icon,
      readyBuilder: (_) {
        final playback = PlayService.instance.playbackService;
        return StreamBuilder<PlayerState>(
          stream: playback.playerStateStream,
          initialData: playback.playerState,
          builder: (_, state) => PlayingLogoMotion(
            playing: state.data == PlayerState.playing,
            hidden: DesktopIntegration.instance.isHidden,
            child: icon,
          ),
        );
      },
    );
  }
}

class PlayingLogoMotion extends StatefulWidget {
  const PlayingLogoMotion(
      {super.key, required this.child, required this.playing, this.hidden});
  final Widget child;
  final bool playing;
  final ValueListenable<bool>? hidden;
  @override
  State<PlayingLogoMotion> createState() => _PlayingLogoMotionState();
}

class _PlayingLogoMotionState extends State<PlayingLogoMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _turns =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));
  ValueListenable<RenderingPreferences>? _rendering;
  AppLifecycleState? _lifecycle;
  bool _visible = false;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rendering = RenderingPreferencesScope.listenableOf(context);
    if (_rendering != rendering) {
      _rendering?.removeListener(_sync);
      _rendering = rendering..addListener(_sync);
    }
    _visible = TickerMode.valuesOf(context).enabled;
    _allowed = AppMotion.enabled(context, MotionKind.playingLogo);
    _sync();
  }

  @override
  void didUpdateWidget(PlayingLogoMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) {
      oldWidget.hidden?.removeListener(_sync);
      widget.hidden?.addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _sync();
  }

  @override
  void didChangeAccessibilityFeatures() => _sync();
  void _sync() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final active = widget.playing &&
        _visible &&
        _allowed &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        !(widget.hidden?.value ?? false) &&
        _lifecycle != AppLifecycleState.hidden &&
        _lifecycle != AppLifecycleState.paused &&
        _lifecycle != AppLifecycleState.detached &&
        (_rendering?.value.animations.allows(MotionKind.playingLogo) ?? true);
    if (active && !_turns.isAnimating) {
      _turns.repeat();
    } else if (!active && _turns.isAnimating) {
      _turns.stop();
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: RotationTransition(
            turns: _turns, child: RepaintBoundary(child: widget.child)),
      );
  @override
  void dispose() {
    widget.hidden?.removeListener(_sync);
    _rendering?.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _turns.dispose();
    super.dispose();
  }
}
