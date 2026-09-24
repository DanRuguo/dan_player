import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/taskbar_progress.dart';

// Keep the independently published, hash-pinned module on the 26.0.5 release.
// Player snapshots must not require another copy of the same 70 MB archive.
const ffmpegModuleUrl =
    'https://github.com/DanRuguo/dan_player/releases/download/v26.0.5/DanPlayer-FFmpeg-7.1.1-windows-x64.zip';
const ffmpegModuleHash =
    'd007d0d6ca34a0d69b9dfe3326c04914efe8fbf86e99d2c5b4a30ce580cceffa';
const ffmpegModuleBytes = 73513838;

/// Uses Windows' default web proxy (including its configured PAC), without
/// changing the machine proxy or printing proxy credentials. Only user consent
/// starts this downloader. The pinned hash is verified before extraction.
const _downloadScript = r'''
param([string]$Url,[string]$Destination)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$response=$null
for($redirect=0;$redirect -lt 6;$redirect++) {
  $uri=[Uri]$Url
  if($uri.Scheme -ne 'https') { throw 'HTTPS required' }
  $request=[Net.HttpWebRequest]::Create($uri)
  $request.Proxy=[Net.WebRequest]::DefaultWebProxy
  $request.AllowAutoRedirect=$false
  $request.Timeout=30000
  $request.ReadWriteTimeout=30000
  $request.UserAgent='DanPlayer/26.0.6-snapshot.1'
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
  while($total -lt 73513838 -and ($count=$downloadStream.Read($buffer,0,$buffer.Length)) -gt 0) {
    $total+=$count
    if($total -gt 73513838) { throw 'Unexpected download size' }
    $downloadFile.Write($buffer,0,$count)
    if($total-$last -ge 524288) { [Console]::WriteLine($total);$last=$total }
  }
  [Console]::WriteLine($total)
} finally { $downloadFile.Dispose();$request.Abort();$downloadStream.Dispose();$response.Dispose() }
''';

class FfmpegModuleInstaller {
  Process? _process;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  void _check() {
    if (_cancelled) throw const FfmpegUnavailable();
  }

  Future<void> install(
      {required void Function(double?) progress,
      void Function(String)? onStage,
      FfmpegRuntime? runtime}) async {
    _check();
    final taskbar = TaskbarProgress.instance.begin();
    try {
      await _install(
          progress: (value) {
            taskbar.update(value);
            progress(value);
          },
          onStage: onStage,
          runtime: runtime);
    } finally {
      taskbar.dispose();
    }
  }

  Future<void> _install(
      {required void Function(double?) progress,
      void Function(String)? onStage,
      FfmpegRuntime? runtime}) async {
    final tools = runtime ?? FfmpegRuntime.shared;
    final target = await tools.installDirectory;
    await target.parent.create(recursive: true);
    final work = await target.parent.createTemp('.ffmpeg-download-');
    Directory? old;
    var published = false;
    try {
      _check();
      final script = File(p.join(work.path, 'download.ps1'));
      await script.writeAsString(_downloadScript);
      final zip = File(p.join(work.path, 'module.zip'));
      final shell = p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
          'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
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
            zip.path
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
      final timer = Timer(const Duration(minutes: 15), () => _process?.kill());
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
      progress(null);
      onStage?.call('verifying archive');
      final unpacked = Directory(p.join(work.path, 'unpacked'));
      await _extractInWorker(zip.path, unpacked.path);
      onStage?.call('archive extracted');
      _check();
      if (!await tools.validateDirectory(unpacked.path))
        throw const FfmpegUnavailable();
      _check();
      if (await target.exists())
        old = await target.rename(p.join(work.path, 'previous'));
      await unpacked.rename(target.path);
      published = true;
      tools.invalidate();
      if (!await tools.ensure(directories: [target.path]))
        throw const FfmpegUnavailable();
      old = null;
    } catch (_) {
      if (published && await target.exists())
        await target.delete(recursive: true);
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

/// Decode only a fixed, authenticated archive, in a worker isolate.
Future<void> extractFfmpegModule(String zipPath, String destination) async {
  final file = File(zipPath);
  if (await file.length() != ffmpegModuleBytes ||
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
      'postproc-58.dll',
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
          !names.contains(entry.name) ||
          !seen.add(entry.name) ||
          total > 256 * 1024 * 1024) {
        throw const FormatException('Invalid module layout');
      }
    }
    if (seen.length != names.length)
      throw const FormatException('Incomplete module');
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
