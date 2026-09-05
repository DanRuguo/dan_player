import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_source_exception.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';

enum CustomMusicSourceProbeStatus {
  success,
  noSample,
  unsupported,
  needsLogin,
  timeout,
  failed,
  cancelled,
}

class CustomMusicSourceProbeResult {
  const CustomMusicSourceProbeResult(this.capability, this.status, this.detail);

  final CustomMusicSourceCapability capability;
  final CustomMusicSourceProbeStatus status;

  /// A short local message, never a server body, URL, header or credential.
  final String detail;
}

class CustomMusicSourceProbeReport {
  CustomMusicSourceProbeReport({
    required Iterable<CustomMusicSourceProbeResult> results,
    required this.elapsed,
    this.sampleTitle,
  }) : results = List.unmodifiable(results);

  final List<CustomMusicSourceProbeResult> results;
  final Duration elapsed;
  final String? sampleTitle;

  Set<CustomMusicSourceCapability> get detectedCapabilities =>
      Set.unmodifiable({
        for (final result in results)
          if (result.status == CustomMusicSourceProbeStatus.success)
            result.capability,
      });
}

typedef CustomMusicSourceProbeTransportFactory = CustomMusicSourceTransport
    Function(CustomMusicSourceProfile profile);

/// An explicit, read-only check of a draft or saved provider. No settings are
/// changed, songs played, complete media downloaded, or response URLs logged.
class CustomMusicSourceProbeService {
  CustomMusicSourceProbeService({
    CustomMusicSourceProbeTransportFactory? transportFactory,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 6),
    this.totalTimeout = const Duration(seconds: 24),
  })  : assert(requestTimeout > Duration.zero),
        assert(totalTimeout > Duration.zero),
        _transportFactory = transportFactory,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const int resourcePrefixByteLimit = 4096;
  static const int maximumConcurrentRequests = 2;
  final Duration requestTimeout;
  final Duration totalTimeout;
  final CustomMusicSourceProbeTransportFactory? _transportFactory;
  final HttpClient Function() _httpClientFactory;

  Future<CustomMusicSourceProbeReport> run(
    CustomMusicSourceProfile profile, {
    required String title,
    String artist = '',
    String album = '',
    CustomMusicSourceCancellation? cancellation,
    void Function(CustomMusicSourceProbeResult result)? onResult,
  }) async {
    final songTitle = title.trim();
    if (songTitle.isEmpty) throw const FormatException('请填写歌曲名');
    final stopwatch = Stopwatch()..start();
    final token = CustomMusicSourceCancellation();
    final unlink = cancellation?.onCancel(token.cancel);
    var expired = false;
    final deadline = Timer(totalTimeout, () {
      expired = true;
      token.cancel();
    });
    final results =
        <CustomMusicSourceCapability, CustomMusicSourceProbeResult>{};
    final legacy = profile.protocol == CustomMusicSourceProtocol.legacyLyrics;
    // A probe discovers capabilities rather than using the user's unchecked
    // boxes as a permanent gate. This detached copy never enables the source
    // for normal playback or changes its saved identity/configuration.
    final testedProfile = profile.copyWith(
      enabled: true,
      capabilities: legacy
          ? const {CustomMusicSourceCapability.lyrics}
          : CustomMusicSourceCapability.values,
    );
    late final transport = _transportFactory?.call(testedProfile) ??
        CustomMusicSourceTransport(testedProfile,
            httpClientFactory: _httpClientFactory,
            requestTimeout: requestTimeout);
    final samples = <Audio>[];

    void publish(CustomMusicSourceProbeResult result) {
      results[result.capability] = result;
      if (cancellation?.isCancelled != true) onResult?.call(result);
    }

    Future<void> check(
      CustomMusicSourceCapability capability,
      Future<CustomMusicSourceProbeResult> Function() operation,
    ) async {
      if (results.containsKey(capability)) return;
      try {
        token.check();
        if (!_hasConfiguredOperation(testedProfile, capability)) {
          publish(CustomMusicSourceProbeResult(capability,
              CustomMusicSourceProbeStatus.unsupported, '当前协议或配置未提供此项接口'));
          return;
        }
        if (profile.authentication != null) {
          throw const CustomMusicSourceException(
            CustomMusicSourceFailureKind.credentialsNotConfigured,
            '来源要求登录或有效凭据',
          );
        }
        publish(await token.race(operation()));
      } catch (error) {
        publish(_errorResult(capability, error,
            timedOut: expired, cancelled: token.isCancelled));
      }
    }

    CustomMusicSourceProbeResult noSample(
            CustomMusicSourceCapability capability) =>
        CustomMusicSourceProbeResult(capability,
            CustomMusicSourceProbeStatus.noSample, '未找到可用于此项测试的歌曲样本');
    CustomMusicSourceProbeResult unsupported(
            CustomMusicSourceCapability capability) =>
        CustomMusicSourceProbeResult(capability,
            CustomMusicSourceProbeStatus.unsupported, '当前协议未提供此项接口');

    try {
      if (legacy) {
        for (final capability in CustomMusicSourceCapability.values) {
          if (capability != CustomMusicSourceCapability.lyrics) {
            publish(unsupported(capability));
          }
        }
      } else {
        await check(CustomMusicSourceCapability.search, () async {
          final query = [songTitle, artist.trim()]
              .where((part) => part.isNotEmpty)
              .join(' ');
          final response =
              await transport.search(query, limit: 5, cancellation: token);
          if (response.tracks.isEmpty) {
            return noSample(CustomMusicSourceCapability.search);
          }
          final ranked = List<Audio>.of(response.tracks)
            ..sort((left, right) {
              final score = _matchScore(right, songTitle, artist, album)
                  .compareTo(_matchScore(left, songTitle, artist, album));
              return score != 0
                  ? score
                  : response.tracks
                      .indexOf(left)
                      .compareTo(response.tracks.indexOf(right));
            });
          samples.addAll(ranked.take(3));
          return const CustomMusicSourceProbeResult(
              CustomMusicSourceCapability.search,
              CustomMusicSourceProbeStatus.success,
              '已取得歌曲搜索结果');
        });
        await check(CustomMusicSourceCapability.metadata, () async {
          if (samples.isEmpty) {
            return noSample(CustomMusicSourceCapability.metadata);
          }
          var track = samples.first;
          try {
            track = await transport.metadata(track, cancellation: token);
            samples[0] = track;
          } catch (_) {
            token.check();
            // Search also supplies metadata; an absent optional detail row
            // does not invalidate fields already received from the source.
            if (!_hasMetadata(track)) rethrow;
          }
          final hasDetails = _hasMetadata(track);
          return CustomMusicSourceProbeResult(
              CustomMusicSourceCapability.metadata,
              hasDetails
                  ? CustomMusicSourceProbeStatus.success
                  : CustomMusicSourceProbeStatus.noSample,
              hasDetails ? '样本包含歌曲信息' : '此样本未提供额外歌曲信息');
        });
      }

      final jobs = <(
        CustomMusicSourceCapability,
        Future<CustomMusicSourceProbeResult> Function()
      )>[
        (
          CustomMusicSourceCapability.cover,
          () async {
            Object? lastError;
            for (final sample in samples) {
              final address = sample.artworkUrl;
              if (address == null || address.isEmpty) continue;
              try {
                await _checkResource(testedProfile, Uri.parse(address), token,
                    image: true);
                return const CustomMusicSourceProbeResult(
                    CustomMusicSourceCapability.cover,
                    CustomMusicSourceProbeStatus.success,
                    '已验证封面图片响应');
              } catch (error) {
                token.check();
                lastError = error;
              }
            }
            if (lastError != null) throw lastError;
            return noSample(CustomMusicSourceCapability.cover);
          }
        ),
        (
          CustomMusicSourceCapability.lyrics,
          () async {
            if (samples.isEmpty &&
                !legacy &&
                profile.protocol != CustomMusicSourceProtocol.danSourceV1) {
              return noSample(CustomMusicSourceCapability.lyrics);
            }
            final track = samples.firstOrNull ??
                Audio(songTitle, artist.trim(), album.trim(), 0, 0, null, null,
                    'probe-song', 0, 0, null);
            final response = await transport.lyrics(track, cancellation: token);
            final text = response.lyric.trim();
            if (text.toLowerCase().startsWith('<!doctype') ||
                text.toLowerCase().startsWith('<html')) {
              throw const FormatException('Not a lyric response');
            }
            final useful = _hasLyricText(text);
            return CustomMusicSourceProbeResult(
                CustomMusicSourceCapability.lyrics,
                useful
                    ? CustomMusicSourceProbeStatus.success
                    : CustomMusicSourceProbeStatus.noSample,
                useful ? '已取得歌词内容' : '此样本没有可用歌词');
          }
        ),
        (
          CustomMusicSourceCapability.comments,
          () async {
            final track = samples.firstOrNull;
            if (track == null) {
              return noSample(CustomMusicSourceCapability.comments);
            }
            final response =
                await transport.comments(track, limit: 3, cancellation: token);
            return CustomMusicSourceProbeResult(
                CustomMusicSourceCapability.comments,
                response.comments.isEmpty
                    ? CustomMusicSourceProbeStatus.noSample
                    : CustomMusicSourceProbeStatus.success,
                response.comments.isEmpty ? '此样本没有公开评论' : '已取得公开评论');
          }
        ),
        for (final forDownload in [false, true])
          (
            forDownload
                ? CustomMusicSourceCapability.download
                : CustomMusicSourceCapability.stream,
            () async {
              final capability = forDownload
                  ? CustomMusicSourceCapability.download
                  : CustomMusicSourceCapability.stream;
              if (samples.isEmpty) return noSample(capability);
              Object? lastError;
              for (final track in samples) {
                token.check();
                if ((forDownload && track.onlineDownloadAllowed == false) ||
                    (!forDownload && track.onlinePlayable == false)) {
                  continue;
                }
                try {
                  final resolution = await transport.resolve(track,
                      forDownload: forDownload, cancellation: token);
                  if (forDownload && !resolution.downloadAllowed) continue;
                  await _checkResource(testedProfile, resolution.uri, token,
                      forDownload: forDownload);
                  return CustomMusicSourceProbeResult(
                      capability,
                      CustomMusicSourceProbeStatus.success,
                      forDownload ? '已验证公开下载响应，未下载整首歌曲' : '已验证音频响应，未实际播放');
                } catch (error) {
                  token.check();
                  lastError = error;
                }
              }
              if (lastError != null) throw lastError;
              return CustomMusicSourceProbeResult(
                  capability,
                  CustomMusicSourceProbeStatus.noSample,
                  forDownload ? '来源明确禁止下载此样本' : '此样本未开放播放');
            }
          ),
      ];
      var nextJob = 0;
      Future<void> worker() async {
        while (nextJob < jobs.length && !token.isCancelled) {
          final job = jobs[nextJob++];
          if (results.containsKey(job.$1)) continue;
          await check(job.$1, job.$2);
        }
      }

      await Future.wait(
          List.generate(maximumConcurrentRequests, (_) => worker()));
      for (final capability in CustomMusicSourceCapability.values) {
        if (!results.containsKey(capability)) {
          publish(_errorResult(capability, const CustomMusicSourceCancelled(),
              timedOut: expired, cancelled: token.isCancelled));
        }
      }
      return CustomMusicSourceProbeReport(
        results: [
          for (final capability in CustomMusicSourceCapability.values)
            results[capability]!,
        ],
        elapsed: stopwatch.elapsed,
        sampleTitle: samples.isEmpty
            ? null
            : samples.map((track) => track.title).join(' / '),
      );
    } finally {
      deadline.cancel();
      unlink?.call();
      token.cancel();
      stopwatch.stop();
    }
  }

  Future<void> _checkResource(CustomMusicSourceProfile profile, Uri initial,
      CustomMusicSourceCancellation token,
      {bool image = false, bool forDownload = false}) async {
    token.check();
    final client = _httpClientFactory()..connectionTimeout = requestTimeout;
    final unlink = token.onCancel(() => client.close(force: true));
    final timeout = Completer<void>();
    var expired = false;
    final timer = Timer(requestTimeout, () {
      expired = true;
      timeout.complete();
      client.close(force: true);
    });
    Future<T> bounded<T>(Future<T> operation) => Future.any([
          token.race(operation),
          timeout.future
              .then<T>((_) => throw TimeoutException('Resource probe')),
        ]);
    try {
      var uri = initial;
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (!_safeResourceUri(uri, profile, image: image)) {
          throw const FormatException('Unsafe resource address');
        }
        final request = await bounded(client.getUrl(uri));
        request.followRedirects = false;
        request.headers.set(
            HttpHeaders.rangeHeader, 'bytes=0-${resourcePrefixByteLimit - 1}');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request.headers
            .set(HttpHeaders.userAgentHeader, 'DanPlayer/26.0.4 Probe/1');
        final base = Uri.parse(profile.baseUrl);
        if (_sameOrigin(base, uri)) {
          for (final header in profile.publicHeaders.entries) {
            request.headers.set(header.key, header.value);
          }
        }
        final response = await bounded(request.close());
        token.check();
        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          final next = location == null ? null : uri.resolve(location);
          if (redirects >= 3 ||
              next == null ||
              (uri.scheme == 'https' && next.scheme != 'https')) {
            throw const FormatException('Unsafe resource redirect');
          }
          await bounded(response.listen((_) {}).cancel());
          uri = next;
          continue;
        }
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          throw CustomMusicSourceException(
              CustomMusicSourceFailureKind.http, '资源验证请求失败',
              statusCode: response.statusCode);
        }
        final prefix = BytesBuilder(copy: false);
        final iterator = StreamIterator<List<int>>(response);
        try {
          while (prefix.length < resourcePrefixByteLimit &&
              await bounded(iterator.moveNext())) {
            final chunk = iterator.current;
            prefix.add(chunk.sublist(
                0,
                math.min(
                    chunk.length, resourcePrefixByteLimit - prefix.length)));
          }
        } finally {
          await bounded(iterator.cancel());
        }
        token.check();
        final bytes = prefix.takeBytes();
        final mime = response.headers.contentType?.mimeType.toLowerCase() ?? '';
        if (image
            ? !_imagePrefix(bytes)
            : !_audioPrefix(bytes, mime, forDownload)) {
          throw const FormatException(
              'Resource is not a supported media response');
        }
        return;
      }
    } catch (error) {
      if (token.isCancelled) throw const CustomMusicSourceCancelled();
      if (expired) throw TimeoutException('Resource probe');
      rethrow;
    } finally {
      timer.cancel();
      unlink();
      client.close(force: true);
    }
  }
}

