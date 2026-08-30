import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/qq_public_search.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:music_api/music_api.dart';
// Reuse only the pinned dependency's anonymous request serializer. Owning the
// HTTP response here keeps status/content-type/schema diagnostics observable.
// ignore: implementation_imports
import 'package:music_api/src/utils/crypto.dart' show weApi;

typedef OnlineProviderSearch = Future<List<Audio>> Function(
    String query, int limit);

enum OnlineMusicFailureKind {
  network,
  timeout,
  api,
  unavailable,
  download,
}

class OnlineMusicException implements Exception {
  const OnlineMusicException(
    this.kind,
    this.message, {
    this.cause,
    this.retryable = false,
    this.serviceCode,
  });

  final OnlineMusicFailureKind kind;
  final String message;
  final Object? cause;
  final bool retryable;
  final int? serviceCode;

  @override
  String toString() => message;
}

class OnlineSearchResponse {
  const OnlineSearchResponse({required this.tracks, required this.failures});

  final List<Audio> tracks;
  final Map<String, String> failures;

  bool get hasPartialFailure => tracks.isNotEmpty && failures.isNotEmpty;
}

class _ProviderSearchResult {
  const _ProviderSearchResult(this.provider, this.tracks, [this.error]);

  final String provider;
  final List<Audio> tracks;
  final OnlineMusicException? error;
}

class _ResolvedUrl {
  const _ResolvedUrl(this.url, this.expiresAt);

  final Uri url;
  final DateTime expiresAt;
}

/// Unified online music gateway.
///
/// It intentionally uses only endpoints already supplied by the project's
/// pinned music_api dependency. No login cookie, paid-track key, or DRM bypass
/// is attempted. Providers may therefore return "不可播放/下载" for restricted
/// tracks, which is surfaced to the UI as a normal capability error.
class OnlineMusicService {
  OnlineMusicService._()
      : _sourcePreferences = (() => AppSettings.instance.onlineSources.value),
        _qqSearchOverride = null,
        _neteaseSearchOverride = null,
        _retryDelay = const Duration(milliseconds: 220),
        _httpClientFactory = HttpClient.new;

  /// Search-only fixture seam. Both hooks are mandatory so an omitted fake can
  /// never silently issue a real provider request in tests.
  OnlineMusicService.forTesting({
    required OnlineSourcePreferences Function() sourcePreferences,
    required OnlineProviderSearch qqSearch,
    required OnlineProviderSearch neteaseSearch,
    Duration retryDelay = Duration.zero,
    HttpClient Function()? httpClientFactory,
  })  : _sourcePreferences = sourcePreferences,
        _qqSearchOverride = qqSearch,
        _neteaseSearchOverride = neteaseSearch,
        _retryDelay = retryDelay,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Fixture seam for the owned raw Netease HTTP/parser path. QQ is disabled
  /// and no other real provider can be contacted by this constructor.
  OnlineMusicService.forNeteaseTransportTesting({
    required HttpClient Function() httpClientFactory,
    Duration retryDelay = Duration.zero,
  })  : _sourcePreferences =
            (() => const OnlineSourcePreferences(qqEnabled: false)),
        _qqSearchOverride = ((_, __) async => const <Audio>[]),
        _neteaseSearchOverride = null,
        _retryDelay = retryDelay,
        _httpClientFactory = httpClientFactory;

  static final OnlineMusicService instance = OnlineMusicService._();

  static const _requestTimeout = Duration(seconds: 12);
  static const _downloadReadTimeout = Duration(seconds: 20);
  static const _searchResponseByteLimit = 2 * 1024 * 1024;
  static const _downloadEnabledProviders = <String>{};
  final OnlineSourcePreferences Function() _sourcePreferences;
  final OnlineProviderSearch? _qqSearchOverride;
  final OnlineProviderSearch? _neteaseSearchOverride;
  final Duration _retryDelay;
  final HttpClient Function() _httpClientFactory;
  final Map<String, _ResolvedUrl> _streamCache = {};

  /// Conservative synchronous capability for menus.
  ///
  /// The pinned anonymous QQ and Netease download endpoints currently reject
  /// requests in real responses. [download] still verifies the official
  /// endpoint when called directly, but the UI should not advertise download
  /// until a provider is explicitly enabled here.
  bool canDownload(Audio audio) =>
      audio.isOnline &&
      _downloadEnabledProviders.contains(audio.onlineProvider?.trim());

