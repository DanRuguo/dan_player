import 'dart:math' as math;

/// Exact observed listening intervals, retained separately from lifetime buckets.
/// The horizon is bounded; old daily totals never invent sub-day timestamps.
class RecentListeningActivity {
  RecentListeningActivity({
    required this.now,
    required int? trackingStartedAt,
    required List<int> playStarts,
    required List<List<int>> intervals,
  }) : start = now.subtract(const Duration(hours: 24)) {
    final lower = start.millisecondsSinceEpoch;
    final upper = now.millisecondsSinceEpoch;
    complete = trackingStartedAt != null && trackingStartedAt <= lower;
    recordedSince = trackingStartedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            math.max(lower, trackingStartedAt));
    playCount = trackingStartedAt == null
        ? null
        : playStarts.where((time) => time >= lower && time <= upper).length;
    for (final interval in intervals) {
      final begin = math.max(lower, interval[0]);
      final end = math.min(upper, interval[1]);
      if (end <= begin) continue;
      milliseconds += end - begin;
      longestIntervalMilliseconds =
          math.max(longestIntervalMilliseconds, end - begin);
      // Each bar is one elapsed hour in the rolling window, including DST days.
      var cursor = begin;
      while (cursor < end) {
        final index =
            ((cursor - lower) ~/ Duration.millisecondsPerHour).clamp(0, 23);
        final boundary =
            math.min(end, lower + (index + 1) * Duration.millisecondsPerHour);
        hourlyMilliseconds[index] += boundary - cursor;
        cursor = boundary;
      }
    }
  }

  final DateTime now;
  final DateTime start;
  late final bool complete;
  late final DateTime? recordedSince;
  late final int? playCount;
  int milliseconds = 0;

  /// Longest observed continuous interval, clipped to this rolling window.
  /// Gaps and unknown history are never joined or reconstructed.
  int longestIntervalMilliseconds = 0;
  final List<int> hourlyMilliseconds = List.filled(24, 0);
  int get activeHours => hourlyMilliseconds.where((value) => value > 0).length;
  List<int> get peakHours {
    final peak = hourlyMilliseconds.fold(0, math.max);
    return peak == 0
        ? const []
        : [
            for (var i = 0; i < 24; i++)
              if (hourlyMilliseconds[i] == peak) i
          ];
  }

  DateTime hourStart(int index) => start.add(Duration(hours: index));
}
