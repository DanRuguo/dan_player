import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';

class AudioIntegrityException implements Exception {
  const AudioIntegrityException(this.message);
  final String message;
}

enum AudioIntegrityPhase { hashing, decoding }

class AudioIntegrityProgress {
  const AudioIntegrityProgress(this.phase, this.fraction);
  final AudioIntegrityPhase phase;
  final double? fraction;
}

class AudioIntegrityReport {
  const AudioIntegrityReport({
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.decodedSeconds,
  });
  final String path, sha256;
  final int bytes;
  final double decodedSeconds;
}

/// Verify the file backing a song, including a CUE song's whole source file.
/// Null output never writes a converted song. This proves decodability and
/// exposes a byte digest, not authenticity or comparison with an original.
List<String> audioIntegrityArguments(String path) => [
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-xerror',
      '-max_error_rate',
      '0',
      '-err_detect',
      'crccheck+bitstream+buffer+explode',
      '-threads',
      '1',
      '-i',
      path,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-threads',
      '1',
      '-filter_threads',
      '1',
      '-progress',
      'pipe:1',
      '-nostats',
      '-abort_on',
      'empty_output',
      '-f',
      'null',
      '-',
    ];

/// All hashing work runs on an owned isolate. Only a path and ports cross its
/// boundary; callbacks and Audio instances remain on the UI isolate.
Future<void> _hashIntegritySource((String, SendPort) input) async {
  final (path, results) = input;
  try {
    var consumed = 0;
    final throttle = Stopwatch()..start();
    final digest = await sha256
        .bind(File(path).openRead().map((bytes) {
          consumed += bytes.length;
          if (throttle.elapsedMilliseconds >= 250) {
            throttle.reset();
            results.send([0, consumed]);
          }
          return bytes;
        }))
        .first;
    results.send([1, digest.toString()]);
  } catch (_) {
    results.send([2]);
  }
}

class AudioIntegrityInspector {
  AudioIntegrityInspector(
      {this.executable, this.timeout = const Duration(minutes: 30)});
  final String? executable;
  final Duration timeout;
  static bool _running = false;

  Future<String> _hash(String path, int size, AudioTrimCancellation token,
      void Function(AudioIntegrityProgress)? update) async {
    final messages = ReceivePort();
    Isolate? worker;
    Timer? timer;
    var timedOut = false;
    void stop() {
      worker?.kill(priority: Isolate.immediate);
      messages.sendPort.send(null);
    }

    try {
      worker = await Isolate.spawn(
          _hashIntegritySource, (path, messages.sendPort),
          onExit: messages.sendPort,
          onError: messages.sendPort,
          errorsAreFatal: true);
      token.addListener(stop);
      timer = Timer(timeout, () {
        timedOut = true;
        stop();
      });
      await for (final event in messages) {
        token.check();
        if (timedOut) {
          throw const AudioIntegrityException('文件校验超时，请重试');
        }
        if (event is List && event.isNotEmpty && event[0] == 0) {
          update?.call(AudioIntegrityProgress(AudioIntegrityPhase.hashing,
              size > 0 ? ((event[1] as int) / size).clamp(0.0, .99) : null));
        } else if (event is List && event.length == 2 && event[0] == 1) {
          return event[1] as String;
        } else {
          throw const AudioIntegrityException('无法读取本地音频文件');
        }
      }
      throw const AudioIntegrityException('无法读取本地音频文件');
    } finally {
      timer?.cancel();
      token.removeListener(stop);
      worker?.kill(priority: Isolate.immediate);
      messages.close();
    }
  }

  Future<AudioIntegrityReport> inspect(Audio audio, AudioTrimCancellation token,
      {void Function(AudioIntegrityProgress)? onProgress}) async {
    // Freeze mutable library properties before the first await.
    final path = audio.localFilePath;
    final expectedSeconds = audio.isCueTrack ? 0 : audio.duration;
    if (!audio.isLocal) {
      throw const AudioIntegrityException('文件校验仅支持本地音频');
    }
    if (_running) {
      throw const AudioIntegrityException('已有文件校验正在进行，请稍后重试');
    }
    _running = true;
    try {
      token.check();
      final source = File(path);
      final before = await source.stat();
      if (before.type != FileSystemEntityType.file || before.size <= 0) {
        throw const AudioIntegrityException('无法读取本地音频文件');
      }
      final resolved = await source.resolveSymbolicLinks();
      var tool = executable;
      if (tool == null) {
        if (!await FfmpegRuntime.shared.ensure()) {
          throw const AudioIntegrityException('请先安装或修复音频工具');
        }
        tool = FfmpegRuntime.shared.path('ffmpeg');
      }
      token.check();
      onProgress
          ?.call(const AudioIntegrityProgress(AudioIntegrityPhase.hashing, 0));
      final digest = await _hash(path, before.size, token, onProgress);
      token.check();
      onProgress?.call(
          const AudioIntegrityProgress(AudioIntegrityPhase.decoding, null));
      var decodedMicros = 0;
      final throttle = Stopwatch()..start();
      await runAudioTool('ffmpeg', audioIntegrityArguments(path),
          cancellation: token,
          timeout: timeout,
          resolve: (_) async => tool!,
          onLine: (line) {
            if (!line.startsWith('out_time_us=')) return;
            final micros = int.tryParse(line.substring(12));
            if (micros == null || micros < 0) return;
            decodedMicros = micros;
            if (throttle.elapsedMilliseconds < 250) return;
            throttle.reset();
            onProgress?.call(AudioIntegrityProgress(
                AudioIntegrityPhase.decoding,
                expectedSeconds > 0
                    ? (micros / 1000000 / expectedSeconds).clamp(0.0, .99)
                    : null));
          });
      token.check();
      if (decodedMicros <= 0) {
        throw const AudioIntegrityException('未解码出有效音频，无法完成文件校验');
      }
      final after = await source.stat();
      if (after.type != FileSystemEntityType.file ||
          before.size != after.size ||
          before.modified != after.modified ||
          resolved != await source.resolveSymbolicLinks()) {
        throw const AudioIntegrityException('校验期间源文件已改变，请重新校验');
      }
      token.check();
      return AudioIntegrityReport(
          path: path,
          sha256: digest,
          bytes: before.size,
          decodedSeconds: decodedMicros / 1000000);
    } on AudioTrimException catch (error) {
      throw AudioIntegrityException(switch (error.code) {
        'cancelled' => '已取消文件校验',
        'timeout' => '文件校验超时，请重试',
        'tools' => '请先安装或修复音频工具',
        _ => '解码检查未通过，请检查文件或编码格式',
      });
    } on FileSystemException {
      throw const AudioIntegrityException('无法读取本地音频文件');
    } finally {
      _running = false;
    }
  }
}
