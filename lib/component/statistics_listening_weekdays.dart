import 'dart:math' as math;

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../statistics/listening_calendar.dart';
import '../statistics/listening_weekdays.dart';
import 'app_content_transition.dart';
import 'app_horizontal_wheel_region.dart';
import 'app_scrollbar.dart';
import 'app_segmented_control.dart';
import 'app_shape.dart';
import 'statistics_card_header.dart';

class StatisticsListeningWeekdays extends StatefulWidget {
  const StatisticsListeningWeekdays({super.key, required this.snapshot});
  final ListeningWeekdays snapshot;

  @override
  State<StatisticsListeningWeekdays> createState() =>
      _StatisticsListeningWeekdaysState();
}

class _StatisticsListeningWeekdaysState
    extends State<StatisticsListeningWeekdays> {
  bool _average = false;
  final _selection = ValueNotifier(0);
  final _focus = FocusNode();
  final _scroll = ScrollController();
  (double, double)? _chartGeometry;
  bool _revealPending = false, _revealScheduled = false;
  static const _names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  static const _shortNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  double? _value(ListeningWeekday day) => _average
      ? day.activeDayAverage
      : day.recordedDays == 0
          ? null
          : day.milliseconds.toDouble();

  String _duration(double? value) {
    if (value == null) return '—';
    if (value > 0 && value < 1000) return ui('不足 1 秒');
    final seconds = value.round() ~/ 1000;
    if (seconds >= 3600) {
      return ui('{0} 小时 {1} 分钟', [seconds ~/ 3600, seconds ~/ 60 % 60]);
    }
    if (seconds >= 60 && seconds < 120) return ui('1 分钟');
    if (seconds >= 60) return ui('{0} 分钟', [seconds ~/ 60]);
    if (seconds == 1) return ui('1 秒');
    return ui('{0} 秒', [seconds]);
  }

  String _axisDuration(double? value) {
    if (value == null) return '—';
    if (value > 0 && value < 1000) return '<0:01';
    final seconds = value.round() ~/ 1000;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (seconds < 3600) return '${seconds ~/ 60}:$remainder';
    final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
    return '${seconds ~/ 3600}:$minutes:$remainder';
  }

  String _detail(int index) {
    final day = widget.snapshot.weekdays[index];
    return '${ui(_names[index])} · ${_duration(_value(day))} · '
        '${ui('有效天数 {0}', [day.activeDays])}';
  }

  void _select(int index, {bool reveal = false}) {
    final next = index.clamp(0, 6);
    if (_selection.value != next) _selection.value = next;
    if (!reveal || !_scroll.hasClients) return;
    final position = _scroll.position;
    final width = position.viewportDimension + position.maxScrollExtent;
    _scroll.jumpTo(((next + .5) * width / 7 - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent));
  }

  Widget _chart(BuildContext context, List<double?> values) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final canReveal = TickerMode.valuesOf(context).enabled;
    return LayoutBuilder(builder: (context, constraints) {
      final labelStyle = theme.textTheme.labelSmall!;
      final text = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context));
      var slot = 44.0;
      for (final name in _shortNames) {
        text.text = TextSpan(text: ui(name), style: labelStyle);
        text.layout();
        slot = math.max(slot, text.width + 20);
      }
      final maximum = values.fold<double>(0, (a, b) => math.max(a, b ?? 0));
      final maximumValue =
          values.any((value) => value != null) ? maximum : null;
      final maximumLabel = _axisDuration(maximumValue);
      final zeroLabel = _axisDuration(0);
      text.text = TextSpan(text: maximumLabel, style: labelStyle);
      text.layout();
      final maximumLabelWidth = text.width;
      text.text = TextSpan(text: zeroLabel, style: labelStyle);
      text.layout();
      final axisWidth = math.min(math.max(maximumLabelWidth, text.width),
          math.min(85.0, constraints.maxWidth * .28));
      text.text = TextSpan(text: maximumLabel, style: labelStyle);
      text.layout(maxWidth: axisWidth);
      final maximumLabelHeight = text.height;
      text.text = TextSpan(text: zeroLabel, style: labelStyle);
      text.layout(maxWidth: axisWidth);
      final height = math.max(160.0, maximumLabelHeight + text.height + 32);
      text.dispose();
      final width = math.max(constraints.maxWidth - axisWidth - 8, slot * 7);
      final geometry = (constraints.maxWidth - axisWidth - 8, width);
      if (_chartGeometry != geometry) {
        _chartGeometry = geometry;
        _revealPending = true;
      }
      if (_revealPending && canReveal && !_revealScheduled) {
        _revealScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _revealScheduled = false;
          if (!mounted || !TickerMode.valuesOf(this.context).enabled) return;
          // Hidden layout retains the request. Returning without a geometry
          // change must still preserve the user's manual horizontal browsing.
          _revealPending = false;
          _select(_selection.value, reveal: true);
        });
      }
      final plot = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (event) {
          _focus.requestFocus();
          _select((event.localPosition.dx / width * 7).floor());
        },
        child: MouseRegion(
          onHover: (event) =>
              _select((event.localPosition.dx / width * 7).floor()),
          child: SizedBox(
            width: width,
            child: Column(children: [
              RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('statistics-weekdays-chart'),
                  size: Size(width, height),
                  painter: _WeekdayPainter(
                    values: values,
                    maximum: maximum,
                    selected: _selection,
                    color: scheme.primary,
                    gridColor: scheme.outlineVariant,
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: _selection,
                builder: (context, selected, _) => Row(children: [
                  for (var index = 0; index < 7; index++)
                    Expanded(
                      child: Text(ui(_shortNames[index]),
                          key: ValueKey('statistics-weekday-${index + 1}'),
                          textAlign: TextAlign.center,
                          style: labelStyle.copyWith(
                              color: selected == index
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: selected == index
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      );
      final input = Focus(
        focusNode: _focus,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final index = _selection.value;
          final target = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft => index - 1,
            LogicalKeyboardKey.arrowRight => index + 1,
            LogicalKeyboardKey.home => 0,
            LogicalKeyboardKey.end => 6,
            _ => null,
          };
          if (target == null) return KeyEventResult.ignored;
          _select(target, reveal: true);
          return KeyEventResult.handled;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: axisWidth,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                        message: _duration(maximumValue),
                        child: Text(maximumLabel,
                            key: const ValueKey('statistics-weekdays-maximum'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: labelStyle.copyWith(
                                color: scheme.onSurfaceVariant))),
                    Tooltip(
                        message: _duration(0),
                        child: Text(zeroLabel,
                            key: const ValueKey('statistics-weekdays-zero'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: labelStyle.copyWith(
                                color: scheme.onSurfaceVariant))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: AppHorizontalWheelRegion(
              controller: _scroll,
              child: AppScrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  key: const ValueKey('statistics-weekdays-scroll'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: plot,
                ),
              ),
            )),
          ],
        ),
      );
      // Inspection repaints only seven points, their labels and one detail.
      // The chart has no recurring sampling clock.
      return ValueListenableBuilder(
        valueListenable: _selection,
        child: input,
        builder: (context, selected, child) => Semantics(
          key: const ValueKey('statistics-weekdays-chart-semantics'),
          label: ui('星期收听习惯'),
          value: _detail(selected),
          slider: true,
          onIncrease:
              selected < 6 ? () => _select(selected + 1, reveal: true) : null,
          onDecrease:
              selected > 0 ? () => _select(selected - 1, reveal: true) : null,
          increasedValue: selected < 6 ? _detail(selected + 1) : null,
          decreasedValue: selected > 0 ? _detail(selected - 1) : null,
          child: ExcludeSemantics(child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final data = widget.snapshot;
    final values = [for (final day in data.weekdays) _value(day)];
    final explanation = [
      if (data.start != null && data.end != null)
        ui('最近 90 个完整日历日：{0} 至 {1}',
            [listeningDayKey(data.start!), listeningDayKey(data.end!)]),
      ui(_average
          ? '有收听日均只除以该星期实际记录到收听的天数；用来比较一次活跃日通常听多久。'
          : '累计时长反映各星期已记录的收听总量；各星期在本区间出现的次数可能不同。'),
      ui('不含今天；缺失日期不视为零收听。没有可计算记录时显示“—”，不推断此前是否听过。'),
    ].join('\n');
    return Card.filled(
      key: const ValueKey('statistics-listening-weekdays'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: AppShape.controlRadius,
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: .55))),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatisticsCardHeader(
              title: Tooltip(
                message: explanation,
                child: Semantics(
                  header: true,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_view_week_rounded,
                        size: 22, color: scheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(ui('星期收听习惯'),
                          key: const ValueKey('statistics-weekdays-title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
              controls: AppSegmentedControl<bool>(
                  key: const ValueKey('statistics-weekdays-metric'),
                  value: _average,
                  maxWidth: 440,
                  wrapCompactLabel: true,
                  semanticLabel: ui('星期收听习惯'),
                  options: [
                    AppSegmentOption(
                        key: const ValueKey('statistics-weekdays-total'),
                        value: false,
                        label: ui('累计时长'),
                        icon: Icons.schedule),
                    AppSegmentOption(
                        key: const ValueKey('statistics-weekdays-average'),
                        value: true,
                        label: ui('有收听日均'),
                        icon: Icons.equalizer),
                  ],
                  onChanged: (value) => setState(() => _average = value)),
            ),
            if (data.start != null && data.end != null) ...[
              const SizedBox(height: 12),
              Text(
                  '${listeningDayKey(data.start!)} – ${listeningDayKey(data.end!)}',
                  key: const ValueKey('statistics-weekdays-date-range'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            AppContentTransition(
              identity: (data, _average),
              child: _chart(context, values),
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder(
              valueListenable: _selection,
              builder: (context, index, _) {
                final day = data.weekdays[index];
                return Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${ui(_names[index])} · ${_duration(_value(day))}',
                        key: const ValueKey(
                            'statistics-weekdays-selected-value'),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Tooltip(
                      message: ui('有效天数指有收听记录且时长大于零的天数；日均只除以这些天数。'),
                      child: Text(ui('有效天数 {0}', [day.activeDays]),
                          key:
                              const ValueKey('statistics-weekdays-active-days'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _selection.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _WeekdayPainter extends CustomPainter {
  const _WeekdayPainter({
    required this.values,
    required this.maximum,
    required this.selected,
    required this.color,
    required this.gridColor,
  }) : super(repaint: selected);

  final List<double?> values;
  final double maximum;
  final ValueListenable<int> selected;
  final Color color, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final height = math.max(0.0, size.height - 24);
    final grid = Paint()
      ..color = gridColor.withValues(alpha: .65)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = 12 + height * row / 3;
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), grid);
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final points = <Offset?>[
      for (var index = 0; index < values.length; index++)
        values[index] == null
            ? null
            : Offset(
                (index + .5) * size.width / 7,
                12 +
                    height *
                        (1 - (maximum == 0 ? 0 : values[index]! / maximum))),
    ];
    final path = Path();
    var connected = false;
    for (final point in points) {
      if (point == null) {
        // Unknown and unavailable averages are gaps, never a zero baseline.
        connected = false;
      } else {
        if (connected) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
        }
        connected = true;
      }
    }
    canvas.drawPath(path, line);
    final x = (selected.value + .5) * size.width / 7;
    canvas.drawLine(Offset(x, 12), Offset(x, size.height - 12), grid);
    final dot = Paint()..color = color;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      if (point != null) {
        canvas.drawCircle(point, index == selected.value ? 4 : 2.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_WeekdayPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      maximum != oldDelegate.maximum ||
      color != oldDelegate.color ||
      gridColor != oldDelegate.gridColor ||
      selected != oldDelegate.selected;
}
