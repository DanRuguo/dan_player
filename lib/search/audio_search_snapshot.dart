import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:dan_player/statistics/playback_statistics.dart';

typedef SearchPlayback = ({
  int count,
  int completed,
  int skipped,
  int listened,
  int last
});
typedef SearchMetadata = ({
  int duration,
  int? bitrate,
  int? sampleRate,
  int? fileSize,
  int track
});

/// Immutable scalar projections for one yielding query. Text/path projections
/// remain owned by the structural index; personal data and history never enter
/// its pinyin cache or force the whole text index to rebuild.
class AudioSearchSnapshot {
  const AudioSearchSnapshot._(
      this.personal, this.history, this.uncertain, this.metadata);
  static const empty = AudioSearchSnapshot._({}, {}, {}, {});
  final Map<String, PersonalTrack> personal;
  final Map<String, SearchPlayback> history;
  final Set<String> uncertain;
  final Map<Audio, SearchMetadata> metadata;

  factory AudioSearchSnapshot.capture(AudioSearchQuery query,
      {Map<String, PersonalTrack>? personal,
      PlaybackStatistics? statistics,
      Iterable<Audio> audios = const []}) {
    final recorder = statistics ?? PlaybackStatistics.instance;
    return AudioSearchSnapshot._(
      query.usesPersonalData
          ? {
              for (final item in (personal ?? PersonalLibrary.latest).entries)
                item.key: PersonalTrack(
                    rating: item.value.rating,
                    tags: List.unmodifiable(item.value.tags),
                    firstAddedAtUtc: item.value.firstAddedAtUtc),
            }
          : const {},
      query.usesPlaybackHistory
          ? {
              for (final item in recorder.tracks.entries)
                if (!item.value.legacyUnassigned)
                  item.key: (
                    count: item.value.playCount,
                    completed: item.value.completedCount,
                    skipped: item.value.skippedCount,
                    listened: item.value.listenMilliseconds,
                    last: item.value.lastPlayedAt
                  ),
            }
          : const {},
      query.usesPlaybackHistory
          ? {
              for (final item in recorder.tracks.values)
                if (item.legacyUnassigned) ...item.candidateTrackIds,
            }
          : const {},
      query.usesLiveMetadata
          ? {
              for (final audio in audios)
                audio: (
                  duration: audio.duration,
                  bitrate: audio.bitrate,
                  sampleRate: audio.sampleRate,
                  fileSize: audio.fileSizeBytes,
                  track: audio.cueTrack?.number ?? audio.track
                ),
            }
          : const {},
    );
  }

  SearchPlayback? playbackOf(Audio audio) {
    final id = audio.isOnline
        ? 'online:${audio.onlineProvider}:${audio.onlineId}'
        : audio.stableTrackId;
    if (uncertain.contains(id)) return null;
    return history[id] ??
        (count: 0, completed: 0, skipped: 0, listened: 0, last: 0);
  }
}
