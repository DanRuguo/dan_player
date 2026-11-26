import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as p;

// Starting from 26.1.2-snapshot.8, missing FFmpeg tools download the slimmed
// audio-focused module published on the v26.1.2-snapshot.8 release, install
// into `tool/ffmpeg`, and immediately re-verify tool integrity & codecs.
const ffmpegModuleName = 'DanPlayer-FFmpeg-7.1.1-audio-windows-x64.zip';
const ffmpegModuleUrl =
    'https://github.com/DanRuguo/dan_player/releases/download/v26.1.2-snapshot.8/$ffmpegModuleName';
const ffmpegModuleHash =
    '818ff3f8970ec410f267901a557183c4b645c59d5ea920251b5049d38856a095';
const ffmpegModuleBytes = 5462138;

typedef FfmpegModuleDownload = Future<void> Function(
    File destination, void Function(double?) progress, bool Function() active);

/// Honors the app proxy selection. System mode delegates to Windows' web
/// proxy (including PAC); no mode changes the machine proxy or prints secrets.
/// The pinned hash is verified before extraction.
const _downloadScript = r'''
param([string]$Url,[string]$Destination,[string]$ProxyMode,[string]$ProxyUrl,[string]$UserAgent,[long]$ExpectedBytes)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$response=$null
for($redirect=0;$redirect -lt 6;$redirect++) {
  $uri=[Uri]$Url
  if($uri.Scheme -ne 'https') { throw 'HTTPS required' }
  $request=[Net.HttpWebRequest]::Create($uri)
  switch($ProxyMode) {
    'direct' { $request.Proxy=$null }
    'custom' { $request.Proxy=[Net.WebProxy]::new([Uri]$ProxyUrl) }
    default { $request.Proxy=[Net.WebRequest]::DefaultWebProxy }
  }
  $request.AllowAutoRedirect=$false
  $request.Timeout=30000
  $request.ReadWriteTimeout=30000
  $request.UserAgent=$UserAgent
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400) {
    $Url=([Uri]::new($uri,$response.Headers['Location'])).AbsoluteUri
    $response.Dispose();$response=$null
  } else { break }
}
if($null -eq $response -or [int]$response.StatusCode -ne 200) { throw 'Download unavailable' }
$downloadStream=$response.GetResponseStream()
$downloadFile=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
try {
  $buffer=New-Object byte[] 131072
  [long]$total=0;[long]$last=0
  while($total -lt $ExpectedBytes -and ($count=$downloadStream.Read($buffer,0,$buffer.Length)) -gt 0) {
    $total+=$count
    if($total -gt $ExpectedBytes) { throw 'Unexpected download size' }
    $downloadFile.Write($buffer,0,$count)
    if($total-$last -ge 262144) { [Console]::WriteLine($total);$last=$total }
  }
  if($total -ne $ExpectedBytes) { throw 'Incomplete FFmpeg module download' }
  [Console]::WriteLine($total)
} finally { $downloadFile.Dispose();$request.Abort();$downloadStream.Dispose();$response.Dispose() }
''';

class FfmpegModuleInstaller {
  FfmpegModuleInstaller({
    this.download,
    this.taskbarProgress,
  });

  final FfmpegModuleDownload? download;
  final TaskbarProgress? taskbarProgress;
  Process? _process;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  void _check() {
    if (_cancelled) throw const FfmpegUnavailable();
  }

  Future<void> install({
    required void Function(double?) progress,
    void Function(String)? onStage,
    FfmpegRuntime? runtime,
  }) async {
    _check();
    final taskbar = (taskbarProgress ?? TaskbarProgress.instance).begin();
    try {
      await _install(
        progress: (value) {
          taskbar.update(value);
          progress(value);
        },
        onStage: onStage,
        runtime: runtime,
      );
    } finally {
      taskbar.dispose();
    }
  }

