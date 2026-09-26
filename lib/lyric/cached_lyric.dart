import 'dart:convert';
import 'package:dan_player/lyric/local_lyric_origin.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';

/// Editable tags and provider preferences must not turn an existing saved
/// result into another automatic network search for the same library track.
String onlineLyricCacheIdentity(Audio audio, {LyricSource? source}) =>
    jsonEncode([2, audio.stableTrackId, source?.toMap()]);

String _legacyOnlineCacheIdentity(Audio audio, {LyricSource? source}) {
  final settings = AppSettings.instance;
  // Metadata/provider changes naturally select a new cache entry. Do not
  // include the display offset: cached timestamps must remain canonical.
  return jsonEncode([
    1,
    audio.stableTrackId,
    audio.title,
    audio.artist,
    audio.album,
    audio.duration,
    source?.toMap(),
    settings.onlineSources.value.toJson(),
    settings.customMusicSources.value
        .map((profile) => profile.toJson())
        .toList(),
  ]);
}

Future<Lyric?> readCachedOnlineLyric(Audio audio,
        {LyricSource? source, OnlineLyricCache? cache}) =>
    (cache ?? OnlineLyricCache.instance).read(
      onlineLyricCacheIdentity(audio, source: source),
      legacyIdentity: () => _legacyOnlineCacheIdentity(audio, source: source),
    );

/// The online priority stage must not consume a local snapshot before the
/// fresh sidecar/tag stage has had a chance to see externally authored lyrics.
Future<Lyric?> readAvailableCachedOnlineLyric(Audio audio,
    {LyricSource? source,
    OnlineLyricCache? cache,
    bool Function()? stillCurrent}) async {
  if (source?.source == LyricSourceType.local) return null;
  for (final candidate in <LyricSource?>[if (source != null) source, null]) {
    if (stillCurrent?.call() == false) return null;
    final lyric =
        await readCachedOnlineLyric(audio, source: candidate, cache: cache);
    if (stillCurrent?.call() == false) return null;
    if (lyric != null) return lyric;
  }
  return null;
}

Future<Lyric?> readCachedLocalLyric(Audio audio,
    {OnlineLyricCache? cache, bool Function()? stillCurrent}) async {
  if (audio.isOnline || stillCurrent?.call() == false) return null;
  final lyric = await readCachedOnlineLyric(audio,
      source: LyricSource(LyricSourceType.local), cache: cache);
  if (stillCurrent?.call() == false) return null;
  if (lyric != null) {
    markDiscoveredLocalLyric(lyric, 'cache:${audio.stableTrackId}');
  }
  return lyric;
}

/// One offline entry point for source-specific, default and local snapshots.
Future<Lyric?> readAvailableCachedLyric(Audio audio,
    {LyricSource? source,
    OnlineLyricCache? cache,
    bool localFirst = true}) async {
  if (source != null &&
      !isLyricSourceCompatible(
          isOnline: audio.isOnline, source: source.source)) {
    source = null;
  }
  final local = LyricSource(LyricSourceType.local);
  final sources = source?.source == LyricSourceType.local
      ? <LyricSource?>[local]
      : <LyricSource?>[
          if (source != null) source,
          if (localFirst && audio.isLocal) local,
          null,
          if (!localFirst && audio.isLocal) local,
        ];
  for (final candidate in sources) {
    final lyric =
        await readCachedOnlineLyric(audio, source: candidate, cache: cache);
    if (lyric != null) {
      if (candidate?.source == LyricSourceType.local) {
        markDiscoveredLocalLyric(lyric, 'cache:${audio.stableTrackId}');
      }
      return lyric;
    }
  }
  return null;
}

/// Keep discovered local lyrics in the same cache, without replacing online
/// choices or user-authored documents. A successful disk commit notifies search.
Future<Lyric?> cacheLocalLyric(Audio audio, Lyric lyric,
        {OnlineLyricCache? cache, bool Function()? shouldStore}) =>
    (cache ?? OnlineLyricCache.instance).resolve(
        onlineLyricCacheIdentity(audio,
            source: LyricSource(LyricSourceType.local)),
        () async => lyric,
        refresh: true,
        shouldStore: shouldStore);
