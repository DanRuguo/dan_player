import 'dart:math' as math;

import 'listening_calendar.dart';

/// A saved daily total is not evidence that an absent date was observed.
/// These comparisons use recorded values only and never infer install dates.
class ListeningTrendDay {
  const ListeningTrendDay(this.date, this.milliseconds,
      {this.hasRecord = true});
  final DateTime date;
  final int milliseconds;
  final bool hasRecord;
}

class ListeningTrendComparison {
  ListeningTrendComparison._(this.current, this.previous)
      : currentMilliseconds =
            current.fold(0, (sum, day) => sum + day.milliseconds),
        previousMilliseconds =
            previous.fold(0, (sum, day) => sum + day.milliseconds),
        activeDays = current.where((day) => day.milliseconds > 0).length,
        previousActiveDays =
            previous.where((day) => day.milliseconds > 0).length,
        maximumDailyMilliseconds = [...current, ...previous]
            .fold(0, (maximum, day) => math.max(maximum, day.milliseconds));

  factory ListeningTrendComparison.fromDaily({
    required Map<String, int> dailyMilliseconds,
    required DateTime capturedAt,
    required int periodDays,
  }) {
    RangeError.checkValueInInterval(periodDays, 1, 366, 'periodDays');
    final today = localCalendarDate(capturedAt);
    List<ListeningTrendDay> window(int offset) {
      final result = <ListeningTrendDay>[];
      for (var index = 0; index < periodDays; index++) {
        // Calendar components keep local dates aligned across DST,
        // month ends and leap years; a day is not assumed to be 24h.
        final day = DateTime(
            today.year, today.month, today.day - offset - periodDays + index);
        final saved = dailyMilliseconds[listeningDayKey(day)];
        result.add(ListeningTrendDay(day, math.max(0, saved ?? 0),
            hasRecord: saved != null));
      }
      return List.unmodifiable(result);
    }

    return ListeningTrendComparison._(window(0), window(periodDays));
  }

  final List<ListeningTrendDay> current, previous;
  final int currentMilliseconds, previousMilliseconds;
  final int activeDays, previousActiveDays;
  final int maximumDailyMilliseconds;
  int get periodDays => current.length;
  int get deltaMilliseconds => currentMilliseconds - previousMilliseconds;
  double? get changePercent => previousMilliseconds == 0
      ? null
      : deltaMilliseconds * 100 / previousMilliseconds;
}

/// Exactly 254 bounded daily map lookups, once for each display capture.
/// No filesystem, recorder mutation, clock, or ongoing subscription belongs here.
class ListeningTrendsSnapshot {
  ListeningTrendsSnapshot.fromDaily({
    required Map<String, int> dailyMilliseconds,
    required this.capturedAt,
    this.currentDayMilliseconds,
  }) : comparisons = Map.unmodifiable({
          for (final days in periods)
            days: ListeningTrendComparison.fromDaily(
                dailyMilliseconds: dailyMilliseconds,
                capturedAt: capturedAt,
                periodDays: days),
        });

  /// The capture supplies today's value separately: rolling comparisons retain
  /// only finished days, and the week reuses those frozen days without scanning
  /// or subscribing to the recorder. Future dates are always zero placeholders.
  late final ListeningTrendComparison calendarWeek = _calendarWeek();
  ListeningTrendComparison _calendarWeek() {
    final today = localCalendarDate(capturedAt);
    final monday =
        DateTime(today.year, today.month, today.day - today.weekday + 1);
    final retained = {
      for (final day in comparisons[90]!.current)
        listeningDayKey(day.date): day,
    };
    List<ListeningTrendDay> week(int offset) => List.unmodifiable([
          for (var index = 0; index < 7; index++)
            _weekDay(
                DateTime(
                    monday.year, monday.month, monday.day - offset + index),
                today,
                retained),
        ]);
    return ListeningTrendComparison._(week(0), week(7));
  }

  ListeningTrendDay _weekDay(
      DateTime date, DateTime today, Map<String, ListeningTrendDay> retained) {
    if (date.isAfter(today)) {
      return ListeningTrendDay(date, 0, hasRecord: false);
    }
    if (date == today) {
      return ListeningTrendDay(date, math.max(0, currentDayMilliseconds ?? 0),
          hasRecord: currentDayMilliseconds != null);
    }
    return retained[listeningDayKey(date)] ??
        ListeningTrendDay(date, 0, hasRecord: false);
  }

  static const periods = [7, 30, 90];
  final DateTime capturedAt;
  final int? currentDayMilliseconds;
  final Map<int, ListeningTrendComparison> comparisons;
}
