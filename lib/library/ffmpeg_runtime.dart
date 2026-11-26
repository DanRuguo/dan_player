import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FfmpegUnavailable implements Exception {
  const FfmpegUnavailable();
}

const ffmpegToolNames = ['ffmpeg', 'ffprobe', 'ffplay'];
typedef FfmpegProbe = Future<String> Function(String, List<String>);

/// A bounded, noninteractive probe. Never searches the current working folder.
Future<String> probeFfmpeg(String executable, List<String> args) async {
  final process = await Process.start(executable, args, runInShell: false);
  await process.stdin.close();
  var text = '';
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen((chunk) {
    if (text.length < 1024 * 1024) text += chunk;
  });
  final outputDone = out.asFuture<void>();
  final err = process.stderr.drain<void>();
  final timer = Timer(const Duration(seconds: 8), process.kill);
  try {
    if (await process.exitCode != 0) throw const FfmpegUnavailable();
    await outputDone;
    await err;
    return text;
  } finally {
    timer.cancel();
    await out.cancel();
  }
}

Future<bool> isFfmpegDirectoryPathSafe(String directory,
    {bool allowMissing = false}) async {
  try {
    var current = p.normalize(p.absolute(directory));
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          !(allowMissing && type == FileSystemEntityType.notFound)) {
        return false;
      }
      final parent = p.dirname(current);
      if (p.equals(parent, current)) return true;
      current = parent;
    }
  } catch (_) {
    return false;
  }
}

Future<bool> _canWriteToolSubdirectory(String appDir) async {
  if (!await isFfmpegDirectoryPathSafe(appDir)) return false;
  final toolRoot = Directory(p.join(appDir, 'tool'));
  if (!await isFfmpegDirectoryPathSafe(toolRoot.path, allowMissing: true)) {
    return false;
  }
  Directory? probe;
  try {
    await toolRoot.create(recursive: true);
    probe = await toolRoot.createTemp('.danplayer-tool-probe-');
    return true;
  } catch (_) {
    return false;
  } finally {
    if (probe != null) {
      try {
        if (await probe.exists()) await probe.delete(recursive: true);
      } catch (_) {}
    }
  }
}

class FfmpegRuntime {
  FfmpegRuntime({
    FfmpegProbe? probe,
    this.installRoot,
    this.applicationDirectory,
  }) : _probe = probe ?? probeFfmpeg;

  final Directory? installRoot;
  final Directory? applicationDirectory;
  static final shared = FfmpegRuntime();
  final FfmpegProbe _probe;
  Map<String, String>? _ready;
  Future<bool>? _pending;
  bool get ready => _ready != null;
  void invalidate() {
    _ready = null;
  }

  String path(String tool) {
    if (!ffmpegToolNames.contains(tool)) throw ArgumentError.value(tool);
    final value = _ready?[tool];
    if (value == null) throw const FfmpegUnavailable();
    return value;
  }

  /// Installs into `<appDir>/tool/ffmpeg` beside the player executable when
  /// writable, falling back to `<AppDataDir>/tool/ffmpeg` only if read-only.
  Future<Directory> get installDirectory async {
    if (installRoot != null) return installRoot!;
    if (applicationDirectory != null) {
      if (await _canWriteToolSubdirectory(applicationDirectory!.path)) {
        return Directory(p.join(applicationDirectory!.path, 'tool', 'ffmpeg'));
      }
    } else if (Platform.environment['FLUTTER_TEST'] != 'true') {
      final appDir = p.dirname(Platform.resolvedExecutable);
      if (await _canWriteToolSubdirectory(appDir)) {
        return Directory(p.join(appDir, 'tool', 'ffmpeg'));
      }
    }
    return Directory(p.join((await getAppDataDir()).path, 'tool', 'ffmpeg'));
  }

