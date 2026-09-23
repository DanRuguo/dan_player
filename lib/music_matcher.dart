import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source_exception.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/online/lrclib_lyrics.dart';
import 'package:dan_player/online/qq_public_search.dart';
import 'package:dan_player/utils.dart';
import 'package:music_api/music_api.dart';

enum ResultSource { qq, kugou, netease, lrclib }

extension ResultSourceDisplay on ResultSource {
  String get sourceLabel => switch (this) {
        ResultSource.qq => 'QQ音乐',
        ResultSource.kugou => '酷狗音乐',
        ResultSource.netease => '网易云音乐',
        ResultSource.lrclib => 'LRCLIB',
      };
}

typedef LyricProviderPayloadLoader = Future<Object?> Function(
  String query,
  int limit,
);
typedef NeteaseLyricPayloadLoader = Future<Object?> Function(String songId);
typedef LrclibRecordPayloadLoader = Future<Object?> Function(int recordId);
typedef QqLyricPayloadLoader = Future<Object?> Function(
  int? songId,
  String? songMid,
);

class LyricSearchResponse {
  LyricSearchResponse({
    required List<SongSearchResult> candidates,
    required Map<ResultSource, String> failures,
    this.sourcesDisabled = false,
  })  : candidates = List.unmodifiable(candidates),
        failures = Map.unmodifiable(failures);

  final List<SongSearchResult> candidates;
  final Map<ResultSource, String> failures;
  final bool sourcesDisabled;

  bool get hasPartialFailure => candidates.isNotEmpty && failures.isNotEmpty;
}

class _LyricProviderException implements Exception {
  const _LyricProviderException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;
}

class _ProviderSearchResult {
  const _ProviderSearchResult(this.source, this.candidates, [this.failure]);

  final ResultSource source;
  final List<SongSearchResult> candidates;
  final String? failure;
}

class LyricApiConnectivityResult {
  final bool isReachable;
  final bool lyricRecognized;
  final String message;
  final int? statusCode;

  const LyricApiConnectivityResult({
    required this.isReachable,
    required this.lyricRecognized,
    required this.message,
    this.statusCode,
  });
}

final RegExp _matchSeparators = RegExp(
  r'[\s\u3000_\-—–·•・、,，.。!！?？:：;；/\\|｜&＆+＋()\[\]{}（）【】「」『』<>《》]+',
  unicode: true,
);

final RegExp _trailingBracketedVersion = RegExp(
  r'\s*[\(（\[【]\s*(?:(?:op|ed|opening|ending)\s*[-–—_:]?\s*)?(?:short|full|tv)?\s*(?:ver(?:sion)?\.?|size|edit|mix|inst(?:rumental)?)\s*[\)）\]】]\s*$',
  caseSensitive: false,
  unicode: true,
);
final RegExp _trailingVersion = RegExp(
  r'\s+(?:short|full|tv)\s*(?:ver(?:sion)?\.?|size|edit|mix)\s*$',
  caseSensitive: false,
  unicode: true,
);
final RegExp _trailingRoleMarker = RegExp(
  r'\s*[-–—_]\s*(?:op|ed|opening|ending)\s*[-–—_]?\s*$',
  caseSensitive: false,
  unicode: true,
);

/// Removes only common trailing release descriptors for matching/search.
/// The original title stored in the library is never changed.
String canonicalSongTitleForMatch(String value) {
  var title = value.trim();
  while (title.isNotEmpty) {
    final before = title;
    title = title
        .replaceFirst(_trailingBracketedVersion, '')
        .replaceFirst(_trailingVersion, '')
        .replaceFirst(_trailingRoleMarker, '')
        .trim();
    if (title == before) break;
  }
  return title.isEmpty ? value.trim() : title;
}

String songMatchSearchQuery(Audio audio) {
  final rawTitle =
      _meaningfulMatchValue(audio.title) ? audio.title : audio.fileNameTitle;
  final title = canonicalSongTitleForMatch(rawTitle);
  final artist = _meaningfulMatchValue(audio.artist) ? audio.artist.trim() : '';
  return [title, if (artist.isNotEmpty) artist].join(' ').trim();
}

List<String> songMatchSearchQueries(Audio audio) {
  final title = canonicalSongTitleForMatch(
    _meaningfulMatchValue(audio.title) ? audio.title : audio.fileNameTitle,
  );
  final contextual = songMatchSearchQuery(audio);
  return {
    if (contextual.isNotEmpty) contextual,
    if (title.isNotEmpty) title,
  }.toList(growable: false);
}

String normalizeSongMatchText(String value) {
  final normalized = StringBuffer();
  for (final rune in value.trim().runes) {
    if (rune == 0x3000) {
      normalized.write(' ');
    } else if (rune >= 0xff01 && rune <= 0xff5e) {
      normalized.writeCharCode(rune - 0xfee0);
    } else {
      normalized.writeCharCode(rune);
    }
  }
  return normalized.toString().toLowerCase().replaceAll(_matchSeparators, '');
}

bool _meaningfulMatchValue(String value) {
  final normalized = normalizeSongMatchText(value);
  return normalized.isNotEmpty &&
      !const {'unknown', '未知', '未知艺术家', '未知专辑'}.contains(normalized);
}

double _fieldSimilarity(String expected, String candidate) {
  final left = normalizeSongMatchText(expected);
  final right = normalizeSongMatchText(candidate);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;

  final leftRunes = left.runes.toList(growable: false);
  final rightRunes = right.runes.toList(growable: false);
  final shorter = min(leftRunes.length, rightRunes.length);
  final longer = max(leftRunes.length, rightRunes.length);
  if (left.contains(right) || right.contains(left)) {
    return 0.78 + 0.18 * (shorter / longer);
  }
  if (shorter == 1) return leftRunes.first == rightRunes.first ? 0.5 : 0;

  Map<String, int> pairs(List<int> runes) {
    final result = <String, int>{};
    for (var index = 0; index + 1 < runes.length; index++) {
      final pair = String.fromCharCodes([runes[index], runes[index + 1]]);
      result[pair] = (result[pair] ?? 0) + 1;
    }
    return result;
  }

  final leftPairs = pairs(leftRunes);
  final rightPairs = pairs(rightRunes);
  var overlap = 0;
  for (final entry in leftPairs.entries) {
    overlap += min(entry.value, rightPairs[entry.key] ?? 0);
  }
  return (2 * overlap) / ((leftRunes.length - 1) + (rightRunes.length - 1));
}

