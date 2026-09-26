/// Calendar dates use components rather than 24-hour durations, so daylight
/// saving transitions do not move a day into the previous/next column.
DateTime localCalendarDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String listeningDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? parseListeningDay(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final date = DateTime.tryParse(value);
  return date != null && listeningDayKey(date) == value ? date : null;
}

enum ListeningCalendarRange { twelveWeeks, year }

class ListeningCalendarDay {
  const ListeningCalendarDay({
    required this.date,
    required this.inRange,
    required this.hasDurationRecord,
    required this.milliseconds,
    required this.playCount,
  });

  final DateTime date;
  final bool inRange;
  final bool hasDurationRecord;
  final int milliseconds;

  /// Null means that the daily play counter had not been enabled that day.
  final int? playCount;
  String get key => listeningDayKey(date);
  int get intensity => milliseconds <= 0
      ? 0
      : milliseconds < 15 * 60000
          ? 1
          : milliseconds < 60 * 60000
              ? 2
              : milliseconds < 180 * 60000
                  ? 3
                  : 4;
}

class ListeningCalendar {
  ListeningCalendar({
    required DateTime now,
    required Map<String, int> dailyMilliseconds,
    required Map<String, int> dailyPlayCounts,
    String? playCountTrackingStartedOn,
    ListeningCalendarRange range = ListeningCalendarRange.twelveWeeks,
  }) {
    today = localCalendarDate(now);
    monday = DateTime(today.year, today.month, today.day - today.weekday + 1);
    start = range == ListeningCalendarRange.twelveWeeks
        ? DateTime(monday.year, monday.month, monday.day - 11 * 7)
        : DateTime(today.year - 1, today.month, today.day + 1);
    final gridStart =
        DateTime(start.year, start.month, start.day - start.weekday + 1);
    final gridEnd = DateTime(monday.year, monday.month, monday.day + 6);
    trackingStartedOn = parseListeningDay(playCountTrackingStartedOn);
    ListeningCalendarDay day(DateTime date) {
      final key = listeningDayKey(date);
      final duration = dailyMilliseconds[key];
      final knownCount = dailyPlayCounts.containsKey(key) ||
          (trackingStartedOn != null && !date.isBefore(trackingStartedOn!));
      return ListeningCalendarDay(
          date: date,
          inRange: !date.isBefore(start) && !date.isAfter(today),
          hasDurationRecord: duration != null && duration >= 0,
          milliseconds: duration == null || duration < 0 ? 0 : duration,
          playCount: knownCount ? (dailyPlayCounts[key] ?? 0) : null);
    }

    weeks = [];
    for (var cursor = gridStart;
        !cursor.isAfter(gridEnd);
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 7)) {
      weeks.add([
        for (var index = 0; index < 7; index++)
          day(DateTime(cursor.year, cursor.month, cursor.day + index))
      ]);
    }
    thisWeek = [
      for (var index = 0; index < today.weekday; index++)
        day(DateTime(monday.year, monday.month, monday.day + index))
    ];
  }

  late final DateTime today;
  late final DateTime monday;
  late final DateTime start;
  late final DateTime? trackingStartedOn;
  late final List<List<ListeningCalendarDay>> weeks;
  late final List<ListeningCalendarDay> thisWeek;
  Iterable<ListeningCalendarDay> get daysInRange =>
      weeks.expand((week) => week).where((day) => day.inRange);
  int get rangeMilliseconds =>
      daysInRange.fold<int>(0, (sum, day) => sum + day.milliseconds);
  int get rangeActiveDays =>
      daysInRange.where((day) => day.milliseconds > 0).length;
  int? get rangePlayCount => daysInRange.every((day) => day.playCount == null)
      ? null
      : daysInRange.fold<int>(0, (sum, day) => sum + (day.playCount ?? 0));
  bool get completeRangePlayCounts =>
      daysInRange.every((day) => day.playCount != null);
  int get weekMilliseconds =>
      thisWeek.fold(0, (sum, day) => sum + day.milliseconds);
  int get weekActiveDays =>
      thisWeek.where((day) => day.milliseconds > 0).length;
  int? get weekPlayCount => thisWeek.every((day) => day.playCount == null)
      ? null
      : thisWeek.fold<int>(0, (sum, day) => sum + (day.playCount ?? 0));
  bool get completeWeekPlayCounts =>
      thisWeek.every((day) => day.playCount != null);
}
