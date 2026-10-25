import 'dart:math' as math;

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

import '../statistics/listening_calendar.dart';
import '../statistics/listening_weekdays.dart';
import 'app_segmented_control.dart';
import 'statistics_bar_row.dart';
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
  static const _names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  double? _value(ListeningWeekday day) => _average
      ? day.activeDayAverage
      : day.recordedDays == 0
          ? null
          : day.milliseconds.toDouble();

  String _duration(double? value) {
    if (value == null) return '—';
    if (value > 0 && value < 1000) return ui('不足 1 秒');
    final milliseconds = value.round();
    final seconds = milliseconds ~/ 1000;
    if (seconds >= 3600)
      return ui('{0} 小时 {1} 分钟', [seconds ~/ 3600, seconds ~/ 60 % 60]);
    if (seconds >= 60) return ui('{0} 分钟', [seconds ~/ 60]);
    return ui('{0} 秒', [seconds]);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final data = widget.snapshot;
    final values = [for (final day in data.weekdays) _value(day)];
    final maximum =
        values.fold<double>(0, (value, next) => math.max(value, next ?? 0));
    final labels = values.map(_duration).toList(growable: false);
    final numberWidth = StatisticsBarRow.measureValues(context, labels);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatisticsCardHeader(
                  title: Text(ui('星期收听习惯'),
                      style: Theme.of(context).textTheme.titleMedium),
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
                const SizedBox(height: 12),
                if (data.start != null && data.end != null)
                  Text(
                      ui('最近 90 个完整日历日：{0} 至 {1}', [
                        listeningDayKey(data.start!),
                        listeningDayKey(data.end!)
                      ]),
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(ui(_average
                    ? '有收听日均只除以该星期实际记录到收听的天数；用来比较一次活跃日通常听多久。'
                    : '累计时长反映各星期已记录的收听总量；各星期在本区间出现的次数可能不同。')),
                for (var index = 0; index < data.weekdays.length; index++) ...[
                  StatisticsBarRow(
                      key: ValueKey('statistics-weekday-${index + 1}'),
                      label: ui(_names[index]),
                      detail: ui('有收听 {0} 天 · 已记零时长 {1} 天 · 缺失 {2} 天', [
                        data.weekdays[index].activeDays,
                        data.weekdays[index].recordedDays -
                            data.weekdays[index].activeDays,
                        data.weekdays[index].missingDays
                      ]),
                      valueLabel: labels[index],
                      value: values[index] ?? 0,
                      maximum: maximum,
                      valueColumnWidth: numberWidth,
                      wrapLabel: true),
                  Text(
                      ui('有收听 {0} 天 · 已记零时长 {1} 天 · 缺失 {2} 天', [
                        data.weekdays[index].activeDays,
                        data.weekdays[index].recordedDays -
                            data.weekdays[index].activeDays,
                        data.weekdays[index].missingDays
                      ]),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Text(ui('不含今天；缺失日期不视为零收听。没有可计算记录时显示“—”，不推断此前是否听过。'),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            )));
  }
}
