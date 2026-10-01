import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/sleep_timer.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The queue's single status area for every sleep timer and stop boundary.
/// Both queue presentations share this widget; playback timelines never host it.
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
        service.playMode,
        service.sleepTimerRemaining,
        service.sleepTimerPaused,
        service.stopAfterCurrent,
      ]),
      builder: (context, _) {
        final label = service.queueStopTargetLabel;
        final remaining = service.sleepTimerRemaining.value;
        if (label == null &&
            remaining == null &&
            !service.stopAfterCurrent.value) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final blocked = service.queueStopBlockedReason;
        final text =
            label == null ? ui('播完当前歌曲后停止') : ui('播放完此曲后停止：{0}', [label]);
        final paused = service.sleepTimerPaused.value;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (remaining != null)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(children: [
                  Icon(Symbols.bedtime, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          ui(paused ? '倒计时已暂停 {0}' : '睡眠定时 {0}',
                              [formatSleepRemaining(remaining)]),
                          key: const ValueKey('sleep-timer-status'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.primary))),
                  IconButton(
                      key: const ValueKey('sleep-status-pause'),
                      tooltip: ui(paused ? '继续倒计时' : '暂停倒计时'),
                      onPressed: service.toggleSleepTimerPaused,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(paused ? Symbols.play_arrow : Symbols.pause,
                          size: 18)),
                  IconButton(
                      key: const ValueKey('sleep-status-cancel'),
                      tooltip: ui('取消倒计时'),
                      onPressed: service.cancelSleepTimer,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.close, size: 18)),
                ])),
          if (label != null || service.stopAfterCurrent.value)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(children: [
                Icon(blocked == null ? Symbols.stop_circle : Symbols.info,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Tooltip(
                        message:
                            blocked == null ? text : '$text\n${ui(blocked)}',
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
                    onPressed: label == null
                        ? () => service.setStopAfterCurrent(false)
                        : service.cancelQueueStop,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Symbols.close, size: 18, color: scheme.primary)),
              ]),
            )
        ]);
      },
    );
  }
}
