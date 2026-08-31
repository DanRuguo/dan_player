import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:github/github.dart';
import 'package:path/path.dart' as path;

/// A small SemVer implementation used by the updater.
///
/// Build metadata is deliberately ignored while pre-release identifiers follow
/// the SemVer precedence rules. This avoids mistakes such as treating 26.0.10
/// as older than 26.0.3.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.revision = 0,
    this.preRelease = const [],
  });

  final int major;
  final int minor;
  final int patch;
  final int revision;
  final List<String> preRelease;

  static AppVersion? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (normalized.length > 96) return null;
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final numbers = [
      for (var i = 1; i <= 3; i++) int.tryParse(match.group(i)!)
    ];
    final revision = int.tryParse(match.group(4) ?? '0');
    final prerelease = match.group(5)?.split('.') ?? const <String>[];
    if (numbers.any((value) => value == null) ||
        revision == null ||
        prerelease.any((part) => part.isEmpty)) {
      return null;
    }

    return AppVersion(
      numbers[0]!,
      numbers[1]!,
      numbers[2]!,
      revision: revision,
      preRelease: prerelease,
    );
  }

  @override
  int compareTo(AppVersion other) {
    final numbers = [major, minor, patch, revision];
    final otherNumbers = [
      other.major,
      other.minor,
      other.patch,
      other.revision
    ];
    for (var i = 0; i < numbers.length; i++) {
      final compared = numbers[i].compareTo(otherNumbers[i]);
      if (compared != 0) return compared;
    }

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < length; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;
      final left = preRelease[i];
      final right = other.preRelease[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      final compared = switch ((leftNumber, rightNumber)) {
        (final int leftValue, final int rightValue) =>
          leftValue.compareTo(rightValue),
        (final int _, null) => -1,
        (null, final int _) => 1,
        _ => left.compareTo(right),
      };
      if (compared != 0) return compared;
    }
    return 0;
  }

  @override
  String toString() {
    final revisionSuffix = revision == 0 ? '' : '.$revision';
    final preReleaseSuffix =
        preRelease.isEmpty ? '' : '-${preRelease.join('.')}';
    return '$major.$minor.$patch$revisionSuffix$preReleaseSuffix';
  }
}

class AvailableUpdate {
  const AvailableUpdate({
    required this.release,
    required this.version,
    this.asset,
    this.checksumAsset,
  });

  final Release release;
  final AppVersion version;
  final ReleaseAsset? asset;
  final ReleaseAsset? checksumAsset;

  bool get isPreview =>
      release.isPrerelease == true || version.preRelease.isNotEmpty;
}

class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

class UpdateDownloadResult {
  const UpdateDownloadResult({
    required this.file,
    required this.sha256Digest,
    required this.checksumVerified,
  });

  final File file;
  final String sha256Digest;
  final bool checksumVerified;

  bool canInstall(AvailableUpdate update) =>
      checksumVerified &&
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256Digest) &&
      path.basename(file.path) == update.asset?.name &&
      UpdateService.isProjectInstaller(update.asset?.name,
          version: update.version.toString());
}

class UpdateDownloadCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }

  void attach(void Function() onCancel) {
    _onCancel = onCancel;
    if (_cancelled) onCancel();
  }

  void detach() => _onCancel = null;
}

class UpdateException implements Exception {
  const UpdateException(this.message, [this.cause]) : arguments = const [];
  const UpdateException.formatted(this.message, this.arguments) : cause = null;

  final String message;
  final Object? cause;
  final List<Object?> arguments;

  @override
  String toString() => message;
}

class UpdateService {
  UpdateService._()
      : _appDataDirectory = getAppDataDir,
        _httpClientFactory = (() => HttpClient()),
        _releaseLoader = _loadReleases,
        _currentVersion = AppSettings.version,
        _savePreferences = _saveSettings;

