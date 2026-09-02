import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';

enum CustomMusicSourceFailureKind {
  unavailable,
  credentialsNotConfigured,
  cancelled,
  timeout,
  network,
  redirect,
  http,
  responseTooLarge,
  invalidResponse,
}

class CustomMusicSourceException implements Exception {
  const CustomMusicSourceException(
    this.kind,
    this.message, {
    this.statusCode,
  });

  final CustomMusicSourceFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CustomMusicSourceCancelled extends CustomMusicSourceException {
  const CustomMusicSourceCancelled()
      : super(CustomMusicSourceFailureKind.cancelled, '自定义歌源请求已取消');
}

/// Cancels one custom-source request without affecting another source or task.
class CustomMusicSourceCancellation {
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void check() {
    if (isCancelled) throw const CustomMusicSourceCancelled();
  }

  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T> race<T>(Future<T> operation) => Future.any(<Future<T>>[
        operation,
        _cancelled.future
            .then<T>((_) => throw const CustomMusicSourceCancelled()),
      ]);
}

class CustomMusicSearchResult {
  CustomMusicSearchResult({
    required this.providerId,
    required List<Audio> tracks,
    required this.reachedLimit,
  }) : tracks = List<Audio>.unmodifiable(tracks);

  final String providerId;
  final List<Audio> tracks;
  final bool reachedLimit;

  @override
  String toString() =>
      'CustomMusicSearchResult(provider: $providerId, tracks: ${tracks.length})';
}

class CustomMusicLyricsResult {
  CustomMusicLyricsResult({
    required this.rawBody,
    required this.lyric,
    this.translation,
    this.type,
    Map<String, dynamic>? json,
  }) : json = json == null ? null : Map<String, dynamic>.unmodifiable(json);

  /// The bounded response body, retained for legacy lyric parsers.
  final String rawBody;
  final Map<String, dynamic>? json;
  final String lyric;
  final String? translation;
  final String? type;

  @override
  String toString() =>
      'CustomMusicLyricsResult(type: ${type ?? 'plain'}, chars: ${lyric.length})';
}

enum CustomMusicCommentsSort { hot, latest }

class CustomMusicComment {
  const CustomMusicComment({
    required this.id,
    required this.author,
    required this.content,
    this.publishedAt,
    this.likeCount = 0,
  });

  final String id;
  final String author;
  final String content;
  final DateTime? publishedAt;
  final int likeCount;
}

class CustomMusicCommentsResult {
  CustomMusicCommentsResult({
    required List<CustomMusicComment> comments,
    required this.page,
    required this.hasMore,
    this.total,
  }) : comments = List<CustomMusicComment>.unmodifiable(comments);

  final List<CustomMusicComment> comments;
  final int page;
  final bool hasMore;
  final int? total;

  @override
  String toString() =>
      'CustomMusicCommentsResult(page: $page, comments: ${comments.length})';
}

class CustomMusicStreamResolution {
  const CustomMusicStreamResolution({
    required this.uri,
    required this.downloadAllowed,
    this.expiresAt,
    this.mimeType,
    this.supportsRange,
  });

  final Uri uri;
  final DateTime? expiresAt;
  final bool downloadAllowed;
  final String? mimeType;
  final bool? supportsRange;

