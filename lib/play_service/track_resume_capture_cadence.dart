import 'package:dan_player/library/track_resume_store.dart';

/// Avoid a storage Future on every visual position sample. The first eligible
/// media position is still captured immediately, including at fast playback
/// rates; later captures follow the store's wall-clock interval.
class TrackResumeCaptureCadence {
  TrackResumeCaptureCadence({Duration Function()? elapsed})
      : _clock = Stopwatch()..start(),
        _elapsedOverride = elapsed;

  final Stopwatch _clock;
  final Duration Function()? _elapsedOverride;
  int? _session;
  Duration? _lastCapture;

  bool due({required int session, required double position}) {
    // TrackResumeStore.remember rejects ordinary captures below 10 seconds.
    // Waiting to arm the cadence avoids delaying the first useful sample.
    if (!position.isFinite || position < 10) return false;
    final now = _elapsedOverride?.call() ?? _clock.elapsed;
    final previous = _lastCapture;
    if (_session == session &&
        previous != null &&
        now >= previous &&
        now - previous < TrackResumeStore.captureInterval) {
      return false;
    }
    _session = session;
    _lastCapture = now;
    return true;
  }
}
