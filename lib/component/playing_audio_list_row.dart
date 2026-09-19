import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
          source: source,
          isCurrent: () => source.value == audioPath,
          child: child);
    }
    return PlaybackReadyBuilder(
      waitingBuilder: (_) => child,
      readyBuilder: (_) {
        final playback = PlayService.instance.playbackService;
        return _CurrentRow(
            source: playback,
            isCurrent: () => playback.nowPlaying?.path == audioPath,
            child: child);
      },
    );
  }
}

class _CurrentRow extends StatefulWidget {
  const _CurrentRow(
      {required this.source, required this.isCurrent, required this.child});
  final Listenable source;
  final bool Function() isCurrent;
  final Widget child;

  @override
  State<_CurrentRow> createState() => _CurrentRowState();
}

class _CurrentRowState extends State<_CurrentRow> {
  late bool _current = widget.isCurrent();

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_changed);
  }

  void _changed() {
    final current = widget.isCurrent();
    if (current != _current) setState(() => _current = current);
  }

  @override
  void didUpdateWidget(_CurrentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_changed);
      widget.source.addListener(_changed);
    }
    _current = widget.isCurrent();
  }

  @override
  void dispose() {
    widget.source.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _current
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .06)
            : Colors.transparent,
        borderRadius: AppShape.controlRadius,
        animationDuration:
            AppMotion.duration(context, MotionKind.feedback, AppMotion.quick),
        child: widget.child,
      );
}
