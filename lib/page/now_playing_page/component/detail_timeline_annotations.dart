import 'dart:math' as math;

import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

String detailTimelineTime(double seconds) {
  final value = seconds.isFinite ? math.max(0, seconds.floor()) : 0;
  final hours = value ~/ 3600;
  final minutes = (value ~/ 60) % 60;
  final remainder = (value % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$remainder'
      : '$minutes:$remainder';
}

/// A small, bounded number of readable divisions; their time is always media
/// time, including CUE-relative tracks. No synthetic waveform or playback clock.
List<double> detailTimelineTicks(double duration, double width,
    {double textScale = 1}) {
  if (!duration.isFinite || duration < 600 || width < 150) return const [];
  final slots = (width / (80 * textScale.clamp(1, 3))).floor().clamp(1, 8);
  if (slots < 2) return const [];
  final target = duration / slots;
  const steps = [60, 120, 300, 600, 900, 1800, 3600, 7200, 14400];
  final step = steps.firstWhere((value) => value >= target,
      orElse: () => (target / 3600).ceil() * 3600);
  return [
    for (var at = step.toDouble(); at < duration; at += step) at,
  ];
}

/// Bookmark hit targets live above the Slider, so inspecting a marker cannot
/// accidentally start a drag. Dense markers remain reachable through the time
/// menu, where every saved point has a separate accessible action.
class DetailTimelineAnnotations extends StatelessWidget {
  const DetailTimelineAnnotations({
    super.key,
    required this.duration,
    required this.bookmarks,
    required this.onBookmark,
    this.loopStart,
    this.loopEnd,
    this.loopEnabled = false,
  });
  final double duration;
  final List<PlaybackBookmark> bookmarks;
  final ValueChanged<PlaybackBookmark>? onBookmark;
  final double? loopStart, loopEnd;
  final bool loopEnabled;

  @override
  Widget build(BuildContext context) {
    final valid = bookmarks.where((b) => b.fitsDuration(duration)).toList();
    final hasLoop = loopStart != null &&
        loopEnd != null &&
        loopStart!.isFinite &&
        loopEnd!.isFinite &&
        loopStart! >= 0 &&
        loopEnd! > loopStart! &&
        loopEnd! <= duration;
    if (valid.isEmpty && !hasLoop) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x(double seconds) =>
            width * (rtl ? 1 - seconds / duration : seconds / duration);
        // Only one hit area per physical neighborhood; the menu preserves
        // access to all bookmarks even at the minimum practical window width.
        final visible = <PlaybackBookmark>[];
        final sorted = List<PlaybackBookmark>.of(valid)
          ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
        for (final bookmark in sorted) {
          if (visible.isEmpty ||
              (x(bookmark.position) - x(visible.last.position)).abs() >= 28) {
            visible.add(bookmark);
          }
        }
        return SizedBox(
          height: 28,
          child: Stack(clipBehavior: Clip.none, children: [
            if (hasLoop)
              Positioned.fill(
                child: Tooltip(
                  message: ui('A-B 循环：{0} – {1}', [
                    detailTimelineTime(loopStart!),
                    detailTimelineTime(loopEnd!),
                  ]),
                  child: CustomPaint(
                    key: const ValueKey('detail-progress-loop-range'),
                    painter: _LoopPainter(
                      start: x(loopStart!),
                      end: x(loopEnd!),
                      color: loopEnabled ? scheme.primary : scheme.outline,
                      enabled: loopEnabled,
                      textStyle: Theme.of(context).textTheme.labelSmall!,
                    ),
                  ),
                ),
              ),
            for (final bookmark in visible)
              Positioned(
                left: (x(bookmark.position) - 14).clamp(-14.0, width - 14),
                top: 0,
                width: 28,
                height: 28,
                child: Tooltip(
                  message: ui('播放书签：{0}', [
                    '${bookmark.label} · ${detailTimelineTime(bookmark.position)}'
                  ]),
                  child: Semantics(
                    button: true,
                    label: ui('播放书签：{0}', [bookmark.label]),
                    child: InkResponse(
                      key: ValueKey('detail-progress-bookmark-${bookmark.id}'),
                      radius: 14,
                      onTap: onBookmark == null
                          ? null
                          : () => onBookmark!(bookmark),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.bookmark_rounded,
                            size: 15, color: scheme.tertiary),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _LoopPainter extends CustomPainter {
  const _LoopPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.enabled,
    required this.textStyle,
  });
  final double start, end;
  final Color color;
  final bool enabled;
  final TextStyle textStyle;
  @override
  void paint(Canvas canvas, Size size) {
    final left = math.min(start, end), right = math.max(start, end);
    final paint = Paint()
      ..color = color.withValues(alpha: enabled ? .7 : .35)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, 23), Offset(right, 23), paint);
    for (final x in [left, right]) {
      canvas.drawLine(Offset(x, 19), Offset(x, 26), paint..strokeWidth = 2);
    }
    if (right - left > 26) {
      for (final pair in [(start, 'A'), (end, 'B')]) {
        final text = TextPainter(
            text: TextSpan(
                text: pair.$2,
                style: textStyle.copyWith(fontSize: 10, color: color)),
            textDirection: TextDirection.ltr)
          ..layout();
        text.paint(canvas, Offset(pair.$1 - text.width / 2, 6));
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_LoopPainter old) =>
      start != old.start ||
      end != old.end ||
      color != old.color ||
      enabled != old.enabled ||
      textStyle != old.textStyle;
}

class DetailTimelineScale extends StatelessWidget {
  const DetailTimelineScale({super.key, required this.duration});
  final double duration;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: LayoutBuilder(builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final times = detailTimelineTicks(duration, constraints.maxWidth,
              textScale: scaler.scale(12) / 12);
          if (times.isEmpty) return const SizedBox.shrink();
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return SizedBox(
            height: scaler.scale(10) + 8,
            child: Stack(children: [
              for (final at in times)
                Positioned(
                  left: (constraints.maxWidth *
                              (rtl ? 1 - at / duration : at / duration) -
                          38 * scaler.scale(10) / 10)
                      .clamp(
                          0.0,
                          math.max(
                              0,
                              constraints.maxWidth -
                                  76 * scaler.scale(10) / 10)),
                  width: 76 * scaler.scale(10) / 10,
                  child: Text(detailTimelineTime(at),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary)),
                ),
            ]),
          );
        }),
      );
}
