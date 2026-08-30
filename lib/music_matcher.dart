import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
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

class _CustomLyricApiFetchResult {
  final int? statusCode;
  final String? body;
  final String? errorMessage;

  const _CustomLyricApiFetchResult({
    this.statusCode,
    this.body,
    this.errorMessage,
  });

  bool get isHttpOk =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
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

  /// for qq result
  final int? qqSongId;
  final String? qqSongMid;

  /// for netease result
  final String? neteaseSongId;

  /// for kugou result
  final String? kugouSongHash;

  /// for LRCLIB result
  final int? lrclibId;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.qqSongId,
      this.qqSongMid,
      this.neteaseSongId,
      this.kugouSongHash,
      this.lrclibId});

  String get sourceLabel => source.sourceLabel;

  String get identity => switch (source) {
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
const _lyricResponseByteLimit = 2 * 1024 * 1024;

Set<ResultSource> _configuredLyricSearchSources() {
  final preferences = AppSettings.instance.onlineSources.value;
  return {
    if (preferences.qqEnabled) ResultSource.qq,
    // Kugou remains a built-in lyric-only fallback. The shared online-song
    // preferences currently expose no Kugou switch, so filtering it here
    // would silently regress the documented three-provider lyric behavior.
    ResultSource.kugou,
    if (preferences.neteaseEnabled) ResultSource.netease,
    // LRCLIB is a read-only lyric catalogue, not an online-song source. It is
    // kept as a final fallback when a platform knows the song but has no lyric.
    ResultSource.lrclib,
  };
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

Future<Object?> _loadKugouSearchPayload(String query, int limit) async {
  final answer = await KuGou.searchSong(keyword: query, size: limit).timeout(
    _providerTimeout,
  );
  _requireTransportCode(answer.code, ResultSource.kugou);
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
  if (enabled.isEmpty) {
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
    ResultSource.kugou: kugouSearch ?? _loadKugouSearchPayload,
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
  final candidates = unique.values.toList()
    ..sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      final source = left.source.index.compareTo(right.source.index);
      if (source != 0) return source;
      final title = normalizeSongMatchText(left.title)
          .compareTo(normalizeSongMatchText(right.title));
      if (title != 0) return title;
      return left.identity.compareTo(right.identity);
    });
  return LyricSearchResponse(candidates: candidates, failures: failures);
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
          ResultSource.kugou =>
            parseKugouLyricSearchPayload(payload, audio, limit),
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
        final message = _searchFailureMessage(source, lastError);
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

String _searchFailureMessage(ResultSource source, Object? error) {
  if (error is _LyricProviderException) return error.message;
  if (error is LrclibException) return error.message;
  if (error is TimeoutException) return '${_sourceLabel(source)}搜索超时，请重试';
  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return '${_sourceLabel(source)}联网失败，请检查网络';
  }
  return '${_sourceLabel(source)}返回的数据无法解析，请重试';
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

String? _positiveNumericText(Object? value) {
  final text = _scalarText(value);
  if (text == null || !RegExp(r'^\d{1,30}$').hasMatch(text)) return null;
  return BigInt.parse(text) > BigInt.zero ? text : null;
}

Future<List<SongSearchResult>> uniSearch(Audio audio) async =>
    (await searchLyricCandidates(audio)).candidates;

Future<Object?> _loadNeteaseLyricPayload(String songId) async {
  final uri = Uri.https('music.163.com', '/api/song/lyric', {
    'id': songId,
    'lv': '-1',
    'kv': '-1',
    'tv': '-1',
    'rv': '-1',
  });
  final client = HttpClient()..connectionTimeout = _providerTimeout;
  try {
    final request = await client.getUrl(uri).timeout(_providerTimeout);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 DanPlayer/26.0.3 AnonymousLyrics',
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

Lrc? parseNeteaseLyricPayload(Object? payload) {
  if (payload is! Map) return null;
  final code = _integer(payload['code']);
  if (code != null && code != 200) return null;
  if (payload['nolyric'] == true || payload['uncollected'] == true) return null;
  final lrcSection = payload['lrc'];
  final lrcText = lrcSection is Map ? _stringText(lrcSection['lyric']) : null;
  if (lrcText == null) return null;
  final translationSection = payload['tlyric'];
  final translation = translationSection is Map
      ? _stringText(translationSection['lyric'])
      : null;
  return _validLyric(Lrc.fromLrcText(
    translation == null ? lrcText : '$lrcText\n$translation',
    LrcSource.web,
    separator: '┃',
  ));
}

Future<Lrc?> getNeteaseLyric(
  String neteaseSongId, {
  NeteaseLyricPayloadLoader? payloadLoader,
}) async {
  if (_positiveNumericText(neteaseSongId) == null) return null;
  try {
    final payload = await (payloadLoader ?? _loadNeteaseLyricPayload)
        .call(neteaseSongId)
        .timeout(_providerTimeout);
    return parseNeteaseLyricPayload(payload);
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
      'Mozilla/5.0 DanPlayer/26.0.3 AnonymousLyrics',
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
}) async {
  if ((songId == null || songId <= 0) && songMid?.trim().isNotEmpty != true) {
    return null;
  }
  try {
    final payload = await (payloadLoader ?? _loadQqPublicLyricPayload)
        .call(songId, songMid)
        .timeout(_providerTimeout);
    return parseQqPublicLyricPayload(payload);
  } catch (error, trace) {
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
    return parseLrclibLyricPayload(payload);
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

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer =
        await KuGou.krc(hash: kugouSongHash).timeout(_providerTimeout);
    if (answer.code != 200 || answer.data is! Map) return null;
    final krcText = (answer.data as Map)["lyric"];
    if (krcText is String) {
      return _validLyric(Krc.fromKrcText(krcText));
    }
  } catch (err, trace) {
    LOGGER.w('[lyric/kugou] 无法读取歌词', stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? qqSongMid,
  String? kugouSongHash,
  String? neteaseSongId,
  int? lrclibId,
}) async {
  Lyric? lyric;
  if (qqSongId != null || qqSongMid != null) {
    lyric = await getQqPublicLyric(songId: qqSongId, songMid: qqSongMid);
    if (lyric == null && qqSongId != null) {
      lyric = await _getQQSyncLyric(qqSongId);
    }
    if (lyric == null && qqSongMid != null && qqSongMid.trim().isNotEmpty) {
      lyric = await _getQQUnsyncLyric(qqSongMid.trim());
    }
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash));
  } else if (neteaseSongId != null) {
    lyric = await getNeteaseLyric(neteaseSongId);
  } else if (lrclibId != null) {
    lyric = await getLrclibLyric(lrclibId);
  }
  return lyric;
}

Future<Lyric?> getLyricForCandidate(SongSearchResult candidate) =>
    getOnlineLyric(
      qqSongId: candidate.qqSongId,
      qqSongMid: candidate.qqSongMid,
      kugouSongHash: candidate.kugouSongHash,
      neteaseSongId: candidate.neteaseSongId,
      lrclibId: candidate.lrclibId,
    );

Future<Lyric?> _getCustomLyric(Audio audio) async {
  final endpoint = AppSettings.instance.lyricApiUrl?.trim();
  if (endpoint == null || endpoint.isEmpty) return null;

  final uri = _buildCustomLyricUri(endpoint, {
    "title": audio.title,
    "artist": audio.artist,
    "album": audio.album,
    "duration": audio.duration.toString(),
    "fileName": audio.fileNameTitle,
    "displayTitle": audio.displayTitle,
  });

  if (uri == null) {
    LOGGER.w("Invalid custom lyric API endpoint");
    return null;
  }

  final response = await _fetchCustomLyricApi(uri);
  if (!response.isHttpOk) {
    if (response.statusCode != null) {
      LOGGER.w(
        "Custom lyric API returned ${response.statusCode}: "
        "${uri.scheme}://${uri.host}${uri.path}",
      );
    } else {
      LOGGER.w("Custom lyric API network request failed");
    }
    return null;
  }

  return _parseCustomLyricResponse(response.body ?? "");
}

Future<LyricApiConnectivityResult> testLyricApiConnectivity(
  String endpoint,
) async {
  final uri = _buildCustomLyricUri(endpoint.trim(), const {
    "title": "Dan Player Test",
    "artist": "Dan Player",
    "album": "Dan Player",
    "duration": "0",
    "fileName": "Dan Player Test",
    "displayTitle": "Dan Player Test",
    "probe": "1",
  });

  if (uri == null) {
    return const LyricApiConnectivityResult(
      isReachable: false,
      lyricRecognized: false,
      message: "接口地址无效，请使用 http 或 https 地址",
    );
  }

  final response = await _fetchCustomLyricApi(uri);
  if (!response.isHttpOk) {
    final statusCode = response.statusCode;
    return LyricApiConnectivityResult(
      isReachable: false,
      lyricRecognized: false,
      statusCode: statusCode,
      message: statusCode == null
          ? "连接失败：${response.errorMessage ?? "未知错误"}"
          : "连接失败：HTTP $statusCode",
    );
  }

  final lyric = _parseCustomLyricResponse(response.body ?? "");
  if (lyric != null) {
    return LyricApiConnectivityResult(
      isReachable: true,
      lyricRecognized: true,
      statusCode: response.statusCode,
      message: "连通正常，返回歌词格式可识别",
    );
  }

  return LyricApiConnectivityResult(
    isReachable: true,
    lyricRecognized: false,
    statusCode: response.statusCode,
    message: "接口可连接，但测试响应未包含可识别歌词",
  );
}

Uri? _buildCustomLyricUri(String endpoint, Map<String, String> parameters) {
  final baseUri = Uri.tryParse(endpoint);
  if (baseUri == null ||
      !(baseUri.scheme == "http" || baseUri.scheme == "https") ||
      baseUri.host.isEmpty) {
    return null;
  }

  final queryParameters = Map<String, String>.from(baseUri.queryParameters);
  queryParameters.addAll(parameters);
  return baseUri.replace(queryParameters: queryParameters);
}

Future<_CustomLyricApiFetchResult> _fetchCustomLyricApi(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri).timeout(
          const Duration(seconds: 8),
        );
    request.headers.set(
      HttpHeaders.acceptHeader,
      "application/json, text/plain;q=0.9, */*;q=0.8",
    );

    final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
    final body = await response.transform(utf8.decoder).join();
    return _CustomLyricApiFetchResult(
      statusCode: response.statusCode,
      body: body,
    );
  } catch (err) {
    return _CustomLyricApiFetchResult(
      errorMessage: err is TimeoutException ? "请求超时" : "网络请求失败",
    );
  } finally {
    client.close(force: true);
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

Lyric? _lyricFromCustomPayload(dynamic payload) {
  if (payload is String) {
    return _validLyric(
      Lrc.fromLrcText(payload, LrcSource.web, separator: "┃"),
    );
  }
  if (payload is! Map) return null;

  final nestedData = payload["data"];
  if (nestedData != null && !_hasKnownLyricField(payload)) {
    final nestedLyric = _lyricFromCustomPayload(nestedData);
    if (nestedLyric != null) return nestedLyric;
  }

  String? type = _stringValue(payload["type"]) ??
      _stringValue(payload["format"]) ??
      _stringValue(payload["source"]);
  String? lyricText = _stringValue(payload["lyric"]);
  String? translation =
      _stringValue(payload["translation"]) ?? _stringValue(payload["trans"]);

  for (final format in const ["qrc", "krc", "lrc"]) {
    final value = payload[format];
    if (value is Map) {
      lyricText ??= _stringValue(value["lyric"]);
      translation ??=
          _stringValue(value["translation"]) ?? _stringValue(value["trans"]);
      type ??= format;
    } else {
      lyricText ??= _stringValue(value);
      if (value is String) type ??= format;
    }
  }

  final tlyric = payload["tlyric"];
  if (tlyric is Map) {
    translation ??= _stringValue(tlyric["lyric"]);
  } else {
    translation ??= _stringValue(tlyric);
  }

  if (lyricText == null) return null;

  try {
    switch ((type ?? "lrc").toLowerCase()) {
      case "qrc":
        return _validLyric(Qrc.fromQrcText(lyricText, translation));
      case "krc":
        return _validLyric(Krc.fromKrcText(lyricText));
      case "lrc":
      default:
        return _validLyric(
          Lrc.fromLrcText(
            translation == null ? lyricText : "$lyricText\n$translation",
            LrcSource.web,
            separator: "┃",
          ),
        );
    }
  } catch (err, trace) {
    LOGGER.e("Failed to parse custom lyric API payload");
    LOGGER.e(err, stackTrace: trace);
    return null;
  }
}

bool _hasKnownLyricField(Map payload) {
  for (final key in const [
    "lyric",
    "lrc",
    "qrc",
    "krc",
    "translation",
    "trans",
    "tlyric",
  ]) {
    if (payload.containsKey(key)) return true;
  }
  return false;
}

String? _stringValue(dynamic value) {
  if (value == null) return null;
  if (value is! String) return value.toString();

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

T? _validLyric<T extends Lyric>(T? lyric) {
  if (lyric == null || lyric.lines.isEmpty) return null;
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(
  Audio audio, {
  Future<Lyric?> Function(Audio audio)? customLyricLoader,
  Future<LyricSearchResponse> Function(Audio audio)? candidateSearch,
  Future<Lyric?> Function(SongSearchResult candidate)? candidateLyricLoader,
}) async {
  Lyric? customLyric;
  try {
    customLyric = await (customLyricLoader ?? _getCustomLyric).call(audio);
  } catch (err, trace) {
    LOGGER.w('[lyric/custom] 自定义歌词来源失败', stackTrace: trace);
  }
  if (customLyric != null) return customLyric;

  LyricSearchResponse response;
  try {
    response = await (candidateSearch ?? searchLyricCandidates).call(audio);
  } catch (err, trace) {
    LOGGER.w('[lyric/search] 候选搜索失败', stackTrace: trace);
    return null;
  }
  final load = candidateLyricLoader ?? getLyricForCandidate;
  for (final candidate in response.candidates.take(5)) {
    try {
      final lyric = await load(candidate);
      if (lyric != null && lyric.lines.isNotEmpty) return lyric;
    } catch (err, trace) {
      LOGGER.w(
        '[lyric/${candidate.source.name}] 候选歌词读取失败',
        stackTrace: trace,
      );
    }
  }
  return null;
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
