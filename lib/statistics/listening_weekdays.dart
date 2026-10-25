import 'listening_trends.dart';

/// A bounded projection of the same completed calendar days as the trends.
/// Missing dates remain unknown; averages divide only by days with listening.
class ListeningWeekday {
  const ListeningWeekday(
      {required this.weekday,
      required this.calendarDays,
      required this.recordedDays,
      required this.activeDays,
      required this.milliseconds});

  final int weekday, calendarDays, recordedDays, activeDays, milliseconds;
  int get missingDays => calendarDays - recordedDays;
  double? get activeDayAverage =>
      activeDays == 0 ? null : milliseconds / activeDays;
}

class ListeningWeekdays {
  ListeningWeekdays.fromDays(List<ListeningTrendDay> days)
      : start = days.isEmpty ? null : days.first.date,
        end = days.isEmpty ? null : days.last.date {
    final counts = List.generate(7, (_) => [0, 0, 0, 0]);
    for (final day in days) {
      final row = counts[day.date.weekday - 1];
      row[0]++;
      if (!day.hasRecord) continue;
      row[1]++;
      if (day.milliseconds > 0) {
        row[2]++;
        row[3] += day.milliseconds;
      }
    }
    weekdays = List.unmodifiable([
      for (var index = 0; index < 7; index++)
        ListeningWeekday(
            weekday: index + 1,
            calendarDays: counts[index][0],
            recordedDays: counts[index][1],
            activeDays: counts[index][2],
            milliseconds: counts[index][3]),
    ]);
  }

  final DateTime? start, end;
  late final List<ListeningWeekday> weekdays;
  int get missingDays => weekdays.fold(0, (sum, day) => sum + day.missingDays);
}
