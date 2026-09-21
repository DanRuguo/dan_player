import 'dart:ffi';

import 'package:dan_player/play_service/replay_gain.dart';

typedef BassSetVolumeAttribute = bool Function(
    int stream, int attribute, double value);
typedef BassSlideVolumeAttribute = bool Function(
    int stream, int attribute, double value, int milliseconds);

/// User volume belongs after the decoded playback buffer. VOLDSP changes only
/// affect newly decoded samples and can therefore be heard much later.
/// BASSmix also applies each decoding source's VOL while mixing it.
class BassPlaybackVolume {
  BassPlaybackVolume(
      {required this.setAttribute, required this.slideAttribute});

  factory BassPlaybackVolume.native(DynamicLibrary library) {
    final set = library.lookupFunction<Int32 Function(Uint32, Uint32, Float),
        int Function(int, int, double)>('BASS_ChannelSetAttribute');
    final slide = library.lookupFunction<
        Int32 Function(Uint32, Uint32, Float, Uint32),
        int Function(int, int, double, int)>('BASS_ChannelSlideAttribute');
    return BassPlaybackVolume(
      setAttribute: (stream, attribute, value) =>
          set(stream, attribute, value) != 0,
      slideAttribute: (stream, attribute, value, milliseconds) =>
          slide(stream, attribute, value, milliseconds) != 0,
    );
  }

  static const playbackAttribute = 2;
  static const dspAttribute = 19;
  static const smoothingMilliseconds = 70;
  final BassSetVolumeAttribute setAttribute;
  final BassSlideVolumeAttribute slideAttribute;

  /// ReplayGain stays in the DSP chain. Factor its former combined target so
  /// peak protection retains exactly the same total gain at every user volume.
  static double playbackMultiplier(double volume, ReplayGainTags tags,
          ReplayGainPreferences preferences, double dspBase) =>
      tags.volume(volume, preferences) / dspBase;

  double initialize(int stream, double volume, ReplayGainTags tags,
      ReplayGainPreferences preferences) {
    final dspBase = tags.volume(1, preferences);
    _set(stream, dspAttribute, dspBase);
    target(stream, volume, tags, preferences, dspBase: dspBase, smooth: false);
    return dspBase;
  }

  void target(int stream, double volume, ReplayGainTags tags,
      ReplayGainPreferences preferences,
      {required double dspBase, required bool smooth}) {
    final target = playbackMultiplier(volume, tags, preferences, dspBase);
    if (!target.isFinite || target < 0) {
      throw ArgumentError.value(volume, 'volume', 'Invalid playback gain');
    }
    // A new native slide starts at its current value, including when reversed
    // mid-drag. Mute/paused/source initialization must bypass the ramp entirely.
    if (smooth &&
        target > 0 &&
        slideAttribute(
            stream, playbackAttribute, target, smoothingMilliseconds)) {
      return;
    }
    // A missing slide capability must still honor the requested volume.
    _set(stream, playbackAttribute, target);
  }

  void _set(int stream, int attribute, double value) {
    if (!setAttribute(stream, attribute, value)) {
      throw const FormatException('Unable to apply playback volume.');
    }
  }
}