  /// Deliberately does not expose a signed URL, token or response header.
  @override
  String toString() => 'CustomMusicStreamResolution('
      'scheme: ${uri.scheme}, expires: ${expiresAt != null}, '
      'downloadAllowed: $downloadAllowed)';
}

/// Bounded, redirect-free HTTP adapter for user-managed music providers.
///
/// Search never resolves media URLs. Stream/download URLs are requested only
/// after a user selects a result. Authentication references remain inert until
/// an OS-protected credential store is wired in; they are never sent as keys.
class CustomMusicSourceTransport {
  CustomMusicSourceTransport(
    this.profile, {
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 6),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const int searchResponseByteLimit = 128 * 1024;
  static const int lyricsResponseByteLimit = 128 * 1024;
  static const int commentsResponseByteLimit = 256 * 1024;
  static const int resolutionResponseByteLimit = 32 * 1024;
  static const int maximumSearchResults = 25;
  static const int maximumComments = 100;

  final CustomMusicSourceProfile profile;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;

  Future<CustomMusicSearchResult> search(
    String rawQuery, {
    int limit = maximumSearchResults,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(CustomMusicSourceCapability.search);
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return CustomMusicSearchResult(
        providerId: profile.providerId,
        tracks: const <Audio>[],
        reachedLimit: false,
      );
    }
    final safeLimit = limit.clamp(1, maximumSearchResults);
    final endpoint = _endpoint(CustomMusicSourceCapability.search);
    final uri = switch (profile.protocol) {
      CustomMusicSourceProtocol.goMusicApi =>
        _withQuery(endpoint, <String, String>{
          'q': query,
          'type': 'song',
        }),
      _ => _withQuery(endpoint, <String, String>{
          'q': query,
          'limit': '$safeLimit',
        }),
    };
    final body = await _get(
      uri,
      byteLimit: searchResponseByteLimit,
      cancellation: cancellation,
    );
    final root = _decodeObject(body, operation: '搜索');
    final payload = _payload(root);
    final values = profile.protocol == CustomMusicSourceProtocol.goMusicApi
        ? payload['songs']
        : payload['tracks'];
    if (values is! List) {
      throw _invalid('自定义歌源返回了无法识别的搜索结果');
    }
    final tracks = <Audio>[];
    for (final value in values.take(safeLimit)) {
      if (value is! Map) continue;
      final track = profile.protocol == CustomMusicSourceProtocol.goMusicApi
          ? _goMusicAudio(value)
          : _danSourceAudio(value);
      if (track != null) tracks.add(track);
    }
    return CustomMusicSearchResult(
      providerId: profile.providerId,
      tracks: tracks,
      reachedLimit: values.length > safeLimit,
    );
  }

  Future<CustomMusicLyricsResult> lyrics(
    Audio audio, {
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(CustomMusicSourceCapability.lyrics);
    final endpoint = _endpoint(CustomMusicSourceCapability.lyrics);
    final query = switch (profile.protocol) {
      CustomMusicSourceProtocol.goMusicApi =>
        _goMusicTrackQuery(_requireGoMusicDescriptor(audio)),
      CustomMusicSourceProtocol.danSourceV1 =>
        _standardTrackQuery(audio, includeIdentity: true),
      CustomMusicSourceProtocol.legacyLyrics =>
        _standardTrackQuery(audio, includeIdentity: false),
    };
    final body = await _get(
      _withQuery(endpoint, query),
      byteLimit: lyricsResponseByteLimit,
      cancellation: cancellation,
      accept: 'application/json, text/plain;q=0.9',
    );
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded == null) {
      return CustomMusicLyricsResult(rawBody: body, lyric: body);
    }
    if (decoded is! Map) {
      throw _invalid('自定义歌源返回了无法识别的歌词');
    }
    final root = Map<String, dynamic>.from(decoded);
    final payload = _payload(root);
    final lyric = _firstText(<Object?>[
      payload['lyric'],
      payload['lrc'],
      payload['content'],
    ]);
    if (lyric == null) {
      throw _invalid('自定义歌源响应中没有歌词内容');
    }
    return CustomMusicLyricsResult(
      rawBody: body,
      json: root,
      lyric: lyric,
      translation: _firstText(<Object?>[
        payload['translation'],
        payload['translatedLyric'],
        payload['tlyric'],
      ]),
      type: _firstText(<Object?>[payload['type'], payload['format']]),
    );
  }

  Future<CustomMusicCommentsResult> comments(
    Audio audio, {
    int page = 0,
    int limit = 30,
    CustomMusicCommentsSort sort = CustomMusicCommentsSort.hot,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    _requireReady(CustomMusicSourceCapability.comments);
    if (profile.protocol == CustomMusicSourceProtocol.goMusicApi &&
        profile.endpoints[CustomMusicSourceCapability.comments] == null) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        'go-music-api-v1 预设没有评论接口，请为该能力配置兼容端点',
      );
    }
    _requireOwnedTrack(audio);
    final safePage = page < 0 ? 0 : page;
    final safeLimit = limit.clamp(1, maximumComments);
    final uri = _withQuery(
      _endpoint(CustomMusicSourceCapability.comments),
      <String, String>{
        'id': audio.onlineId!,
        'page': '$safePage',
        'limit': '$safeLimit',
        'sort': sort.name,
      },
    );
    final body = await _get(
      uri,
      byteLimit: commentsResponseByteLimit,
      cancellation: cancellation,
    );
    final root = _decodeObject(body, operation: '评论');
    final payload = _payload(root);
    final values = payload['comments'];
    if (values is! List) {
      throw _invalid('自定义歌源返回了无法识别的评论结果');
    }
    final rows = <CustomMusicComment>[];
    for (final value in values.take(safeLimit)) {
      if (value is! Map) continue;
      final content = _firstText(<Object?>[value['content'], value['text']]);
      if (content == null) continue;
      final authorValue = value['author'];
      final author = authorValue is Map
          ? _firstText(<Object?>[
              authorValue['name'],
              authorValue['nickname'],
              authorValue['displayName'],
            ])
          : _firstText(<Object?>[authorValue]);
      rows.add(CustomMusicComment(
        id: _firstText(<Object?>[value['id']]) ?? 'row-${rows.length}',
        author: author ?? '匿名用户',
        content: content,
        publishedAt: _dateTime(value['publishedAt'] ?? value['timestamp']),
        likeCount: _nonNegativeInt(value['likeCount'] ?? value['likes']),
      ));
    }
    return CustomMusicCommentsResult(
      comments: rows,
      page: safePage,
      hasMore: payload['hasMore'] == true || values.length > safeLimit,
      total: _optionalNonNegativeInt(payload['total']),
    );
  }