  @visibleForTesting
  UpdateService.forTesting({
    required Future<Directory> Function() appDataDirectory,
    required HttpClient Function() httpClientFactory,
    Future<List<Release>> Function()? releaseLoader,
    String currentVersion = AppSettings.version,
    Future<void> Function()? savePreferences,
  })  : _appDataDirectory = appDataDirectory,
        _httpClientFactory = httpClientFactory,
        _releaseLoader = releaseLoader ?? (() async => const []),
        _currentVersion = currentVersion,
        _savePreferences = savePreferences ?? (() async {});

  static final instance = UpdateService._();
  static int _ignoreRevision = 0;

  static const _requestTimeout = Duration(seconds: 15);
  static const _downloadIdleTimeout = Duration(seconds: 30);
  static const _automaticCheckInterval = Duration(hours: 24);

  final Future<Directory> Function() _appDataDirectory;
  final HttpClient Function() _httpClientFactory;
  final Future<List<Release>> Function() _releaseLoader;
  final String _currentVersion;
  final Future<void> Function() _savePreferences;
  Future<List<Release>>? _checkInFlight;

  static Future<void> _saveSettings() => AppSettings.instance
      .saveSettings(captureWindowSize: false, throwOnError: true);

  static Future<List<Release>> _loadReleases() =>
      AppSettings.github.repositories
          .listReleases(AppSettings.githubRepositorySlug)
          .take(100)
          .toList();

  bool get shouldCheckAutomatically {
    final settings = AppSettings.instance;
    if (!settings.autoCheckUpdates) return false;
    final lastCheck = settings.lastUpdateCheckAt;
    return lastCheck == null ||
        DateTime.now().difference(lastCheck) >= _automaticCheckInterval;
  }

  Future<AvailableUpdate?> checkLatest({
    bool includeIgnored = false,
    bool? includePreviews,
  }) async {
    final previews =
        includePreviews ?? AppSettings.instance.receivePreviewUpdates;
    // Share only the HTTP operation, never another caller's channel decision.
    final task = _checkInFlight ??= _fetchReleases();
    try {
      final releases = await task;
      final current = AppVersion.tryParse(_currentVersion);
      if (current == null) {
        throw const UpdateException('当前版本号格式无效，无法安全比较更新。');
      }
      final update = selectLatestRelease(releases,
          current: current, includePreviews: previews);
      if (!includeIgnored &&
          update?.version.toString() ==
              AppSettings.instance.ignoredUpdateVersion) {
        return null;
      }
      return update;
    } finally {
      if (identical(_checkInFlight, task)) _checkInFlight = null;
    }
  }

  Future<void> recordSuccessfulCheck() async {
    AppSettings.instance.lastUpdateCheckAt = DateTime.now();
    await _savePreferences();
  }

  Future<void> ignoreVersion(AppVersion version) async {
    final settings = AppSettings.instance;
    final previous = settings.ignoredUpdateVersion;
    final revision = ++_ignoreRevision;
    settings.ignoredUpdateVersion = version.toString();
    try {
      await _savePreferences();
    } catch (_) {
      if (revision == _ignoreRevision &&
          settings.ignoredUpdateVersion == version.toString()) {
        settings.ignoredUpdateVersion = previous;
      }
      rethrow;
    }
  }

  Future<List<Release>> _fetchReleases() async {
    try {
      return await _releaseLoader().timeout(_requestTimeout);
    } on TimeoutException catch (error) {
      throw UpdateException('检查更新超时，请检查网络连接后重试。', error);
    } on SocketException catch (error) {
      throw UpdateException('无法连接 GitHub，请检查网络连接后重试。', error);
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException('GitHub 更新服务暂时不可用，请稍后重试。', error);
    }
  }