double computeSongMatchScore(
  Audio audio,
  String title,
  String artists,
  String album,
) {
  final expectedTitle = canonicalSongTitleForMatch(
    _meaningfulMatchValue(audio.title) ? audio.title : audio.fileNameTitle,
  );
  final fields = <(String, String, double)>[
    (expectedTitle, canonicalSongTitleForMatch(title), 0.74),
    (audio.artist, artists, 0.18),
    (audio.album, album, 0.08),
  ];
  var score = 0.0;
  var availableWeight = 0.0;
  for (final (expected, candidate, weight) in fields) {
    if (!_meaningfulMatchValue(expected)) continue;
    availableWeight += weight;
    score += _fieldSimilarity(expected, candidate) * weight;
  }
  return availableWeight == 0 ? 0 : score / availableWeight;
}

class SongSearchResult {
  final ResultSource source;
  final String title;
  final String artists;
  final String album;
  final double score;

  /// Match groups use the same precision shown in the candidate list.
  int get matchPercent => (score * 100).round();
  final bool scoreVerified;
  final Lyric? previewLyric;

  /// Duration supplied by the search response; null means version unverified.
  final double? durationSeconds;

  /// for qq result
  final int? qqSongId;
  final String? qqSongMid;

  /// for netease result
  final String? neteaseSongId;

  /// for kugou result
  final String? kugouSongHash;

  /// for LRCLIB result
  final int? lrclibId;

  /// Retains the exact editable provider snapshot until a candidate is chosen.
  final CustomMusicSourceProfile? customProfile;
  final Audio? customAudio;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.scoreVerified = true,
      this.previewLyric,
      this.durationSeconds,
      this.qqSongId,
      this.qqSongMid,
      this.neteaseSongId,
      this.kugouSongHash,
      this.lrclibId,
      this.customProfile,
      this.customAudio});

  String get sourceLabel => customProfile?.name ?? source.sourceLabel;

  String get identity => !scoreVerified && customProfile != null
      ? 'manual-custom:${customProfile!.id}'
      : customProfile != null && customProfile!.id != 'kugou'
          ? 'custom:${customProfile!.id}:${customAudio?.onlineId ?? title}'
          : switch (source) {
              ResultSource.qq => 'qq:${qqSongId ?? qqSongMid ?? ''}',
              ResultSource.kugou => 'kugou:${kugouSongHash ?? ''}',
              ResultSource.netease => 'netease:${neteaseSongId ?? ''}',
              ResultSource.lrclib => 'lrclib:${lrclibId ?? ''}',
            };

  @override
  String toString() {
    return json.encode({
      "source": source.toString(),
      "title": title,
      "artists": artists,
      "album": album,
      "score": score,
    });
  }
}

const _providerTimeout = Duration(seconds: 12);
const _customLyricSweepTimeout = Duration(seconds: 8);
const _lyricResponseByteLimit = 2 * 1024 * 1024;

/// One user-managed lyric provider that can be requested explicitly from the
/// lyric editor. It deliberately stays separate from [ResultSource]: custom
/// providers are profiles, not built-in search-result platforms.
class CustomLyricSourceChoice {
  const CustomLyricSourceChoice(this.profile);

  final CustomMusicSourceProfile profile;

  String get identity => 'custom-lyric:${profile.id}';
}

/// Returns a stable snapshot of selectable custom lyric providers.
///
/// Metadata-based Dan v1 and legacy endpoints can look up local tracks. The
/// go-music-api preset instead needs the opaque identity produced by the same
/// profile's search response, so it is never offered for an unrelated track.
List<CustomLyricSourceChoice> customLyricSourceChoicesFor(
  Audio audio, {
  Iterable<CustomMusicSourceProfile>? profiles,
}) =>
    List<CustomLyricSourceChoice>.unmodifiable(
      (profiles ?? AppSettings.instance.customMusicSources.value)
          .where((profile) => _customLyricProfileCanQuery(profile, audio))
          .map(CustomLyricSourceChoice.new),
    );

bool _customLyricProfileCanQuery(
  CustomMusicSourceProfile profile,
  Audio audio,
) {
  if (!profile.enabled ||
      profile.authentication != null ||
      !profile.capabilities.contains(CustomMusicSourceCapability.lyrics)) {
    return false;
  }
  if (profile.protocol != CustomMusicSourceProtocol.goMusicApi) return true;
  return audio.onlineProvider == profile.providerId &&
      _hasUsableGoMusicIdentity(audio.onlineId);
}

bool _hasUsableGoMusicIdentity(String? value) {
  if (value == null || !value.startsWith('gma1.') || value.length > 16384) {
    return false;
  }
  try {
    var encoded = value.substring('gma1.'.length);
    encoded += '=' * ((4 - encoded.length % 4) % 4);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
    if (decoded is! Map) return false;
    return <Object?>[
      decoded['id'],
      decoded['source'],
      decoded['name'],
    ].every((field) => field is String && field.trim().isNotEmpty);
  } on Object {
    return false;
  }
}

Set<ResultSource> _configuredLyricSearchSources() {
  final preferences = AppSettings.instance.onlineSources.value;
  return {
    if (preferences.qqEnabled) ResultSource.qq,
    if (_configuredKugouLyricProfile(needsSearch: true) != null)
      ResultSource.kugou,
    if (preferences.neteaseEnabled) ResultSource.netease,
    if (AppSettings.instance.lrclibEnabled.value) ResultSource.lrclib,
  };
}

CustomMusicSourceProfile? _configuredKugouLyricProfile({
  bool needsSearch = false,
}) {
  for (final profile in AppSettings.instance.customMusicSources.value) {
    if (profile.id == 'kugou' &&
        profile.enabled &&
        profile.authentication == null &&
        profile.capabilities.contains(CustomMusicSourceCapability.lyrics) &&
        (!needsSearch ||
            profile.capabilities
                .contains(CustomMusicSourceCapability.search))) {
      return profile;
    }
  }
  return null;
}

Future<Object?> _loadQqSearchPayload(String query, int limit) async {
  try {
    final songs = await QqPublicSearchTransport()
        .search(query, limit)
        .timeout(_providerTimeout);
    return {
      'code': 0,
      'req': {
        'code': 0,
        'data': {
          'body': {
            'item_song': [
              for (final song in songs) song.toMusicApiSearchRow(),
            ],
          },
        },
      },
    };
  } on QqPublicSearchException catch (error) {
    throw _LyricProviderException(
      error.message,
      retryable: error.retryable,
    );
  }
}

