import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
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

typedef _CustomTransportFactory = CustomMusicSourceTransport Function(
  CustomMusicSourceProfile profile,
);

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

/// Cancels one submitted online search and every active custom-source request
/// owned by it. Built-in transports are still independently bounded, while the
/// caller can stop waiting for them immediately when its page/dialog closes.
class OnlineSearchCancellation {
  final CustomMusicSourceCancellation _token = CustomMusicSourceCancellation();

  bool get isCancelled => _token.isCancelled;

  void cancel() => _token.cancel();

  void check() {
    if (isCancelled) throw _cancelledOnlineSearch();
  }

  void Function() onCancel(void Function() listener) =>
      _token.onCancel(listener);

  Future<T> race<T>(Future<T> operation) async {
    try {
      return await _token.race(operation);
    } on CustomMusicSourceCancelled {
      throw _cancelledOnlineSearch();
    }
  }
}

OnlineMusicException _cancelledOnlineSearch() => const OnlineMusicException(
      OnlineMusicFailureKind.unavailable,
      '联网请求已取消',
    );

class _ProviderSearchResult {
  const _ProviderSearchResult(this.providerKey, this.tracks, [this.error]);

  final String providerKey;
  final List<Audio> tracks;
  final OnlineMusicException? error;
}

class _ResolvedUrl {
  const _ResolvedUrl(this.url, this.expiresAt, {this.profileScope});

  final Uri url;
  final DateTime expiresAt;

  /// Custom profiles are immutable. Binding a cache entry to the exact
  /// instance makes any edit, disable/re-enable cycle or import invalidate it
  /// without coupling this service to settings UI events.
  final CustomMusicSourceProfile? profileScope;
}

/// Unified online music gateway.
///
/// Requests platform endpoints and explicit user-managed provider protocols.
/// No login cookie, paid-track key, or DRM bypass is attempted. Availability
/// is resolved per track rather than inferred from the provider's publisher.
class OnlineMusicService {
  OnlineMusicService._()
      : _sourcePreferences = (() => AppSettings.instance.onlineSources.value),
        _customProfiles = (() => AppSettings.instance.customMusicSources.value),
        _qqSearchOverride = null,
        _neteaseSearchOverride = null,
        _customTransportFactory = CustomMusicSourceTransport.new,
        _customSearchSweepTimeout = const Duration(seconds: 8),
        _retryDelay = const Duration(milliseconds: 220),
        _httpClientFactory = HttpClient.new;

  /// Search-only fixture seam. Both hooks are mandatory so an omitted fake can
  /// never silently issue a real provider request in tests.
  OnlineMusicService.forTesting({
    required OnlineSourcePreferences Function() sourcePreferences,
    required OnlineProviderSearch qqSearch,
    required OnlineProviderSearch neteaseSearch,
    List<CustomMusicSourceProfile> Function()? customProfiles,
    CustomMusicSourceTransport Function(CustomMusicSourceProfile)?
        customTransportFactory,
    Duration customSearchSweepTimeout = const Duration(seconds: 8),
    Duration retryDelay = Duration.zero,
    HttpClient Function()? httpClientFactory,
  })  : _sourcePreferences = sourcePreferences,
        _customProfiles = customProfiles ?? (() => const []),
        _qqSearchOverride = qqSearch,
        _neteaseSearchOverride = neteaseSearch,
        _customTransportFactory =
            customTransportFactory ?? CustomMusicSourceTransport.new,
        _customSearchSweepTimeout = customSearchSweepTimeout,
        _retryDelay = retryDelay,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Fixture seam for the owned raw Netease HTTP/parser path. QQ is disabled
  /// and no other real provider can be contacted by this constructor.
  OnlineMusicService.forNeteaseTransportTesting({
    required HttpClient Function() httpClientFactory,
    Duration retryDelay = Duration.zero,
  })  : _sourcePreferences =
            (() => const OnlineSourcePreferences(qqEnabled: false)),
        _customProfiles = (() => const []),
        _qqSearchOverride = ((_, __) async => const <Audio>[]),
        _neteaseSearchOverride = null,
        _customTransportFactory = CustomMusicSourceTransport.new,
        _customSearchSweepTimeout = const Duration(seconds: 8),
        _retryDelay = retryDelay,
        _httpClientFactory = httpClientFactory;

  static final OnlineMusicService instance = OnlineMusicService._();

