import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 27, 12, 30);
  int at(int hours, [int seconds = 0]) =>
      now.add(Duration(hours: hours, seconds: seconds)).millisecondsSinceEpoch;
  final audio = Audio.online(
      provider: 'netease',
      id: 'rolling',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: 300);

  test('24 hours clips both interval edges and excludes future starts', () {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 4,
      'recentTrackingStartedAt': at(-48),
      'recentPlayStarts': [at(-24, -1), at(-24), at(-1), at(1)],
      'recentListeningIntervals': [
        [at(-24, -30), at(-24, 30)],
        [at(-1), at(0, 30)]
      ],
    });
    addTearDown(stats.dispose);
    final recent = stats.recentActivity(now);
    expect(recent.playCount, 2);
    expect(recent.milliseconds, 3630000);
    expect(recent.hourlyMilliseconds.first, 30000);
    expect(recent.hourlyMilliseconds.last, 3600000);
    expect(recent.activeHours, 2);
    expect(recent.complete, isTrue);
    expect(recent.hourStart(24), now);
  });

  test('legacy daily and lifetime counters never invent subday history', () {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 3,
      'days': {'2026-09-27': 900000},
      'hours': List.filled(24, 1000),
      'playCountTrackingStartedOn': '2026-09-01',
      'dailyPlayCounts': {'2026-09-27': 7},
    });
    addTearDown(stats.dispose);
    final recent = stats.recentActivity(now);
    expect(recent.playCount, isNull);
    expect(recent.recordedSince, isNull);
    expect(recent.complete, isFalse);
    expect(stats.dailyPlayCounts['2026-09-27'], 7);
  });

  test('real starts merge adjacent samples, retain pause gaps and resume count',
      () {
    var clock = now;
    final stats = PlaybackStatistics.inMemory(clock: () => clock);
    addTearDown(stats.dispose);
    stats.start(audio);
    for (var i = 0; i < 100; i++) {
      clock = clock.add(const Duration(milliseconds: 100));
      stats.tick(audio, PlayerState.playing);
    }
    stats.pause();
    clock = clock.add(const Duration(seconds: 10));
    stats.start(audio);
    clock = clock.add(const Duration(seconds: 1));
    stats.tick(audio, PlayerState.playing);
    expect(stats.recentListeningIntervals.length, 2);
    expect(stats.recentActivity(clock).milliseconds, 11000);
    expect(stats.recentActivity(clock).playCount, 1);
    expect(stats.recentActivity(clock).complete, isFalse);
    final copied = PlaybackStatistics.displayCopy(stats.snapshot());
    addTearDown(copied.dispose);
    stats.recentListeningIntervals.first[0]++;
    expect(copied.recentActivity(clock).milliseconds, 11000);
  });

  test('48-hour retention bounds data while preserving 24-hour coverage', () {
    var clock = now;
    final stats = PlaybackStatistics.inMemory(clock: () => clock, initialData: {
      'version': 4,
      'recentTrackingStartedAt': at(-72),
      'recentPlayStarts': [at(-60), at(-24)],
      'recentListeningIntervals': [
        [at(-50), at(-47)],
        [at(-2), at(-1)]
      ],
    });
    addTearDown(stats.dispose);
    stats.start(audio);
    expect(stats.recentPlayStarts, [at(-24), at(0)]);
    expect(stats.recentListeningIntervals.first.first, at(-48));
    expect(stats.recentActivity(clock).complete, isTrue);
    expect(stats.recentActivity(clock).milliseconds, 3600000);
  });

  test(
      'ordered retention preserves cutoff starts and trims only expired prefix',
      () {
    final stats = PlaybackStatistics.inMemory(clock: () => now, initialData: {
      'version': 4,
      'recentTrackingStartedAt': at(-72),
      'recentPlayStarts': [at(-60), at(-48), at(-48), at(-1), at(1)],
      'recentListeningIntervals': [
        [at(-60), at(-49)],
        [at(-49), at(-48)],
        [at(-48), at(-47)],
        [at(-2), at(-1)]
      ],
    });
    addTearDown(stats.dispose);
    stats.start(audio);
    expect(stats.recentPlayStarts, [at(-48), at(-48), at(-1), at(0), at(1)]);
    expect(stats.recentListeningIntervals, [
      [at(-48), at(-47)],
      [at(-2), at(-1)]
    ]);
    expect(() => PlaybackStatistics.validateSnapshot(stats.snapshot()),
        returnsNormally);
  });

  test('strict recent parser rejects malformed and overlapping histories', () {
    for (final fields in [
      {'recentTrackingStartedAt': -1},
      {'recentTrackingStartedAt': 8640000000000001},
      {
        'recentPlayStarts': [3, 2]
      },
      {
        'recentPlayStarts': [1.5]
      },
      {
        'recentListeningIntervals': [
          [1, 1]
        ]
      },
      {
        'recentListeningIntervals': [
          [1, 5],
          [4, 8]
        ]
      },
      {
        'recentListeningIntervals': [
          [1, 2, 3]
        ]
      },
      {'recentPlayStarts': List.filled(20001, 1)},
      {
        'recentTrackingStartedAt': null,
        'recentPlayStarts': [1]
      },
    ]) {
      expect(
          () => PlaybackStatistics.validateSnapshot(
              {'version': 4, 'recentTrackingStartedAt': 0, ...fields}),
          throwsFormatException);
    }
    expect(() => PlaybackStatistics.validateSnapshot({'version': 5}),
        throwsUnsupportedError);
  });

  test(
      'event cap advances coverage and never presents a truncated total as complete',
      () {
    final stats = PlaybackStatistics.inMemory(clock: () => now, initialData: {
      'version': 4,
      'recentTrackingStartedAt': at(-48),
      'recentPlayStarts':
          List.filled(PlaybackStatistics.recentRecordLimit, at(-1)),
    });
    addTearDown(stats.dispose);
    stats.start(audio);
    expect(stats.recentPlayStarts.length, PlaybackStatistics.recentRecordLimit);
    expect(stats.recentActivity(now).complete, isFalse);
    expect(stats.recentTrackingStartedAt, at(-1, 0) + 1);
  });

  test(
      'wall clock rollback resets exact coverage without altering lifetime totals',
      () {
    var clock = now;
    final stats = PlaybackStatistics.inMemory(clock: () => clock);
    addTearDown(stats.dispose);
    stats.start(audio);
    clock = clock.add(const Duration(seconds: 1));
    stats.tick(audio, PlayerState.playing);
    clock = clock.subtract(const Duration(hours: 1));
    stats.tick(audio, PlayerState.playing);
    clock = clock.add(const Duration(seconds: 1));
    stats.tick(audio, PlayerState.playing);
    expect(stats.totalListenMilliseconds, 2000);
    expect(stats.totalPlayCount, 1);
    expect(stats.recentActivity(clock).milliseconds, 1000);
    expect(stats.recentActivity(clock).playCount, 0);
    expect(stats.recentActivity(clock).complete, isFalse);
    expect(() => PlaybackStatistics.validateSnapshot(stats.snapshot()),
        returnsNormally);
  });

  test('84 inclusive local dates and leap anniversary use exact totals', () {
    final weeks =
        ListeningCalendar(now: now, dailyMilliseconds: {}, dailyPlayCounts: {});
    expect(weeks.daysInRange.length, 84);
    expect(weeks.start, DateTime(2026, 7, 6));
    final leap = ListeningCalendar(
        now: DateTime(2024, 2, 29),
        range: ListeningCalendarRange.year,
        dailyMilliseconds: {
          '2023-02-28': 99,
          '2023-03-01': 100,
          '2024-02-29': 200
        },
        dailyPlayCounts: {'2023-03-01': 2, '2024-02-29': 3},
        playCountTrackingStartedOn: '2023-03-01');
    expect(leap.start, DateTime(2023, 3, 1));
    expect(leap.daysInRange.length, 366);
    expect(leap.rangeMilliseconds, 300);
    expect(leap.rangePlayCount, 5);
    expect(leap.rangeActiveWeeks, 2);
  });

  test('saved listening insights respect range, gaps, ties and empty today',
      () {
    final calendar = ListeningCalendar(
        now: DateTime(2026, 9, 27),
        dailyPlayCounts: {},
        dailyMilliseconds: {
          '2026-09-21': 1000,
          '2026-09-22': 1000,
          '2026-09-23': 1000,
          '2026-09-25': 1000,
          '2026-09-26': 4000,
        });
    expect(calendar.currentStreak, 2);
    expect(calendar.longestStreak, 3);
    expect(calendar.busiestDay!.key, '2026-09-26');
    expect(calendar.favoriteWeekday, DateTime.saturday);
    expect(calendar.weekendPercent, 50);
    expect(calendar.averageDailyMilliseconds, 8000 ~/ 84);
    expect(calendar.rangeActiveWeeks, 1);
  });

  test('artist and album rankings exclude ambiguous identities and namesakes',
      () {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 4,
      'tracks': [
        for (final item in [
          ('a', 'Artist A', 'Shared', 2, false),
          ('b', 'Artist A', 'Other', 3, false),
          ('c', 'Artist B', 'Shared', 7, false),
          ('d', 'Artist A', 'Shared', 99, true)
        ])
          TrackPlaybackStatistics(
                  id: item.$1,
                  title: item.$1,
                  artist: item.$2,
                  album: item.$3,
                  online: false,
                  playCount: item.$4,
                  legacyUnassigned: item.$5)
              .toMap(),
      ]
    });
    addTearDown(stats.dispose);
    final artists = stats.groupedRankings(albums: false);
    expect(artists.length, 2);
    expect(artists.first.playCount, 5);
    expect(stats.groupedRankings(albums: true).length, 3);
  });
}
