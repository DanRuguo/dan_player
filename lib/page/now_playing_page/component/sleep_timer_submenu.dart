import 'dart:math' as math;
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/player_number_dialog.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/sleep_timer.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SleepTimerSubmenu extends StatelessWidget {
  const SleepTimerSubmenu({super.key, this.playbackService});

  final PlaybackService? playbackService;

  static const presets = [10, 20, 30, 60, 90];

  Future<void> _custom(
      NavigatorState navigator, PlaybackService service) async {
    // Activating this item closes the outer "more" menu and disposes this
    // submenu's overlay before the callback. Use its captured host navigator.
    if (!navigator.mounted) return;
    final minutes = await showAppDialog<int>(
        context: navigator.context,
        builder: (_) => PlayerNumberDialog(
            title: ui('自定义睡眠定时'),
            label: ui('分钟'),
            value: (service.sleepTimerRemaining.value?.inMinutes ?? 30)
                .clamp(1, 1440),
            minimum: 1,
            maximum: 1440));
    if (minutes != null && navigator.mounted) {
      service.startSleepTimer(Duration(minutes: minutes));
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final service = playbackService ?? PlayService.instance.playbackService;
    final navigator = Navigator.of(context, rootNavigator: true);
    Widget label(String text, {bool time = false, bool enabled = true}) =>
        ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: math.max(
                    72, math.min(360, MediaQuery.sizeOf(context).width - 136))),
            child: Text(text,
                softWrap: true,
                style: time
                    ? TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: enabled ? 1 : .38))
                    : null));
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.sleepTimerRemaining,
        service.sleepTimerPaused,
        service.sleepTimerFinishCurrent,
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
                leadingIcon: SleepPresetIcon(minutes: minutes),
                child: label(ui("{0} 分钟后", [minutes]), time: true),
              ),
            MenuItemButton(
              key: const ValueKey('sleep-custom'),
              onPressed: () => _custom(navigator, service),
              leadingIcon: const Icon(Symbols.edit),
              child: label(ui('自定义睡眠定时')),
            ),
            MenuItemButton(
              key: const ValueKey('sleep-finish-current'),
              onPressed: () => service.setSleepTimerFinishCurrent(
                  !service.sleepTimerFinishCurrent.value),
              leadingIcon: const Icon(Symbols.nights_stay),
              trailingIcon: service.sleepTimerFinishCurrent.value
                  ? const Icon(Symbols.check)
                  : null,
              child: label(ui('倒计时结束后播完本曲')),
            ),
            const Divider(),
            MenuItemButton(
              onPressed: () => service.setStopAfterCurrent(!stopAfter),
              leadingIcon: const Icon(Symbols.music_note),
              trailingIcon: stopAfter ? const Icon(Symbols.check) : null,
              child: label(ui("播完当前歌曲后停止")),
            ),
            MenuItemButton(
              onPressed: service.playlist.value.isEmpty ||
                      service.queueStopBlockedReason != null
                  ? null
                  : service.stopAfterQueueRound,
              leadingIcon: const Icon(Symbols.stop_circle),
              child: label(ui('播完当前队列后停止')),
            ),
            if (service.queueStopBoundary.active)
              MenuItemButton(
                  onPressed: service.cancelQueueStop,
                  leadingIcon: const Icon(Symbols.close),
                  child: label(ui('取消停止目标'))),
            if (remaining != null) const Divider(),
            if (remaining != null) ...[
              MenuItemButton(
                key: const ValueKey('sleep-adjust-more'),
                onPressed: () =>
                    service.adjustSleepTimer(const Duration(minutes: 5)),
                leadingIcon: const Icon(Symbols.add),
                child: label(ui('延长 5 分钟'), time: true),
              ),
              MenuItemButton(
                key: const ValueKey('sleep-adjust-less'),
                onPressed: remaining > const Duration(minutes: 5)
                    ? () =>
                        service.adjustSleepTimer(const Duration(minutes: -5))
                    : null,
                leadingIcon: const Icon(Symbols.remove),
                child: label(ui('缩短 5 分钟'),
                    time: true,
                    enabled: remaining > const Duration(minutes: 5)),
              ),
              MenuItemButton(
                key: const ValueKey('sleep-toggle-paused'),
                onPressed: service.toggleSleepTimerPaused,
                leadingIcon: Icon(service.sleepTimerPaused.value
                    ? Symbols.play_arrow
                    : Symbols.pause),
                child: label(
                    ui(service.sleepTimerPaused.value ? '继续倒计时' : '暂停倒计时')),
              ),
            ],
            if (remaining != null)
              MenuItemButton(
                key: const ValueKey('sleep-menu-cancel'),
                onPressed: service.cancelSleepTimer,
                leadingIcon: const Icon(Symbols.timer_off),
                child: label(
                    ui("取消倒计时（{0}）", [formatSleepRemaining(remaining)]),
                    time: true),
              ),
          ],
          child: Text(
            style: remaining == null
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.primary),
            remaining == null
                ? ui("睡眠定时")
                : ui(service.sleepTimerPaused.value ? '倒计时已暂停 {0}' : "睡眠定时 {0}",
                    [formatSleepRemaining(remaining)]),
          ),
        );
      },
    );
  }
}

/// One timer outline with a different hand position for each duration.
class SleepPresetIcon extends StatelessWidget {
  const SleepPresetIcon({super.key, required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return ExcludeSemantics(
        child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
          painter: _SleepPresetPainter(
              minutes, theme.color ?? Theme.of(context).colorScheme.primary)),
    ));
  }
}

class _SleepPresetPainter extends CustomPainter {
  const _SleepPresetPainter(this.minutes, this.color);
  final int minutes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const center = Offset(12, 14);
    canvas.drawCircle(center, 8, paint);
    canvas.drawLine(const Offset(10, 2), const Offset(14, 2), paint);
    canvas.drawLine(const Offset(12, 2), const Offset(12, 4), paint);
    canvas.drawLine(const Offset(18.5, 5.5), const Offset(20, 4), paint);
    final angle = minutes / 120 * 2 * math.pi - math.pi / 2;
    canvas.drawLine(
        center, center + Offset(math.cos(angle), math.sin(angle)) * 4.8, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SleepPresetPainter oldDelegate) =>
      oldDelegate.minutes != minutes || oldDelegate.color != color;
}