  Future<CustomMusicStreamResolution> resolve(
    Audio audio, {
    bool forDownload = false,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    final capability = forDownload
        ? CustomMusicSourceCapability.download
        : CustomMusicSourceCapability.stream;
    _requireReady(capability);
    _requireOwnedTrack(audio);
    if (profile.protocol == CustomMusicSourceProtocol.goMusicApi) {
      final descriptor = _requireGoMusicDescriptor(audio);
      final uri =
          _withQuery(_endpoint(capability), _goMusicTrackQuery(descriptor));
      return CustomMusicStreamResolution(
        uri: _safeResponseUri(uri.toString()),
        downloadAllowed:
            profile.capabilities.contains(CustomMusicSourceCapability.download),
        supportsRange: true,
      );
    }

    final uri = _withQuery(
      _endpoint(capability),
      <String, String>{
        'id': audio.onlineId!,
        'purpose': forDownload ? 'download' : 'stream',
      },
    );
    final body = await _get(
      uri,
      byteLimit: resolutionResponseByteLimit,
      cancellation: cancellation,
    );
    final root = _decodeObject(body, operation: '播放地址解析');
    final payload = _payload(root);
    final rawUrl = _firstText(<Object?>[payload['url']]);
    if (rawUrl == null) {
      throw _invalid('自定义歌源响应中没有播放地址');
    }
    final explicitDownload = payload['downloadAllowed'] == true &&
        profile.capabilities.contains(CustomMusicSourceCapability.download);
    if (forDownload && !explicitDownload) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '该歌源没有对这首歌曲明确授权下载',
      );
    }
    return CustomMusicStreamResolution(
      uri: _safeResponseUri(rawUrl),
      expiresAt: _dateTime(payload['expiresAt']),
      downloadAllowed: explicitDownload,
      mimeType: _safeMimeType(payload['mimeType'] ?? payload['mime']),
      supportsRange: payload['supportsRange'] is bool
          ? payload['supportsRange'] as bool
          : null,
    );
  }