  AvailableUpdate? selectLatestRelease(
    Iterable<Release> releases, {
    required AppVersion current,
    required bool includePreviews,
    String? architecture,
  }) {
    Release? newest;
    AppVersion? newestVersion;
    for (final release in releases) {
      if (release.isDraft == true) continue;
      final version = AppVersion.tryParse(release.tagName);
      if (version == null || version.compareTo(current) <= 0) continue;
      final preview =
          release.isPrerelease == true || version.preRelease.isNotEmpty;
      if (preview && !includePreviews) continue;
      final comparison =
          newestVersion == null ? 1 : version.compareTo(newestVersion);
      if (comparison > 0 ||
          (comparison == 0 && newest?.isPrerelease == true && !preview)) {
        newest = release;
        newestVersion = version;
      }
    }
    if (newest == null || newestVersion == null) return null;
    final asset = selectWindowsAsset(newest.assets ?? const [],
        architecture: architecture, version: newestVersion.toString());
    return AvailableUpdate(
      release: newest,
      version: newestVersion,
      asset: asset,
      checksumAsset: asset == null
          ? null
          : selectChecksumAsset(newest.assets ?? const [], asset.name!),
    );
  }

  static bool isProjectInstaller(String? name, {String? version}) {
    if (name == null) return false;
    final match = RegExp(r'^DanPlayer-(.+)-Setup-(x64|arm64|x86)\.exe$',
            caseSensitive: false)
        .firstMatch(name);
    if (match == null) return false;
    final parsed = AppVersion.tryParse(match.group(1));
    return parsed != null && (version == null || parsed.toString() == version);
  }

  ReleaseAsset? selectWindowsAsset(
    List<ReleaseAsset> assets, {
    String? architecture,
    String? version,
  }) {
    final currentArchitecture = architecture ?? _windowsArchitecture();
    for (final asset in assets) {
      final name = asset.name?.toLowerCase() ?? '';
      if (asset.browserDownloadUrl == null || name.isEmpty) continue;
      // This updater launches only our versioned Setup package. Portable ZIPs,
      // arbitrary EXEs and MSIX require the explicit release-page fallback.
      if (!isProjectInstaller(asset.name, version: version)) continue;
      if (name.endsWith('-setup-$currentArchitecture.exe')) return asset;
    }
    return null;
  }

  String _windowsArchitecture() {
    final value = (Platform.environment['PROCESSOR_ARCHITEW6432'] ??
            Platform.environment['PROCESSOR_ARCHITECTURE'] ??
            '')
        .toLowerCase();
    if (value.contains('arm64') || value.contains('aarch64')) return 'arm64';
    if (value.contains('amd64') || value.contains('x86_64')) return 'x64';
    if (value.contains('x86')) return 'x86';
    return 'unknown';
  }

  ReleaseAsset? selectChecksumAsset(
      List<ReleaseAsset> assets, String assetName) {
    final lowerAssetName = assetName.toLowerCase();
    final exactNames = {
      '$lowerAssetName.sha256',
      '$lowerAssetName.sha256sum',
      '$lowerAssetName.sha256.txt',
    };
    for (final asset in assets) {
      if (exactNames.contains(asset.name?.toLowerCase())) return asset;
    }
    for (final asset in assets) {
      final name = asset.name?.toLowerCase() ?? '';
      if (name == 'sha256sums' ||
          name == 'sha256sums.txt' ||
          name == 'checksums.txt' ||
          name == 'checksum.txt') {
        return asset;
      }
    }
    return null;
  }