CustomMusicSourceProbeResult _errorResult(
    CustomMusicSourceCapability capability, Object error,
    {bool timedOut = false, bool cancelled = false}) {
  if (timedOut ||
      error is TimeoutException ||
      (error is CustomMusicSourceException &&
          error.kind == CustomMusicSourceFailureKind.timeout)) {
    return CustomMusicSourceProbeResult(
        capability, CustomMusicSourceProbeStatus.timeout, '请求超时，可稍后重试');
  }
  if (cancelled || error is CustomMusicSourceCancelled) {
    return CustomMusicSourceProbeResult(
        capability, CustomMusicSourceProbeStatus.cancelled, '测试已取消');
  }
  if (error is LyricUnavailableException) {
    return CustomMusicSourceProbeResult(
        capability, CustomMusicSourceProbeStatus.noSample, '未找到可用于此项测试的歌曲样本');
  }
  if (error is CustomMusicSourceException) {
    if (error.kind == CustomMusicSourceFailureKind.credentialsNotConfigured ||
        error.statusCode == 401 ||
        error.statusCode == 403) {
      return CustomMusicSourceProbeResult(
          capability, CustomMusicSourceProbeStatus.needsLogin, '来源要求登录或有效凭据');
    }
    if (error.statusCode == 404 ||
        error.statusCode == 410 ||
        error.statusCode == 204) {
      return CustomMusicSourceProbeResult(
          capability, CustomMusicSourceProbeStatus.noSample, '未找到可用于此项测试的歌曲样本');
    }
    if (error.kind == CustomMusicSourceFailureKind.unavailable) {
      return CustomMusicSourceProbeResult(
          capability, CustomMusicSourceProbeStatus.noSample, '未找到可用于此项测试的歌曲样本');
    }
    if (error.statusCode == 405 || error.statusCode == 501) {
      return CustomMusicSourceProbeResult(capability,
          CustomMusicSourceProbeStatus.unsupported, '当前协议或配置未提供此项接口');
    }
  }
  return CustomMusicSourceProbeResult(
      capability, CustomMusicSourceProbeStatus.failed, '响应无效或连接失败，可检查配置后重试');
}