  void _requireReady(CustomMusicSourceCapability capability) {
    if (!profile.enabled) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '该自定义歌源已停用',
      );
    }
    if (!profile.capabilities.contains(capability)) {
      throw CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '该自定义歌源未声明 ${capability.id} 能力',
      );
    }
    if (profile.authentication != null) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.credentialsNotConfigured,
        '该歌源需要凭据，但安全凭据存储尚未配置',
      );
    }
  }

  Uri _endpoint(CustomMusicSourceCapability capability) {
    final explicit = profile.endpointFor(capability);
    if (explicit != null) return _validateEndpoint(explicit);
    if (profile.protocol != CustomMusicSourceProtocol.goMusicApi) {
      throw CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '该自定义歌源没有配置 ${capability.id} 接口',
      );
    }
    final route = switch (capability) {
      CustomMusicSourceCapability.search => 'api/v1/music/search',
      CustomMusicSourceCapability.lyrics => 'api/v1/music/lyric',
      CustomMusicSourceCapability.stream ||
      CustomMusicSourceCapability.download =>
        'api/v1/music/stream',
      _ => throw CustomMusicSourceException(
          CustomMusicSourceFailureKind.unavailable,
          'go-music-api-v1 预设不包含 ${capability.id} 接口',
        ),
    };
    final base = Uri.parse(profile.baseUrl);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return _validateEndpoint(base.replace(path: '$basePath$route'));
  }

  Uri _validateEndpoint(Uri uri) {
    if (!_isSafeHttpUri(uri)) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '自定义歌源接口地址不安全或无效',
      );
    }
    return uri;
  }

  void _requireOwnedTrack(Audio audio) {
    if (!audio.isOnline ||
        audio.onlineProvider != profile.providerId ||
        audio.onlineId == null ||
        audio.onlineId!.isEmpty) {
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        '歌曲不属于当前自定义歌源',
      );
    }
  }

  Map<String, String> _standardTrackQuery(
    Audio audio, {
    required bool includeIdentity,
  }) {
    final query = <String, String>{
      'title': audio.title,
      'artist': audio.artist,
      'album': audio.album,
      'duration': '${audio.duration}',
      'fileName': audio.fileNameTitle,
      'displayTitle': audio.displayTitle,
    };
    if (includeIdentity &&
        audio.onlineProvider == profile.providerId &&
        audio.onlineId != null) {
      query['id'] = audio.onlineId!;
    }
    return query;
  }

  Audio? _danSourceAudio(Map value) {
    final id = _firstText(<Object?>[value['id']]);
    final title = _firstText(<Object?>[value['title'], value['name']]);
    if (id == null || title == null || id.length > 4096) return null;
    return Audio.online(
      provider: profile.providerId,
      id: id,
      title: title,
      artist:
          _firstText(<Object?>[value['artist'], value['artists']]) ?? 'UNKNOWN',
      album: _firstText(<Object?>[value['album']]) ?? 'UNKNOWN',
      duration: _boundedDuration(value['duration']),
      artworkUrl: _optionalSafeUrl(
        value['artworkUrl'] ?? value['coverUrl'] ?? value['cover'],
      ),
      playable: value['streamAvailable'] is bool
          ? value['streamAvailable'] as bool
          : value['playable'] is bool
              ? value['playable'] as bool
              : null,
      downloadAllowed: value['downloadAllowed'] is bool
          ? value['downloadAllowed'] as bool
          : null,
      bitrate: _optionalNonNegativeInt(value['bitrate']),
      albumArtist: _firstText(<Object?>[
        value['albumArtist'],
        value['album_artist'],
      ]),
      composer: _firstText(<Object?>[value['composer']]),
      language: _firstText(<Object?>[value['language']]),
    );
  }

  Audio? _goMusicAudio(Map value) {
    if (value['is_invalid'] == true) return null;
    final explicitlyValid = value['is_invalid'] == false;
    final id = _firstText(<Object?>[value['id']]);
    final source = _firstText(<Object?>[value['source']]);
    final title = _firstText(<Object?>[value['name']]);
    if (id == null || source == null || title == null) return null;
    final descriptor = _GoMusicTrackDescriptor(
      id: id,
      source: source,
      name: title,
      artist: _firstText(<Object?>[value['artist']]) ?? 'UNKNOWN',
      album: _firstText(<Object?>[value['album']]) ?? 'UNKNOWN',
      duration: _boundedDuration(value['duration']),
      cover: _optionalSafeUrl(value['cover']),
      extra: _safeStringMap(value['extra']),
    );
    final opaqueId = descriptor.encode();
    if (opaqueId.length > 16384) return null;
    return Audio.online(
      provider: profile.providerId,
      id: opaqueId,
      title: descriptor.name,
      artist: descriptor.artist,
      album: descriptor.album,
      duration: descriptor.duration,
      artworkUrl: descriptor.cover,
      playable: value['is_invalid'] is bool
          ? explicitlyValid &&
              profile.capabilities.contains(CustomMusicSourceCapability.stream)
          : null,
      // The go-music-api preset is a user-operated media proxy whose /stream
      // route serves both playback and downloads. This is the sole preset
      // where that local proxy contract may stand in for a per-row flag.
      downloadAllowed: explicitlyValid &&
              profile.capabilities
                  .contains(CustomMusicSourceCapability.download)
          ? true
          : null,
      bitrate: _optionalNonNegativeInt(value['bitrate']),
    );
  }

  _GoMusicTrackDescriptor _requireGoMusicDescriptor(Audio audio) {
    _requireOwnedTrack(audio);
    final descriptor = _GoMusicTrackDescriptor.decode(audio.onlineId!);
    if (descriptor == null) {
      throw _invalid('go-music-api-v1 曲目标识已损坏或无法识别');
    }
    return descriptor;
  }

  Map<String, String> _goMusicTrackQuery(_GoMusicTrackDescriptor descriptor) {
    final query = <String, String>{
      'id': descriptor.id,
      'source': descriptor.source,
      'name': descriptor.name,
      'artist': descriptor.artist,
      'album': descriptor.album,
      'duration': '${descriptor.duration}',
    };
    if (descriptor.cover case final cover?) {
      query['cover'] = cover;
    }
    if (descriptor.extra.isNotEmpty) {
      query['extra'] = jsonEncode(descriptor.extra);
    }
    return query;
  }

  Future<String> _get(
    Uri uri, {
    required int byteLimit,
    required CustomMusicSourceCancellation? cancellation,
    String accept = 'application/json',
  }) async {
    final token = cancellation ?? CustomMusicSourceCancellation();
    token.check();
    final client = _httpClientFactory()..connectionTimeout = requestTimeout;
    final removeListener = token.onCancel(() => client.close(force: true));
    try {
      final request = await token.race(
        client.getUrl(uri).timeout(requestTimeout),
      );
      token.check();
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DanPlayer/26.0.4 CustomSource/1',
      );
      request.headers.set(HttpHeaders.acceptHeader, accept);
      for (final entry in profile.publicHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await token.race(
        request.close().timeout(requestTimeout),
      );
      token.check();
      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.redirect,
          '自定义歌源尝试重定向，已拒绝该响应',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw CustomMusicSourceException(
          CustomMusicSourceFailureKind.http,
          '自定义歌源请求失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      if (response.contentLength > byteLimit) {
        throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.responseTooLarge,
          '自定义歌源响应过大，已停止读取',
        );
      }
      final bytes = BytesBuilder(copy: false);
      final stream = response.timeout(requestTimeout);
      await for (final chunk in stream) {
        token.check();
        if (bytes.length + chunk.length > byteLimit) {
          throw const CustomMusicSourceException(
            CustomMusicSourceFailureKind.responseTooLarge,
            '自定义歌源响应过大，已停止读取',
          );
        }
        bytes.add(chunk);
      }
      token.check();
      try {
        return utf8.decode(bytes.takeBytes());
      } on FormatException {
        throw _invalid('自定义歌源返回的文本不是有效 UTF-8');
      }
    } on CustomMusicSourceException {
      rethrow;
    } on TimeoutException {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.timeout,
        '自定义歌源请求超时',
      );
    } on SocketException {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.network,
        '无法连接自定义歌源',
      );
    } on HttpException {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.network,
        '自定义歌源连接异常',
      );
    } on Object {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.network,
        '自定义歌源请求异常',
      );
    } finally {
      removeListener();
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeObject(String body, {required String operation}) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw _invalid('自定义歌源返回了无法解析的$operation响应');
    }
    if (decoded is! Map) {
      throw _invalid('自定义歌源返回了非对象$operation响应');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map _payload(Map root) => root['data'] is Map ? root['data'] as Map : root;

  CustomMusicSourceException _invalid(String message) =>
      CustomMusicSourceException(
        CustomMusicSourceFailureKind.invalidResponse,
        message,
      );
}