  Future<List<String>> candidates() async {
    final env = Platform.environment;
    final result = <String>[];
    final override = env['DAN_PLAYER_FFMPEG_DIR'];
    if (override != null && override.isNotEmpty) return [override];
    void addPath(String? value) {
      for (var item in (value ?? '').split(Platform.isWindows ? ';' : ':')) {
        item = item.trim().replaceAll('"', '');
        if (p.isAbsolute(item)) result.add(p.normalize(item));
      }
    }

    final app =
        applicationDirectory?.path ?? p.dirname(Platform.resolvedExecutable);
    result.addAll([
      p.join(app, 'tool', 'ffmpeg'),
      p.join(app, 'tool', 'ffmpeg', 'bin'),
      p.join(app, 'tool'),
      p.join(app, 'tools', 'ffmpeg'),
      (await installDirectory).path,
    ]);
    try {
      final dataDir = (await getAppDataDir()).path;
      result.add(p.join(dataDir, 'tool', 'ffmpeg'));
      result.add(p.join(dataDir, 'tools', 'ffmpeg'));
    } catch (_) {}
    try {
      final supportDir = (await getApplicationSupportDirectory()).path;
      result.add(p.join(supportDir, 'tools', 'ffmpeg-7.1.1'));
    } catch (_) {}

    addPath(env['PATH'] ?? env['Path']);
    // Re-read persistent PATH so "I have installed it" works without restarting.
    if (Platform.isWindows && env['FLUTTER_TEST'] != 'true') {
      try {
        final shell = p.join(env['SystemRoot'] ?? r'C:\Windows', 'System32',
            'WindowsPowerShell', 'v1.0', 'powershell.exe');
        final text = await probeFfmpeg(shell, [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Environment]::ExpandEnvironmentVariables([string][Environment]::GetEnvironmentVariable('Path','User')); [Environment]::ExpandEnvironmentVariables([string][Environment]::GetEnvironmentVariable('Path','Machine'))"
        ]);
        for (final line in const LineSplitter().convert(text)) {
          addPath(line);
        }
      } catch (_) {/* The inherited PATH and local module remain available. */}
    }
    return result.toSet().toList();
  }

  Future<bool> ensure({bool force = false, List<String>? directories}) async {
    if (force) {
      final inflight = _pending;
      if (inflight != null) {
        try {
          await inflight;
        } catch (_) {}
      }
      invalidate();
    }
    if (ready && directories == null) return true;
    return await (_pending ??=
        _discover(directories).whenComplete(() => _pending = null));
  }

  Future<bool> validateDirectory(String directory) async {
    try {
      if (!await isFfmpegDirectoryPathSafe(directory)) return false;
      final paths = {
        for (final name in ffmpegToolNames)
          name: p.join(directory, '$name${Platform.isWindows ? '.exe' : ''}')
      };
      for (final name in ffmpegToolNames) {
        final f = File(paths[name]!);
        if (await FileSystemEntity.type(f.path, followLinks: false) !=
            FileSystemEntityType.file) {
          return false;
        }
        final version = await _probe(paths[name]!, ['-version']);
        if (!version.startsWith('$name version ')) return false;
      }
      final encoders =
          await _probe(paths['ffmpeg']!, ['-hide_banner', '-encoders']);
      for (final codec in [
        'libmp3lame',
        'flac',
        'aac',
        'alac',
        'libvorbis',
        'libopus',
        'pcm_s16le'
      ]) {
        if (!RegExp('\\b$codec\\b').hasMatch(encoders)) return false;
      }
      // Exercise the filter/encoder path without touching any user audio.
      await _probe(paths['ffmpeg']!, [
        '-nostdin',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=44100:cl=stereo',
        '-t',
        '0.01',
        '-af',
        'atrim=start=0',
        '-f',
        'null',
        '-'
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _discover(List<String>? directories) async {
    for (final directory in directories ?? await candidates()) {
      if (await validateDirectory(directory)) {
        _ready = {
          for (final name in ffmpegToolNames)
            name: p.join(directory, '$name${Platform.isWindows ? '.exe' : ''}')
        };
        return true;
      }
    }
    return false;
  }
}