  Future<void> _install({
    required void Function(double?) progress,
    void Function(String)? onStage,
    FfmpegRuntime? runtime,
  }) async {
    final tools = runtime ?? FfmpegRuntime.shared;
    final proxy = AppSettings.instance.networkProxy.value;
    final proxyUrl = proxy.mode == NetworkProxyMode.custom
        ? NetworkProxyPreferences.normalizeCustomProxy(
            proxy.customProxyUrl ?? '')
        : null;
    if (proxy.mode == NetworkProxyMode.custom && proxyUrl == null) {
      throw const FormatException('Invalid custom HTTP proxy');
    }
    final target = await tools.installDirectory;
    if (!await isFfmpegDirectoryPathSafe(target.path, allowMissing: true)) {
      throw const FileSystemException('Unsafe FFmpeg installation directory');
    }
    await target.parent.create(recursive: true);
    if (!await isFfmpegDirectoryPathSafe(target.parent.path)) {
      throw const FileSystemException('Unsafe FFmpeg installation directory');
    }
    final work = await target.parent.createTemp('.ffmpeg-download-');
    Directory? old;
    var published = false;
    try {
      _check();
      final zip = File(p.join(work.path, 'module.zip'));
      onStage?.call('downloading archive');
      if (download != null) {
        await download!(zip, (value) {
          if (!_cancelled) progress(value);
        }, () => !_cancelled);
      } else {
        final script = File(p.join(work.path, 'download.ps1'));
        await script.writeAsString(_downloadScript);
        final shell = p.join(
            Platform.environment['SystemRoot'] ?? r'C:\Windows',
            'System32',
            'WindowsPowerShell',
            'v1.0',
            'powershell.exe');
        _process = await Process.start(
            shell,
            [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              script.path,
              '-Url',
              ffmpegModuleUrl,
              '-Destination',
              zip.path,
              '-ProxyMode',
              proxy.mode.name,
              '-ProxyUrl',
              proxyUrl ?? '',
              '-UserAgent',
              'DanPlayer/${AppSettings.version}',
              '-ExpectedBytes',
              '$ffmpegModuleBytes',
            ],
            runInShell: false);
        await _process!.stdin.close();
        _check();
        final output = _process!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          final bytes = int.tryParse(line);
          if (bytes != null) progress((bytes / ffmpegModuleBytes).clamp(0, 1));
        }).asFuture<void>();
        final errors = _process!.stderr.drain<void>();
        final timer =
            Timer(const Duration(minutes: 15), () => _process?.kill());
        try {
          final exit = await _process!.exitCode;
          onStage?.call('download process ended');
          await Future.wait([output, errors]);
          _check();
          if (exit != 0) throw const FfmpegUnavailable();
        } finally {
          timer.cancel();
          _process = null;
        }
      }
      _check();
      progress(null);
      onStage?.call('verifying archive');
      final unpacked = Directory(p.join(work.path, 'unpacked'));
      await _extractInWorker(zip.path, unpacked.path);
      onStage?.call('archive extracted');
      _check();
      if (!await tools.validateDirectory(unpacked.path)) {
        throw const FfmpegUnavailable();
      }
      _check();
      if (await target.exists()) {
        old = await target.rename(p.join(work.path, 'previous'));
      }
      await unpacked.rename(target.path);
      published = true;
      onStage?.call('re-verifying installed tool');
      tools.invalidate();
      if (!await tools.ensure(force: true, directories: [target.path])) {
        throw const FfmpegUnavailable();
      }
      LOGGER.i('[ffmpeg] Installed and verified FFmpeg module in ${target.path}');
      old = null;
      progress(1);
    } catch (_) {
      if (published &&
          await target.exists() &&
          !await FileSystemEntity.isLink(target.path)) {
        await target.delete(recursive: true);
      }
      if (old != null && await old.exists()) await old.rename(target.path);
      tools.invalidate();
      rethrow;
    } finally {
      _process?.kill();
      _process = null;
      // Retain the prior module if an external file lock prevents rollback.
      if ((old == null || !await old.exists()) && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }
}

Future<void> _extractInWorker(String zipPath, String destination) =>
    Isolate.run(() => extractFfmpegModule(zipPath, destination));

/// Decode only the pinned v26.1.2-snapshot.8 slim audio FFmpeg archive.
Future<void> extractFfmpegModule(String zipPath, String destination) async {
  final file = File(zipPath);
  if (await FileSystemEntity.type(zipPath, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != ffmpegModuleBytes ||
      (await sha256.bind(file.openRead()).first).toString() !=
          ffmpegModuleHash) {
    throw const FormatException('Module checksum mismatch');
  }
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input, verify: true);
    const names = {
      'ffmpeg.exe',
      'ffprobe.exe',
      'ffplay.exe',
      'avcodec-61.dll',
      'avdevice-61.dll',
      'avfilter-10.dll',
      'avformat-61.dll',
      'avutil-59.dll',
      'swresample-5.dll',
      'swscale-8.dll',
      'LICENSE',
      'README.txt'
    };
    final seen = <String>{};
    var total = 0;
    for (final entry in archive) {
      total += entry.size;
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          !names.contains(entry.name) ||
          !seen.add(entry.name) ||
          total > 64 * 1024 * 1024) {
        throw const FormatException('Invalid module layout');
      }
    }
    if (seen.length != names.length) {
      throw const FormatException('Incomplete module');
    }
    await Directory(destination).create(recursive: true);
    for (final entry in archive) {
      final stream = OutputFileStream(p.join(destination, entry.name));
      try {
        entry.writeContent(stream);
      } finally {
        stream.close();
      }
    }
  } finally {
    input.close();
  }
}