class _GoMusicTrackDescriptor {
  const _GoMusicTrackDescriptor({
    required this.id,
    required this.source,
    required this.name,
    required this.artist,
    required this.album,
    required this.duration,
    required this.cover,
    required this.extra,
  });

  static const String _prefix = 'gma1.';

  final String id;
  final String source;
  final String name;
  final String artist;
  final String album;
  final int duration;
  final String? cover;
  final Map<String, String> extra;

  String encode() {
    final json = jsonEncode(<String, Object>{
      'id': id,
      'source': source,
      'name': name,
      'artist': artist,
      'album': album,
      'duration': duration,
      if (cover != null) 'cover': cover!,
      if (extra.isNotEmpty) 'extra': extra,
    });
    return '$_prefix${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
  }

  static _GoMusicTrackDescriptor? decode(String value) {
    if (!value.startsWith(_prefix) || value.length > 16384) return null;
    try {
      var encoded = value.substring(_prefix.length);
      encoded += '=' * ((4 - encoded.length % 4) % 4);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! Map) return null;
      final id = _firstText(<Object?>[decoded['id']]);
      final source = _firstText(<Object?>[decoded['source']]);
      final name = _firstText(<Object?>[decoded['name']]);
      if (id == null || source == null || name == null) return null;
      return _GoMusicTrackDescriptor(
        id: id,
        source: source,
        name: name,
        artist: _firstText(<Object?>[decoded['artist']]) ?? 'UNKNOWN',
        album: _firstText(<Object?>[decoded['album']]) ?? 'UNKNOWN',
        duration: _boundedDuration(decoded['duration']),
        cover: _optionalSafeUrl(decoded['cover']),
        extra: _safeStringMap(decoded['extra']),
      );
    } on Object {
      return null;
    }
  }
}