bool _meaningful(String? text) =>
    text != null &&
    text.trim().isNotEmpty &&
    !const {'UNKNOWN', '未知', '未知艺术家', '未知专辑'}
        .contains(text.trim().toUpperCase());

bool _hasMetadata(Audio track) =>
    _meaningful(track.artist) ||
    _meaningful(track.album) ||
    track.duration > 0 ||
    track.bitrate != null ||
    _meaningful(track.composer) ||
    _meaningful(track.albumArtist);

bool _hasConfiguredOperation(
    CustomMusicSourceProfile profile, CustomMusicSourceCapability capability) {
  if (profile.protocol == CustomMusicSourceProtocol.legacyLyrics) {
    return capability == CustomMusicSourceCapability.lyrics &&
        profile.endpointFor(capability) != null;
  }
  // Metadata and cover can arrive directly in a valid search response.
  if (capability == CustomMusicSourceCapability.metadata ||
      capability == CustomMusicSourceCapability.cover) {
    return true;
  }
  if (profile.protocol == CustomMusicSourceProtocol.danSourceV1 ||
      capability == CustomMusicSourceCapability.comments) {
    return profile.endpointFor(capability) != null;
  }
  return true;
}

bool _hasLyricText(String text) {
  final words = text.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim().toLowerCase();
  if (words.isEmpty) return false;
  return !RegExp(
    r'^(纯音乐[,，。\s]*(请欣赏)?|此歌曲为没有填词的纯音乐[,，。\s]*请您欣赏|instrumental|no lyrics[.!]?|暂无歌词)$',
  ).hasMatch(words);
}