Future<Object?> _loadNeteaseSearchPayload(String query, int limit) async {
  final answer = await Netease.search(keyWord: query, size: limit)
      .timeout(_providerTimeout);
  _requireTransportCode(answer.code, ResultSource.netease);
  return answer.data;
}

void _requireTransportCode(int code, ResultSource source) {
  if (code == 200) return;
  throw _LyricProviderException(
    '${_sourceLabel(source)}搜索失败（服务代码 $code）',
    retryable: code == 408 ||
        code == 429 ||
        code == 2001 ||
        (code >= 500 && code <= 599),
  );
}

Future<LyricSearchResponse> searchLyricCandidates(
  Audio audio, {
  Set<ResultSource>? sources,
  LyricProviderPayloadLoader? qqSearch,
  LyricProviderPayloadLoader? neteaseSearch,
  LyricProviderPayloadLoader? kugouSearch,
  LyricProviderPayloadLoader? lrclibSearch,
  int perSourceLimit = 20,
  int maxAttempts = 2,
  Duration retryDelay = const Duration(milliseconds: 160),
}) async {
  final enabled = sources ?? _configuredLyricSearchSources();
  final extraProfiles = sources == null
      ? AppSettings.instance.customMusicSources.value
          .where((profile) =>
              profile.id != 'kugou' &&
              profile.enabled &&
              profile.authentication == null &&
              profile.capabilities
                  .contains(CustomMusicSourceCapability.search) &&
              profile.capabilities.contains(CustomMusicSourceCapability.lyrics))
          .toList()
      : <CustomMusicSourceProfile>[];
  if (enabled.isEmpty && extraProfiles.isEmpty) {
    return LyricSearchResponse(
      candidates: const [],
      failures: const {},
      sourcesDisabled: true,
    );
  }
  final limit = perSourceLimit.clamp(1, 50).toInt();
  final attempts = maxAttempts.clamp(1, 3).toInt();
  final queries = songMatchSearchQueries(audio);
  final lrclibTransport = LrclibLyricsTransport();
  final loaders = <ResultSource, LyricProviderPayloadLoader>{
    ResultSource.qq: qqSearch ?? _loadQqSearchPayload,
    ResultSource.kugou: kugouSearch ??
        (query, limit) async {
          final profile = _configuredKugouLyricProfile(needsSearch: true);
          if (profile == null) return <SongSearchResult>[];
          final response = await CustomMusicSourceTransport(profile)
              .search(query, limit: limit);
          if (!_isCurrentCustomLyricProfile(profile)) {
            return <SongSearchResult>[];
          }
          return [
            for (final track in response.tracks)
              SongSearchResult(
                ResultSource.kugou,
                track.title,
                track.artist,
                track.album,
                computeSongMatchScore(
                    audio, track.title, track.artist, track.album),
                kugouSongHash: track.onlineId,
                customProfile: profile,
                customAudio: track,
                durationSeconds: _positiveSeconds(track.duration),
              ),
          ];
        },
    ResultSource.netease: neteaseSearch ?? _loadNeteaseSearchPayload,
    ResultSource.lrclib: lrclibSearch ??
        (query, limit) async {
          final title = canonicalSongTitleForMatch(
            _meaningfulMatchValue(audio.title)
                ? audio.title
                : audio.fileNameTitle,
          );
          final contextualQuery = queries.length > 1 && query == queries.first;
          final records = await lrclibTransport
              .search(
                trackName: title,
                artistName:
                    contextualQuery && _meaningfulMatchValue(audio.artist)
                        ? audio.artist
                        : null,
                limit: limit,
              )
              .timeout(_providerTimeout);
          return [for (final record in records) record.toJson()];
        },
  };
  final extraSearch = Future.wait(extraProfiles.map((profile) async {
    final found = <SongSearchResult>[];
    try {
      for (final query in queries) {
        final response = await CustomMusicSourceTransport(profile)
            .search(query, limit: limit)
            .timeout(_providerTimeout);
        if (!_isCurrentCustomLyricProfile(profile)) return <SongSearchResult>[];
        for (final track in response.tracks) {
          found.add(SongSearchResult(
              ResultSource.kugou,
              track.title,
              track.artist,
              track.album,
              computeSongMatchScore(
                  audio, track.title, track.artist, track.album),
              customProfile: profile,
              customAudio: track,
              durationSeconds: _positiveSeconds(track.duration)));
        }
        if (found.isNotEmpty) break;
      }
    } catch (error, trace) {
      LOGGER.w('[lyric/custom-search:${profile.id}] 候选搜索失败', stackTrace: trace);
    }
    return found;
  }));
  final outcomes = await Future.wait([
    for (final source in ResultSource.values)
      if (enabled.contains(source))
        _searchLyricSource(
          source: source,
          audio: audio,
          queries: queries,
          limit: limit,
          attempts: attempts,
          retryDelay: retryDelay,
          loader: loaders[source]!,
        ),
  ]);

  final failures = <ResultSource, String>{};
  final unique = <String, SongSearchResult>{};
  for (final outcome in outcomes) {
    if (outcome.failure != null) failures[outcome.source] = outcome.failure!;
    for (final candidate in outcome.candidates) {
      final previous = unique[candidate.identity];
      if (previous == null || candidate.score > previous.score) {
        unique[candidate.identity] = candidate;
      }
    }
  }
  for (final group in await extraSearch) {
    for (final candidate in group) {
      final previous = unique[candidate.identity];
      if (previous == null || candidate.score > previous.score) {
        unique[candidate.identity] = candidate;
      }
    }
  }
  final candidates = unique.values.toList()..sort(compareLyricCandidates);
  return LyricSearchResponse(candidates: candidates, failures: failures);
}

List<SongSearchResult> visibleManualLyricCandidates(
        Iterable<SongSearchResult> candidates) =>
    (candidates
        .where((candidate) =>
            !candidate.scoreVerified ||
            (candidate.score.isFinite && candidate.score >= .6))
        .toList()
      ..sort(compareLyricCandidates));