Uri _withQuery(Uri uri, Map<String, String> added) => uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...added,
      },
    );

bool _isSafeHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    !uri.hasFragment;

Uri _safeResponseUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !_isSafeHttpUri(uri)) {
    throw const CustomMusicSourceException(
      CustomMusicSourceFailureKind.invalidResponse,
      '自定义歌源返回了不安全或无效的播放地址',
    );
  }
  return uri;
}

String? _optionalSafeUrl(Object? value) {
  if (value is! String || value.length > 4096) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null && _isSafeHttpUri(uri) ? uri.toString() : null;
}

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    if (value is! String) continue;
    final text = value.trim();
    if (text.isNotEmpty &&
        text.length <= 16384 &&
        !text.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
      return text;
    }
  }
  return null;
}

int _nonNegativeInt(Object? value) {
  final number = _tryInt(value);
  return number == null || number < 0 ? 0 : number;
}

int? _optionalNonNegativeInt(Object? value) {
  if (value == null) return null;
  final number = _tryInt(value);
  return number == null || number < 0 ? null : number;
}

int? _tryInt(Object? value) {
  try {
    if (value is num) return value.isFinite ? value.toInt() : null;
    return value is String ? int.tryParse(value.trim()) : null;
  } on Object {
    return null;
  }
}

int _boundedDuration(Object? value) {
  final duration = _nonNegativeInt(value);
  return duration > 30 * 24 * 60 * 60 ? 0 : duration;
}

String? _safeMimeType(Object? value) {
  if (value is! String) return null;
  final mime = value.trim().toLowerCase();
  return RegExp(r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$')
          .hasMatch(mime)
      ? mime
      : null;
}

DateTime? _dateTime(Object? value) {
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  if (value is num) {
    final raw = _tryInt(value);
    if (raw == null) return null;
    final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on RangeError {
      return null;
    }
  }
  return null;
}

Map<String, String> _safeStringMap(Object? value) {
  if (value is! Map) return const <String, String>{};
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String) continue;
    final key = (entry.key as String).trim();
    final rawValue = entry.value;
    final text = rawValue is String || rawValue is num || rawValue is bool
        ? '$rawValue'
        : null;
    if (key.isEmpty ||
        key.length > 128 ||
        text == null ||
        text.length > 2048 ||
        key.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        text.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      continue;
    }
    result[key] = text;
    if (result.length >= 32) break;
  }
  return Map<String, String>.unmodifiable(result);
}