int _matchScore(Audio audio, String title, String artist, String album) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_/.,，。·]+'), '');
  int field(String actual, String expected, int weight) {
    final query = normalize(expected);
    if (query.isEmpty) return 0;
    final candidate = normalize(actual);
    return candidate == query
        ? weight * 2
        : candidate.contains(query)
            ? weight
            : 0;
  }

  return field(audio.title, title, 8) +
      field(audio.artist, artist, 3) +
      field(audio.album, album, 1);
}

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme == right.scheme &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

bool _safeResourceUri(Uri uri, CustomMusicSourceProfile profile,
    {bool image = false}) {
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme == 'http' && !image) return true;
  final base = Uri.parse(profile.baseUrl);
  return uri.scheme == 'http' &&
      base.scheme == 'http' &&
      _sameOrigin(base, uri);
}

bool _starts(List<int> bytes, List<int> signature, [int offset = 0]) {
  if (bytes.length < signature.length + offset) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i + offset] != signature[i]) return false;
  }
  return true;
}

bool _imagePrefix(Uint8List bytes) =>
    _starts(bytes, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) ||
    _starts(bytes, const [0xff, 0xd8, 0xff]) ||
    _starts(bytes, 'GIF8'.codeUnits) ||
    (_starts(bytes, 'RIFF'.codeUnits) && _starts(bytes, 'WEBP'.codeUnits, 8)) ||
    _starts(bytes, 'BM'.codeUnits);

bool _audioPrefix(Uint8List bytes, String mime, bool forDownload) {
  if (bytes.isEmpty) return false;
  final text = String.fromCharCodes(bytes.take(100)).trimLeft().toLowerCase();
  if (text.startsWith('<') || text.startsWith('{') || text.startsWith('[')) {
    return false;
  }
  if (text.startsWith('#extm3u')) return !forDownload;
  return _starts(bytes, 'ID3'.codeUnits) ||
      _starts(bytes, 'fLaC'.codeUnits) ||
      _starts(bytes, 'OggS'.codeUnits) ||
      (_starts(bytes, 'RIFF'.codeUnits) &&
          _starts(bytes, 'WAVE'.codeUnits, 8)) ||
      _starts(bytes, 'ftyp'.codeUnits, 4) ||
      _starts(bytes, 'FORM'.codeUnits) ||
      _starts(bytes, const [0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11]) ||
      (bytes.length > 1 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0) ||
      (mime.startsWith('audio/') &&
          bytes.any((value) => value < 9 || value > 126));
}