  Future<UpdateDownloadResult> download(
    AvailableUpdate update, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    UpdateDownloadCancellation? cancellation,
  }) async {
    _throwIfCancelled(cancellation);
    final asset = update.asset;
    final downloadUrl = asset?.browserDownloadUrl;
    final originalName = asset?.name;
    if (asset == null || downloadUrl == null || originalName == null) {
      throw const UpdateException('此版本没有可识别的 Windows 安装包，请前往发布页获取。');
    }
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com') {
      throw const UpdateException('更新包地址不是受信任的 GitHub HTTPS 地址。');
    }

    final safeName = path
        .basename(originalName)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw const UpdateException('更新包文件名无效。');
    }

    Directory? operationDirectory;
    File? partial;
    File? target;
    var completed = false;
    try {
      final appDataDirectory = await _appDataDirectory();
      _throwIfCancelled(cancellation);
      final updatesRoot = Directory(
        path.join(appDataDirectory.path, 'updates', update.version.toString()),
      );
      await updatesRoot.create(recursive: true);
      _throwIfCancelled(cancellation);

      // The directory belongs exclusively to this operation. A cancelled old
      // dialog can never delete, hash, or promote another download's bytes.
      // The completed package stays here too, so cancellation racing the final
      // rename can clean up only this operation's own result.
      operationDirectory = await updatesRoot.createTemp('download-');
      _throwIfCancelled(cancellation);
      target = File(path.join(operationDirectory.path, safeName));
      partial = File('${target.path}.partial');
      await _downloadToFile(
        uri,
        partial,
        expectedSize: asset.size,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      _throwIfCancelled(cancellation);

      final digest = await _sha256ForFile(partial, cancellation);
      _throwIfCancelled(cancellation);
      var checksumVerified = false;
      final checksumAsset = update.checksumAsset;
      if (checksumAsset?.browserDownloadUrl != null) {
        final checksumUri = Uri.tryParse(checksumAsset!.browserDownloadUrl!);
        if (checksumUri == null ||
            checksumUri.scheme != 'https' ||
            checksumUri.host.toLowerCase() != 'github.com') {
          throw const UpdateException('校验文件地址无效，已停止更新。');
        }
        final checksumText = utf8.decode(
          await _downloadSmallFile(checksumUri, cancellation: cancellation),
          allowMalformed: true,
        );
        _throwIfCancelled(cancellation);
        final expected = _parseChecksum(
          checksumText,
          originalName,
          exactCompanion: checksumAsset.name?.toLowerCase().startsWith(
                    originalName.toLowerCase(),
                  ) ==
              true,
        );
        if (expected == null) {
          throw const UpdateException('发布者提供的 SHA-256 校验文件无法识别，已停止更新。');
        }
        if (digest.toLowerCase() != expected.toLowerCase()) {
          throw const UpdateException('更新包 SHA-256 校验失败，文件可能不完整或已被篡改。');
        }
        checksumVerified = true;
      }

      _throwIfCancelled(cancellation);
      final completedFile = await partial.rename(target.path);
      _throwIfCancelled(cancellation);
      completed = true;
      return UpdateDownloadResult(
        file: completedFile,
        sha256Digest: digest,
        checksumVerified: checksumVerified,
      );
    } catch (error) {
      if (cancellation?.isCancelled == true) {
        throw const UpdateException('已取消下载。');
      }
      if (error is UpdateException) rethrow;
      if (error is TimeoutException) {
        throw UpdateException('下载更新超时，请检查网络后重试。', error);
      }
      if (error is SocketException) {
        throw UpdateException('下载更新时网络连接中断，请重试。', error);
      }
      throw UpdateException('更新包下载失败，请稍后重试。', error);
    } finally {
      if (!completed) {
        await _removeOwnedDownload(partial, target, operationDirectory);
      }
    }
  }

  static void _throwIfCancelled(UpdateDownloadCancellation? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw const UpdateException('已取消下载。');
    }
  }

  Future<String> _sha256ForFile(
    File file,
    UpdateDownloadCancellation? cancellation,
  ) async {
    _throwIfCancelled(cancellation);
    final checkedBytes = file.openRead().map((chunk) {
      _throwIfCancelled(cancellation);
      return chunk;
    });
    final digest = await sha256.bind(checkedBytes).first;
    _throwIfCancelled(cancellation);
    return digest.toString();
  }

  static Future<void> _removeOwnedDownload(
    File? partial,
    File? target,
    Directory? operationDirectory,
  ) async {
    for (final file in [partial, target]) {
      if (file == null) continue;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Cleanup must not replace the original cancellation/download error.
      }
    }
    if (operationDirectory != null) {
      try {
        // Non-recursive: never remove anything outside our two owned paths.
        await operationDirectory.delete();
      } catch (_) {}
    }
  }

  Future<void> _downloadToFile(
    Uri uri,
    File file, {
    int? expectedSize,
    void Function(UpdateDownloadProgress progress)? onProgress,
    UpdateDownloadCancellation? cancellation,
  }) async {
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    cancellation?.attach(() => client.close(force: true));
    IOSink? sink;
    try {
      _throwIfCancelled(cancellation);
      final response = await _getSecureResponse(client, uri, cancellation);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException.formatted(
            '更新服务器返回 HTTP {0}。', [response.statusCode]);
      }

      final total =
          response.contentLength > 0 ? response.contentLength : expectedSize;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.timeout(_downloadIdleTimeout)) {
        _throwIfCancelled(cancellation);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          UpdateDownloadProgress(receivedBytes: received, totalBytes: total),
        );
        _throwIfCancelled(cancellation);
      }
      _throwIfCancelled(cancellation);
      await sink.flush();
      _throwIfCancelled(cancellation);
      await sink.close();
      sink = null;
      _throwIfCancelled(cancellation);
      if (received == 0) {
        throw const UpdateException('更新服务器返回了空文件，已停止更新。');
      }
      if (expectedSize != null &&
          expectedSize > 0 &&
          received != expectedSize) {
        throw const UpdateException('更新包大小与发布信息不一致，文件可能未下载完整。');
      }
    } finally {
      try {
        await sink?.close();
      } finally {
        cancellation?.detach();
        client.close(force: true);
      }
    }
  }

  Future<Uint8List> _downloadSmallFile(
    Uri uri, {
    UpdateDownloadCancellation? cancellation,
  }) async {
    const limit = 1024 * 1024;
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    cancellation?.attach(() => client.close(force: true));
    try {
      _throwIfCancelled(cancellation);
      final response = await _getSecureResponse(client, uri, cancellation);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException.formatted(
            '校验服务器返回 HTTP {0}。', [response.statusCode]);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_downloadIdleTimeout)) {
        _throwIfCancelled(cancellation);
        if (bytes.length + chunk.length > limit) {
          throw const UpdateException('SHA-256 校验文件异常过大。');
        }
        bytes.add(chunk);
      }
      _throwIfCancelled(cancellation);
      return bytes.takeBytes();
    } finally {
      cancellation?.detach();
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _getSecureResponse(
    HttpClient client,
    Uri initialUri,
    UpdateDownloadCancellation? cancellation,
  ) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      _throwIfCancelled(cancellation);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const UpdateException('更新服务器尝试使用非安全 HTTPS 地址，已停止下载。');
      }
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      _throwIfCancelled(cancellation);
      // Validate each redirect before making the next request; checking the
      // redirect history afterwards would already have sent an HTTP request.
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader,
          'Dan-Player-Updater/${AppSettings.version}');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(_requestTimeout);
      _throwIfCancelled(cancellation);
      if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw const UpdateException('更新服务器返回了无效的重定向。');
      }
      final next = uri.resolve(location);
      await response.listen((_) {}).cancel();
      _throwIfCancelled(cancellation);
      uri = next;
    }
    throw const UpdateException('更新服务器重定向次数过多，已停止下载。');
  }

  String? _parseChecksum(
    String contents,
    String assetName, {
    required bool exactCompanion,
  }) {
    final sumPattern = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$');
    final bsdPattern = RegExp(r'^SHA256\s*\((.+)\)\s*=\s*([0-9a-fA-F]{64})$',
        caseSensitive: false);
    bool matchesName(String value) {
      final normalized = value.trim().replaceFirst(RegExp(r'^\./'), '');
      return normalized.toLowerCase() == assetName.toLowerCase();
    }

    for (final line in const LineSplitter().convert(contents)) {
      final sum = sumPattern.firstMatch(line.trim());
      if (sum != null && matchesName(sum.group(2)!)) return sum.group(1);
      final bsd = bsdPattern.firstMatch(line.trim());
      if (bsd != null && matchesName(bsd.group(1)!)) return bsd.group(2);
    }
    if (exactCompanion) {
      return RegExp(r'^([0-9a-fA-F]{64})$')
          .firstMatch(contents.trim())
          ?.group(1);
    }
    return null;
  }
}
