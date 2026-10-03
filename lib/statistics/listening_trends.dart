import 'dart:math' as math;

import 'listening_calendar.dart';

/// A saved daily total is not evidence that an absent date was observed.
/// These comparisons use recorded values only and never infer install dates.
class ListeningTrendDay {
  const ListeningTrendDay(this.date, this.milliseconds);
  final DateTime date;
  final int milliseconds;
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
        result.add(ListeningTrendDay(
            day, math.max(0, dailyMilliseconds[listeningDayKey(day)] ?? 0)));
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
  }) : comparisons = Map.unmodifiable({
          for (final days in periods)
            days: ListeningTrendComparison.fromDaily(
                dailyMilliseconds: dailyMilliseconds,
                capturedAt: capturedAt,
                periodDays: days),
        });
  static const periods = [7, 30, 90];
  final DateTime capturedAt;
  final Map<int, ListeningTrendComparison> comparisons;
}
