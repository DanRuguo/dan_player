import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/online/app_network_proxy.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:path/path.dart' as p;

const japaneseDictionaryModuleName =
    'DanPlayer-JapaneseReadings-IPADIC-6.2.0.zip';
const japaneseDictionaryModuleUrl =
    'https://github.com/DanRuguo/dan_player/releases/download/v26.1.1/$japaneseDictionaryModuleName';
const japaneseDictionaryModuleBytes = 10952592;
const japaneseDictionaryModuleSha256 =
    '036bfd033ee99dbfd5f96e4ccc555d6370b9d9ef360392adb684ec12a93e84c5';

typedef JapaneseDictionaryDownload = Future<void> Function(
    File destination, void Function(double?) progress, bool Function() active);

/// Only constructed by a user-invoked install action. A verified data-only
/// module is committed atomically; cancellation and failure retain an old copy.
class JapaneseDictionaryModuleInstaller {
  JapaneseDictionaryModuleInstaller({
    JapaneseDictionaryRuntime? runtime,
    this.download,
    this.taskbarProgress,
  }) : _runtime = runtime ?? JapaneseDictionaryRuntime.shared;
  final JapaneseDictionaryRuntime _runtime;
  final JapaneseDictionaryDownload? download;
  final TaskbarProgress? taskbarProgress;
  HttpClient? _client;
  HttpClientRequest? _request;
  bool _cancelled = false, _running = false;

  void cancel() {
    _cancelled = true;
    _request?.abort(const JapaneseDictionaryUnavailable());
    _client?.close(force: true);
  }

  void _check() {
    if (_cancelled) throw const JapaneseDictionaryUnavailable();
  }

