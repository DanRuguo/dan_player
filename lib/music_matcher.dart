import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/utils.dart';
import 'package:music_api/music_api.dart';

enum ResultSource { qq, kugou, netease }

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

double _computeScore(Audio audio, String title, String artists, String album) {
  int maxScore = audio.title.length + audio.artist.length + audio.album.length;
  if (maxScore == 0) return 0.0;

  int score = 0;

  int minTitleLength = min(audio.title.length, title.length);
  for (int i = 0; i < minTitleLength; ++i) {
    if (audio.title[i] == title[i]) score += 1;
  }

  int minArtistLength = min(audio.artist.length, artists.length);
  for (int i = 0; i < minArtistLength; ++i) {
    if (audio.artist[i] == artists[i]) score += 1;
  }

  int minAlbumLength = min(audio.album.length, album.length);
  for (int i = 0; i < minAlbumLength; ++i) {
    if (audio.album[i] == album[i]) score += 1;
  }

  return score / maxScore;
}

class SongSearchResult {
  ResultSource source;
  String title;
  String artists;
  String album;
  double score;

  /// for qq result
  int? qqSongId;

  /// for netease result
  String? neteaseSongId;

  /// for kugou result
  String? kugouSongHash;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.qqSongId, this.neteaseSongId, this.kugouSongHash});

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

  static SongSearchResult fromQQSearchResult(Map itemSong, Audio audio) {
    final List singer = itemSong["singer"];
    final buffer = StringBuffer(singer.first["name"]);
    for (int i = 1; i < singer.length; ++i) {
      buffer.write("、${singer[i]["name"]}");
    }

    final title = itemSong["name"] ?? "";
    final album = itemSong["album"]["title"] ?? "";
    final artists = buffer.toString();

    return SongSearchResult(
      ResultSource.qq,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      qqSongId: itemSong["id"],
    );
  }

  static SongSearchResult fromNeteaseSearchResult(Map song, Audio audio) {
    final title = song["name"] ?? "";

    final List artistList = song["artists"];
    final buffer = StringBuffer(artistList.first["name"]);
    for (int i = 1; i < artistList.length; ++i) {
      buffer.write("、${artistList[i]["name"]}");
    }
    final artists = buffer.toString();

    final album = song["album"]["name"] ?? "";

    return SongSearchResult(
      ResultSource.netease,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      neteaseSongId: song["id"].toString(),
    );
  }

  static SongSearchResult fromKugouSearchResult(Map info, Audio audio) {
    final title = info["songname"];
    final album = info["album_name"];
    final artists = info["singername"];

    return SongSearchResult(
      ResultSource.kugou,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      kugouSongHash: info["hash"],
    );
  }
}

Future<List<SongSearchResult>> uniSearch(Audio audio) async {
  final query = audio.title;
  try {
    List<SongSearchResult> result = [];

    final Map kugouAnswer = (await KuGou.searchSong(keyword: query)).data;
    final List kugouResultList = kugouAnswer["data"]["info"];
    for (int j = 0; j < kugouResultList.length; j++) {
      if (j >= 5) break;
      result.add(SongSearchResult.fromKugouSearchResult(
        kugouResultList[j],
        audio,
      ));
    }

    final Map neteaseAnswer = (await Netease.search(keyWord: query)).data;
    final List neteaseResultList = neteaseAnswer["result"]["songs"];
    for (int k = 0; k < neteaseResultList.length; k++) {
      if (k >= 5) break;
      result.add(SongSearchResult.fromNeteaseSearchResult(
        neteaseResultList[k],
        audio,
      ));
    }

    final Map qqAnswer = (await QQ.search(keyWord: query)).data;
    final List qqResultList = qqAnswer["req"]["data"]["body"]["item_song"];
    for (int i = 0; i < qqResultList.length; i++) {
      if (i >= 5) break;
      result.add(SongSearchResult.fromQQSearchResult(
        qqResultList[i],
        audio,
      ));
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  } catch (err, trace) {
    LOGGER.e("query: $query");
    LOGGER.e(err, stackTrace: trace);
  }
  return Future.value([]);
}

Future<Lrc?> _getNeteaseUnsyncLyric(String neteaseSongId) async {
  try {
    final answer = await Netease.lyric(id: neteaseSongId);
    final lrcText = answer.data["lrc"]["lyric"];
    if (lrcText is String) {
      final tlyric = answer.data["tlyric"];
      final lrcTrans = tlyric is Map ? tlyric["lyric"] : null;
      return Lrc.fromLrcText(
        lrcText + (lrcTrans is String ? "\n$lrcTrans" : ""),
        LrcSource.web,
        separator: "┃",
      );
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Qrc?> _getQQSyncLyric(int qqSongId) async {
  try {
    final answer = await QQ.songLyric3(songId: qqSongId);
    final qrcText = answer.data["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = answer.data["trans"];
      if (qrcTransRawStr is String) {
        return Qrc.fromQrcText(qrcText, qrcTransRawStr);
      }
      return Qrc.fromQrcText(qrcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer = await KuGou.krc(hash: kugouSongHash);
    final krcText = answer.data["lyric"];
    if (krcText is String) {
      return Krc.fromKrcText(krcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) async {
  Lyric? lyric;
  if (qqSongId != null) {
    lyric = (await _getQQSyncLyric(qqSongId));
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash));
  } else if (neteaseSongId != null) {
    lyric = await _getNeteaseUnsyncLyric(neteaseSongId);
  }
  return lyric;
}

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
    LOGGER.w("Invalid custom lyric API: $endpoint");
    return null;
  }

  final response = await _fetchCustomLyricApi(uri);
  if (!response.isHttpOk) {
    if (response.statusCode != null) {
      LOGGER.w("Custom lyric API returned ${response.statusCode}: $uri");
    } else {
      LOGGER.w("Custom lyric API failed: ${response.errorMessage}");
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
    return _CustomLyricApiFetchResult(errorMessage: err.toString());
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

Future<Lyric?> getMostMatchedLyric(Audio audio) async {
  final customLyric = await _getCustomLyric(audio);
  if (customLyric != null) return customLyric;

  final unisearchResult = await uniSearch(audio);
  if (unisearchResult.isEmpty) return null;

  final mostMatch = unisearchResult.first;

  return switch (mostMatch.source) {
    ResultSource.qq => getOnlineLyric(qqSongId: mostMatch.qqSongId),
    ResultSource.kugou =>
      getOnlineLyric(kugouSongHash: mostMatch.kugouSongHash),
    ResultSource.netease =>
      getOnlineLyric(neteaseSongId: mostMatch.neteaseSongId),
  };
}
