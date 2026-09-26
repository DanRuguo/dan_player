import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ListeningCalendarCard extends StatefulWidget {
  const ListeningCalendarCard(
      {super.key, required this.statistics, this.now, this.dailyChart});
  final PlaybackStatistics statistics;
  final DateTime? now;
  final Widget? dailyChart;

  @override
  State<ListeningCalendarCard> createState() => _ListeningCalendarCardState();
}

enum _ListeningActivityRange { daily, twelveWeeks, year }

class _ListeningCalendarCardState extends State<ListeningCalendarCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  _ListeningActivityRange _range = _ListeningActivityRange.twelveWeeks;
  late final ScrollController _scroll = _CalendarScrollController(_scrollBy);
  String? _selectedDay;
  String? _positionedRange;
  late final AnimationController _rangeFade =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late final Animation<double> _rangeOpacity =
      CurvedAnimation(parent: _rangeFade, curve: AppMotion.standardCurve);
  double? _scrollTarget;
  int _scrollGeneration = 0;
  bool _alignEnd = true;
  bool _anchorScheduled = false;
  _ListeningActivityRange? _widthRange;

  Duration _durationFor(MotionKind kind) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return TickerMode.valuesOf(context).enabled &&
            !features.disableAnimations &&
            !features.reduceMotion
        ? AppMotion.duration(context, kind, AppMotion.standard)
        : Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) {
      _completeDisabledMotion();
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _completeDisabledMotion();
  }

  void _completeDisabledMotion() {
    if (_durationFor(MotionKind.transitions) == Duration.zero) {
      _rangeFade.value = 1;
    }
    if (_durationFor(MotionKind.feedback) == Duration.zero &&
        _scrollTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollTarget != null && _scroll.hasClients) {
          final target = _scrollTarget!;
          _scrollTarget = null;
          _scrollGeneration++;
          _scroll.jumpTo(target.clamp(_scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  void _moveTo(double target) {
    if (!_scroll.hasClients) return;
    final duration = _durationFor(MotionKind.feedback);
    final generation = ++_scrollGeneration;
    _scrollTarget = target;
    if (duration == Duration.zero) {
      _scrollTarget = null;
      _scroll.jumpTo(target);
    } else {
      unawaited(_scroll
          .animateTo(target, duration: duration, curve: AppMotion.standardCurve)
          .whenComplete(() {
        if (mounted && generation == _scrollGeneration) _scrollTarget = null;
      }));
    }
  }

  bool _scrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _scrollGeneration++;
      _scrollTarget = null;
    }
    if (_scrollTarget == null &&
        (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification)) {
      _alignEnd = notification.metrics.extentAfter < .5;
    }
    return false;
  }

  bool _metricsNotification(ScrollMetricsNotification notification) {
    if (notification.metrics.axis != Axis.horizontal ||
        !_alignEnd ||
        _scrollTarget != null ||
        _rangeFade.isAnimating ||
        _anchorScheduled) {
      return false;
    }
    // Keep an end-anchored calendar in view while its cells resize. The width
    // tween already supplies the movement; no second scroll animation is added.
    _anchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorScheduled = false;
      if (mounted && _scroll.hasClients && _alignEnd && _scrollTarget == null) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    (_rangeOpacity as CurvedAnimation).dispose();
    _rangeFade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta == Offset.zero ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final delta =
        event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    final target = ((_scrollTarget ?? position.pixels) + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == (_scrollTarget ?? position.pixels)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _alignEnd = target >= position.maxScrollExtent - .5;
      _moveTo(target);
    });
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = ((_scrollTarget ?? position.pixels) + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _alignEnd = target >= position.maxScrollExtent - .5;
    _moveTo(target);
  }

  Color _color(ColorScheme scheme, int intensity) => intensity == 0
      ? scheme.surfaceContainerHighest
      : Color.lerp(
          scheme.primaryContainer, scheme.primary, (intensity - 1) / 3)!;

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    if (seconds < 60) return ui('{0} 秒', [seconds]);
    final minutes = seconds ~/ 60;
    if (minutes < 60) return ui('{0} 分钟', [minutes]);
    return ui('{0} 小时 {1} 分', [minutes ~/ 60, minutes % 60]);
  }

  String _detail(ListeningCalendarDay day) =>
      '${day.key} · ${day.hasDurationRecord ? _duration(day.milliseconds) : ui('无时长记录')}'
      ' · ${day.playCount == null ? ui('播放次数未记录') : ui('{0} 次', [
              day.playCount
            ])}';

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final calendar = ListeningCalendar(
        now: widget.now ?? DateTime.now(),
        dailyMilliseconds: widget.statistics.dailyMilliseconds,
        dailyPlayCounts: widget.statistics.dailyPlayCounts,
        playCountTrackingStartedOn:
            widget.statistics.playCountTrackingStartedOn,
        range: _range == _ListeningActivityRange.year
            ? ListeningCalendarRange.year
            : ListeningCalendarRange.twelveWeeks);
    final positionIdentity = '${_range.name}:${calendar.today}';
    if (_positionedRange != positionIdentity) {
      final initial = _positionedRange == null;
      _positionedRange = positionIdentity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _alignEnd = true;
          if (initial) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          } else {
            _moveTo(_scroll.position.maxScrollExtent);
          }
        }
      });
    }
    final selected = calendar.weeks
        .expand((week) => week)
        .where((day) => day.key == _selectedDay && day.inRange);
    final selectedDay =
        selected.isEmpty ? calendar.thisWeek.last : selected.first;
    final daily = _range == _ListeningActivityRange.daily;
    final countValue =
        daily ? widget.statistics.totalPlayCount : calendar.rangePlayCount;
    final peaks = widget.statistics.mostActiveHours;
    String hourRange(int hour) => '${hour.toString().padLeft(2, '0')}:00–'
        '${(hour + 1).toString().padLeft(2, '0')}:00';
    return DecoratedBox(
      key: const ValueKey('statistics-calendar-card'),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppShape.surfaceRadius,
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: .55))),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.headphones_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(ui('听歌行为'),
                      style: Theme.of(context).textTheme.titleLarge))
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final range in _ListeningActivityRange.values)
                ChoiceChip(
                    key: ValueKey('statistics-calendar-${range.name}'),
                    label: Text(ui(switch (range) {
                      _ListeningActivityRange.daily => '每天',
                      _ListeningActivityRange.twelveWeeks => '近12周',
                      _ListeningActivityRange.year => '近一年',
                    })),
                    selected: _range == range,
                    onSelected: (selected) {
                      if (selected && range != _range) {
                        setState(() {
                          _range = range;
                          _selectedDay = null;
                        });
                        final duration = _durationFor(MotionKind.transitions);
                        if (duration == Duration.zero) {
                          _rangeFade.value = 1;
                        } else {
                          _rangeFade.duration = duration;
                          _rangeFade.forward(from: 0);
                        }
                      }
                    }),
            ]),
            const SizedBox(height: 10),
            FadeTransition(
                key: const ValueKey('calendar-range-fade'),
                opacity: _rangeOpacity,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          daily
                              ? ui('全部记录 · 按小时累计')
                              : '${listeningDayKey(calendar.start)} – ${listeningDayKey(calendar.today)}',
                          key: const ValueKey('statistics-activity-range'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      LayoutBuilder(builder: (context, constraints) {
                        final scale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        final available =
                            constraints.maxWidth / math.max(1, scale);
                        final columns = available >= 600
                            ? 3
                            : available >= 370
                                ? 2
                                : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                        return Wrap(spacing: 12, runSpacing: 12, children: [
                          _metric(
                              width,
                              ui('播放次数'),
                              countValue == null
                                  ? '—'
                                  : ui('{0} 次', [countValue]),
                              Icons.play_circle_outline_rounded,
                              'statistics-activity-plays'),
                          _metric(
                              width,
                              ui('听歌时长'),
                              _duration(daily
                                  ? widget.statistics.totalListenMilliseconds
                                  : calendar.rangeMilliseconds),
                              Icons.headphones_rounded,
                              'statistics-activity-duration'),
                          Tooltip(
                              message: daily && peaks.isNotEmpty
                                  ? peaks.map(hourRange).join('、')
                                  : ui('活跃时间'),
                              child: _metric(
                                  width,
                                  ui('活跃时间'),
                                  daily
                                      ? peaks.isEmpty
                                          ? '—'
                                          : hourRange(peaks.first)
                                      : ui('{0} 天', [calendar.rangeActiveDays]),
                                  daily
                                      ? Icons.schedule_rounded
                                      : Icons.today_rounded,
                                  'statistics-activity-active')),
                        ]);
                      }),
                      const SizedBox(height: 10),
                      Text(
                          daily
                              ? ui('小时分布包含全部历史记录，不表示某一天；恢复播放不重复计次。')
                              : calendar.completeRangePlayCounts
                                  ? ui('按所选日期范围统计；恢复播放不重复计次。')
                                  : countValue == null
                                      ? ui('旧记录没有每日播放次数；启用记录后才显示，不从累计次数推算。')
                                      : ui('播放次数自 {0} 开始记录，该范围此前次数未知。', [
                                          widget.statistics
                                              .playCountTrackingStartedOn
                                        ]),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      if (daily) ...[
                        const SizedBox(height: 18),
                        if (widget.dailyChart != null) widget.dailyChart!,
                      ] else ...[
                        const SizedBox(height: 12),
                        LayoutBuilder(
                            builder: (context, constraints) => _heatmap(
                                calendar, scheme, constraints.maxWidth)),
                        const SizedBox(height: 12),
                        Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(ui('少'),
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                              for (var intensity = 0;
                                  intensity <= 4;
                                  intensity++)
                                Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                        color: _color(scheme, intensity),
                                        borderRadius:
                                            BorderRadius.circular(3))),
                              Text(ui('多'),
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                              const SizedBox(width: 8),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                        border: Border.all(
                                            color: scheme.outlineVariant),
                                        borderRadius:
                                            BorderRadius.circular(3))),
                                const SizedBox(width: 6),
                                Text(ui('无记录'),
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              ]),
                            ]),
                        const SizedBox(height: 10),
                        Semantics(
                            liveRegion: true,
                            child: Text(_detail(selectedDay),
                                key: const ValueKey(
                                    'statistics-calendar-detail'),
                                style: Theme.of(context).textTheme.bodySmall)),
                        const SizedBox(height: 4),
                        Text(ui('颜色按真实每日时长显示；悬停或点击查看详情，最近一周在右侧。'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ])),
          ])),
    );
  }

  Widget _metric(
      double width, String label, String value, IconData icon, String key) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
        width: width,
        child: DecoratedBox(
            key: ValueKey(key),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: AppShape.controlRadius),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(icon, size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(label,
                                style: Theme.of(context).textTheme.labelLarge))
                      ]),
                      const SizedBox(height: 8),
                      Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ]))));
  }

  Widget _heatmap(
      ListeningCalendar calendar, ColorScheme scheme, double available) {
    final scaler = MediaQuery.textScalerOf(context);
    final cellHeight = (18 * scaler.scale(12) / 12).clamp(18.0, 24.0);
    final headerHeight = math.max(30.0, scaler.scale(12) * 1.4);
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final labels = [ui('周一'), '', ui('周三'), '', ui('周五'), '', ''];
    final measure = TextPainter(
        textDirection: Directionality.of(context), textScaler: scaler);
    var labelWidth = 0.0;
    for (final label in labels) {
      measure.text = TextSpan(text: label, style: labelStyle);
      measure.layout();
      labelWidth = math.max(labelWidth, measure.width);
    }
    measure.dispose();
    labelWidth += 8;
    final gridAvailable = math.max(0.0, available - labelWidth);
    final targetCellWidth =
        math.max(cellHeight, gridAvailable / calendar.weeks.length - 4);
    final changedRange = _widthRange != _range;
    _widthRange = _range;
    return TweenAnimationBuilder<double>(
        key: const ValueKey('calendar-cell-width'),
        duration:
            changedRange ? Duration.zero : _durationFor(MotionKind.layout),
        curve: AppMotion.standardCurve,
        tween: Tween(begin: targetCellWidth, end: targetCellWidth),
        builder: (context, cellWidth, _) {
          final weekWidth = cellWidth + 4;
          final monthLabels = <int, String>{};
          for (var index = 0; index < calendar.weeks.length; index++) {
            final first =
                calendar.weeks[index].where((day) => day.inRange).firstOrNull;
            if (first != null &&
                (index == 0 || first.date.day <= 7) &&
                (monthLabels.isEmpty || index - monthLabels.keys.last >= 3)) {
              monthLabels[index] = ui('{0}月', [first.date.month]);
            }
          }
          final grid = SizedBox(
              width: calendar.weeks.length * weekWidth,
              child: Column(children: [
                SizedBox(
                    height: headerHeight,
                    child: AnimatedBuilder(
                        animation: _scroll,
                        builder: (context, _) => Stack(children: [
                              for (final entry in monthLabels.entries)
                                // A cropped month suffix is misleading at the left
                                // edge. Keep only labels whose start is in view.
                                if (!_scroll.hasClients ||
                                    entry.key * weekWidth >= _scroll.offset)
                                  Positioned(
                                      left: entry.key * weekWidth,
                                      top: 0,
                                      child:
                                          Text(entry.value, style: labelStyle)),
                            ]))),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final week in calendar.weeks)
                    SizedBox(
                        width: weekWidth,
                        child: Column(children: [
                          for (final day in week)
                            Padding(
                                padding:
                                    const EdgeInsets.only(right: 4, bottom: 4),
                                child: SizedBox(
                                    width: cellWidth,
                                    height: cellHeight,
                                    child: day.inRange
                                        ? Tooltip(
                                            message: _detail(day),
                                            child: Semantics(
                                                label: _detail(day),
                                                button: true,
                                                selected:
                                                    _selectedDay == day.key,
                                                child: Material(
                                                    color: day.hasDurationRecord
                                                        ? _color(scheme,
                                                            day.intensity)
                                                        : scheme
                                                            .surfaceContainerLow,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                    3),
                                                            side: BorderSide(
                                                                color: _selectedDay ==
                                                                        day.key
                                                                    ? scheme
                                                                        .primary
                                                                    : day
                                                                            .hasDurationRecord
                                                                        ? Colors
                                                                            .transparent
                                                                        : scheme
                                                                            .outlineVariant,
                                                                width: _selectedDay ==
                                                                        day.key
                                                                    ? 2
                                                                    : 1)),
                                                    child: InkWell(
                                                        key: ValueKey(
                                                            'listening-day-${day.key}'),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                3),
                                                        onTap: () => setState(
                                                            () => _selectedDay =
                                                                day.key)))))
                                        : const SizedBox.shrink())),
                        ])),
                ]),
              ]));
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: labelWidth,
                child: Padding(
                    padding: EdgeInsets.only(top: headerHeight, right: 8),
                    child: Column(children: [
                      for (final label in labels)
                        SizedBox(
                            height: cellHeight + 4,
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(label, style: labelStyle)))
                    ]))),
            Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: _metricsNotification,
                    child: NotificationListener<ScrollNotification>(
                        onNotification: _scrollNotification,
                        child: ScrollConfiguration(
                            behavior: const DanPlayerScrollBehavior(),
                            child: AppScrollbar(
                                controller: _scroll,
                                child: Listener(
                                    behavior: HitTestBehavior.translucent,
                                    onPointerSignal: _wheel,
                                    child: SingleChildScrollView(
                                        key: const ValueKey(
                                            'statistics-calendar-scroll'),
                                        controller: _scroll,
                                        physics:
                                            const AlwaysScrollableScrollPhysics(
                                                parent:
                                                    ClampingScrollPhysics()),
                                        scrollDirection: Axis.horizontal,
                                        child: grid))))))),
          ]);
        });
  }
}

// Native horizontal pointer signals resolve through this position. Only their
// final movement changes; touch drag, overscroll and ballistic physics remain
// Flutter's, while repeated wheel signals share the same animated target.
class _CalendarScrollController extends ScrollController {
  _CalendarScrollController(this.onPointerScroll);
  final ValueChanged<double> onPointerScroll;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _CalendarScrollPosition(
          physics: physics,
          context: context,
          oldPosition: oldPosition,
          onPointerScroll: onPointerScroll);
}

class _CalendarScrollPosition extends ScrollPositionWithSingleContext {
  _CalendarScrollPosition(
      {required super.physics,
      required super.context,
      super.oldPosition,
      required this.onPointerScroll});
  final ValueChanged<double> onPointerScroll;

  @override
  void pointerScroll(double delta) => onPointerScroll(delta);
}