  Future<void> install({
    required void Function(double?) progress,
    void Function(String)? onStage,
  }) async {
    if (_running) throw StateError('Dictionary installation already running');
    _check();
    _running = true;
    final taskbar = (taskbarProgress ?? TaskbarProgress.instance).begin();
    Directory? work, previous;
    var committed = false;
    Directory? target;
    try {
      target = await _runtime.installDirectory;
      if (!await isJapaneseDictionaryDirectoryPathSafe(target.path,
          allowMissing: true)) {
        throw const FileSystemException(
            'Unsafe dictionary installation directory');
      }
      await target.parent.create(recursive: true);
      if (!await isJapaneseDictionaryDirectoryPathSafe(target.parent.path)) {
        throw const FileSystemException(
            'Unsafe dictionary installation directory');
      }
      work = await target.parent.createTemp('.japanese-reading-install-');
      final archive = File(p.join(work.path, 'module.zip'));
      onStage?.call('正在下载日语假名字典…');
      await (download ?? _download)(archive, (value) {
        if (!_cancelled) {
          taskbar.update(value);
          progress(value);
        }
      }, () => !_cancelled);
      _check();
      onStage?.call('正在校验并安装字典…');
      progress(null);
      taskbar.update(null);
      final unpacked = Directory(p.join(work.path, 'new'));
      await _extractModuleOffThread(archive.path, unpacked.path);
      _check();
      if (!await _runtime.validateDirectory(unpacked.path)) {
        throw const JapaneseDictionaryUnavailable();
      }
      _check();
      if (!await isJapaneseDictionaryDirectoryPathSafe(target.path,
          allowMissing: true)) {
        throw const FileSystemException(
            'Unsafe dictionary installation directory');
      }
      if (await target.exists()) {
        previous = await target.rename(p.join(work.path, 'previous'));
      }
      _check();
      await unpacked.rename(target.path);
      committed = true;
      _runtime.invalidate();
      if (!await _runtime.ensure(force: true)) {
        throw const JapaneseDictionaryUnavailable();
      }
      _check();
      previous = null;
      progress(1);
    } catch (_) {
      if (target != null &&
          committed &&
          await target.exists() &&
          !await FileSystemEntity.isLink(target.path)) {
        await target.delete(recursive: true);
      }
      if (target != null && previous != null && await previous.exists()) {
        await previous.rename(target.path);
      }
      _runtime.invalidate();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      _request = null;
      taskbar.dispose();
      _running = false;
      if (work != null &&
          (previous == null || !await previous.exists()) &&
          await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  Future<void> _download(File destination, void Function(double?) progress,
      bool Function() active) async {
    final client = _client = AppNetworkProxy.createHttpClient(
        preferences: AppSettings.instance.networkProxy.value);
    client.connectionTimeout = const Duration(seconds: 30);
    final request = _request = await client
        .getUrl(Uri.parse(japaneseDictionaryModuleUrl))
        .timeout(const Duration(seconds: 30));
    request.headers
        .set(HttpHeaders.userAgentHeader, 'DanPlayer/${AppSettings.version}');
    request.maxRedirects = 5;
    if (!active()) {
      request.abort();
      throw const JapaneseDictionaryUnavailable();
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok ||
        (response.contentLength >= 0 &&
            response.contentLength != japaneseDictionaryModuleBytes)) {
      throw const FormatException('Unexpected dictionary response');
    }
    final file = await destination.open(mode: FileMode.writeOnly);
    var received = 0, lastReported = 0;
    try {
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        if (!active()) throw const JapaneseDictionaryUnavailable();
        received += bytes.length;
        if (received > japaneseDictionaryModuleBytes) {
          throw const FormatException('Dictionary download exceeds limit');
        }
        await file.writeFrom(bytes);
        if (received - lastReported >= 128 * 1024) {
          lastReported = received;
          progress(received / japaneseDictionaryModuleBytes);
        }
      }
      if (received != japaneseDictionaryModuleBytes) {
        throw const FormatException('Incomplete dictionary download');
      }
      await file.flush();
    } finally {
      await file.close();
    }
  }
}

// Keep the isolate closure outside the installer instance. Capturing its async
// stack would also capture the live HttpClient, taskbar and UI-owned futures.
Future<void> _extractModuleOffThread(String archivePath, String destination) =>
    Isolate.run(
        () => extractJapaneseDictionaryModule(archivePath, destination));

/// Runs off the UI isolate. The exact ZIP is authenticated before decoding;
/// archive names, size, symlinks and duplicates are checked before any write.
Future<void> extractJapaneseDictionaryModule(
    String archivePath, String destination) async {
  final file = File(archivePath);
  if (await FileSystemEntity.type(archivePath, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != japaneseDictionaryModuleBytes ||
      (await sha256.bind(file.openRead()).first).toString() !=
          japaneseDictionaryModuleSha256) {
    throw const FormatException('Japanese dictionary module checksum mismatch');
  }
  const names = {
    japaneseDictionaryFileName,
    'supplemental-reading-v1.json.gz',
    'kanji-reading-v1.json.gz',
    'MODULE.json',
    'README.txt',
    'licenses/LINDERA/LICENSE',
    'licenses/IPADIC/NOTICE.txt',
    'licenses/IPADIC/PROVENANCE.md',
    'licenses/EDRDG/LICENCE.html',
    'licenses/EDRDG/CC-BY-SA-4.0.txt',
    'licenses/EDRDG/PROVENANCE.md',
  };
  if (!await isJapaneseDictionaryDirectoryPathSafe(destination,
          allowMissing: true) ||
      await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
    throw const FileSystemException('Unsafe dictionary extraction directory');
  }
  final stream = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeBuffer(stream, verify: true);
    final seen = <String>{};
    var size = 0;
    for (final entry in archive) {
      size += entry.size;
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          !names.contains(entry.name) ||
          !seen.add(entry.name) ||
          size > 16 * 1024 * 1024) {
        throw const FormatException(
            'Invalid Japanese dictionary module layout');
      }
    }
    if (seen.length != names.length) {
      throw const FormatException('Incomplete Japanese dictionary module');
    }
    for (final entry in archive) {
      final outputPath = p.join(destination, entry.name);
      await Directory(p.dirname(outputPath)).create(recursive: true);
      final output = OutputFileStream(outputPath);
      try {
        entry.writeContent(output);
      } finally {
        output.close();
      }
    }
  } finally {
    stream.close();
  }
}