/// Only explicit manual lookup queries metadata-only providers. Their returned
/// lyrics are selectable, clearly unscored, and never eligible for automation.
Future<LyricSearchResponse> searchManualLyricCandidates(Audio audio,
    {Future<LyricSearchResponse> Function(Audio)? rankedSearch}) async {
  final unscored = Future.wait(customLyricSourceChoicesFor(audio)
      .where((choice) => !choice.profile.capabilities
          .contains(CustomMusicSourceCapability.search))
      .map((choice) async {
    try {
      final lyric = await getLyricForCustomSourceChoice(audio, choice);
      if (lyric == null || lyric.lines.isEmpty) return null;
      return SongSearchResult(
          ResultSource.kugou, audio.title, audio.artist, audio.album, 0,
          scoreVerified: false,
          previewLyric: lyric,
          customProfile: choice.profile,
          customAudio: audio);
    } catch (_) {
      return null;
    }
  }));
  final ranked = await (rankedSearch ?? searchLyricCandidates)(audio);
  final candidates = visibleManualLyricCandidates([
    ...ranked.candidates,
    ...(await unscored).whereType<SongSearchResult>(),
  ]);
  return LyricSearchResponse(
      candidates: candidates,
      failures: ranked.failures,
      sourcesDisabled: ranked.sourcesDisabled && candidates.isEmpty);
}

/// Shared by the manual candidate list and automatic fallback. Word timing is
/// assessed only after loading a score group, never ahead of a higher match.
int compareLyricCandidates(SongSearchResult left, SongSearchResult right) {
  if (left.scoreVerified != right.scoreVerified) {
    return left.scoreVerified ? -1 : 1;
  }
  final score =
      left.scoreVerified ? right.matchPercent.compareTo(left.matchPercent) : 0;
  if (score != 0) return score;
  int priority(SongSearchResult candidate) {
    final custom = candidate.customProfile;
    if (custom != null) {
      final index = AppSettings.instance.customMusicSources.value
          .indexWhere((p) => p.id == custom.id);
      return 3 + (index < 0 ? 1000 : index);
    }
    return switch (candidate.source) {
      ResultSource.qq => 0,
      ResultSource.netease => 1,
      ResultSource.lrclib => 2,
      ResultSource.kugou => 1003,
    };
  }

  final source = priority(left).compareTo(priority(right));
  if (source != 0) return source;
  final title = normalizeSongMatchText(left.title)
      .compareTo(normalizeSongMatchText(right.title));
  return title != 0 ? title : left.identity.compareTo(right.identity);
}

Future<_ProviderSearchResult> _searchLyricSource({
  required ResultSource source,
  required Audio audio,
  required List<String> queries,
  required int limit,
  required int attempts,
  required Duration retryDelay,
  required LyricProviderPayloadLoader loader,
}) async {
  for (final query in queries) {
    Object? lastError;
    StackTrace? lastTrace;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final payload = await loader(query, limit).timeout(_providerTimeout);
        final candidates = switch (source) {
          ResultSource.qq => parseQqLyricSearchPayload(payload, audio, limit),
          ResultSource.kugou => payload is List<SongSearchResult>
              ? payload
              : parseKugouLyricSearchPayload(payload, audio, limit),
          ResultSource.netease =>
            parseNeteaseLyricSearchPayload(payload, audio, limit),
          ResultSource.lrclib =>
            parseLrclibLyricSearchPayload(payload, audio, limit),
        };
        if (candidates.isNotEmpty) {
          return _ProviderSearchResult(source, candidates);
        }
        // A valid empty result is a query mismatch, not a transport failure.
        // Try the title-only variant without repeating the same empty query.
        break;
      } catch (error, trace) {
        lastError = error;
        lastTrace = trace;
        if (attempt < attempts && _isRetryableSearchError(error)) {
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        final message = _searchFailureMessage(lastError);
        LOGGER.w(
          '[lyric search/${source.name}] $message',
          stackTrace: lastTrace,
        );
        return _ProviderSearchResult(source, const [], message);
      }
    }
  }
  return _ProviderSearchResult(source, const []);
}

bool _isRetryableSearchError(Object error) =>
    error is TimeoutException ||
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException ||
    (error is LrclibException && error.retryable) ||
    (error is _LyricProviderException && error.retryable);

String _searchFailureMessage(Object? error) {
  if (error is _LyricProviderException) return error.message;
  if (error is LrclibException) return error.message;
  if (error is TimeoutException) return '搜索超时，请重试。';
  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return '联网失败，请检查网络。';
  }
  return '返回的数据无法解析，请重试。';
}

String _sourceLabel(ResultSource source) => source.sourceLabel;

List<SongSearchResult> parseQqLyricSearchPayload(
  Object? payload,
  Audio audio,
  int limit,
) {
  final root = _requiredMap(payload, 'QQ音乐');
  _checkBusinessCode(root['code'], expected: 0, source: ResultSource.qq);
  _checkBusinessCode(
    _valueAt(root, const ['req', 'code']),
    expected: 0,
    source: ResultSource.qq,
  );
  final rows = _listAt(root, const ['req', 'data', 'body', 'item_song']) ??
      _listAt(root, const ['req', 'data', 'body', 'song', 'list']);
  if (rows == null) throw const FormatException('Missing QQ song list');
  final results = <SongSearchResult>[];
  for (final value in rows) {
    if (results.length >= limit) break;
    if (value is! Map) continue;
    final title = _stringText(value['name']) ??
        _stringText(value['title']) ??
        _stringText(value['songname']);
    if (title == null) continue;
    final artists = _joinedNames(value['singer'] ?? value['singers']);
    final albumValue = value['album'];
    final album = albumValue is Map
        ? _stringText(albumValue['title']) ??
            _stringText(albumValue['name']) ??
            ''
        : _stringText(albumValue) ?? _stringText(value['albumname']) ?? '';
    final id = _positiveInt(value['id'] ?? value['songid']);
    final mid = _stringText(value['mid']) ?? _stringText(value['songmid']);
    if (id == null && mid == null) continue;
    results.add(SongSearchResult(
      ResultSource.qq,
      title,
      artists,
      album,
      computeSongMatchScore(audio, title, artists, album),
      qqSongId: id,
      qqSongMid: mid,
      durationSeconds: _positiveSeconds(value['interval']),
    ));
  }
  return results;
}

