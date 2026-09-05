import 'dart:convert';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';

typedef NeteaseApiGet = Future<String> Function(Uri uri,
    {required int byteLimit,
    required CustomMusicSourceCancellation? cancellation});

/// The documented Node.js NeteaseCloudMusicApi / enhanced HTTP contract.
/// Parsing is independent of the upstream implementation. All requests use the
/// same bounded, cancellable transport as other user-managed providers.
class NeteaseMusicApi {
  const NeteaseMusicApi(this.profile, {required NeteaseApiGet get})
      : _get = get;

  final CustomMusicSourceProfile profile;
  final NeteaseApiGet _get;
  static final _idPattern = RegExp(r'^[1-9]\d{0,19}$');

  Future<CustomMusicSearchResult> search(String query,
      {required int limit, CustomMusicSourceCancellation? cancellation}) async {
    cancellation?.check();
    final count =
        limit.clamp(1, CustomMusicSourceTransport.maximumSearchResults);
    if (query.trim().isEmpty) {
      return CustomMusicSearchResult(
          providerId: profile.providerId,
          tracks: const [],
          reachedLimit: false);
    }
    final root = await _request(
        CustomMusicSourceCapability.search,
        {
          'keywords': query.trim(),
          'type': '1',
          'limit': '$count',
          'offset': '0'
        },
        byteLimit: 256 * 1024,
        cancellation: cancellation);
    final result = root['result'];
    if (result is! Map) throw _invalid();
    final values = result['songs'];
    if (values == null && result['songCount'] == 0) {
      return CustomMusicSearchResult(
          providerId: profile.providerId,
          tracks: const [],
          reachedLimit: false);
    }
    if (values is! List) throw _invalid();
    final seen = <String>{};
    final tracks = <Audio>[];
    for (final row in values.take(count)) {
      if (row is! Map) continue;
      final track = _audio(row);
      if (track != null && seen.add(track.onlineId!)) tracks.add(track);
    }
    return CustomMusicSearchResult(
        providerId: profile.providerId,
        tracks: tracks,
        reachedLimit: _number(result['songCount']) > tracks.length);
  }

  Future<Audio> metadata(Audio audio,
      {CustomMusicSourceCancellation? cancellation}) async {
    final id = _ownedId(audio);
    final root = await _request(
        profile.capabilities.contains(CustomMusicSourceCapability.metadata)
            ? CustomMusicSourceCapability.metadata
            : CustomMusicSourceCapability.cover,
        {'ids': id},
        byteLimit: 128 * 1024,
        cancellation: cancellation);
    final songs = root['songs'];
    if (songs is! List) throw _invalid();
    for (final row in songs) {
      if (row is Map && '${row['id']}' == id) {
        final refreshed = _audio(row);
        if (refreshed != null) return refreshed;
      }
    }
    throw _invalid();
  }

  Future<CustomMusicLyricsResult> lyrics(Audio audio,
      {CustomMusicSourceCancellation? cancellation}) async {
    final root = await _request(
        CustomMusicSourceCapability.lyrics, {'id': _ownedId(audio)},
        byteLimit: 128 * 1024, cancellation: cancellation);
    final lrc = root['lrc'];
    final translated = root['tlyric'];
    final lyric = lrc is Map ? _text(lrc['lyric']) : null;
    if (lyric == null) {
      throw _unavailable('该歌曲暂无可用歌词');
    }
    return CustomMusicLyricsResult(
        rawBody: jsonEncode(root),
        json: Map<String, dynamic>.from(root),
        lyric: lyric,
        translation: translated is Map ? _text(translated['lyric']) : null,
        type: 'lrc');
  }

  Future<CustomMusicCommentsResult> comments(Audio audio,
      {required int page,
      required int limit,
      required CustomMusicCommentsSort sort,
      CustomMusicSourceCancellation? cancellation}) async {
    final id = _ownedId(audio);
    final count = limit.clamp(1, CustomMusicSourceTransport.maximumComments);
    final index = page.clamp(0, 9);
    final hot = sort == CustomMusicCommentsSort.hot;
    // The music/hot endpoints use bounded offsets. Do not pretend the separate
    // comment/new API's cursor pagination is an interchangeable page number.
    final root = await _request(
        CustomMusicSourceCapability.comments,
        {
          'id': id,
          'limit': '$count',
          'offset': '${index * count}',
          if (hot) 'type': '0',
        },
        hotComments: hot,
        byteLimit: 256 * 1024,
        cancellation: cancellation);
    final values = root[hot ? 'hotComments' : 'comments'];
    if (values is! List) throw _invalid();
    final comments = <CustomMusicComment>[];
    for (final row in values.take(count)) {
      if (row is! Map) continue;
      final content = _text(row['content']);
      final commentId = '${row['commentId']}';
      if (content == null || !_idPattern.hasMatch(commentId)) continue;
      final user = row['user'];
      final timestamp = _number(row['time']);
      comments.add(CustomMusicComment(
          id: commentId,
          author: user is Map ? _text(user['nickname']) ?? '匿名用户' : '匿名用户',
          content: content,
          publishedAt: timestamp > 0 && timestamp < 8640000000000000
              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              : null,
          likeCount: _number(row['likedCount']).clamp(0, 1000000000)));
    }
    return CustomMusicCommentsResult(
        comments: comments,
        page: index,
        hasMore: index < 9 && root[hot ? 'hasMore' : 'more'] == true,
        total: root['total'] is num
            ? _number(root['total']).clamp(0, 1 << 40)
            : null,
        supportedSorts: const [
          CustomMusicCommentsSort.hot,
          CustomMusicCommentsSort.latest
        ]);
  }

