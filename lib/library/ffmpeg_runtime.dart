import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class FfmpegRuntime {
  FfmpegRuntime({FfmpegProbe? probe, this.installRoot})
      : _probe = probe ?? probeFfmpeg;
  final Directory? installRoot;
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

  Future<Directory> get installDirectory async =>
      installRoot ??
      Directory(p.join((await getApplicationSupportDirectory()).path, 'tools',
          'ffmpeg-7.1.1'));

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

    addPath(env['PATH'] ?? env['Path']);
    // Re-read persistent PATH so "I have installed it" works without restarting.
    if (Platform.isWindows) {
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
    final app = p.dirname(Platform.resolvedExecutable);
    result.addAll([
      p.join(app, 'tool', 'ffmpeg'),
      p.join(app, 'tool', 'ffmpeg', 'bin'),
      p.join(app, 'tool'),
      p.join(app, 'tools', 'ffmpeg'),
      (await installDirectory).path,
    ]);
    return result.toSet().toList();
  }

  Future<bool> ensure({bool force = false, List<String>? directories}) {
    if (force) invalidate();
    if (ready) return Future.value(true);
    return _pending ??=
        _discover(directories).whenComplete(() => _pending = null);
  }

  Future<bool> validateDirectory(String directory) async {
    try {
      final paths = {
        for (final name in ffmpegToolNames)
          name: p.join(directory, '$name${Platform.isWindows ? '.exe' : ''}')
      };
      for (final name in ffmpegToolNames) {
        if (!await File(paths[name]!).exists()) return false;
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