List<SongSearchResult> parseNeteaseLyricSearchPayload(
  Object? payload,
  Audio audio,
  int limit,
) {
  final root = _requiredMap(payload, '网易云音乐');
  _checkBusinessCode(root['code'], expected: 200, source: ResultSource.netease);
  final rows = _listAt(root, const ['result', 'songs']);
  if (rows == null) throw const FormatException('Missing Netease song list');
  final results = <SongSearchResult>[];
  for (final value in rows) {
    if (results.length >= limit) break;
    if (value is! Map) continue;
    final title = _stringText(value['name']) ?? _stringText(value['title']);
    final id = _positiveNumericText(value['id']);
    if (title == null || id == null) continue;
    final artists = _joinedNames(value['artists'] ?? value['ar']);
    final albumValue = value['album'] ?? value['al'];
    final album = albumValue is Map
        ? _stringText(albumValue['name']) ?? ''
        : _stringText(albumValue) ?? '';
    results.add(SongSearchResult(
      ResultSource.netease,
      title,
      artists,
      album,
      computeSongMatchScore(audio, title, artists, album),
      neteaseSongId: id,
      durationSeconds: _positiveSeconds(value['duration'] ?? value['dt'],
          milliseconds: true),
    ));
  }
  return results;
}

List<SongSearchResult> parseKugouLyricSearchPayload(
  Object? payload,
  Audio audio,
  int limit,
) {
  final root = _requiredMap(payload, '酷狗音乐');
  _checkBusinessCode(root['error_code'],
      expected: 0, source: ResultSource.kugou);
  final rows = _listAt(root, const ['data', 'info']);
  if (rows == null) throw const FormatException('Missing Kugou song list');
  final results = <SongSearchResult>[];
  for (final value in rows) {
    if (results.length >= limit) break;
    if (value is! Map) continue;
    final title =
        _stringText(value['songname']) ?? _stringText(value['song_name']);
    final hash = _stringText(value['hash']);
    if (title == null || hash == null) continue;
    final artists = _stringText(value['singername']) ?? '';
    final album = _stringText(value['album_name']) ?? '';
    results.add(SongSearchResult(
      ResultSource.kugou,
      title,
      artists,
      album,
      computeSongMatchScore(audio, title, artists, album),
      kugouSongHash: hash,
      durationSeconds: _positiveSeconds(value['duration']),
    ));
  }
  return results;
}

List<SongSearchResult> parseLrclibLyricSearchPayload(
  Object? payload,
  Audio audio,
  int limit,
) {
  final records = parseLrclibSearchPayload(payload, limit: limit);
  return [
    for (final record in records)
      SongSearchResult(
        ResultSource.lrclib,
        record.trackName,
        record.artistName,
        record.albumName,
        computeSongMatchScore(
          audio,
          record.trackName,
          record.artistName,
          record.albumName,
        ),
        lrclibId: record.id,
        durationSeconds: _positiveSeconds(record.durationSeconds),
      ),
  ];
}

Map _requiredMap(Object? value, String provider) {
  if (value is Map) return value;
  throw FormatException('$provider response is not an object');
}

void _checkBusinessCode(
  Object? raw, {
  required int expected,
  required ResultSource source,
}) {
  if (raw == null) return;
  final code = _integer(raw);
  if (code == expected) return;
  if (code == null) throw const FormatException('Invalid business code');
  throw _LyricProviderException(
    '${_sourceLabel(source)}请求失败（服务代码 $code）',
    retryable: code == 408 ||
        code == 429 ||
        code == 2001 ||
        (code >= 500 && code <= 599),
  );
}

Object? _valueAt(Map root, List<String> path) {
  Object? value = root;
  for (final key in path) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

List? _listAt(Map root, List<String> path) {
  final value = _valueAt(root, path);
  return value is List ? value : null;
}

String _joinedNames(Object? value) {
  if (value is String) return value.trim();
  if (value is! List) return '';
  return value
      .map((entry) =>
          entry is Map ? _stringText(entry['name']) : _stringText(entry))
      .whereType<String>()
      .join('、');
}

String? _stringText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

String? _scalarText(Object? value) {
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite) return null;
    final parsed = value.toInt();
    return value == parsed ? parsed : null;
  }
  return int.tryParse(value?.toString() ?? '');
}

