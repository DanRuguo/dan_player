import 'dart:math' as math;

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../statistics/listening_calendar.dart';
import '../statistics/listening_trends.dart';
import 'app_menu_anchor.dart';
import 'app_shape.dart';
import 'app_toolbar_style.dart';
import 'app_horizontal_wheel_region.dart';
import 'app_scrollbar.dart';
import 'statistics_comparison_lines.dart';

class StatisticsListeningTrends extends StatefulWidget {
  const StatisticsListeningTrends({super.key, required this.snapshot});
  final ListeningTrendsSnapshot snapshot;
  @override
  State<StatisticsListeningTrends> createState() =>
      _StatisticsListeningTrendsState();
}

enum _TrendSeries { current, previous, both }

class _StatisticsListeningTrendsState extends State<StatisticsListeningTrends> {
  final _focus = FocusNode();
  final _chartScroll = ScrollController();
  bool _calendarWeek = false;
  var _series = _TrendSeries.both;
  var _period = 7;
  int? _selection;
  (double, double)? _weekGeometry;
  bool _revealWeekSelection = false;
  bool _weekRevealScheduled = false;
  ListeningTrendComparison get _data => _calendarWeek
      ? widget.snapshot.calendarWeek
      : widget.snapshot.comparisons[_period]!;
  int get _index => (_selection ??
          (_calendarWeek
              ? localCalendarDate(widget.snapshot.capturedAt).weekday - 1
              : _period - 1))
      .clamp(0, _period - 1);
  bool get _showCurrent => _series != _TrendSeries.previous;
  bool get _showPrevious => _series != _TrendSeries.current;
  double get _maximum => [
        if (_showCurrent) ..._data.current,
        if (_showPrevious) ..._data.previous
      ].fold(0.0, (value, day) => math.max(value, day.milliseconds.toDouble()));

