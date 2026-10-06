import 'package:dan_player/statistics/recent_listening_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  int at(int minutes) =>
      now.add(Duration(minutes: minutes)).millisecondsSinceEpoch;

  test(
      'longest listening clips edges and does not join pause gaps or future data',
      () {
    final recent = RecentListeningActivity(
        now: now,
        trackingStartedAt: at(-2880),
        playStarts: [],
        intervals: [
          [at(-1500), at(-1420)], // Only 20 minutes inside the window.
          [at(-90), at(-55)],
          [at(-54), at(-20)], // A real gap; these are not a 70-minute session.
          [at(-10), at(60)], // Only the ten observed minutes count.
          [at(70), at(160)], // Entirely in the future.
        ]);
    expect(recent.longestIntervalMilliseconds, 35 * 60000);
    expect(recent.milliseconds, 99 * 60000);
    expect(recent.complete, isTrue);
  });

  test('unknown empty history and a truncated window do not invent a session',
      () {
    final unknown = RecentListeningActivity(
        now: now, trackingStartedAt: null, playStarts: [], intervals: []);
    expect(unknown.longestIntervalMilliseconds, 0);
    expect(unknown.recordedSince, isNull);
    final partial = RecentListeningActivity(
        now: now,
        trackingStartedAt: at(-15),
        playStarts: [],
        intervals: [
          [at(-12), at(-10)]
        ]);
    expect(partial.longestIntervalMilliseconds, 2 * 60000);
    expect(partial.complete, isFalse);
  });
}
