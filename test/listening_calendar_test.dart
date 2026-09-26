import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected range sums only actual inclusive calendar dates', () {
    ListeningCalendar calendar(ListeningCalendarRange range) =>
        ListeningCalendar(
          now: DateTime(2026, 9, 26),
          range: range,
          dailyMilliseconds: {
            '2025-09-26': 999999,
            '2025-09-27': 3600000,
            '2026-07-05': 60000,
            '2026-07-06': 120000,
            '2026-09-26': 180000,
            '2026-09-27': 999999,
          },
          dailyPlayCounts: {
            '2025-09-26': 99,
            '2025-09-27': 7,
            '2026-07-05': 3,
            '2026-07-06': 2,
            '2026-09-26': 4,
            '2026-09-27': 99,
          },
          playCountTrackingStartedOn: '2025-09-27',
        );
    final weeks = calendar(ListeningCalendarRange.twelveWeeks);
    final year = calendar(ListeningCalendarRange.year);
    expect(weeks.rangeMilliseconds, 300000);
    expect(weeks.rangePlayCount, 6);
    expect(weeks.rangeActiveDays, 2);
    expect(weeks.completeRangePlayCounts, isTrue);
    expect(year.rangeMilliseconds, 3960000);
    expect(year.rangePlayCount, 16);
    expect(year.rangeActiveDays, 4);
    expect(year.completeRangePlayCounts, isTrue);
    expect(year.daysInRange.last.key, '2026-09-26');
  });

  test('partial range keeps unknown earlier days distinct from recorded zero',
      () {
    ListeningCalendar calendar(String? started) => ListeningCalendar(
          now: DateTime(2026, 9, 26),
          dailyMilliseconds: {'2026-08-01': 60000, '2026-09-25': 0},
          dailyPlayCounts: {},
          playCountTrackingStartedOn: started,
        );
    expect(calendar(null).rangePlayCount, isNull);
    final partial = calendar('2026-09-25');
    expect(partial.rangePlayCount, 0);
    expect(partial.completeRangePlayCounts, isFalse);
    expect(partial.daysInRange.first.playCount, isNull);
    expect(partial.daysInRange.last.playCount, 0);
    expect(partial.rangeMilliseconds, 60000);
    expect(partial.rangeActiveDays, 1);
  });
  final audio = Audio.online(
      provider: 'netease',
      id: 'calendar',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: 180);
  final next = Audio.online(
      provider: 'bilibili',
      id: 'next',
      title: 'Next',
      artist: 'Artist',
      album: 'Album',
      duration: 180);

  test('day counts match real starts, pause resume and source changes', () {
    var now = DateTime(2026, 9, 26, 23, 59, 59);
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(stats.dispose);
    expect(stats.playCountTrackingStartedOn, isNull);
    stats.start(audio);
    stats.start(audio);
    stats.pause();
    now = DateTime(2026, 9, 27);
    stats.start(audio);
    stats.tick(audio, PlayerState.playing);
    expect(stats.dailyPlayCounts, {'2026-09-26': 1});
    stats.start(next);
    expect(stats.dailyPlayCounts, {'2026-09-26': 1, '2026-09-27': 1});
    expect(stats.totalPlayCount, 2);
    expect(stats.playCountTrackingStartedOn, '2026-09-26');
  });

  test('old all-time counters remain unknown until actual new recording', () {
    final stats = PlaybackStatistics.inMemory(
        clock: () => DateTime(2026, 9, 26),
        initialData: {
          'version': 2,
          'days': {'2026-09-21': 60000},
          'tracks': [
            {'id': 'online:netease:calendar', 'playCount': 99}
          ]
        });
    addTearDown(stats.dispose);
    ListeningCalendar calendar() => ListeningCalendar(
        now: DateTime(2026, 9, 26),
        dailyMilliseconds: stats.dailyMilliseconds,
        dailyPlayCounts: stats.dailyPlayCounts,
        playCountTrackingStartedOn: stats.playCountTrackingStartedOn);
    expect(calendar().weekPlayCount, isNull);
    expect(calendar().weekMilliseconds, 60000);
    stats.start(audio);
    expect(stats.totalPlayCount, 100);
    expect(calendar().weekPlayCount, 1);
    expect(calendar().completeWeekPlayCounts, isFalse);
    expect(calendar().thisWeek.first.playCount, isNull);
  });

  test('schema3 roundtrip keeps exact counters without new plays', () {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 3,
      'days': {'2026-09-21': 1, '2026-09-22': 0},
      'dailyPlayCounts': {'2026-09-21': 7},
      'playCountTrackingStartedOn': '2026-09-21'
    });
    final reload = PlaybackStatistics.inMemory(initialData: stats.snapshot());
    addTearDown(stats.dispose);
    addTearDown(reload.dispose);
    expect(reload.dailyPlayCounts, stats.dailyPlayCounts);
    expect(reload.dailyMilliseconds, stats.dailyMilliseconds);
    final calendar = ListeningCalendar(
        now: DateTime(2026, 9, 26),
        dailyMilliseconds: reload.dailyMilliseconds,
        dailyPlayCounts: reload.dailyPlayCounts,
        playCountTrackingStartedOn: reload.playCountTrackingStartedOn);
    expect(calendar.weekPlayCount, 7);
    expect(calendar.completeWeekPlayCounts, isTrue);
    expect(calendar.thisWeek[1].hasDurationRecord, isTrue);
    expect(calendar.thisWeek[1].milliseconds, 0);
    expect(calendar.thisWeek[2].hasDurationRecord, isFalse);
    expect(calendar.thisWeek[2].playCount, 0);
  });

  test('daily schema rejects malformed dates and counts before restore', () {
    for (final changes in [
      {'playCountTrackingStartedOn': '2026-02-30'},
      {'dailyPlayCounts': <Object?>[]},
      {
        'dailyPlayCounts': {'2026-09-26': -1}
      },
      {
        'dailyPlayCounts': {'2026-09-26': 1.5}
      },
      {
        'dailyPlayCounts': {'2026-9-26': 1}
      },
      {
        'dailyPlayCounts': {'2026-02-30': 1}
      },
      {
        'dailyPlayCounts': {'2026-09-26': 1},
        'playCountTrackingStartedOn': null
      },
    ]) {
      expect(
          () => PlaybackStatistics.validateSnapshot({
                'version': 3,
                'playCountTrackingStartedOn': '2026-09-26',
                ...changes
              }),
          throwsFormatException);
    }
    expect(() => PlaybackStatistics.validateSnapshot({'version': 4}),
        throwsUnsupportedError);
    expect(() => PlaybackStatistics.validateSnapshot({'version': 2}),
        returnsNormally);
  });

  test('reinitializing an isolated recorder clears all new daily state',
      () async {
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    stats.start(audio);
    await stats.initialize();
    expect(stats.dailyPlayCounts, isEmpty);
    expect(stats.playCountTrackingStartedOn, isNull);
    expect(stats.dailyMilliseconds, isEmpty);
    expect(stats.totalPlayCount, 0);
  });

  test('twelve weeks are Monday columns; future days cannot be inspected', () {
    final calendar = ListeningCalendar(
        now: DateTime(2026, 9, 26, 23),
        dailyMilliseconds: {'2026-09-21': 1000, '2026-09-27': 9000},
        dailyPlayCounts: {'2026-09-21': 2, '2026-09-27': 99},
        playCountTrackingStartedOn: '2026-09-21');
    expect(calendar.weeks.length, 12);
    expect(
        calendar.weeks
            .every((week) => week.first.date.weekday == DateTime.monday),
        isTrue);
    expect(calendar.start, DateTime(2026, 7, 6));
    expect(calendar.thisWeek.length, 6);
    expect(calendar.weekMilliseconds, 1000);
    expect(calendar.weekPlayCount, 2);
    expect(calendar.weeks.last.last.inRange, isFalse);
    expect(calendar.weeks.last.first.key, '2026-09-21');
  });

  test('Sunday to Monday resets weekly totals across the year boundary', () {
    ListeningCalendar calendar(DateTime now) => ListeningCalendar(
        now: now,
        dailyMilliseconds: {'2025-12-28': 5000, '2025-12-29': 6000},
        dailyPlayCounts: {'2025-12-28': 4, '2025-12-29': 2},
        playCountTrackingStartedOn: '2025-01-01');
    expect(calendar(DateTime(2025, 12, 28)).monday, DateTime(2025, 12, 22));
    expect(calendar(DateTime(2025, 12, 28)).weekPlayCount, 4);
    expect(calendar(DateTime(2025, 12, 29)).weekPlayCount, 2);
    expect(calendar(DateTime(2025, 12, 29)).weekMilliseconds, 6000);
  });

  test('year calendar covers leap day and has exactly one cell per local day',
      () {
    final calendar = ListeningCalendar(
        now: DateTime(2024, 3, 1),
        dailyMilliseconds: {},
        dailyPlayCounts: {},
        range: ListeningCalendarRange.year);
    final days = calendar.weeks
        .expand((week) => week)
        .where((day) => day.inRange)
        .toList();
    expect(days.length, 366);
    expect(days.first.key, '2023-03-02');
    expect(days.where((day) => day.key == '2024-02-29').length, 1);
    expect(days.map((day) => day.key).toSet().length, days.length);
  });

  test('missing/negative duration is unknown; positive buckets use real time',
      () {
    final calendar =
        ListeningCalendar(now: DateTime(2026, 9, 27), dailyMilliseconds: {
      '2026-09-21': -100,
      '2026-09-22': 0,
      '2026-09-23': 1,
      '2026-09-24': 900000,
      '2026-09-25': 3600000,
      '2026-09-26': 10800000
    }, dailyPlayCounts: {});
    expect(
        calendar.thisWeek.map((day) => day.intensity), [0, 0, 1, 2, 3, 4, 0]);
    expect(calendar.thisWeek.first.hasDurationRecord, isFalse);
    expect(calendar.thisWeek[1].hasDurationRecord, isTrue);
    expect(calendar.weekActiveDays, 4);
  });
}