  @override
  void didUpdateWidget(StatisticsListeningTrends oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _selection = null;
      _revealWeekSelection = true;
    }
  }

  void _select(int index, {bool reveal = false}) {
    final next = index.clamp(0, _period - 1);
    if (next != _index) setState(() => _selection = next);
    if (!reveal || !_calendarWeek || !_chartScroll.hasClients) return;
    final position = _chartScroll.position;
    final width = position.viewportDimension + position.maxScrollExtent;
    _chartScroll.jumpTo(
        ((next + .5) * width / 7 - position.viewportDimension / 2)
            .clamp(0.0, position.maxScrollExtent));
  }

  int _hit(double x, double width) => _calendarWeek
      ? (x / math.max(1, width) * 7).floor().clamp(0, 6)
      : ((x - 12) / math.max(1, width - 24) * (_period - 1))
          .round()
          .clamp(0, _period - 1);

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    if (milliseconds > 0 && seconds == 0) return ui('不足 1 秒');
    return hours > 0
        ? ui('{0} 小时 {1} 分钟', [hours, minutes])
        : minutes > 0
            ? ui('{0} 分钟', [minutes])
            : ui('{0} 秒', [seconds]);
  }

  String _dayDetail(ListeningTrendDay day) {
    final today = localCalendarDate(widget.snapshot.capturedAt);
    final status = !_calendarWeek
        ? ''
        : day.date.isAfter(today)
            ? '未来日期，按 0 占位'
            : day.date == today
                ? '当天未结束，仅计截至展示时间的记录'
                : !day.hasRecord
                    ? '缺失记录，按 0 显示'
                    : '';
    return '${listeningDayKey(day.date)} · ${_duration(day.milliseconds)}${status.isEmpty ? '' : ' · ${ui(status)}'}';
  }

  String _detail(int index) => [
        if (_showCurrent) '${ui('本期（实线）')} ${_dayDetail(_data.current[index])}',
        if (_showPrevious)
          '${ui('前期（虚线）')} ${_dayDetail(_data.previous[index])}',
      ].join('\n');

  Widget _periodMenu(BuildContext context) => AppMenuAnchor(
        style: const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
        menuChildren: [
          MenuItemButton(
              key: const ValueKey('statistics-trends-calendar-week'),
              leadingIcon: SizedBox.square(
                  dimension: 20,
                  child:
                      _calendarWeek ? const Icon(Icons.check, size: 20) : null),
              onPressed: () => setState(() {
                    _calendarWeek = true;
                    _period = 7;
                    _selection = null;
                    _revealWeekSelection = true;
                  }),
              child: Text(ui('按严格一周'))),
          for (final days in ListeningTrendsSnapshot.periods)
            MenuItemButton(
              key: ValueKey('statistics-trends-period-$days'),
              leadingIcon: SizedBox.square(
                  dimension: 20,
                  child: !_calendarWeek && days == _period
                      ? const Icon(Icons.check, size: 20)
                      : null),
              onPressed: () => setState(() {
                _period = days;
                _calendarWeek = false;
                _selection = null;
              }),
              child: Text(ui('近 {0} 天', [days])),
            ),
        ],
        builder: (context, controller, _) => OutlinedButton(
            key: const ValueKey('statistics-trends-period'),
            style: appToolbarControlStyle(context),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AppToolbarLabel(
                label: _calendarWeek ? ui('按严格一周') : ui('近 {0} 天', [_period]),
                icon: Icons.date_range_outlined,
                trailing: const Icon(Icons.expand_more, size: 18))),
      );

  Widget _metric(BuildContext context, String label, String value,
          {String? detail}) =>
      DecoratedBox(
          decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .45),
              borderRadius: AppShape.controlRadius),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(detail,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ])));

  String _seriesLabel(_TrendSeries series) => switch (series) {
        _TrendSeries.current => '本期收听',
        _TrendSeries.previous => '前期收听',
        _TrendSeries.both => '两期对比',
      };
  Widget _seriesMenu(BuildContext context) => AppMenuAnchor(
      style: const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
      menuChildren: [
        for (final series in _TrendSeries.values)
          MenuItemButton(
              key: ValueKey('statistics-trends-series-${series.name}'),
              leadingIcon: SizedBox.square(
                  dimension: 20,
                  child: series == _series
                      ? const Icon(Icons.check, size: 20)
                      : null),
              onPressed: () => setState(() => _series = series),
              child: Text(ui(_seriesLabel(series))))
      ],
      builder: (context, controller, _) => OutlinedButton(
          key: const ValueKey('statistics-trends-series'),
          style: appToolbarControlStyle(context),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: AppToolbarLabel(
              label: ui(_seriesLabel(_series)),
              icon: Icons.show_chart_rounded,
              trailing: const Icon(Icons.expand_more, size: 18))));

  Widget _chart(BuildContext context, ListeningTrendComparison current,
          ColorScheme scheme) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final width = _calendarWeek
            ? math.max(constraints.maxWidth, 7 * 42 * scale)
            : constraints.maxWidth;
        if (_calendarWeek) {
          final geometry = (constraints.maxWidth, width);
          if (_weekGeometry != geometry) {
            _weekGeometry = geometry;
            _revealWeekSelection = true;
          }
          if (_revealWeekSelection && !_weekRevealScheduled) {
            _weekRevealScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _weekRevealScheduled = false;
              if (!mounted || !_calendarWeek) return;
              _revealWeekSelection = false;
              _select(_index, reveal: true);
            });
          }
        } else {
          _weekGeometry = null;
        }
        final paint = CustomPaint(
            painter: _TrendPainter(
                data: current,
                maximum: _maximum,
                selection: _index,
                showCurrent: _showCurrent,
                showPrevious: _showPrevious,
                calendarWeek: _calendarWeek,
                currentColor: scheme.primary,
                previousColor: scheme.tertiary,
                gridColor: scheme.outlineVariant));
        final input = MouseRegion(
            onHover: (event) => _select(_hit(event.localPosition.dx, width)),
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  _focus.requestFocus();
                  _select(_hit(details.localPosition.dx, width));
                },
                child: SizedBox(
                    key: const ValueKey('statistics-trends-chart'),
                    width: width,
                    height: 160,
                    child: paint)));
        final plot = SizedBox(
            width: width,
            child: Column(children: [
              input,
              if (_calendarWeek)
                Row(children: [
                  for (final day in ['周一', '周二', '周三', '周四', '周五', '周六', '周日'])
                    Expanded(
                        child: Text(ui(day),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall))
                ]),
            ]));
        final surface = _calendarWeek
            ? AppHorizontalWheelRegion(
                controller: _chartScroll,
                child: AppScrollbar(
                    controller: _chartScroll,
                    child: SingleChildScrollView(
                        key: const ValueKey('statistics-trends-week-scroll'),
                        controller: _chartScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: plot)))
            : plot;
        return Semantics(
            key: const ValueKey('statistics-trends-chart-semantics'),
            label: ui('逐日对照'),
            value: _detail(_index),
            increasedValue: _index < _period - 1 ? _detail(_index + 1) : null,
            decreasedValue: _index > 0 ? _detail(_index - 1) : null,
            slider: true,
            onIncrease: _index < _period - 1
                ? () => _select(_index + 1, reveal: true)
                : null,
            onDecrease:
                _index > 0 ? () => _select(_index - 1, reveal: true) : null,
            child: Focus(
                focusNode: _focus,
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  final target = switch (event.logicalKey) {
                    LogicalKeyboardKey.arrowLeft => _index - 1,
                    LogicalKeyboardKey.arrowRight => _index + 1,
                    LogicalKeyboardKey.home => 0,
                    LogicalKeyboardKey.end => _period - 1,
                    _ => null
                  };
                  if (target == null) return KeyEventResult.ignored;
                  _select(target, reveal: true);
                  return KeyEventResult.handled;
                },
                child: surface));
      });

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final current = _data;
    final percentage = current.changePercent;
    final change =
        '${current.deltaMilliseconds < 0 ? '−' : '+'}${_duration(current.deltaMilliseconds.abs())}';
    final comparison = percentage == null
        ? ui('前期无收听记录，不计算百分比。')
        : '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(1)}%';
    final caption = ui(_calendarWeek
        ? '按周一至周日与上一周对照；今天尚未结束，未来日期和缺失记录按 0 占位，增减为暂时结果。'
        : '比较已结束的日历日期，不含今天；缺失日期按 0 显示，不代表此前已完整记录。');
    return Card.filled(
        key: const ValueKey('statistics-listening-trends'),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: AppShape.controlRadius,
            side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .55))),
        color: scheme.surfaceContainerLow,
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final title = Semantics(
                        header: true,
                        child: Row(children: [
                          Icon(Icons.show_chart_rounded,
                              size: 22, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(ui('收听趋势对比'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600))),
                        ]));
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final controlWidth = math.min(220.0, constraints.maxWidth);
                    final menu = SizedBox(
                        width: math.min(452.0, constraints.maxWidth),
                        child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                  width: controlWidth,
                                  child: _periodMenu(context)),
                              SizedBox(
                                  width: controlWidth,
                                  child: _seriesMenu(context)),
                            ]));
                    return constraints.maxWidth / scale >= 760
                        ? Row(children: [
                            Expanded(child: title),
                            const SizedBox(width: 12),
                            menu
                          ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                title,
                                const SizedBox(height: 12),
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: menu)
                              ]);
                  }),
                  const SizedBox(height: 12),
                  Text(
                      '${listeningDayKey(current.current.first.date)} – ${listeningDayKey(current.current.last.date)}',
                      key: const ValueKey('statistics-trends-date-range'),
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final columns = constraints.maxWidth / scale >= 660 ? 3 : 1;
                    final metrics = [
                      _metric(context, ui('本期收听'),
                          _duration(current.currentMilliseconds)),
                      _metric(context, ui('相比前期'), change, detail: comparison),
                      _metric(context, ui('活跃日期'),
                          ui('{0} / {1} 天', [current.activeDays, _period]),
                          detail: ui('前期 {0} 天', [current.previousActiveDays])),
                    ];
                    return columns == 3
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                for (var i = 0; i < 3; i++) ...[
                                  if (i > 0) const SizedBox(width: 12),
                                  Expanded(child: metrics[i])
                                ]
                              ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                for (var i = 0; i < 3; i++) ...[
                                  if (i > 0) const SizedBox(height: 10),
                                  metrics[i]
                                ]
                              ]);
                  }),
                  const SizedBox(height: 16),
                  Wrap(spacing: 20, runSpacing: 8, children: [
                    if (_showCurrent)
                      Text(ui('本期（实线）'),
                          style: TextStyle(color: scheme.primary)),
                    if (_showPrevious)
                      Text(ui('前期（虚线）'),
                          style: TextStyle(color: scheme.tertiary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(ui('每日最高 {0}', [_duration(_maximum.round())]),
                      style: theme.textTheme.bodySmall),
                  _chart(context, current, scheme),
                  const SizedBox(height: 8),
                  Text(_detail(_index),
                      key: const ValueKey('statistics-trends-selected-day'),
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  Text(ui('悬停或点按查看日期；聚焦图表后可用方向键、Home 和 End。'),
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Tooltip(
                      message: caption,
                      child: Text(caption,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant))),
                ])));
  }

  @override
  void dispose() {
    _focus.dispose();
    _chartScroll.dispose();
    super.dispose();
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(
      {required this.data,
      required this.maximum,
      required this.showCurrent,
      required this.showPrevious,
      required this.calendarWeek,
      required this.selection,
      required this.currentColor,
      required this.previousColor,
      required this.gridColor});
  final ListeningTrendComparison data;
  final int selection;
  final double maximum;
  final bool showCurrent, showPrevious, calendarWeek;
  final Color currentColor, previousColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) =>
      paintStatisticsComparisonLines(canvas, size,
          count: data.periodDays,
          maximum: maximum,
          current: (index) => data.current[index].milliseconds,
          previous: (index) => data.previous[index].milliseconds,
          selection: selection,
          currentColor: currentColor,
          previousColor: previousColor,
          gridColor: gridColor,
          centerSlots: calendarWeek,
          showCurrent: showCurrent,
          showPrevious: showPrevious);

  @override
  bool shouldRepaint(_TrendPainter old) =>
      !identical(data, old.data) ||
      selection != old.selection ||
      maximum != old.maximum ||
      showCurrent != old.showCurrent ||
      showPrevious != old.showPrevious ||
      calendarWeek != old.calendarWeek ||
      currentColor != old.currentColor ||
      previousColor != old.previousColor ||
      gridColor != old.gridColor;
}
