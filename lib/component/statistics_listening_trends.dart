import 'dart:math' as math;

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../statistics/listening_calendar.dart';
import '../statistics/listening_trends.dart';
import 'app_menu_anchor.dart';
import 'app_shape.dart';
import 'app_toolbar_style.dart';

class StatisticsListeningTrends extends StatefulWidget {
  const StatisticsListeningTrends({super.key, required this.snapshot});
  final ListeningTrendsSnapshot snapshot;
  @override
  State<StatisticsListeningTrends> createState() =>
      _StatisticsListeningTrendsState();
}

class _StatisticsListeningTrendsState extends State<StatisticsListeningTrends> {
  final _focus = FocusNode();
  var _period = 7;
  int? _selection;
  ListeningTrendComparison get _data => widget.snapshot.comparisons[_period]!;
  int get _index => (_selection ?? _period - 1).clamp(0, _period - 1);

  @override
  void didUpdateWidget(StatisticsListeningTrends oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) _selection = null;
  }

  void _select(int index) {
    final next = index.clamp(0, _period - 1);
    if (next != _index) setState(() => _selection = next);
  }

  int _hit(double x, double width) =>
      ((x - 12) / math.max(1, width - 24) * (_period - 1))
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

  String _detail(int index) =>
      '${ui('本期（实线）')} ${listeningDayKey(_data.current[index].date)} · ${_duration(_data.current[index].milliseconds)}\n'
      '${ui('前期（虚线）')} ${listeningDayKey(_data.previous[index].date)} · ${_duration(_data.previous[index].milliseconds)}';

  Widget _periodMenu(BuildContext context) => AppMenuAnchor(
        style: const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
        menuChildren: [
          for (final days in ListeningTrendsSnapshot.periods)
            MenuItemButton(
              key: ValueKey('statistics-trends-period-$days'),
              leadingIcon: SizedBox.square(
                  dimension: 20,
                  child: days == _period
                      ? const Icon(Icons.check, size: 20)
                      : null),
              onPressed: () => setState(() {
                _period = days;
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
                label: ui('近 {0} 天', [_period]),
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
    final caption = ui('比较已结束的日历日期，不含今天；缺失日期按 0 显示，不代表此前已完整记录。');
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
                    final menu = SizedBox(
                        width: math.min(240, constraints.maxWidth),
                        child: _periodMenu(context));
                    return constraints.maxWidth / scale >= 600
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
                    Text(ui('本期（实线）'), style: TextStyle(color: scheme.primary)),
                    Text(ui('前期（虚线）'),
                        style: TextStyle(color: scheme.tertiary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      ui('每日最高 {0}',
                          [_duration(current.maximumDailyMilliseconds)]),
                      style: theme.textTheme.bodySmall),
                  LayoutBuilder(
                      builder: (context, constraints) => Semantics(
                          key: const ValueKey(
                              'statistics-trends-chart-semantics'),
                          label: ui('逐日对照'),
                          value: _detail(_index),
                          increasedValue:
                              _index < _period - 1 ? _detail(_index + 1) : null,
                          decreasedValue:
                              _index > 0 ? _detail(_index - 1) : null,
                          slider: true,
                          onIncrease: _index < _period - 1
                              ? () => _select(_index + 1)
                              : null,
                          onDecrease:
                              _index > 0 ? () => _select(_index - 1) : null,
                          child: Focus(
                              focusNode: _focus,
                              onKeyEvent: (_, event) {
                                if (event is! KeyDownEvent &&
                                    event is! KeyRepeatEvent) {
                                  return KeyEventResult.ignored;
                                }
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.arrowLeft) {
                                  _select(_index - 1);
                                } else if (key ==
                                    LogicalKeyboardKey.arrowRight) {
                                  _select(_index + 1);
                                } else if (key == LogicalKeyboardKey.home) {
                                  _select(0);
                                } else if (key == LogicalKeyboardKey.end) {
                                  _select(_period - 1);
                                } else {
                                  return KeyEventResult.ignored;
                                }
                                return KeyEventResult.handled;
                              },
                              child: MouseRegion(
                                  onHover: (event) => _select(_hit(
                                      event.localPosition.dx,
                                      constraints.maxWidth)),
                                  child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (details) {
                                        _focus.requestFocus();
                                        _select(_hit(details.localPosition.dx,
                                            constraints.maxWidth));
                                      },
                                      child: SizedBox(
                                          key: const ValueKey(
                                              'statistics-trends-chart'),
                                          height: 160,
                                          child: CustomPaint(
                                              painter: _TrendPainter(
                                                  data: current,
                                                  selection: _index,
                                                  currentColor: scheme.primary,
                                                  previousColor:
                                                      scheme.tertiary,
                                                  gridColor: scheme
                                                      .outlineVariant)))))))),
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
    super.dispose();
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(
      {required this.data,
      required this.selection,
      required this.currentColor,
      required this.previousColor,
      required this.gridColor});
  final ListeningTrendComparison data;
  final int selection;
  final Color currentColor, previousColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.max(0.0, size.width - 24);
    final height = math.max(0.0, size.height - 24);
    Offset point(int index, int value) => Offset(
        12 + index * width / math.max(1, data.periodDays - 1),
        12 +
            height *
                (1 -
                    (data.maximumDailyMilliseconds == 0
                        ? 0
                        : value / data.maximumDailyMilliseconds)));
    final grid = Paint()
      ..color = gridColor.withValues(alpha: .65)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = 12 + height * row / 3;
      canvas.drawLine(Offset(12, y), Offset(12 + width, y), grid);
    }
    Path series(List<ListeningTrendDay> days) {
      final path = Path();
      for (var i = 0; i < days.length; i++) {
        final offset = point(i, days[i].milliseconds);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      return path;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    line.color = previousColor;
    for (final metric in series(data.previous).computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 10) {
        canvas.drawPath(
            metric.extractPath(offset, math.min(offset + 6, metric.length)),
            line);
      }
    }
    line.color = currentColor;
    canvas.drawPath(series(data.current), line);
    final selected = point(selection, data.current[selection].milliseconds);
    canvas.drawLine(
        Offset(selected.dx, 12), Offset(selected.dx, 12 + height), grid);
    canvas.drawCircle(point(selection, data.previous[selection].milliseconds),
        4, Paint()..color = previousColor);
    canvas.drawCircle(selected, 4, Paint()..color = currentColor);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      !identical(data, old.data) ||
      selection != old.selection ||
      currentColor != old.currentColor ||
      previousColor != old.previousColor ||
      gridColor != old.gridColor;
}