  static const _requestTimeout = Duration(seconds: 12);
  static const _downloadReadTimeout = Duration(seconds: 20);
  static const _searchResponseByteLimit = 2 * 1024 * 1024;
  final OnlineSourcePreferences Function() _sourcePreferences;
  final List<CustomMusicSourceProfile> Function() _customProfiles;
  final OnlineProviderSearch? _qqSearchOverride;
  final OnlineProviderSearch? _neteaseSearchOverride;
  final _CustomTransportFactory _customTransportFactory;
  final Duration _customSearchSweepTimeout;
  final Duration _retryDelay;
  final HttpClient Function() _httpClientFactory;
  final Map<String, _ResolvedUrl> _streamCache = {};
  CustomMusicSourceCancellation? _pendingCustomStreamResolution;

  void cancelPendingStreamResolution() {
    _pendingCustomStreamResolution?.cancel();
    _pendingCustomStreamResolution = null;
  }

  /// Whether a user can try downloading. Unknown per-track availability is
  /// resolved by the endpoint, not a source-wide or publisher-based denylist.
  bool canDownload(Audio audio) {
    if (!audio.isOnline || audio.onlineDownloadAllowed == false) return false;
    final custom = _customProfileFor(audio.onlineProvider);
    if (custom != null) {
      return custom.enabled &&
          custom.authentication == null &&
          custom.capabilities.contains(CustomMusicSourceCapability.download);
    }
    return OnlineMusicSource.fromId(audio.onlineProvider)?.supportsDownload ??
        false;
  }

  String? downloadUnavailableReason(Audio audio) {
    if (!audio.isOnline) return "该歌曲不是联网曲目";
    if (canDownload(audio)) return null;
    if (audio.onlineDownloadAllowed == false) {
      return "该歌源明确标记这首歌曲不可下载";
    }
    final customId =
        CustomMusicSourceProfile.profileIdFromProvider(audio.onlineProvider);
    if (customId != null) {
      final profile = _customProfileFor(audio.onlineProvider);
      if (profile == null) return "对应的自定义歌源已被移除";
      if (!profile.enabled) return "对应的自定义歌源已停用";
      if (profile.authentication != null) return "歌源凭据尚未配置";
      if (!profile.capabilities
          .contains(CustomMusicSourceCapability.download)) {
        return "该自定义歌源未提供下载能力";
      }
      return "该歌曲的下载地址当前不可用或需要登录";
    }
    return OnlineMusicSource.fromId(audio.onlineProvider)
            ?.downloadUnavailableReason ??
        "该联网音乐来源当前不支持下载";
  }

  Future<OnlineSearchResponse> search(
    String rawQuery, {
    int limit = 30,
    bool commentsOnly = false,
    OnlineSearchCancellation? cancellation,
  }) async {
    cancellation?.check();
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const OnlineSearchResponse(tracks: [], failures: {});
    }

