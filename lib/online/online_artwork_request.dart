import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/cover_image_import.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';

/// One cancellable artwork request. It returns validated, size-limited artwork
/// preview; it never writes to a music file or changes any of its tags.
class OnlineArtworkRequest {
  OnlineArtworkRequest({
    HttpClient Function()? httpClientFactory,
    this.totalTimeout = const Duration(seconds: 6),
  })  : assert(totalTimeout > Duration.zero),
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  final Duration totalTimeout;
  HttpClient? _client;
  bool _cancelled = false;
  bool _timedOut = false;
  static const _byteLimit = maxCoverInputBytes;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _checkCancelled() {
    if (_timedOut) {
      throw TimeoutException('封面获取超时，请稍后重试', totalTimeout);
    }
    if (_cancelled) throw const HttpException('封面下载已取消');
  }

  Future<Uint8List> loadCover(
    String address, {
    String? provider,
    CustomMusicSourceProfile? expectedProfile,
  }) =>
      _loadWithDeadline(
        address,
        provider: provider,
        expectedProfile: expectedProfile,
      );

  /// Keep display artwork at its source resolution. The same bounded download
  /// and image dimension check apply, while Flutter decodes only the requested
  /// physical size. Imported/custom artwork still uses [loadCover].
  Future<Uint8List> loadCoverBytes(
    String address, {
    String? provider,
  }) =>
      _loadWithDeadline(address, provider: provider, preserveOriginal: true);

  Future<Uint8List> _loadWithDeadline(
    String address, {
    String? provider,
    CustomMusicSourceProfile? expectedProfile,
    bool preserveOriginal = false,
  }) {
    return _loadCover(
      address,
      provider: provider,
      expectedProfile: expectedProfile,
      preserveOriginal: preserveOriginal,
    ).timeout(
      totalTimeout,
      onTimeout: () {
        _timedOut = true;
        _client?.close(force: true);
        throw TimeoutException('封面获取超时，请稍后重试', totalTimeout);
      },
    );
  }

