import 'playback_pitch.dart';
import 'playback_rate.dart';

/// Explicit user preferences for one stable track, independent of defaults.
class TrackPlaybackSettings {
  const TrackPlaybackSettings({required this.rate, required this.pitch});
  final double rate;
  final double pitch;

  void validate() {
    PlaybackRate.validate(rate);
    PlaybackPitch.validate(pitch);
  }

  Map<String, double> toMap() => {'rate': rate, 'pitch': pitch};

  /// A damaged optional profile must not make ratings/tags unreadable.
  static TrackPlaybackSettings? decode(Object? value) {
    if (value is! Map) return null;
    final rate = value['rate'], pitch = value['pitch'];
    if (rate is! num ||
        pitch is! num ||
        !rate.isFinite ||
        !pitch.isFinite ||
        rate < PlaybackRate.min ||
        rate > PlaybackRate.max ||
        pitch < PlaybackPitch.min ||
        pitch > PlaybackPitch.max) {
      return null;
    }
    return TrackPlaybackSettings(
        rate: rate.toDouble(), pitch: pitch.toDouble());
  }
}

typedef TrackPlaybackRevision = ({int rate, int pitch});
typedef TrackPlaybackCapture = ({
  String? track,
  int session,
  TrackPlaybackRevision revision
});

/// Manual defaults win over an older source-open snapshot, separately for
/// each parameter. Native output recovery does not create a new selection.
class TrackPlaybackOwnership {
  int _rate = 0, _pitch = 0;
  TrackPlaybackRevision get revision => (rate: _rate, pitch: _pitch);
  void changedRate() => _rate++;
  void changedPitch() => _pitch++;
  void changedTrackSettings() {
    _rate++;
    _pitch++;
  }

  TrackPlaybackSettings resolve(
          {required TrackPlaybackRevision opening,
          required TrackPlaybackSettings defaults,
          TrackPlaybackSettings? saved}) =>
      TrackPlaybackSettings(
          rate: opening.rate == _rate
              ? saved?.rate ?? defaults.rate
              : defaults.rate,
          pitch: opening.pitch == _pitch
              ? saved?.pitch ?? defaults.pitch
              : defaults.pitch);

  bool accepts(TrackPlaybackCapture captured,
          {required String track,
          required String? currentTrack,
          required int session}) =>
      captured.track == track &&
      currentTrack == track &&
      captured.session == session &&
      captured.revision == revision;
}
