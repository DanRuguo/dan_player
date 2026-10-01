import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'playback_timeline_bookmarks.dart';
import 'waveform_progress.dart';

/// The lyrics page's timeline only: seek, waveform, bookmarks and segment loop.
/// All current and future sleep/stop status belongs to CurrentPlaylistView's
/// shared queue header, never to a footer below this timeline.
class NowPlayingProgress extends StatelessWidget {
  const NowPlayingProgress({
    super.key,
    required this.playbackService,
    required this.waveformEnabled,
    required this.waveformDensity,
    this.hidden,
  });

  final PlaybackService playbackService;
  final bool waveformEnabled;
  final WaveformBarDensity waveformDensity;
  final ValueListenable<bool>? hidden;

  @override
  Widget build(BuildContext context) {
    final playback = playbackService;
    return PlaybackTimelineBookmarks(
      audio: playback.nowPlaying,
      hidden: hidden,
      builder: (bookmarks) => WaveformProgress(
        audio: playback.nowPlaying,
        bookmarks: bookmarks,
        loopStart: playback.segmentLoop.start,
        loopEnd: playback.segmentLoop.end,
        loopEnabled: playback.segmentLoop.enabled,
        waveformDensity: waveformDensity,
        waveformEnabled: waveformEnabled,
        positions: playback.positionStream,
        readPosition: () => playback.position,
        duration: playback.length,
        trackIdentity: (
          playback.nowPlaying?.path,
          playback.playbackSessionToken
        ),
        enabled: playback.nowPlaying != null && playback.canEditQueue,
        onSeek: playback.seek,
        hidden: hidden,
      ),
    );
  }
}
