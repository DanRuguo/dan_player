import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';

class KugouMusicApiException extends CustomMusicSourceException {
  const KugouMusicApiException(super.kind, super.message, {this.businessCode});

  /// Provider business result only; never includes request URLs or bodies.
  final int? businessCode;
}

/// Independently implemented KuGou wire adapter. Protocol references:
/// ZeroBit-Player lib/API/apis.dart, ECHO KugouStreamingProvider /
/// KugouLyricsProvider, and music-lib's public mobile song-info route
/// (2026-09-03). No reference implementation is embedded.
///
/// Requests are anonymous. Only the standard hash is resolved; login, payment,
/// high-quality unlocks and preview fragments are not promoted to full tracks.
/// User credential references remain unsupported. No Android app-signing
/// secrets, forged identities or account cookies are used.
class KugouMusicApi {
  KugouMusicApi(
    this.profile, {
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 6),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final CustomMusicSourceProfile profile;
  final Duration requestTimeout;
  final HttpClient Function() _httpClientFactory;

  static const _searchByteLimit = 128 * 1024;
  static const _lyricsByteLimit = 128 * 1024;
  static const _resolutionByteLimit = 32 * 1024;
  static const _maximumResults = 25;
  static final _hashPattern = RegExp(r'^[a-fA-F0-9]{16,64}$');
  static final _numberIdPattern = RegExp(r'^\d{1,20}$');

  Future<CustomMusicSearchResult> search(
    String query, {
    int limit = _maximumResults,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(CustomMusicSourceCapability.search);
    final text = query.trim();
    final count = limit.clamp(1, _maximumResults);
    if (text.isEmpty) {
      return CustomMusicSearchResult(
        providerId: profile.providerId,
        tracks: const [],
        reachedLimit: false,
      );
    }
    return _run(cancellation, (session) async {
      final response = await session.get(
        _query(_endpoint(CustomMusicSourceCapability.search), {
          'format': 'json',
          'keyword': text,
          'page': '1',
          'pagesize': '$count',
          'showtype': '1',
        }),
        byteLimit: _searchByteLimit,
      );
      final payload = _payload(response);
      final rows = payload['info'];
      if (rows is! List) throw _invalid();
      final tracks = <Audio>[];
      final seen = <String>{};
      for (final row in rows.take(count)) {
        if (row is! Map) continue;
        final track = _audio(row);
        if (track != null && seen.add(track.onlineId!)) tracks.add(track);
      }
      return CustomMusicSearchResult(
        providerId: profile.providerId,
        tracks: tracks,
        reachedLimit: rows.length >= count,
      );
    });
  }

  Future<Audio> metadata(
    Audio audio, {
    CustomMusicSourceCancellation? cancellation,
  }) async {
    final primary =
        profile.capabilities.contains(CustomMusicSourceCapability.metadata)
            ? CustomMusicSourceCapability.metadata
            : CustomMusicSourceCapability.cover;
    _requireReady(primary);
    final key = _requireTrack(audio);
    return _run(cancellation, (session) async {
      final response = await session.get(
        _query(_endpoint(primary), {
          'hash': key.hash,
        }),
        byteLimit: _searchByteLimit,
      );
      var payload = _payload(response);
      if (profile.capabilities.contains(CustomMusicSourceCapability.cover) &&
          profile.endpointFor(CustomMusicSourceCapability.cover) != null &&
          _endpoint(CustomMusicSourceCapability.cover) != _endpoint(primary)) {
        final cover = await session.get(
          _query(
              _endpoint(CustomMusicSourceCapability.cover), {'hash': key.hash}),
          byteLimit: _searchByteLimit,
        );
        final url = _cover(_payload(cover));
        if (url == null) throw _unavailable();
        payload = {...payload, 'imgurl': url};
      }
      return _audio(payload, fallback: audio, key: key) ?? (throw _invalid());
    });
  }

  /// The lyrics endpoint is a service root. Both relative `search` and
  /// `download` routes stay under this user-editable root and retain its query.
  Future<CustomMusicLyricsResult> lyrics(
    Audio audio, {
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(CustomMusicSourceCapability.lyrics);
    final endpoint = _endpoint(CustomMusicSourceCapability.lyrics);
    final base = endpoint.replace(
      path: endpoint.path.endsWith('/') ? endpoint.path : '${endpoint.path}/',
    );
    final key = audio.onlineProvider == profile.providerId
        ? _KugouTrackKey.parse(audio.onlineId)
        : null;
    return _run(cancellation, (session) async {
      final response = await session.get(
        _query(base.resolve('search'), {
          ...endpoint.queryParameters,
          'ver': '1',
          'man': 'yes',
          'client': 'pc',
          if (key != null) 'hash': key.hash,
          'keyword': '${audio.title} ${audio.artist}'.trim(),
          if (audio.duration > 0) 'duration': '${audio.duration * 1000}',
        }),
        byteLimit: _lyricsByteLimit,
      );
      final candidates =
          response['candidates'] ?? _payload(response)['candidates'];
      if (candidates is! List) throw _invalid();
      String? lyricId;
      String? accessKey;
      for (final candidate in candidates.take(5)) {
        if (candidate is! Map) continue;
        final id = _text(candidate['id']);
        final access = _text(candidate['accesskey'] ?? candidate['accessKey']);
        if (id != null &&
            access != null &&
            id.length <= 128 &&
            access.length <= 512) {
          lyricId = id;
          accessKey = access;
          break;
        }
      }
      if (lyricId == null || accessKey == null) throw _unavailable();
      final content = await session.get(
        _query(base.resolve('download'), {
          ...endpoint.queryParameters,
          'ver': '1',
          'client': 'pc',
          'id': lyricId,
          'accesskey': accessKey,
          'fmt': 'lrc',
          'charset': 'utf8',
        }),
        byteLimit: _lyricsByteLimit,
      );
      final raw = _text(content['content'] ?? _payload(content)['content']);
      if (raw == null) throw _unavailable();
      String lyric;
      if (raw.contains('[') ||
          raw.contains('\n') ||
          RegExp(r'[^\x00-\x7f]').hasMatch(raw)) {
        lyric = raw;
      } else {
        try {
          lyric = utf8.decode(base64Decode(raw));
        } on FormatException {
          throw _invalid();
        }
      }
      if (lyric.trim().isEmpty) throw _unavailable();
      final normalized = <String, dynamic>{'type': 'lrc', 'lyric': lyric};
      return CustomMusicLyricsResult(
        rawBody: jsonEncode(normalized),
        json: normalized,
        lyric: lyric,
        type: 'lrc',
      );
    });
  }

  Future<CustomMusicStreamResolution> resolve(
    Audio audio, {
    bool forDownload = false,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(forDownload
        ? CustomMusicSourceCapability.download
        : CustomMusicSourceCapability.stream);
    final key = _requireTrack(audio);
    if (audio.onlinePlayable == false ||
        (forDownload && audio.onlineDownloadAllowed == false)) {
      throw _protected();
    }
    return _run(cancellation, (session) async {
      final response = await session.get(
        _query(
          _endpoint(forDownload
              ? CustomMusicSourceCapability.download
              : CustomMusicSourceCapability.stream),
          {'cmd': 'playInfo', 'hash': key.hash},
        ),
        byteLimit: _resolutionByteLimit,
      );
      final payload = _payload(response);
      if (_restricted(response) ||
          _restricted(payload) ||
          _preview(response) ||
          _preview(payload)) {
        throw _protected();
      }
      final returnedDuration = _number(payload['timeLength']);
      if (audio.duration > 0 &&
          returnedDuration != null &&
          returnedDuration > 0 &&
          returnedDuration < audio.duration - 3) {
        throw _protected();
      }
      Uri? media;
      for (final value in [
        payload['url'],
        payload['play_url'],
        payload['backup_url']
      ]) {
        final candidates = value is List ? value.take(4) : [value];
        for (final candidate in candidates) {
          media = _safeUri(_text(candidate));
          if (media != null) break;
        }
        if (media != null) break;
      }
      if (media == null) throw _unavailable();
      return CustomMusicStreamResolution(
        uri: media,
        // The anonymous provider returned a complete public audio URL; no
        // invented custom authorization field is required by this protocol.
        downloadAllowed:
            profile.capabilities.contains(CustomMusicSourceCapability.download),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        mimeType: 'audio/mpeg',
      );
    });
  }

  _KugouTrackKey _requireTrack(Audio audio) {
    if (audio.onlineProvider != profile.providerId) throw _invalid();
    return _KugouTrackKey.parse(audio.onlineId) ?? (throw _invalid());
  }

  void _requireReady(CustomMusicSourceCapability capability) {
    if (!profile.enabled || !profile.capabilities.contains(capability)) {
      throw _unavailable();
    }
    if (profile.authentication != null) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.credentialsNotConfigured,
        '歌源凭据尚未配置',
      );
    }
  }

  Uri _endpoint(CustomMusicSourceCapability capability) =>
      _safeUri(profile.endpointFor(capability)?.toString()) ??
      (throw _unavailable());

  Audio? _audio(Map row, {Audio? fallback, _KugouTrackKey? key}) {
    final hash =
        _text(row['hash'] ?? row['Hash'] ?? row['FileHash']) ?? key?.hash;
    if (hash == null || !_hashPattern.hasMatch(hash)) return null;
    final albumId = _id(row['album_id'] ?? row['albumid'] ?? row['AlbumId']) ??
        key?.albumId ??
        '0';
    final albumAudioId =
        _id(row['album_audio_id'] ?? row['mixsongid'] ?? row['audio_id']) ??
            key?.albumAudioId ??
            '0';
    final fileName = _text(row['filename'] ?? row['FileName']);
    final nameParts = fileName?.split(' - ');
    final title = _text(row['songname'] ?? row['SongName'] ?? row['title']) ??
        (nameParts != null && nameParts.length > 1
            ? nameParts.skip(1).join(' - ')
            : fileName) ??
        fallback?.title;
    if (title == null || title.isEmpty) return null;
    final artist =
        _text(row['singername'] ?? row['SingerName'] ?? row['artist']) ??
            (nameParts != null && nameParts.length > 1
                ? nameParts.first
                : null) ??
            fallback?.artist ??
            'UNKNOWN';
    final albumValue = row['album'];
    final album =
        _text(row['album_name'] ?? row['AlbumName'] ?? row['albumname']) ??
            (albumValue is Map
                ? _text(albumValue['name'] ?? albumValue['album_name'])
                : _text(albumValue)) ??
            fallback?.album ??
            'UNKNOWN';
    final available = !_restricted(row) && !_preview(row);
    final rawDuration =
        _number(row['duration'] ?? row['Duration'] ?? row['timelength']);
    final duration = rawDuration == null
        ? fallback?.duration ?? 0
        : (rawDuration > 10000 ? rawDuration / 1000 : rawDuration)
            .round()
            .clamp(0, 86400);
    final bitrate = _number(row['bitrate'] ?? row['BitRate']);
    return Audio.online(
      provider: profile.providerId,
      id: fallback?.onlineId ?? '${hash.toLowerCase()}.$albumId.$albumAudioId',
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artworkUrl:
          profile.capabilities.contains(CustomMusicSourceCapability.cover)
              ? _cover(row) ?? fallback?.artworkUrl
              : null,
      playable:
          profile.capabilities.contains(CustomMusicSourceCapability.stream)
              ? available && fallback?.onlinePlayable != false
              : false,
      downloadAllowed:
          profile.capabilities.contains(CustomMusicSourceCapability.download)
              ? available && fallback?.onlineDownloadAllowed != false
              : false,
      bitrate:
          profile.capabilities.contains(CustomMusicSourceCapability.metadata) &&
                  bitrate != null
              ? bitrate.round().clamp(0, 10000000)
              : null,
    );
  }

  String? _cover(Map row) {
    final trans = row['trans_param'];
    final group = row['group'];
    final groupFirst = group is List && group.isNotEmpty && group.first is Map
        ? group.first as Map
        : const {};
    final groupTrans = groupFirst['trans_param'];
    final candidate = _text(row['imgurl'] ??
            row['image'] ??
            row['cover'] ??
            row['album_img']) ??
        (trans is Map ? _text(trans['union_cover']) : null) ??
        (groupTrans is Map ? _text(groupTrans['union_cover']) : null);
    var uri = _safeUri(candidate?.replaceAll('{size}', '500'));
    if (uri?.scheme == 'http' &&
        (uri!.host.endsWith('.kugou.com') ||
            uri.host.endsWith('.kugoucdn.com'))) {
      uri = uri.replace(scheme: 'https');
    }
    return uri?.toString();
  }

  Future<T> _run<T>(
    CustomMusicSourceCancellation? cancellation,
    Future<T> Function(_KugouSession session) operation,
  ) async {
    final token = cancellation ?? CustomMusicSourceCancellation();
    token.check();
    final client = _httpClientFactory()..connectionTimeout = requestTimeout;
    final unlisten = token.onCancel(() => client.close(force: true));
    var timedOut = false;
    final timeout = Completer<void>();
    final timer = Timer(requestTimeout, () {
      timedOut = true;
      timeout.complete();
      client.close(force: true);
    });
    try {
      return await Future.any([
        token.race(operation(_KugouSession(client, profile, token))),
        timeout.future.then<T>((_) => throw TimeoutException('KuGou timeout')),
      ]);
    } catch (error) {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      if (timedOut || error is TimeoutException) {
        throw const CustomMusicSourceException(
            CustomMusicSourceFailureKind.timeout, '联网请求超时，请稍后重试');
      }
      if (error is CustomMusicSourceException) rethrow;
      throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.network, '无法连接自定义歌源');
    } finally {
      timer.cancel();
      unlisten();
      client.close(force: true);
    }
  }

  static Uri _query(Uri uri, Map<String, String> values) => uri.replace(
        query: {...uri.queryParameters, ...values}
            .entries
            .map((entry) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
            .join('&'),
      );
  static Map _payload(Map root) =>
      root['data'] is Map ? root['data'] as Map : root;
  static String? _text(Object? value) {
    if (value is! String && value is! num) return null;
    final text = value.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return text.isEmpty || text.length > 16384 ? null : text;
  }

  static String? _id(Object? value) {
    final text = _text(value);
    return text != null && _numberIdPattern.hasMatch(text) ? text : null;
  }

  static num? _number(Object? value) {
    final result = value is num
        ? value
        : value is String
            ? num.tryParse(value)
            : null;
    return result != null && result.isFinite ? result : null;
  }

  static Uri? _safeUri(String? value) {
    if (value == null || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            uri.fragment.isEmpty
        ? uri
        : null;
  }

  static bool _restricted(Map value) =>
      const ['pay_type', 'price', 'pkg_price', 'privilege', '128privilege']
          .any((key) => (_number(value[key]) ?? 0) > 0) ||
      value['requireLogin'] == true ||
      value['need_login'] == true;
  static bool _preview(Map value) =>
      const ['is_free_part', 'IsFreePart', 'isFreePart', 'is_trial', 'trial']
          .any((key) => value[key] == true || (_number(value[key]) ?? 0) > 0) ||
      const ['free_part_info', 'freePartInfo', 'free_part', 'hash_offset']
          .any((key) => value[key] is Map && (value[key] as Map).isNotEmpty) ||
      (value['trans_param'] is Map && _preview(value['trans_param'] as Map));
  static CustomMusicSourceException _invalid() =>
      const CustomMusicSourceException(
          CustomMusicSourceFailureKind.invalidResponse, '歌源返回了无法识别的数据');
  static CustomMusicSourceException _unavailable() =>
      const CustomMusicSourceException(
          CustomMusicSourceFailureKind.unavailable, '自定义歌源当前不可用');
  static CustomMusicSourceException _protected() =>
      const CustomMusicSourceException(
          CustomMusicSourceFailureKind.http, '该歌曲需要登录、购买或仅提供试听',
          statusCode: 403);
}

class _KugouTrackKey {
  const _KugouTrackKey(this.hash, this.albumId, this.albumAudioId);
  final String hash;
  final String albumId;
  final String albumAudioId;

  static _KugouTrackKey? parse(String? value) {
    if (value == null) return null;
    final parts = value.split('.');
    if (parts.isEmpty ||
        parts.length > 3 ||
        !KugouMusicApi._hashPattern.hasMatch(parts.first)) {
      return null;
    }
    final album = parts.length > 1 ? KugouMusicApi._id(parts[1]) : '0';
    final audio = parts.length > 2 ? KugouMusicApi._id(parts[2]) : '0';
    return album == null || audio == null
        ? null
        : _KugouTrackKey(parts.first.toLowerCase(), album, audio);
  }
}

class _KugouSession {
  const _KugouSession(this.client, this.profile, this.token);
  final HttpClient client;
  final CustomMusicSourceProfile profile;
  final CustomMusicSourceCancellation token;

  Future<Map<String, dynamic>> get(
    Uri uri, {
    required int byteLimit,
    Map<String, String> headers = const {},
  }) async {
    token.check();
    final request = await client.getUrl(uri);
    token.check();
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'DanPlayer/26.0.4');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.refererHeader, 'https://www.kugou.com/');
    request.headers.set('Origin', 'https://www.kugou.com');
    for (final entry in {...headers, ...profile.publicHeaders}.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    token.check();
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.redirect, '歌源返回了不允许的重定向');
    }
    if (response.statusCode != 200) {
      throw CustomMusicSourceException(
          CustomMusicSourceFailureKind.http, '歌源请求失败',
          statusCode: response.statusCode);
    }
    if (response.contentLength > byteLimit) throw _tooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      token.check();
      if (bytes.length + chunk.length > byteLimit) throw _tooLarge();
      bytes.add(chunk);
    }
    token.check();
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw KugouMusicApi._invalid();
    }
    if (decoded is! Map<String, dynamic>) throw KugouMusicApi._invalid();
    final body = KugouMusicApi._payload(decoded);
    for (final value in [decoded, body]) {
      final code = KugouMusicApi._number(
          value['code'] ?? value['errcode'] ?? value['err_code']);
      if (code == 401 ||
          code == 403 ||
          value['requireLogin'] == true ||
          value['need_login'] == true) {
        throw KugouMusicApi._protected();
      }
      if ((value.containsKey('status') &&
              !const [1, 200]
                  .contains(KugouMusicApi._number(value['status']))) ||
          (code != null && code != 0 && code != 200)) {
        throw KugouMusicApiException(
          CustomMusicSourceFailureKind.unavailable,
          '自定义歌源当前不可用',
          businessCode: code?.toInt(),
        );
      }
    }
    return decoded;
  }

  static CustomMusicSourceException _tooLarge() =>
      const CustomMusicSourceException(
          CustomMusicSourceFailureKind.responseTooLarge, '自定义歌源响应过大，已停止读取');
}