    // Snapshot once. Built-in search switches affect the next submitted
    // search. A custom profile's own enable switch is stricter: disabling it
    // prevents future requests to that user-managed server.
    final sources = _sourcePreferences().enabledSources;
    final customProfiles = _customProfiles()
        .where((profile) =>
            profile.enabled &&
            profile.capabilities.contains(CustomMusicSourceCapability.search) &&
            (!commentsOnly ||
                (profile.authentication == null &&
                    profile.endpointFor(CustomMusicSourceCapability.comments) !=
                        null)))
        .take(CustomMusicSourceProfileCodec.maximumProfiles)
        .toList(growable: false);
    if (sources.isEmpty && customProfiles.isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        onlineSourcesDisabledMessage,
      );
    }
    final safeLimit = limit < 1 ? 1 : (limit > 50 ? 50 : limit);
    final batchesFuture = Future.wait(<Future<List<_ProviderSearchResult>>>[
      Future.wait(<Future<_ProviderSearchResult>>[
        for (final source in sources)
          _guardSearch(
              source.id,
              source.label,
              () => switch (source) {
                    OnlineMusicSource.qq =>
                      (_qqSearchOverride ?? _searchQq)(query, safeLimit),
                    OnlineMusicSource.netease => (_neteaseSearchOverride ??
                        _searchNetease)(query, safeLimit),
                  }),
      ]),
      _searchCustomProfiles(
        customProfiles,
        query,
        safeLimit,
        cancellation: cancellation,
      ),
    ]);
    final batches = cancellation == null
        ? await batchesFuture
        : await cancellation.race(batchesFuture);
    final results = <_ProviderSearchResult>[
      for (final batch in batches) ...batch,
    ];
    final failures = <String, String>{};
    final tracks = <Audio>[];
    final identities = <String>{};
    for (final result in results) {
      if (result.error != null) {
        failures.update(
          result.providerKey,
          (existing) => '$existing；${result.error!.message}',
          ifAbsent: () => result.error!.message,
        );
      }
      for (final track in result.tracks) {
        if (identities.add(track.path)) tracks.add(track);
      }
    }

    if (tracks.isEmpty &&
        results.isNotEmpty &&
        results.every((result) => result.error != null)) {
      final errors = results.map((result) => result.error!).toList();
      throw OnlineMusicException(
        _combinedFailureKind(errors),
        failures.values.toSet().join("；"),
      );
    }
    return OnlineSearchResponse(tracks: tracks, failures: failures);
  }

  Future<_ProviderSearchResult> _guardSearch(
    String providerKey,
    String displayLabel,
    Future<List<Audio>> Function() search, {
    int maxAttempts = 2,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return _ProviderSearchResult(providerKey, await search());
      } catch (error, trace) {
        final mapped =
            _mapError(error, operation: "搜索", provider: displayLabel);
        final willRetry = mapped.retryable && attempt < maxAttempts;
        LOGGER.w(
          "[online/$displayLabel] ${mapped.message} "
          "(attempt $attempt/$maxAttempts${willRetry ? ', retrying' : ''})",
          stackTrace: trace,
        );
        if (!willRetry) {
          return _ProviderSearchResult(providerKey, const [], mapped);
        }
        if (_retryDelay > Duration.zero) {
          await Future<void>.delayed(_retryDelay);
        }
      }
    }
    throw StateError('unreachable');
  }

  Future<List<_ProviderSearchResult>> _searchCustomProfiles(
    List<CustomMusicSourceProfile> profiles,
    String query,
    int limit, {
    OnlineSearchCancellation? cancellation,
  }) async {
    if (profiles.isEmpty) return const <_ProviderSearchResult>[];
    final results = List<_ProviderSearchResult?>.filled(profiles.length, null);
    var nextIndex = 0;
    var deadlineExpired = false;
    final sweepCancellation = CustomMusicSourceCancellation();
    final removeExternalCancellation =
        cancellation?.onCancel(sweepCancellation.cancel);
    final deadlineTimer = Timer(_customSearchSweepTimeout, () {
      deadlineExpired = true;
      sweepCancellation.cancel();
    });

    OnlineMusicException stoppedError() => deadlineExpired
        ? const OnlineMusicException(
            OnlineMusicFailureKind.timeout,
            '联网请求超时，请稍后重试',
            retryable: true,
          )
        : _cancelledOnlineSearch();

    Future<void> worker() async {
      while (nextIndex < profiles.length) {
        final index = nextIndex++;
        final profile = profiles[index];
        if (sweepCancellation.isCancelled) {
          results[index] = _ProviderSearchResult(
              profile.providerId, const [], stoppedError());
          continue;
        }
        // Each custom transport already owns a strict total deadline. A dead
        // user-managed service must not receive an automatic second request.
        final result = await _guardSearch(
          profile.providerId,
          profile.name,
          () async => (await _customTransportFactory(profile).search(
            query,
            limit: limit,
            cancellation: sweepCancellation,
          ))
              .tracks,
          maxAttempts: 1,
        );
        if (sweepCancellation.isCancelled) {
          results[index] = _ProviderSearchResult(
            profile.providerId,
            const [],
            stoppedError(),
          );
        } else if (result.error == null &&
            !_isCurrentCustomProfileSnapshot(
              profile,
              CustomMusicSourceCapability.search,
            )) {
          results[index] = _ProviderSearchResult(
            profile.providerId,
            const [],
            const OnlineMusicException(
              OnlineMusicFailureKind.unavailable,
              '该联网音乐来源当前不可用',
            ),
          );
        } else {
          results[index] = result;
        }
      }
    }

    try {
      final workerCount = profiles.length < 4 ? profiles.length : 4;
      await Future.wait(
          List<Future<void>>.generate(workerCount, (_) => worker()));
      for (var index = 0; index < results.length; index++) {
        final result = results[index];
        if (result == null || result.error != null) continue;
        if (_isCurrentCustomProfileSnapshot(
          profiles[index],
          CustomMusicSourceCapability.search,
        )) {
          continue;
        }
        results[index] = _ProviderSearchResult(
          profiles[index].providerId,
          const [],
          const OnlineMusicException(
            OnlineMusicFailureKind.unavailable,
            '该联网音乐来源当前不可用',
          ),
        );
      }
      return <_ProviderSearchResult>[
        for (var index = 0; index < results.length; index++)
          results[index] ??
              _ProviderSearchResult(
                profiles[index].providerId,
                const [],
                stoppedError(),
              ),
      ];
    } finally {
      deadlineTimer.cancel();
      removeExternalCancellation?.call();
      sweepCancellation.cancel();
    }
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
          'Mozilla/5.0 DanPlayer/26.0.4 AnonymousSearch');
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

  Future<Audio> refreshMetadata(
    Audio audio, {
    CustomMusicSourceCancellation? cancellation,
  }) async {
    if (audio.onlineProvider == 'netease') {
      return _refreshNeteaseMetadata(audio, cancellation: cancellation);
    }
    final custom = _customProfileFor(audio.onlineProvider);
    if (custom == null) {
      if (CustomMusicSourceProfile.profileIdFromProvider(
              audio.onlineProvider) !=
          null) {
        throw const OnlineMusicException(
            OnlineMusicFailureKind.unavailable, '对应的自定义歌源已被移除');
      }
      return audio;
    }
    final capability =
        custom.capabilities.contains(CustomMusicSourceCapability.metadata)
            ? CustomMusicSourceCapability.metadata
            : custom.capabilities.contains(CustomMusicSourceCapability.cover)
                ? CustomMusicSourceCapability.cover
                : CustomMusicSourceCapability.search;
    _requireCurrentCustomProfile(audio,
        expected: custom, capability: capability, operation: '读取歌曲信息');
    if (capability == CustomMusicSourceCapability.search) return audio;
    final result = await _customTransportFactory(custom)
        .metadata(audio, cancellation: cancellation);
    _requireCurrentCustomProfile(audio,
        expected: custom, capability: capability, operation: '读取歌曲信息');
    return result;
  }

  Future<Audio> _refreshNeteaseMetadata(
    Audio audio, {
    CustomMusicSourceCancellation? cancellation,
  }) async {
    final id = audio.onlineId;
    if (id == null || !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id)) return audio;
    final token = cancellation ?? CustomMusicSourceCancellation();
    token.check();
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    final unlink = token.onCancel(() => client.close(force: true));
    try {
      final operation = () async {
        final request = await client.getUrl(Uri.https(
          'music.163.com',
          '/api/song/detail/',
          {'id': id, 'ids': '[$id]'},
        ));
        token.check();
        request.followRedirects = false;
        request.headers
            .set(HttpHeaders.refererHeader, 'https://music.163.com/');
        request.headers.set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 DanPlayer/26.0.4 AnonymousMetadata');
        final response = await request.close();
        token.check();
        const limit = 256 * 1024;
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > limit) {
          throw const FormatException(
              'Invalid metadata HTTP response or length');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          token.check();
          if (bytes.length + chunk.length > limit) {
            throw const FormatException('Metadata response exceeds limit');
          }
          bytes.add(chunk);
        }
        final root = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (root is! Map) throw const FormatException('Missing song metadata');
        _requireBusinessCode(root['code'], expected: 200, provider: '网易云音乐');
        final songs = root['songs'];
        if (songs is! List) {
          throw const FormatException('Missing song metadata');
        }
        for (final row in songs.whereType<Map>()) {
          final detailed = _neteaseAudio(row);
          if (detailed == null || detailed.onlineId != id) continue;
          return Audio.fromOnlineMap({
            ...audio.toOnlineMap(),
            'title': detailed.title,
            'artist': detailed.artist,
            'album': detailed.album,
            'duration':
                detailed.duration > 0 ? detailed.duration : audio.duration,
            'artworkUrl': detailed.artworkUrl ?? audio.artworkUrl,
          });
        }
        return audio;
      }();
      return await token.race(operation).timeout(_requestTimeout);
    } finally {
      unlink();
      client.close(force: true);
    }
  }

  Future<Uri> resolveStreamUrl(Audio audio, {bool forceRefresh = false}) async {
    _validateOnlineAudio(audio);
    cancelPendingStreamResolution();
    final customProfileId =
        CustomMusicSourceProfile.profileIdFromProvider(audio.onlineProvider);
    final initialCustom = _customProfileFor(audio.onlineProvider);
    if (customProfileId != null) {
      if (initialCustom == null || !initialCustom.enabled) {
        _streamCache.remove(audio.path);
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "对应的自定义歌源已移除或停用，无法解析播放地址",
        );
      }
      if (!initialCustom.capabilities
          .contains(CustomMusicSourceCapability.stream)) {
        _streamCache.remove(audio.path);
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "该自定义歌源当前未提供播放解析能力",
        );
      }
      if (initialCustom.authentication != null) {
        _streamCache.remove(audio.path);
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "该歌源需要凭据，但安全凭据尚未配置",
        );
      }
      if (audio.onlinePlayable == false) {
        _streamCache.remove(audio.path);
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "该歌源明确标记这首歌曲不可播放",
        );
      }
    }
    final cached = _streamCache[audio.path];
    final cacheMatchesProfile = initialCustom == null
        ? cached?.profileScope == null
        : identical(cached?.profileScope, initialCustom);
    if (!forceRefresh &&
        cached != null &&
        cacheMatchesProfile &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    if (cached != null && !cacheMatchesProfile) {
      _streamCache.remove(audio.path);
    }

    try {
      final now = DateTime.now();
      final custom = initialCustom;
      late final Uri url;
      var expiresAt = now.add(const Duration(minutes: 10));
      if (custom != null) {
        final cancellation = CustomMusicSourceCancellation();
        _pendingCustomStreamResolution = cancellation;
        late final CustomMusicStreamResolution resolution;
        try {
          resolution = await _customTransportFactory(custom).resolve(
            audio,
            cancellation: cancellation,
          );
        } finally {
          if (identical(_pendingCustomStreamResolution, cancellation)) {
            _pendingCustomStreamResolution = null;
          }
        }
        _requireCurrentCustomProfile(
          audio,
          expected: custom,
          capability: CustomMusicSourceCapability.stream,
          operation: '播放',
        );
        url = _validatedUri(resolution.uri);
        final remoteExpiry = resolution.expiresAt;
        if (remoteExpiry != null) {
          // Refresh a little before signed URLs expire. An already-expired
          // value remains usable for this attempt but is not cached.
          final early = remoteExpiry.subtract(const Duration(seconds: 5));
          expiresAt = early.isAfter(now) ? early : now;
        }
      } else if (CustomMusicSourceProfile.profileIdFromProvider(
              audio.onlineProvider) !=
          null) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "对应的自定义歌源已被移除，无法解析播放地址",
        );
      } else {
        url = switch (audio.onlineProvider) {
          "qq" => await _resolveQqUrl(audio),
          "netease" => await _resolveNeteaseUrl(audio),
          _ => throw OnlineMusicException(
              OnlineMusicFailureKind.api,
              "不支持的联网音乐来源：${audio.onlineProvider}",
            ),
        };
      }
      _streamCache[audio.path] = _ResolvedUrl(
        url,
        expiresAt,
        profileScope: custom,
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
    if (!canDownload(audio)) {
      throw OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        downloadUnavailableReason(audio) ?? "当前来源不支持下载",
      );
    }
    if (destination.path.trim().isEmpty) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.download,
        "下载失败：目标路径无效",
      );
    }
    Uri uri;
    CustomMusicSourceProfile? resolvedCustomProfile;
    try {
      final custom = _customProfileFor(audio.onlineProvider);
      if (custom != null) {
        resolvedCustomProfile = custom;
        final resolution = await _customTransportFactory(custom).resolve(
          audio,
          forDownload: true,
        );
        _requireCurrentCustomProfile(
          audio,
          expected: custom,
          capability: CustomMusicSourceCapability.download,
          operation: '下载',
        );
        if (!resolution.downloadAllowed) {
          throw const OnlineMusicException(
            OnlineMusicFailureKind.unavailable,
            "该歌源明确标记这首歌曲不可下载",
          );
        }
        uri = _validatedUri(resolution.uri);
      } else if (CustomMusicSourceProfile.profileIdFromProvider(
              audio.onlineProvider) !=
          null) {
        throw const OnlineMusicException(
          OnlineMusicFailureKind.unavailable,
          "对应的自定义歌源已被移除，无法下载",
        );
      } else {
        uri = switch (audio.onlineProvider) {
          "qq" => await _resolveQqUrl(audio, download: true),
          "netease" => await _resolveNeteaseDownloadUrl(audio),
          _ => throw OnlineMusicException(
              OnlineMusicFailureKind.api,
              "不支持的联网音乐来源：${audio.onlineProvider}",
            ),
        };
      }
    } on OnlineMusicException {
      rethrow;
    } catch (error) {
      throw _mapError(error, operation: "获取下载地址", provider: audio.sourceLabel);
    }

    final client = HttpClient()..connectionTimeout = _requestTimeout;
    OnlineMusicException? customProfileInvalidation;
    Timer? customProfileMonitor;

    void requireCurrentDownloadProfile() {
      final invalidation = customProfileInvalidation;
      if (invalidation != null) throw invalidation;
      if (resolvedCustomProfile case final expected?) {
        _requireCurrentCustomProfile(
          audio,
          expected: expected,
          capability: CustomMusicSourceCapability.download,
          operation: '下载',
        );
      }
    }

    if (resolvedCustomProfile != null) {
      requireCurrentDownloadProfile();
      // Closing the client immediately avoids waiting for the media server's
      // read timeout when a profile is disabled or edited mid-download. The
      // explicit checks after every await/chunk remain the source of truth and
      // also cover test/custom profile providers that do not expose a notifier.
      customProfileMonitor = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (customProfileInvalidation != null) return;
          try {
            requireCurrentDownloadProfile();
          } on OnlineMusicException catch (error) {
            customProfileInvalidation = error;
            client.close(force: true);
          }
        },
      );
    }
    final temporary = File(
      "${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.part",
    );
    IOSink? sink;
    try {
      requireCurrentDownloadProfile();
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      requireCurrentDownloadProfile();
      request.headers.set(HttpHeaders.userAgentHeader, "Dan Player/26.0.4");
      final response = await request.close().timeout(_requestTimeout);
      requireCurrentDownloadProfile();
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
      requireCurrentDownloadProfile();
      sink = temporary.openWrite();
      var received = 0;
      final total = response.contentLength >= 0 ? response.contentLength : null;
      await for (final chunk in response.timeout(_downloadReadTimeout)) {
        requireCurrentDownloadProfile();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      requireCurrentDownloadProfile();
      await sink.flush();
      requireCurrentDownloadProfile();
      await sink.close();
      sink = null;
      requireCurrentDownloadProfile();
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
      await _replaceDownloadedFile(
        temporary,
        destination,
        validate: requireCurrentDownloadProfile,
      );
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      if (customProfileInvalidation case final invalidation?) {
        throw invalidation;
      }
      throw _mapError(error, operation: "下载", provider: audio.sourceLabel);
    } finally {
      customProfileMonitor?.cancel();
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
    if ((uri.scheme != "http" && uri.scheme != "https") ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
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
    if (error is CustomMusicSourceException) {
      late final OnlineMusicFailureKind kind;
      late final String message;
      switch (error.kind) {
        case CustomMusicSourceFailureKind.timeout:
          kind = OnlineMusicFailureKind.timeout;
          message = '联网请求超时，请稍后重试';
        case CustomMusicSourceFailureKind.network:
          kind = OnlineMusicFailureKind.network;
          message = '联网失败，请检查网络连接';
        case CustomMusicSourceFailureKind.credentialsNotConfigured:
          kind = OnlineMusicFailureKind.unavailable;
          message = '歌源凭据尚未配置';
        case CustomMusicSourceFailureKind.cancelled:
          kind = OnlineMusicFailureKind.unavailable;
          message = '联网请求已取消';
        case CustomMusicSourceFailureKind.unavailable:
          kind = OnlineMusicFailureKind.unavailable;
          message = '该联网音乐来源当前不可用';
        case CustomMusicSourceFailureKind.responseTooLarge:
        case CustomMusicSourceFailureKind.invalidResponse:
          kind = OnlineMusicFailureKind.api;
          message = '音乐服务返回的数据无效或过大';
        case CustomMusicSourceFailureKind.redirect:
          kind = OnlineMusicFailureKind.api;
          message = '音乐服务拒绝了请求';
        case CustomMusicSourceFailureKind.http:
          final statusCode = error.statusCode ?? 0;
          if (statusCode == 401 || statusCode == 403) {
            kind = OnlineMusicFailureKind.unavailable;
            message = '音乐服务要求登录或拒绝访问此歌曲';
          } else if (statusCode == 408 || statusCode == 504) {
            kind = OnlineMusicFailureKind.timeout;
            message = '联网请求超时，请稍后重试';
          } else if (statusCode == 429 || statusCode >= 500) {
            kind = OnlineMusicFailureKind.network;
            message = '联网失败，请检查网络连接';
          } else if (statusCode == 404 || statusCode == 410) {
            kind = OnlineMusicFailureKind.unavailable;
            message = '该联网音乐来源当前不可用';
          } else {
            kind = OnlineMusicFailureKind.api;
            message = '音乐服务拒绝了请求';
          }
      }
      return OnlineMusicException(
        kind,
        message,
        cause: error,
        retryable: kind == OnlineMusicFailureKind.network ||
            kind == OnlineMusicFailureKind.timeout,
        serviceCode: error.statusCode,
      );
    }
    if (error is TimeoutException) {
      return OnlineMusicException(
        OnlineMusicFailureKind.timeout,
        '联网请求超时，请稍后重试',
        cause: error,
        retryable: true,
      );
    }
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException) {
      return OnlineMusicException(
        OnlineMusicFailureKind.network,
        '联网失败，请检查网络连接',
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
      '联网操作失败，请稍后重试',
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
    if (kinds.length == 1 &&
        kinds.contains(OnlineMusicFailureKind.unavailable)) {
      return OnlineMusicFailureKind.unavailable;
    }
    return OnlineMusicFailureKind.api;
  }

  CustomMusicSourceProfile? _customProfileFor(String? providerId) {
    final profileId =
        CustomMusicSourceProfile.profileIdFromProvider(providerId);
    if (profileId == null) return null;
    for (final profile in _customProfiles()) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  bool _isCurrentCustomProfileSnapshot(
    CustomMusicSourceProfile expected,
    CustomMusicSourceCapability capability,
  ) {
    final current = _customProfileFor(expected.providerId);
    return identical(current, expected) &&
        current!.enabled &&
        current.authentication == null &&
        current.capabilities.contains(capability);
  }

  void _requireCurrentCustomProfile(
    Audio audio, {
    required CustomMusicSourceProfile expected,
    required CustomMusicSourceCapability capability,
    required String operation,
  }) {
    final current = _customProfileFor(audio.onlineProvider);
    if (current == null || !current.enabled) {
      _streamCache.remove(audio.path);
      throw OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '对应的自定义歌源已移除或停用，无法$operation',
      );
    }
    if (!identical(current, expected)) {
      _streamCache.remove(audio.path);
      throw OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '自定义歌源配置已改变，请重新$operation',
      );
    }
    if (!current.capabilities.contains(capability)) {
      _streamCache.remove(audio.path);
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '该自定义歌源当前未提供所需能力',
      );
    }
    if (current.authentication != null) {
      _streamCache.remove(audio.path);
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '该歌源需要凭据，但安全凭据尚未配置',
      );
    }
    if (capability == CustomMusicSourceCapability.stream &&
        audio.onlinePlayable == false) {
      _streamCache.remove(audio.path);
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '该歌源明确标记这首歌曲不可播放',
      );
    }
    if (capability == CustomMusicSourceCapability.download &&
        audio.onlineDownloadAllowed == false) {
      throw const OnlineMusicException(
        OnlineMusicFailureKind.unavailable,
        '该歌源明确标记这首歌曲不可下载',
      );
    }
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
    File destination, {
    void Function()? validate,
  }) async {
    File? backup;
    var replacedDestination = false;
    try {
      validate?.call();
      if (await destination.exists()) {
        validate?.call();
        backup = File(
          "${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.backup",
        );
        await destination.rename(backup.path);
        validate?.call();
      }

      validate?.call();
      await temporary.rename(destination.path);
      replacedDestination = true;
      validate?.call();
    } catch (_) {
      if (replacedDestination && await destination.exists()) {
        try {
          await destination.delete();
        } catch (_) {}
      }
      if (backup != null && await backup.exists()) {
        try {
          if (!await destination.exists()) {
            await backup.rename(destination.path);
          }
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