  String? downloadUnavailableReason(Audio audio) {
    if (!audio.isOnline) return "该歌曲不是联网曲目";
    if (canDownload(audio)) return null;
    return OnlineMusicSource.fromId(audio.onlineProvider)
            ?.downloadUnavailableReason ??
        "该联网音乐来源当前不支持下载";
  }

  Future<OnlineSearchResponse> search(String rawQuery, {int limit = 30}) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const OnlineSearchResponse(tracks: [], failures: {});
    }

    // Snapshot once. Toggling settings affects the next submitted search, not
    // in-flight work or the URL/lyrics resolvers for saved/queued online songs.
    final sources = _sourcePreferences().enabledSources;
    if (sources.isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        onlineSourcesDisabledMessage,
      );
    }
    final safeLimit = limit < 1 ? 1 : (limit > 50 ? 50 : limit);
    final results = await Future.wait([
      for (final source in sources)
        _guardSearch(
            source.label,
            () => switch (source) {
                  OnlineMusicSource.qq =>
                    (_qqSearchOverride ?? _searchQq)(query, safeLimit),
                  OnlineMusicSource.netease => (_neteaseSearchOverride ??
                      _searchNetease)(query, safeLimit),
                }),
    ]);
    final failures = <String, String>{};
    final tracks = <Audio>[];
    final identities = <String>{};
    for (final result in results) {
      if (result.error != null) {
        failures[result.provider] = result.error!.message;
      }
      for (final track in result.tracks) {
        if (identities.add(track.path)) tracks.add(track);
      }
    }

    if (tracks.isEmpty && failures.length == results.length) {
      final errors = results.map((result) => result.error!).toList();
      throw OnlineMusicException(
        _combinedFailureKind(errors),
        failures.values.join("；"),
      );
    }
    return OnlineSearchResponse(tracks: tracks, failures: failures);
  }

  Future<_ProviderSearchResult> _guardSearch(
    String provider,
    Future<List<Audio>> Function() search,
  ) async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return _ProviderSearchResult(provider, await search());
      } catch (error, trace) {
        final mapped = _mapError(error, operation: "搜索", provider: provider);
        final willRetry = mapped.retryable && attempt < maxAttempts;
        LOGGER.w(
          "[online/$provider] ${mapped.message} "
          "(attempt $attempt/$maxAttempts${willRetry ? ', retrying' : ''})",
          stackTrace: trace,
        );
        if (!willRetry) {
          return _ProviderSearchResult(provider, const [], mapped);
        }
        if (_retryDelay > Duration.zero) {
          await Future<void>.delayed(_retryDelay);
        }
      }
    }
    throw StateError('unreachable');
  }

  Future<List<Audio>> _searchQq(String query, int limit) async {
    try {
      final songs = await QqPublicSearchTransport(
        httpClientFactory: _httpClientFactory,
      ).search(query, limit);
      return [for (final song in songs) _qqPublicAudio(song)];
    } on QqPublicSearchException catch (error) {
      throw OnlineMusicException(
        error.serviceCode == 408
            ? OnlineMusicFailureKind.timeout
            : error.retryable
                ? OnlineMusicFailureKind.network
                : OnlineMusicFailureKind.api,
        error.message,
        cause: error,
        retryable: error.retryable,
        serviceCode: error.serviceCode,
      );
    }
  }

  Audio _qqPublicAudio(QqPublicSong song) {
    return Audio.online(
      provider: "qq",
      id: song.mid,
      numericId: song.numericId,
      mediaId: song.mediaMid ?? song.mid,
      title: song.title,
      artist: song.artists,
      album: song.album,
      duration: song.durationSeconds,
      artworkUrl: song.albumMid == null
          ? null
          : "https://y.qq.com/music/photo_new/T002R300x300M000${song.albumMid}.jpg",
    );
  }

  Future<List<Audio>> _searchNetease(String query, int limit) async {
    final data = await _requestNeteaseSearch(query, limit);
    _requireBusinessCode(data["code"], expected: 200, provider: "网易云音乐");
    final songs = _listAt(data, const ["result", "songs"]);
    if (songs == null) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "网易云音乐返回了无法识别的搜索结果",
      );
    }
    final tracks = <Audio>[];
    for (final value in songs.take(limit)) {
      if (value is! Map) continue;
      final audio = _neteaseAudio(value);
      if (audio != null) tracks.add(audio);
    }
    return tracks;
  }

  Future<Map<String, dynamic>> _requestNeteaseSearch(
      String query, int limit) async {
    final uri = Uri.https('music.163.com', '/weapi/search/get');
    final form = weApi({
      's': query,
      'type': 1,
      'limit': limit,
      'offset': 0,
      'csrf_token': '',
    });
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    try {
      final request = await client.postUrl(uri).timeout(_requestTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 DanPlayer/26.0.3 AnonymousSearch');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
      final response = await request.close().timeout(_requestTimeout);
      final contentType = response.headers.contentType?.mimeType;
      if (response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500) {
        throw OnlineMusicException(
          response.statusCode == 408
              ? OnlineMusicFailureKind.timeout
              : OnlineMusicFailureKind.network,
          '网易云音乐搜索服务暂时不可用（HTTP ${response.statusCode}）',
          retryable: true,
          serviceCode: response.statusCode,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw OnlineMusicException(
          OnlineMusicFailureKind.api,
          '网易云音乐搜索失败（HTTP ${response.statusCode}）',
          serviceCode: response.statusCode,
        );
      }
      if (response.contentLength > _searchResponseByteLimit) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.api,
          '网易云音乐搜索响应过大，已停止解析',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_requestTimeout)) {
        if (bytes.length + chunk.length > _searchResponseByteLimit) {
          throw const OnlineMusicException(
            OnlineMusicFailureKind.api,
            '网易云音乐搜索响应过大，已停止解析',
          );
        }
        bytes.add(chunk);
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException catch (error) {
        throw OnlineMusicException(
          OnlineMusicFailureKind.api,
          '网易云音乐返回了无法解析的响应${contentType == null ? '' : '（$contentType）'}',
          cause: error,
        );
      }
      if (decoded is! Map) {
        throw OnlineMusicException(
          OnlineMusicFailureKind.api,
          '网易云音乐返回了非对象响应${contentType == null ? '' : '（$contentType）'}',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Audio? _neteaseAudio(Map song) {
    final id = _firstString([song["id"]]);
    if (id == null) return null;
    final artistValues = song["artists"] is List
        ? song["artists"] as List
        : song["ar"] is List
            ? song["ar"] as List
            : const [];
    final artist = artistValues
        .whereType<Map>()
        .map((item) => item["name"]?.toString() ?? "")
        .where((name) => name.isNotEmpty)
        .join("、");
    final album = song["album"] is Map
        ? song["album"] as Map
        : song["al"] is Map
            ? song["al"] as Map
            : const {};
    final durationMs =
        _nonNegative(_integer(song["duration"]) ?? _integer(song["dt"]));
    return Audio.online(
      provider: "netease",
      id: id,
      title: _firstString([song["name"]]) ?? "UNKNOWN",
      artist: artist,
      album: album["name"]?.toString() ?? "UNKNOWN",
      duration: durationMs ~/ 1000,
      artworkUrl: _firstString([album["picUrl"], album["blurPicUrl"]]),
    );
  }

  Future<Uri> resolveStreamUrl(Audio audio, {bool forceRefresh = false}) async {
    _validateOnlineAudio(audio);
    final cached = _streamCache[audio.path];
    if (!forceRefresh &&
        cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }

    try {
      final url = switch (audio.onlineProvider) {
        "qq" => await _resolveQqUrl(audio),
        "netease" => await _resolveNeteaseUrl(audio),
        _ => throw OnlineMusicException(
            OnlineMusicFailureKind.api,
            "不支持的联网音乐来源：${audio.onlineProvider}",
          ),
      };
      _streamCache[audio.path] = _ResolvedUrl(
        url,
        DateTime.now().add(const Duration(minutes: 10)),
      );
      return url;
    } catch (error) {
      throw _mapError(error, operation: "获取播放地址", provider: audio.sourceLabel);
    }
  }

  Future<Uri> _resolveQqUrl(Audio audio, {bool download = false}) async {
    final answer = download
        ? await QQ
            .songDownload(
              songMid: audio.onlineId,
              mediaMid: audio.onlineMediaId ?? audio.onlineId,
            )
            .timeout(_requestTimeout)
        : await QQ
            .songListen(
              songMid: audio.onlineId,
              mediaMid: audio.onlineMediaId ?? audio.onlineId,
            )
            .timeout(_requestTimeout);
    _requireAnswerSuccess(
      answer.code,
      "QQ音乐",
      download ? "获取下载地址" : "获取播放地址",
    );
    final data = answer.data;
    if (data is! Map) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "QQ音乐返回了无法识别的音源数据",
      );
    }
    _requireBusinessCode(data["code"], expected: 0, provider: "QQ音乐");

    final section = download ? "queryvkey" : "req_0";
    _requireBusinessCode(
      _valueAt(data, [section, "code"]),
      expected: 0,
      provider: "QQ音乐",
    );
    final info = _listAt(data, [section, "data", "midurlinfo"]) ??
        _listAt(data, const ["queryvkey", "data", "midurlinfo"]);
    String? direct;
    for (final item in info?.whereType<Map>() ?? const <Map>[]) {
      final result = _integer(item["result"]);
      final candidate = _firstString([item["url"], item["purl"]]);
      if (candidate != null && (result == null || result == 0)) {
        direct = candidate;
        break;
      }
    }
    if (direct == null) return _unavailableUri("QQ音乐");
    final directUri = Uri.tryParse(direct);
    if (directUri != null && directUri.hasScheme) {
      return _validatedUri(directUri);
    }

    final sip = _firstString([
      ..._stringListAt(data, const ["req", "data", "freeflowsip"]),
      ..._stringListAt(data, const ["req", "data", "sip"]),
      ..._stringListAt(data, [section, "data", "sip"]),
      ..._stringListAt(data, const ["queryvkey", "data", "sip"]),
    ]);
    final base = Uri.tryParse(
      sip ?? "https://isure.stream.qqmusic.qq.com/",
    );
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "QQ音乐返回了无效的音源节点",
      );
    }
    return _validatedUri(base.resolve(direct));
  }

  Future<Uri> _resolveNeteaseUrl(Audio audio) async {
    // In the pinned c6f3e0a dependency, passing its declared int `br` causes
    // an internal int.parse(int) TypeError. The wrapper's default is valid and
    // was verified against a real response, so deliberately omit `br` here.
    final answer =
        await Netease.songUrl(id: audio.onlineId).timeout(_requestTimeout);
    _requireAnswerSuccess(answer.code, "网易云音乐", "获取播放地址");
    final data = answer.data;
    if (data is! Map) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "网易云音乐返回了无法识别的音源数据",
      );
    }
    _requireBusinessCode(data["code"], expected: 200, provider: "网易云音乐");
    for (final item in _mapItems(data["data"])) {
      final itemCode = _integer(item["code"]);
      if (itemCode != null && itemCode != 200) continue;
      final value = _firstString([item["url"]]);
      final uri = value == null ? null : Uri.tryParse(value);
      if (uri != null) return _validatedUri(uri);
    }
    return _unavailableUri("网易云音乐");
  }

  Future<Uri> _resolveNeteaseDownloadUrl(Audio audio) async {
    final answer = await Netease.api(
      "/song/download/url",
      params: {"id": audio.onlineId, "br": "320000"},
      cookie: <Cookie>[],
    ).timeout(_requestTimeout);
    _requireAnswerSuccess(answer.code, "网易云音乐", "获取下载地址");
    final data = answer.data;
    if (data is! Map) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "网易云音乐返回了无法识别的下载数据",
      );
    }
    _requireBusinessCode(data["code"], expected: 200, provider: "网易云音乐");
    for (final item in _mapItems(data["data"])) {
      final itemCode = _integer(item["code"]);
      if (itemCode != null && itemCode != 200) continue;
      final value = _firstString([item["url"]]);
      final uri = value == null ? null : Uri.tryParse(value);
      if (uri != null) return _validatedUri(uri);
    }
    return _unavailableUri("网易云音乐");
  }

  Future<void> download(
    Audio audio,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    _validateOnlineAudio(audio);
    if (destination.path.trim().isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.download,
        "下载失败：目标路径无效",
      );
    }
    Uri uri;
    try {
      uri = switch (audio.onlineProvider) {
        "qq" => await _resolveQqUrl(audio, download: true),
        "netease" => await _resolveNeteaseDownloadUrl(audio),
        _ => throw OnlineMusicException(
            OnlineMusicFailureKind.api,
            "不支持的联网音乐来源：${audio.onlineProvider}",
          ),
      };
    } on OnlineMusicException {
      rethrow;
    } catch (error) {
      throw _mapError(error, operation: "获取下载地址", provider: audio.sourceLabel);
    }

    final client = HttpClient()..connectionTimeout = _requestTimeout;
    final temporary = File(
      "${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.part",
    );
    IOSink? sink;
    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, "Dan Player/26.0.3");
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnlineMusicException(
          OnlineMusicFailureKind.download,
          "下载失败：HTTP ${response.statusCode}",
        );
      }
      final mimeType = response.headers.contentType?.mimeType.toLowerCase();
      if (_isRejectedDownloadMimeType(mimeType)) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.download,
          "下载失败：服务端返回的不是音频文件",
        );
      }
      _validateDestinationExtension(destination.path, mimeType);
      if (response.contentLength == 0) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.download,
          "下载失败：服务端返回了空文件",
        );
      }
      await destination.parent.create(recursive: true);
      sink = temporary.openWrite();
      var received = 0;
      final total = response.contentLength >= 0 ? response.contentLength : null;
      await for (final chunk in response.timeout(_downloadReadTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.download,
          "下载失败：服务端返回了空文件",
        );
      }
      if (total != null && received != total) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.download,
          "下载失败：文件接收不完整",
        );
      }
      await _replaceDownloadedFile(temporary, destination);
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      throw _mapError(error, operation: "下载", provider: audio.sourceLabel);
    } finally {
      client.close(force: true);
    }
  }

  static String suggestedFileName(Audio audio) {
    final raw = "${audio.title} - ${audio.artist}";
    final safe = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), "_")
        .replaceAll(RegExp(r"[. ]+$"), "")
        .trim();
    return "${safe.isEmpty ? "Dan Player 下载" : safe}.mp3";
  }

  void _validateOnlineAudio(Audio audio) {
    if (!audio.isOnline ||
        audio.onlineProvider!.trim().isEmpty ||
        audio.onlineId!.trim().isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "该联网曲目的来源信息不完整",
      );
    }
  }

  Uri _unavailableUri(String provider) => throw OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        "$provider未提供这首歌的可用地址，可能需要会员、已下架或受地区限制",
      );

  Uri _validatedUri(Uri uri) {
    if ((uri.scheme != "http" && uri.scheme != "https") || uri.host.isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.api,
        "音乐服务返回了无效地址",
      );
    }
    return uri;
  }

  OnlineMusicException _mapError(
    Object error, {
    required String operation,
    required String provider,
  }) {
    if (error is OnlineMusicException) return error;
    if (error is TimeoutException) {
      return OnlineMusicException(
        OnlineMusicFailureKind.timeout,
        "$provider$operation超时，请稍后重试",
        cause: error,
        retryable: true,
      );
    }
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException) {
      return OnlineMusicException(
        OnlineMusicFailureKind.network,
        "$provider联网失败，请检查网络连接",
        cause: error,
        retryable: true,
      );
    }
    if (error is FileSystemException && operation == "下载") {
      return OnlineMusicException(
        OnlineMusicFailureKind.download,
        "下载失败：无法写入目标文件",
        cause: error,
      );
    }
    return OnlineMusicException(
      OnlineMusicFailureKind.api,
      "$provider$operation失败，请稍后重试",
      cause: error,
    );
  }

  static OnlineMusicFailureKind _combinedFailureKind(
    Iterable<OnlineMusicException> errors,
  ) {
    final kinds = errors.map((error) => error.kind).toSet();
    if (kinds.contains(OnlineMusicFailureKind.network)) {
      return OnlineMusicFailureKind.network;
    }
    if (kinds.contains(OnlineMusicFailureKind.timeout)) {
      return OnlineMusicFailureKind.timeout;
    }
    return OnlineMusicFailureKind.api;
  }

  static void _requireAnswerSuccess(
    int code,
    String provider,
    String operation,
  ) {
    if (code == 200) return;
    if (code == 408 || code == 504) {
      throw OnlineMusicException(
        OnlineMusicFailureKind.timeout,
        "$provider$operation超时，请稍后重试",
        retryable: true,
        serviceCode: code,
      );
    }
    if (code >= 500) {
      throw OnlineMusicException(
        OnlineMusicFailureKind.network,
        "$provider服务暂时不可用，请稍后重试",
        retryable: true,
        serviceCode: code,
      );
    }
    throw OnlineMusicException(
      OnlineMusicFailureKind.api,
      "$provider$operation失败（服务代码 $code）",
      serviceCode: code,
    );
  }

  static void _requireBusinessCode(
    Object? rawCode, {
    required int expected,
    required String provider,
  }) {
    if (rawCode == null) return;
    final code = _integer(rawCode);
    if (code == expected) return;
    if (code == null) {
      throw OnlineMusicException(
        OnlineMusicFailureKind.api,
        "$provider返回了无法识别的服务状态",
      );
    }
    final knownTransient = provider == "QQ音乐" && code == 2001;
    throw OnlineMusicException(
      OnlineMusicFailureKind.api,
      knownTransient
          ? "$provider请求遇到临时服务状态（代码 $code）"
          : "$provider请求失败（服务代码 $code）",
      retryable: knownTransient,
      serviceCode: code,
    );
  }

  static bool _isRejectedDownloadMimeType(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType.startsWith("text/") ||
        mimeType == "application/json" ||
        mimeType.endsWith("+json") ||
        mimeType == "application/xml" ||
        mimeType.endsWith("+xml");
  }

  static void _validateDestinationExtension(String path, String? mimeType) {
    final allowed = switch (mimeType) {
      "audio/mpeg" || "audio/mp3" => const {"mp3"},
      "audio/mp4" => const {"m4a", "mp4"},
      "audio/aac" => const {"aac"},
      "audio/flac" || "audio/x-flac" => const {"flac"},
      "audio/ogg" => const {"ogg", "opus"},
      "audio/opus" => const {"opus", "ogg"},
      "audio/wav" || "audio/x-wav" => const {"wav"},
      _ => null,
    };
    if (allowed == null) return;
    final fileName = path.split(RegExp(r"[/\\]")).last;
    final dot = fileName.lastIndexOf(".");
    if (dot < 0 || dot == fileName.length - 1) return;
    final extension = fileName.substring(dot + 1).toLowerCase();
    if (allowed.contains(extension)) return;
    final suggestion = allowed.first;
    throw OnlineMusicException(
      OnlineMusicFailureKind.download,
      "下载内容不是 .$extension 格式，请将文件扩展名改为 .$suggestion",
    );
  }

  static Future<void> _replaceDownloadedFile(
    File temporary,
    File destination,
  ) async {
    File? backup;
    if (await destination.exists()) {
      backup = File(
        "${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.backup",
      );
      await destination.rename(backup.path);
    }

    try {
      await temporary.rename(destination.path);
    } catch (_) {
      if (backup != null &&
          await backup.exists() &&
          !await destination.exists()) {
        try {
          await backup.rename(destination.path);
        } catch (restoreError, trace) {
          LOGGER.e(
            "[online download] failed to restore existing destination: "
            "$restoreError",
            stackTrace: trace,
          );
        }
      }
      rethrow;
    }

    if (backup != null && await backup.exists()) {
      try {
        await backup.delete();
      } catch (error, trace) {
        LOGGER.w(
          "[online download] downloaded file replaced successfully, but the "
          "temporary backup could not be removed: $error",
          stackTrace: trace,
        );
      }
    }
  }

  static int _nonNegative(int? value) => value != null && value > 0 ? value : 0;

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "");
  }

  static dynamic _valueAt(Map root, List<String> path) {
    dynamic value = root;
    for (final key in path) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value;
  }

  static List? _listAt(Map root, List<String> path) {
    final value = _valueAt(root, path);
    return value is List ? value : null;
  }

  static List<String> _stringListAt(Map root, List<String> path) {
    final values = _listAt(root, path);
    if (values == null) return const [];
    return [
      for (final value in values)
        if (_firstString([value]) case final text?) text,
    ];
  }

  static Iterable<Map> _mapItems(Object? value) sync* {
    if (value is Map) {
      yield value;
    } else if (value is List) {
      yield* value.whereType<Map>();
    }
  }

  static String? _firstString(Iterable<Object?> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != "null") return text;
    }
    return null;
  }
}
