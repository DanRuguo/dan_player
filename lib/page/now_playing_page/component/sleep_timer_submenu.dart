import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SleepTimerSubmenu extends StatelessWidget {
  const SleepTimerSubmenu({super.key, this.playbackService});

  final PlaybackService? playbackService;

  static const presets = [10, 20, 30, 60, 90];

  String _format(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return "${hours.toString().padLeft(2, "0")}:"
          "${minutes.toString().padLeft(2, "0")}:"
          "${seconds.toString().padLeft(2, "0")}";
    }
    return "${minutes.toString().padLeft(2, "0")}:"
        "${seconds.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final service = playbackService ?? PlayService.instance.playbackService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.sleepTimerRemaining,
        service.stopAfterCurrent,
        service,
        service.queueStopBoundary,
        service.segmentLoop,
        service.playMode,
      ]),
      builder: (context, _) {
        final remaining = service.sleepTimerRemaining.value;
        final stopAfter = service.stopAfterCurrent.value;
        return SubmenuButton(
          leadingIcon: Icon(
            remaining != null || stopAfter || service.queueStopBoundary.active
                ? Symbols.bedtime
                : Symbols.bedtime_off,
          ),
          menuChildren: [
            for (final minutes in presets)
              MenuItemButton(
                onPressed: () => service.startSleepTimer(
                  Duration(minutes: minutes),
                ),
                leadingIcon: const Icon(Symbols.timer),
                child: Text(ui("{0} 分钟后", [minutes])),
              ),
            const Divider(),
            MenuItemButton(
              onPressed: () => service.setStopAfterCurrent(!stopAfter),
              leadingIcon: const Icon(Symbols.music_note),
              trailingIcon: stopAfter ? const Icon(Symbols.check) : null,
              child: Text(ui("播完当前歌曲后停止")),
            ),
            MenuItemButton(
              onPressed: service.playlist.value.isEmpty ||
                      service.queueStopBlockedReason != null
                  ? null
                  : service.stopAfterQueueRound,
              leadingIcon: const Icon(Symbols.stop_circle),
              child: Text(ui('播完设置时这轮队列后停止')),
            ),
            if (service.queueStopBoundary.active)
              MenuItemButton(
                  onPressed: service.cancelQueueStop,
                  leadingIcon: const Icon(Symbols.close),
                  child: Text(ui('取消停止目标'))),
            if (remaining != null) const Divider(),
            if (remaining != null)
              MenuItemButton(
                onPressed: service.cancelSleepTimer,
                leadingIcon: const Icon(Symbols.timer_off),
                child: Text(ui("取消倒计时（{0}）", [_format(remaining)])),
              ),
          ],
          child: Text(
            remaining == null
                ? ui("睡眠定时")
                : ui("睡眠定时 {0}", [_format(remaining)]),
          ),
        );
      },
    );
  }
}