int? _positiveInt(Object? value) {
  final parsed = _integer(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _positiveSeconds(Object? value, {bool milliseconds = false}) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return milliseconds ? parsed / 1000 : parsed;
}

String? _positiveNumericText(Object? value) {
  final text = _scalarText(value);
  if (text == null || !RegExp(r'^\d{1,30}$').hasMatch(text)) return null;
  return BigInt.parse(text) > BigInt.zero ? text : null;
}

Future<List<SongSearchResult>> uniSearch(Audio audio) async =>
    (await searchLyricCandidates(audio)).candidates;

Future<Object?> _loadNeteaseLyricPayload(String songId) async {
  final uri = Uri.https('music.163.com', '/api/song/lyric/v1', {
    'id': songId,
    'cp': 'false',
    'lv': '0',
    'kv': '0',
    'tv': '0',
    'rv': '0',
    'yv': '0',
    'ytv': '0',
    'yrv': '0',
  });
  final client = HttpClient()..connectionTimeout = _providerTimeout;
  try {
    final request = await client.getUrl(uri).timeout(_providerTimeout);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 DanPlayer/26.0.4 AnonymousLyrics',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
    final response = await request.close().timeout(_providerTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Netease lyric HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    if (response.contentLength > _lyricResponseByteLimit) {
      throw const FormatException('Netease lyric response too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(_providerTimeout)) {
      if (bytes.length + chunk.length > _lyricResponseByteLimit) {
        throw const FormatException('Netease lyric response too large');
      }
      bytes.add(chunk);
    }
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  } finally {
    client.close(force: true);
  }
}

Lyric? parseNeteaseLyricPayload(Object? payload) {
  if (payload is! Map) return null;
  final code = _integer(payload['code']);
  if (code != null && code != 200) return null;
  return parseOnlineLyricPayload(payload);
}

Future<Lyric?> getNeteaseLyric(
  String neteaseSongId, {
  NeteaseLyricPayloadLoader? payloadLoader,
}) async {
  if (_positiveNumericText(neteaseSongId) == null) return null;
  try {
    final payload = await (payloadLoader ?? _loadNeteaseLyricPayload)
        .call(neteaseSongId)
        .timeout(_providerTimeout);
    if (payload is Map &&
        (payload['code'] == null || payload['code'] == 200) &&
        payload['nolyric'] == true) {
      throw const InstrumentalLyric();
    }
    return parseNeteaseLyricPayload(payload);
  } on InstrumentalLyric {
    rethrow;
  } catch (err, trace) {
    LOGGER.w('[lyric/netease] 无法读取歌词', stackTrace: trace);
  }

  return null;
}

Future<Object?> _loadQqPublicLyricPayload(
  int? songId,
  String? songMid,
) async {
  final mid = songMid?.trim();
  final parameters = <String, String>{
    'format': 'json',
    'nobase64': '1',
    'songtype': '0',
    if (mid?.isNotEmpty == true) 'songmid': mid!,
    if (mid?.isNotEmpty != true && songId != null && songId > 0)
      'musicid': songId.toString(),
  };
  if (!parameters.containsKey('songmid') &&
      !parameters.containsKey('musicid')) {
    return null;
  }
  final uri = Uri.https(
    'c.y.qq.com',
    '/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
    parameters,
  );
  final client = HttpClient()..connectionTimeout = _providerTimeout;
  try {
    final request = await client.getUrl(uri).timeout(_providerTimeout);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 DanPlayer/26.0.4 AnonymousLyrics',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.refererHeader, 'https://y.qq.com/');
    final response = await request.close().timeout(_providerTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('QQ lyric HTTP ${response.statusCode}', uri: uri);
    }
    if (response.contentLength > _lyricResponseByteLimit) {
      throw const FormatException('QQ lyric response too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(_providerTimeout)) {
      if (bytes.length + chunk.length > _lyricResponseByteLimit) {
        throw const FormatException('QQ lyric response too large');
      }
      bytes.add(chunk);
    }
    final body = utf8.decode(bytes.takeBytes()).trim();
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      final start = body.indexOf('(');
      final end = body.lastIndexOf(')');
      if (start >= 0 && end > start) {
        return jsonDecode(body.substring(start + 1, end));
      }
      rethrow;
    }
  } finally {
    client.close(force: true);
  }
}

Lrc? parseQqPublicLyricPayload(Object? payload) {
  if (payload is! Map) return null;
  final code = _integer(payload['code'] ?? payload['retcode']);
  if (code != null && code != 0) return null;
  final lyricText = _stringText(payload['lyric']);
  if (lyricText == null) return null;
  final translation = _stringText(payload['trans']);
  final decodedLyric = _decodeQqLyricEntities(lyricText);
  final decodedTranslation =
      translation == null ? null : _decodeQqLyricEntities(translation);
  return _validLyric(Lrc.fromLrcText(
    decodedTranslation == null
        ? decodedLyric
        : '$decodedLyric\n$decodedTranslation',
    LrcSource.web,
    separator: '┃',
  ));
}

String _decodeQqLyricEntities(String value) {
  final numeric = value.replaceAllMapped(
    RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false),
    (match) {
      final token = match.group(1)!;
      final hex = token.startsWith('x') || token.startsWith('X');
      final code =
          int.tryParse(hex ? token.substring(1) : token, radix: hex ? 16 : 10);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    },
  );
  return numeric
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

Future<Lrc?> getQqPublicLyric({
  int? songId,
  String? songMid,
  QqLyricPayloadLoader? payloadLoader,
  bool throwOnFailure = false,
}) async {
  if ((songId == null || songId <= 0) && songMid?.trim().isNotEmpty != true) {
    return null;
  }
  try {
    final payload = await (payloadLoader ?? _loadQqPublicLyricPayload)
        .call(songId, songMid)
        .timeout(_providerTimeout);
    if (payload is! Map) {
      throw const FormatException('Invalid QQ lyric response');
    }
    final code = _integer(payload['code'] ?? payload['retcode']);
    if (code == -1901) throw const LyricUnavailableException();
    if (code != null && code != 0) {
      throw HttpException('QQ lyric service code $code');
    }
    if (payload['instrumental'] == true || payload['nolyric'] == true) {
      throw const InstrumentalLyric();
    }
    final text = payload['lyric'];
    if (text == null || text is String && text.trim().isEmpty) {
      throw const LyricUnavailableException();
    }
    if (text is! String) throw const FormatException('Invalid QQ lyric text');
    final parsed = parseQqPublicLyricPayload(payload);
    if (parsed == null) {
      throw const LyricUnavailableException();
    }
    return parsed;
  } on InstrumentalLyric {
    rethrow;
  } catch (error, trace) {
    if (throwOnFailure) rethrow;
    LOGGER.w('[lyric/qq-public] 无法读取普通歌词', stackTrace: trace);
  }
  return null;
}

Future<Object?> _loadLrclibRecordPayload(int recordId) async {
  final record =
      await LrclibLyricsTransport().getById(recordId).timeout(_providerTimeout);
  return record?.toJson();
}

/// Converts an LRCLIB record without inventing timing information.
///
/// Synced LRC is parsed normally. Plain text is retained as one untimed block
/// so the player can display it while avoiding fake per-line timestamps and
/// misleading karaoke progress.
Lyric? parseLrclibLyricPayload(Object? payload) {
  final record =
      payload is LrclibRecord ? payload : parseLrclibRecordPayload(payload);
  if (record == null || !record.hasLyrics) return null;
  final synced = record.syncedLyrics;
  if (synced != null) {
    final lyric = _validLyric(
      Lrc.fromLrcText(synced, LrcSource.web, separator: '┃'),
    );
    if (lyric != null) return lyric;
  }
  final plain = record.plainLyrics;
  return plain == null ? null : _validLyric(PlainLyric(plain));
}

Future<Lyric?> getLrclibLyric(
  int recordId, {
  LrclibRecordPayloadLoader? payloadLoader,
}) async {
  if (recordId <= 0) return null;
  try {
    final payload = await (payloadLoader ?? _loadLrclibRecordPayload)
        .call(recordId)
        .timeout(_providerTimeout);
    if (payload is Map && payload['instrumental'] == true) {
      throw const InstrumentalLyric();
    }
    return parseLrclibLyricPayload(payload);
  } on InstrumentalLyric {
    rethrow;
  } catch (error, trace) {
    LOGGER.w('[lyric/lrclib] 无法读取歌词', stackTrace: trace);
  }
  return null;
}

Future<Qrc?> _getQQSyncLyric(int songId) async {
  try {
    // The pinned music_api implementation only sends musicid for songLyric3;
    // its public songMid parameter is ignored by the actual request.
    final answer =
        await QQ.songLyric3(songId: songId).timeout(_providerTimeout);
    if (answer.code != 200 || answer.data is! Map) return null;
    final data = answer.data as Map;
    final qrcText = data["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = data["trans"];
      if (qrcTransRawStr is String) {
        return _validLyric(Qrc.fromQrcText(qrcText, qrcTransRawStr));
      }
      return _validLyric(Qrc.fromQrcText(qrcText));
    }
  } catch (err, trace) {
    LOGGER.w('[lyric/qq] 无法读取歌词', stackTrace: trace);
  }

  return null;
}

Future<Lyric?> _getKugouSyncLyric(String kugouSongHash) async {
  final profile = _configuredKugouLyricProfile();
  if (profile == null) return null;
  final cancellation = CustomMusicSourceCancellation();
  final deadline = Timer(_customLyricSweepTimeout, cancellation.cancel);
  try {
    final audio = Audio.online(
      provider: profile.providerId,
      id: kugouSongHash,
      title: '',
      artist: '',
      album: '',
      duration: 0,
    );
    // Older Kugou associations retain only the hash. Recover that exact song's
    // metadata before accepting a lyric-server fallback with its own identity.
    // An edited protocol keeps its own direct lyric contract and need not
    // provide a metadata endpoint merely because the stable profile ID remains.
    final transport = CustomMusicSourceTransport(profile);
    final selected = profile.protocol == CustomMusicSourceProtocol.kugou
        ? await transport.metadata(audio, cancellation: cancellation)
        : audio;
    final response =
        await transport.lyrics(selected, cancellation: cancellation);
    if (!_isCurrentCustomLyricProfile(profile)) return null;
    return _parseCustomLyricResponse(response.rawBody);
  } catch (err, trace) {
    LOGGER.w('[lyric/kugou] 无法读取歌词', stackTrace: trace);
  } finally {
    deadline.cancel();
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? qqSongMid,
  String? kugouSongHash,
  String? neteaseSongId,
  int? lrclibId,
  bool throwOnFailure = false,
  Future<Lyric?> Function(int)? qqWordLoader,
  QqLyricPayloadLoader? qqPayloadLoader,
}) async {
  try {
    Lyric? lyric;
    if (qqSongId != null || qqSongMid != null) {
      if (qqSongId != null) {
        try {
          lyric = await (qqWordLoader ?? _getQQSyncLyric)(qqSongId)
              .timeout(const Duration(seconds: 3));
          if (hasWordTiming(lyric)) return lyric;
        } catch (_) {
          /* A failed word endpoint must retain ordinary fallback. */
        }
      }
      Object? publicFailure;
      StackTrace? publicFailureTrace;
      try {
        lyric = await getQqPublicLyric(
            songId: qqSongId,
            songMid: qqSongMid,
            throwOnFailure: true,
            payloadLoader: qqPayloadLoader);
      } on InstrumentalLyric {
        rethrow;
      } catch (error, trace) {
        publicFailure = error;
        publicFailureTrace = trace;
      }
      if (lyric == null && qqSongMid != null && qqSongMid.trim().isNotEmpty) {
        try {
          lyric = await _getQQUnsyncLyric(qqSongMid.trim());
        } catch (_) {
          if (publicFailure != null) {
            Error.throwWithStackTrace(publicFailure, publicFailureTrace!);
          }
          rethrow;
        }
      }
      if (lyric == null && publicFailure != null) {
        Error.throwWithStackTrace(publicFailure, publicFailureTrace!);
      }
    } else if (kugouSongHash != null) {
      lyric = (await _getKugouSyncLyric(kugouSongHash));
    } else if (neteaseSongId != null) {
      lyric = await getNeteaseLyric(neteaseSongId);
    } else if (lrclibId != null) {
      lyric = await getLrclibLyric(lrclibId);
    }
    return lyric;
  } on InstrumentalLyric {
    rethrow;
  } catch (_) {
    if (throwOnFailure) rethrow;
    return null;
  }
}

Future<Lyric?> getLyricForCandidate(SongSearchResult candidate) {
  if (candidate.customProfile case final profile?) {
    final audio = candidate.customAudio;
    if (audio == null || !_isCurrentCustomLyricProfile(profile)) {
      return Future.value(null);
    }
    if (candidate.previewLyric != null) {
      return Future.value(candidate.previewLyric);
    }
    return getLyricForCustomSourceChoice(
        audio, CustomLyricSourceChoice(profile));
  }
  return getOnlineLyric(
    qqSongId: candidate.qqSongId,
    qqSongMid: candidate.qqSongMid,
    kugouSongHash: candidate.kugouSongHash,
    neteaseSongId: candidate.neteaseSongId,
    lrclibId: candidate.lrclibId,
    throwOnFailure: true,
  );
}

/// Loads exactly the custom lyric provider selected by the user.
///
/// A profile is checked both before and after I/O. This prevents a response
/// from a source edited, disabled or removed while the request was in flight
/// from being published into the editor.
Future<Lyric?> getLyricForCustomSourceChoice(
  Audio audio,
  CustomLyricSourceChoice choice, {
  Duration timeout = _customLyricSweepTimeout,
}) async {
  final profile = choice.profile;
  if (!_customLyricProfileCanQuery(profile, audio) ||
      !_isCurrentCustomLyricProfile(profile)) {
    return null;
  }

  final cancellation = CustomMusicSourceCancellation();
  final deadlineTimer = Timer(timeout, cancellation.cancel);
  try {
    final response = await CustomMusicSourceTransport(
      profile,
      requestTimeout: timeout,
    ).lyrics(audio, cancellation: cancellation).timeout(timeout);
    if (!_isCurrentCustomLyricProfile(profile)) return null;
    return _parseCustomLyricResponse(response.rawBody);
  } on TimeoutException {
    cancellation.cancel();
    rethrow;
  } finally {
    deadlineTimer.cancel();
  }
}

bool _isCurrentCustomLyricProfile(CustomMusicSourceProfile expected) {
  for (final current in AppSettings.instance.customMusicSources.value) {
    if (identical(current, expected) &&
        current.enabled &&
        current.authentication == null &&
        current.capabilities.contains(CustomMusicSourceCapability.lyrics)) {
      return true;
    }
  }
  return false;
}

Future<LyricApiConnectivityResult> testLyricApiConnectivity(
  String endpoint,
) async {
  final profile = CustomMusicSourceProfile.legacyLyric(endpoint.trim());
  if (profile == null) {
    return const LyricApiConnectivityResult(
      isReachable: false,
      lyricRecognized: false,
      message: "接口地址无效，请使用 http 或 https 地址",
    );
  }
  try {
    final response = await CustomMusicSourceTransport(profile).lyrics(
      Audio(
        'Dan Player Test',
        'Dan Player',
        'Dan Player',
        0,
        0,
        null,
        null,
        'Dan Player Test.mp3',
        0,
        0,
        null,
      ),
    );
    final lyric = _parseCustomLyricResponse(response.rawBody);
    if (lyric != null) {
      return const LyricApiConnectivityResult(
        isReachable: true,
        lyricRecognized: true,
        statusCode: HttpStatus.ok,
        message: "连通正常，返回歌词格式可识别",
      );
    }
    return const LyricApiConnectivityResult(
      isReachable: true,
      lyricRecognized: false,
      statusCode: HttpStatus.ok,
      message: "接口可连接，但测试响应未包含可识别歌词",
    );
  } on CustomMusicSourceException catch (error) {
    return LyricApiConnectivityResult(
      isReachable: false,
      lyricRecognized: false,
      statusCode: error.statusCode,
      message: error.statusCode == null
          ? "连接失败：${error.message}"
          : "连接失败：HTTP ${error.statusCode}",
    );
  } catch (_) {
    return const LyricApiConnectivityResult(
      isReachable: false,
      lyricRecognized: false,
      message: "连接失败：网络请求失败",
    );
  }
}

Lyric? _parseCustomLyricResponse(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;

  try {
    return _lyricFromCustomPayload(json.decode(trimmed));
  } catch (_) {
    return _validLyric(
      Lrc.fromLrcText(trimmed, LrcSource.web, separator: "┃"),
    );
  }
}

Lyric? _lyricFromCustomPayload(dynamic payload) =>
    parseOnlineLyricPayload(payload);

T? _validLyric<T extends Lyric>(T? lyric) {
  if (lyric == null || lyric.lines.isEmpty) return null;
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(
  Audio audio, {
  Future<LyricSearchResponse> Function(Audio audio)? candidateSearch,
  Future<Lyric?> Function(SongSearchResult candidate)? candidateLyricLoader,
  bool Function()? stillCurrent,
}) async {
  bool current() => stillCurrent?.call() ?? true;
  if (!current()) return null;
  LyricSearchResponse response;
  try {
    response = await (candidateSearch ?? searchLyricCandidates).call(audio);
  } catch (err, trace) {
    LOGGER.w('[lyric/search] 候选搜索失败', stackTrace: trace);
    response = LyricSearchResponse(candidates: const [], failures: const {});
  }
  final load = candidateLyricLoader ?? getLyricForCandidate;
  final candidates = response.candidates
      .where((candidate) =>
          candidate.scoreVerified &&
          candidate.score.isFinite &&
          candidate.score >= .6)
      .toList()
    ..sort(compareLyricCandidates);
  for (var start = 0; start < candidates.length;) {
    var end = start + 1;
    while (end < candidates.length &&
        candidates[end].matchPercent == candidates[start].matchPercent) {
      end++;
    }
    Lyric? fallback;
    var instrumental = false;
    // Preserve manual-list order, retry failures, and prefer timed words only
    // within this displayed percentage. Never let a lower match displace valid lyrics.
    for (final candidate in candidates.sublist(start, end)) {
      if (!current()) return null;
      try {
        final lyric = await load(candidate).timeout(_providerTimeout);
        if (!current()) return null;
        if (lyric == null || lyric.lines.isEmpty) continue;
        if (hasWordTiming(lyric)) return lyric;
        fallback ??= lyric;
      } on InstrumentalLyric {
        instrumental = true;
      } catch (err, trace) {
        LOGGER.w('[lyric/${candidate.source.name}] 候选歌词读取失败',
            stackTrace: trace);
      }
    }
    if (fallback != null) return fallback;
    if (instrumental && current()) throw const InstrumentalLyric();
    start = end;
  }
  if (!current()) return null;
  // Metadata-only endpoints cannot prove a >=60% match. They remain manual
  // choices, but never become an automatic or bulk-cache fallback.
  return null;
}

String? _songVersionKind(String title) {
  if (RegExp(r'\bshort(?:\s*ver\.?)?|\btv\s*(?:size|ver\.?)|ショート|短版',
          caseSensitive: false)
      .hasMatch(title)) {
    return 'short';
  }
  if (RegExp(r'\bfull(?:\s*(?:ver(?:sion)?\.?|size))?\b|完整版|フル',
          caseSensitive: false)
      .hasMatch(title)) {
    return 'full';
  }
  return null;
}

/// Automatic matching must retain version evidence that the fuzzy text score
/// deliberately ignores. Manual selection does not use this acceptance gate.
bool isAutomaticLyricCandidateCompatible(
    Audio audio, SongSearchResult candidate) {
  final duration = candidate.durationSeconds ??
      _positiveSeconds(candidate.customAudio?.duration);
  final hasDurations = audio.duration > 0 && duration != null;
  if (hasDurations &&
      (audio.duration - duration).abs() > (audio.duration * .04).clamp(5, 12)) {
    return false;
  }
  final localVersion = _songVersionKind(audio.title);
  final remoteVersion = _songVersionKind(candidate.title);
  if (localVersion != null &&
      remoteVersion != null &&
      localVersion != remoteVersion) {
    return false;
  }
  if (localVersion != remoteVersion && !hasDurations) return false;
  return true;
}

Future<Lrc?> _getQQUnsyncLyric(String songMid) async {
  try {
    final answer =
        await QQ.songLyric(songMid: songMid).timeout(_providerTimeout);
    if (answer.code != 200 || answer.data is! Map) return null;
    final data = answer.data as Map;
    final lyricText = data['lyric'];
    if (lyricText is! String) return null;
    final translation = data['trans'];
    return _validLyric(Lrc.fromLrcText(
      lyricText + (translation is String ? '\n$translation' : ''),
      LrcSource.web,
      separator: '┃',
    ));
  } catch (err, trace) {
    LOGGER.w('[lyric/qq] 无法读取普通歌词', stackTrace: trace);
  }
  return null;
}
