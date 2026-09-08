import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Shared by the queue and playback area; the marker belongs to the service,
/// so closing either surface cannot lose the target or change playback mode.
class QueueStopStatus extends StatelessWidget {
  const QueueStopStatus({super.key, this.playbackService});
  final PlaybackService? playbackService;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final service = playbackService ?? PlayService.instance.playbackService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        service,
        service.queueStopBoundary,
        service.segmentLoop,
        service.playMode
      ]),
      builder: (context, _) {
        final label = service.queueStopTargetLabel;
        if (label == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final blocked = service.queueStopBlockedReason;
        final text = ui('播放完此曲后停止：{0}', [label]);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(children: [
            Icon(blocked == null ? Symbols.stop_circle : Symbols.info,
                size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Tooltip(
                    message: blocked == null ? text : '$text\n${ui(blocked)}',
                    child: Text(
                        blocked == null ? text : '$text · ${ui(blocked)}',
                        key: const ValueKey('queue-stop-target'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.primary)))),
            IconButton(
                key: const ValueKey('queue-cancel-stop'),
                tooltip: ui('取消停止目标'),
                onPressed: service.cancelQueueStop,
                visualDensity: VisualDensity.compact,
                icon: Icon(Symbols.close, size: 18, color: scheme.primary)),
          ]),
        );
      },
    );
  }
}