  Future<Uint8List> _loadCover(
    String address, {
    String? provider,
    CustomMusicSourceProfile? expectedProfile,
    required bool preserveOriginal,
  }) async {
    _checkCancelled();
    if (expectedProfile != null &&
        provider != null &&
        provider != expectedProfile.providerId) {
      throw const FormatException('对应的自定义歌源已移除、停用或无法提供封面');
    }
    final effectiveProvider = provider ?? expectedProfile?.providerId;
    final isCustomProvider = effectiveProvider?.startsWith('custom:') == true;
    final currentProfile = _currentCustomArtworkProfile(effectiveProvider);
    final customProfile = expectedProfile ?? currentProfile;
    if (isCustomProvider &&
        (customProfile == null || !identical(currentProfile, customProfile))) {
      throw const FormatException('对应的自定义歌源已移除、停用或无法提供封面');
    }
    var uri = Uri.tryParse(address);
    if (uri?.scheme == 'http' && !isCustomProvider) {
      uri = uri!.replace(scheme: 'https');
    }
    if (uri == null || !_isSafeArtworkUri(uri, customProfile)) {
      throw const FormatException('封面来源没有提供安全且有效的图片地址');
    }
    final client = _httpClientFactory()..connectionTimeout = totalTimeout;
    _client = client;
    var customProfileInvalidated = false;
    void onCustomProfilesChanged() {
      if (customProfile == null ||
          identical(
            _currentCustomArtworkProfile(customProfile.providerId),
            customProfile,
          )) {
        return;
      }
      customProfileInvalidated = true;
      client.close(force: true);
    }

    if (customProfile != null) {
      AppSettings.instance.customMusicSources
          .addListener(onCustomProfilesChanged);
    }
    final bytes = BytesBuilder(copy: false);
    try {
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        _checkCancelled();
        if (!_isSafeArtworkUri(uri!, customProfile)) {
          throw const HttpException('封面下载包含不安全的重定向');
        }
        final request = await client.getUrl(uri).timeout(totalTimeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'Dan-Player/26.0.4');
        if (_isCurrentCustomOrigin(uri, customProfile)) {
          for (final entry in customProfile!.publicHeaders.entries) {
            request.headers.set(entry.key, entry.value);
          }
        }
        response = await request.close().timeout(totalTimeout);
        _checkCancelled();
        if (!_isSafeArtworkUri(uri, customProfile)) {
          throw const HttpException('自定义歌源已停用或封面地址不再安全');
        }
        if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          break;
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const HttpException('封面重定向无效');
        uri = uri.resolve(location);
        await response.listen((_) {}).cancel();
        response = null;
      }
      if (response == null) throw const HttpException('封面重定向次数过多');
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('封面服务器返回 HTTP ${response.statusCode}');
      }
      if (response.contentLength > _byteLimit) {
        throw const CoverImageException('封面图片不能超过 20 MiB，请先缩小原图后重试。');
      }
      await for (final chunk in response.timeout(totalTimeout)) {
        _checkCancelled();
        if (!_isSafeArtworkUri(uri!, customProfile)) {
          throw const HttpException('自定义歌源已停用或封面地址不再安全');
        }
        if (bytes.length + chunk.length > _byteLimit) {
          throw const CoverImageException('封面图片不能超过 20 MiB，请先缩小原图后重试。');
        }
        bytes.add(chunk);
      }
    } catch (error) {
      if (customProfileInvalidated) {
        throw const HttpException('自定义歌源已停用或封面地址不再安全');
      }
      rethrow;
    } finally {
      if (customProfile != null) {
        AppSettings.instance.customMusicSources
            .removeListener(onCustomProfilesChanged);
      }
      client.close(force: true);
      _client = null;
    }
    _checkCancelled();
    _requireCurrentCustomProfile(customProfile);
    if (bytes.isEmpty) throw const FormatException('封面服务器返回了空图片');

    final downloaded = bytes.takeBytes();
    final result = preserveOriginal
        ? await _validateDisplayDimensions(downloaded)
        : (await CoverImageImporter.shared.fromBytes(downloaded)).bytes;
    _checkCancelled();
    _requireCurrentCustomProfile(customProfile);
    return result;
  }

  static Future<Uint8List> _validateDisplayDimensions(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > 32768 ||
          height > 32768 ||
          width * height > maxCoverInputPixels) {
        throw const CoverImageException('封面图片最多支持 4000 万像素，请先缩小原图后重试。');
      }
      return bytes;
    } on CoverImageException {
      rethrow;
    } catch (_) {
      throw const CoverImageException('封面图片已损坏或无法解码。');
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static CustomMusicSourceProfile? _currentCustomArtworkProfile(
    String? provider,
  ) {
    final profileId = CustomMusicSourceProfile.profileIdFromProvider(provider);
    if (profileId == null) return null;
    for (final profile in AppSettings.instance.customMusicSources.value) {
      if (profile.id == profileId &&
          profile.enabled &&
          profile.authentication == null &&
          profile.capabilities.contains(CustomMusicSourceCapability.cover)) {
        return profile;
      }
    }
    return null;
  }

  static void _requireCurrentCustomProfile(
    CustomMusicSourceProfile? expected,
  ) {
    if (expected == null ||
        identical(
          _currentCustomArtworkProfile(expected.providerId),
          expected,
        )) {
      return;
    }
    throw const HttpException('自定义歌源已停用或封面地址不再安全');
  }

  static bool _isSafeArtworkUri(
    Uri uri,
    CustomMusicSourceProfile? expected,
  ) {
    if (expected != null &&
        !identical(
          _currentCustomArtworkProfile(expected.providerId),
          expected,
        )) {
      return false;
    }
    return uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        (uri.scheme == 'https' || _allowsCustomCleartext(uri, expected));
  }

  static bool _allowsCustomCleartext(
    Uri uri,
    CustomMusicSourceProfile? expected,
  ) {
    if (expected == null || uri.scheme != 'http') return false;
    final current = _currentCustomArtworkProfile(expected.providerId);
    if (!identical(current, expected)) return false;
    final base = Uri.tryParse(expected.baseUrl);
    return base != null &&
        base.scheme == 'http' &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.host.toLowerCase() == base.host.toLowerCase() &&
        uri.port == base.port;
  }

  static bool _isCurrentCustomOrigin(
    Uri uri,
    CustomMusicSourceProfile? expected,
  ) {
    if (expected == null ||
        !identical(
          _currentCustomArtworkProfile(expected.providerId),
          expected,
        )) {
      return false;
    }
    final base = Uri.tryParse(expected.baseUrl);
    return base != null &&
        uri.host.toLowerCase() == base.host.toLowerCase() &&
        uri.port == base.port;
  }
}
