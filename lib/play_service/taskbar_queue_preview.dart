import 'package:dan_player/play_service/playback_modes.dart';

/// Read-only natural continuation. A future shuffled cycle has not been
/// generated yet, so its first item cannot truthfully be advertised.
int? knownNextQueueIndex({
  required int length,
  required int currentIndex,
  required PlayMode playMode,
  required bool shuffle,
  bool canAdvance = true,
  bool stopAtCurrent = false,
  bool repeatingSegment = false,
}) {
  if (!canAdvance ||
      stopAtCurrent ||
      repeatingSegment ||
      currentIndex < 0 ||
      currentIndex >= length) {
    return null;
  }
  final next = nextQueueAdvance(
      length: length,
      currentIndex: currentIndex,
      playMode: playMode,
      shuffle: shuffle,
      automatic: true);
  return next.newShuffleCycle && length > 1 ? null : next.index;
}