  Future<CustomMusicStreamResolution> resolve(Audio audio,
      {required bool forDownload,
      CustomMusicSourceCancellation? cancellation}) async {
    final id = _ownedId(audio);
    final root = await _request(
        forDownload
            ? CustomMusicSourceCapability.download
            : CustomMusicSourceCapability.stream,
        {'id': id, 'br': '128000'},
        byteLimit: 32 * 1024,
        cancellation: cancellation);
    final data = root['data'];
    Map? row;
    if (data is Map) {
      row = data;
    } else if (data is List) {
      for (final candidate in data) {
        if (candidate is Map && '${candidate['id']}' == id) {
          row = candidate;
          break;
        }
      }
    }
    if (row == null || '${row['id']}' != id) throw _invalid();
    if (_number(row['code']) != 200 || row['freeTrialInfo'] != null) {
      throw _unavailable('该歌曲暂未提供完整音源，可能需要登录或购买');
    }
    final url = _url(row['url']);
    if (url == null) {
      throw _unavailable('该歌曲暂未提供完整音源，可能需要登录或购买');
    }
    return CustomMusicStreamResolution(
        uri: url,
        // Streaming permission never implies downloading permission. A valid
        // response from the dedicated download endpoint is required each time.
        downloadAllowed: forDownload,
        expiresAt: _number(row['expi']) > 0
            ? DateTime.now()
                .add(Duration(seconds: _number(row['expi']).clamp(1, 86400)))
            : null,
        mimeType: row['type'] == 'flac' ? 'audio/flac' : 'audio/mpeg');
  }

  Future<Map> _request(
      CustomMusicSourceCapability capability, Map<String, String> query,
      {required int byteLimit,
      required CustomMusicSourceCancellation? cancellation,
      bool hotComments = false}) async {
    var endpoint = profile.endpointFor(capability);
    if (endpoint == null) throw _unavailable('请配置网易云增强 API 接口地址');
    if (hotComments) {
      endpoint = endpoint.resolve('hot').replace(query: endpoint.query);
    }
    final body = await _get(
        endpoint
            .replace(queryParameters: {...endpoint.queryParameters, ...query}),
        byteLimit: byteLimit,
        cancellation: cancellation);
    cancellation?.check();
    Object? value;
    try {
      value = jsonDecode(body);
    } on FormatException {
      throw _invalid();
    }
    if (value is! Map) throw _invalid();
    final code = _number(value['code']);
    if (const [301, 401, 403].contains(code)) {
      throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.http, '该来源要求登录或有效凭据',
          statusCode: 401);
    }
    if (code != 200) throw _unavailable('网易云增强 API 暂时无法完成请求');
    return value;
  }

  String _ownedId(Audio audio) {
    final id = audio.onlineId;
    if (audio.onlineProvider != profile.providerId ||
        id == null ||
        !_idPattern.hasMatch(id)) {
      throw _unavailable('歌曲不属于当前网易云增强 API 来源');
    }
    return id;
  }

  Audio? _audio(Map row) {
    final id = '${row['id']}';
    final title = _text(row['name']);
    if (!_idPattern.hasMatch(id) || title == null) return null;
    final artists = row['ar'] ?? row['artists'];
    final names = artists is List
        ? artists
            .whereType<Map>()
            .map((item) => _text(item['name']))
            .nonNulls
            .toList()
        : <String>[];
    final album = row['al'] ?? row['album'];
    final cover = album is Map ? _url(album['picUrl']) : null;
    return Audio.online(
        provider: profile.providerId,
        id: id,
        title: title,
        artist: names.isEmpty ? 'UNKNOWN' : names.join(' / '),
        album: album is Map ? _text(album['name']) ?? 'UNKNOWN' : 'UNKNOWN',
        duration:
            (_number(row['dt'] ?? row['duration']) ~/ 1000).clamp(0, 86400),
        artworkUrl:
            profile.capabilities.contains(CustomMusicSourceCapability.cover)
                ? cover?.toString()
                : null,
        playable:
            profile.capabilities.contains(CustomMusicSourceCapability.stream)
                ? null
                : false,
        downloadAllowed:
            profile.capabilities.contains(CustomMusicSourceCapability.download)
                ? null
                : false);
  }
}

int _number(Object? value) => value is num && value.isFinite
    ? value.toInt()
    : int.tryParse('$value') ?? 0;
String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
Uri? _url(Object? value) {
  final text = _text(value);
  final uri = text == null || text.length > 4096 ? null : Uri.tryParse(text);
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  // The upstream often returns legacy cleartext NetEase CDN URLs. Upgrade only
  // the known CDN; custom service origins keep their explicitly chosen scheme.
  if (uri.scheme == 'http' &&
      uri.host.toLowerCase().endsWith('.music.126.net')) {
    return uri.replace(scheme: 'https');
  }
  return uri;
}

CustomMusicSourceException _invalid() => const CustomMusicSourceException(
    CustomMusicSourceFailureKind.invalidResponse, '网易云增强 API 返回了无法识别的响应');
CustomMusicSourceException _unavailable(String message) =>
    CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable, message);
