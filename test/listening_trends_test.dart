import 'dart:collection';

import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:flutter_test/flutter_test.dart';

class _LookupOnlyDays extends MapBase<String, int> {
  int reads = 0;
  @override
  int? operator [](Object? key) {
    reads++;
    return null;
  }

  @override
  void operator []=(String key, int value) =>
      throw UnsupportedError('read only');
  @override
  Iterable<String> get keys => throw StateError('History must not be scanned.');
  @override
  void clear() => throw UnsupportedError('read only');
  @override
  int? remove(Object? key) => throw UnsupportedError('read only');
}

void main() {
  ListeningTrendComparison compare(Map<String, int> days,
          {DateTime? at, int period = 7}) =>
      ListeningTrendComparison.fromDaily(
          dailyMilliseconds: days,
          capturedAt: at ?? DateTime(2026, 10, 3, 15),
          periodDays: period);

  test('finished windows are adjacent and omit today and future totals', () {
    final data = compare({
      '2026-09-19': 1000,
      '2026-09-25': 2000,
      '2026-09-26': 4000,
      '2026-10-02': 5000,
      '2026-10-03': 9000000,
      '2099-01-01': 9000000,
    });
    expect(listeningDayKey(data.current.first.date), '2026-09-26');
    expect(listeningDayKey(data.current.last.date), '2026-10-02');
    expect(listeningDayKey(data.previous.first.date), '2026-09-19');
    expect(listeningDayKey(data.previous.last.date), '2026-09-25');
    expect(data.currentMilliseconds, 9000);
    expect(data.previousMilliseconds, 3000);
    expect(data.activeDays, 2);
    expect(data.previousActiveDays, 2);
    expect(data.maximumDailyMilliseconds, 5000);
    expect(data.changePercent, 200);
  });
  test('calendar components include leap day without duplicated dates', () {
    final data = compare({'2024-02-29': 1000}, at: DateTime(2024, 3, 3));
    expect(data.current.map((day) => listeningDayKey(day.date)), [
      '2024-02-25',
      '2024-02-26',
      '2024-02-27',
      '2024-02-28',
      '2024-02-29',
      '2024-03-01',
      '2024-03-02'
    ]);
    expect(data.currentMilliseconds, 1000);
    expect(data.current.map((day) => listeningDayKey(day.date)).toSet(),
        hasLength(7));
  });
  test('month and year boundaries retain complete local calendar dates', () {
    final data =
        compare({'2025-12-31': 2500}, at: DateTime(2026, 1, 2, 23, 59));
    expect(listeningDayKey(data.current.last.date), '2026-01-01');
    expect(data.currentMilliseconds, 2500);
    final utc = DateTime.utc(2026, 1, 2, 23, 59);
    final local = utc.toLocal();
    final fromUtc = compare({}, at: utc);
    expect(listeningDayKey(fromUtc.current.last.date),
        listeningDayKey(DateTime(local.year, local.month, local.day - 1)));
  });
  test('zero previous totals never claim an infinite or 100 percent increase',
      () {
    expect(compare({}).changePercent, isNull);
    expect(compare({'2026-10-02': 5000}).changePercent, isNull);
    final stopped = compare({'2026-09-25': 5000});
    expect(stopped.changePercent, -100);
    expect(stopped.deltaMilliseconds, -5000);
  });
  test(
      'negative change and subsecond daily activity retain exact source values',
      () {
    final data = compare({'2026-09-25': 2, '2026-10-02': 1});
    expect(data.currentMilliseconds, 1);
    expect(data.activeDays, 1);
    expect(data.deltaMilliseconds, -1);
    expect(data.changePercent, -50);
  });
  test('missing and invalid negative totals do not create active days', () {
    final data = compare({'2026-10-02': -100, '2026-09-25': 0});
    expect(data.activeDays, 0);
    expect(data.currentMilliseconds, 0);
    expect(data.maximumDailyMilliseconds, 0);
  });
  test('capture freezes values and does not mutate recorder input', () {
    final days = {'2026-10-02': 1000};
    final snapshot = ListeningTrendsSnapshot.fromDaily(
        dailyMilliseconds: days, capturedAt: DateTime(2026, 10, 3));
    days['2026-10-02'] = 5000;
    expect(snapshot.comparisons[7]!.currentMilliseconds, 1000);
    expect(days, {'2026-10-02': 5000});
    expect(() => snapshot.comparisons.clear(), throwsUnsupportedError);
    expect(
        () => snapshot.comparisons[7]!.current.clear(), throwsUnsupportedError);
  });
  test('all three periods use bounded lookups rather than enumerate history',
      () {
    final days = _LookupOnlyDays();
    final snapshot = ListeningTrendsSnapshot.fromDaily(
        dailyMilliseconds: days, capturedAt: DateTime(2026, 10, 3));
    expect(snapshot.comparisons.keys, [7, 30, 90]);
    expect(days.reads, 254);
    expect(snapshot.comparisons[90]!.current, hasLength(90));
  });
  test('period limits reject unbounded or empty series', () {
    expect(() => compare({}, period: 0), throwsRangeError);
    expect(() => compare({}, period: 367), throwsRangeError);
  });
}
