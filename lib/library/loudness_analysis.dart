import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';

class LoudnessAnalysisException implements Exception {
  const LoudnessAnalysisException(this.message);
  final String message;
}

class LoudnessCancellation {
  bool _cancelled = false;
  void Function()? _stop;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    _stop?.call();
  }

  void check() {
    if (_cancelled) throw const LoudnessAnalysisException('已取消响度分析');
  }
}

/// Measurements of the decoded source, before the player's volume/EQ/rate.
/// A null integrated value means below the R128 gate; null peaks mean silence.
class LoudnessReport {
  const LoudnessReport({
    required this.integratedLufs,
    required this.rangeLu,
    required this.samplePeakDb,
    required this.truePeakDb,
    this.analyzedSeconds,
  });
  final double? integratedLufs, samplePeakDb, truePeakDb;
  final double rangeLu;
  final double? analyzedSeconds;

  /// A static gain estimate, capped by -1 dBTP. It is never applied implicitly
  /// and is not a limiter or an end-to-end output measurement.
  double? suggestedGain(double target) {
    if (integratedLufs == null || truePeakDb == null) return null;
    if (!target.isFinite || target < -70 || target > -5) {
      throw ArgumentError.value(target);
    }
    return math.min(target - integratedLufs!, -1 - truePeakDb!);
  }
}

LoudnessReport parseLoudnessSummary(String log, {double? analyzedSeconds}) {
  final index = log.lastIndexOf('Summary:');
  if (index < 0) {
    throw const LoudnessAnalysisException('无法读取完整的响度分析结果');
  }
  final summary = log.substring(index);
  String capture(String expression) {
    final match = RegExp(expression).firstMatch(summary);
    if (match == null) {
      throw const LoudnessAnalysisException('无法读取完整的响度分析结果');
    }
    return match.group(1)!;
  }

  double? number(String raw, {bool silence = false}) {
    if (silence && raw.toLowerCase() == '-inf') return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value < -200 || value > 100) {
      throw const LoudnessAnalysisException('无法读取完整的响度分析结果');
    }
    return value;
  }

  final integrated = number(
      capture(r'Integrated loudness:\s+I:\s+(\S+)\s+LUFS'),
      silence: true);
  final range = number(capture(r'Loudness range:\s+LRA:\s+(\S+)\s+LU'))!;
  if (range < 0) {
    throw const LoudnessAnalysisException('无法读取完整的响度分析结果');
  }
  return LoudnessReport(
    analyzedSeconds: analyzedSeconds,
    integratedLufs:
        integrated == null || integrated <= -69.95 ? null : integrated,
    rangeLu: range,
    samplePeakDb:
        number(capture(r'Sample peak:\s+Peak:\s+(\S+)\s+dBFS'), silence: true),
    truePeakDb:
        number(capture(r'True peak:\s+Peak:\s+(\S+)\s+dBFS'), silence: true),
  );
}

List<String> loudnessArguments(Audio audio) {
  if (!audio.isLocal) {
    throw const LoudnessAnalysisException('响度分析仅支持本地歌曲');
  }
  final cue = audio.cueTrack;
  final trim = cue == null
      ? ''
      : (() {
          final start = cue.startSeconds;
          final end = cue.endSeconds;
          if (!start.isFinite ||
              start < 0 ||
              (end != null && (!end.isFinite || end <= start))) {
            throw const LoudnessAnalysisException('歌曲范围无效');
          }
          return 'atrim=start=${start.toStringAsFixed(9)}'
              '${end == null ? '' : ':end=${end.toStringAsFixed(9)}'},asetpts=PTS-STARTPTS,';
        })();
  return [
    '-nostdin',
    '-hide_banner',
    '-nostats',
    '-loglevel',
    'info',
    '-threads',
    '1',
    '-filter_threads',
    '1',
    '-i',
    audio.localFilePath,
    '-map',
    '0:a:0',
    '-vn',
    '-sn',
    '-dn',
    '-af',
    '${trim}ebur128=peak=sample+true:framelog=verbose',
    '-progress',
    'pipe:1',
    '-stats_period',
    '0.25',
    '-f',
    'null',
    '-',
  ];
}

/// One explicit, cancellable scan at a time. No temp output, no library writes,
/// no playback clock or decoder mutation. FFmpeg does all sample work off the
/// UI isolate; one decoding/filter thread avoids competing with playback.
class LoudnessAnalyzer {
  LoudnessAnalyzer(
      {this.executable, this.timeout = const Duration(minutes: 30)});
  final String? executable;
  final Duration timeout;
  static bool _running = false;

  Future<LoudnessReport> analyze(Audio audio, LoudnessCancellation cancellation,
      {void Function(double)? onProgress}) async {
    cancellation.check();
    final arguments = loudnessArguments(audio);
    final sourcePath = audio.localFilePath;
    final cue = audio.cueTrack;
    final expected = cue?.endSeconds != null
        ? cue!.endSeconds! - cue.startSeconds
        : audio.duration.toDouble();
    if (_running) {
      throw const LoudnessAnalysisException('已有响度分析正在进行，请稍后重试');
    }
    _running = true;
    Process? process;
    Timer? timer;
    try {
      final source = File(sourcePath);
      final before = await source.stat();
      if (before.type != FileSystemEntityType.file) {
        throw const LoudnessAnalysisException('无法读取本地音频文件');
      }
      final resolved = await source.resolveSymbolicLinks();
      var tool = executable;
      if (tool == null) {
        if (!await FfmpegRuntime.shared.ensure()) {
          throw const LoudnessAnalysisException('请先安装或修复音频工具');
        }
        tool = FfmpegRuntime.shared.path('ffmpeg');
      }
      cancellation.check();
      process = await Process.start(tool, arguments, runInShell: false);
      final child = process;
      cancellation._stop = () => child.kill();
      if (cancellation.isCancelled) child.kill();
      await child.stdin.close();
      var timedOut = false;
      timer = Timer(timeout, () {
        timedOut = true;
        child.kill();
      });
      var tail = '';
      final errors = child.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        tail += chunk;
        if (tail.length > 32768) tail = tail.substring(tail.length - 32768);
      }).asFuture<void>();
      final throttle = Stopwatch()..start();
      var observedMicros = 0;
      final progress = child.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('out_time_us=')) return;
        final micros = int.tryParse(line.substring(12));
        if (micros == null || micros < 0) return;
        observedMicros = micros;
        if (expected <= 0 || throttle.elapsedMilliseconds < 250) return;
        throttle.reset();
        onProgress?.call((micros / 1000000 / expected).clamp(0.0, .99));
      }).asFuture<void>();
      final exit = await child.exitCode;
      await Future.wait([errors, progress]);
      cancellation.check();
      if (timedOut) throw const LoudnessAnalysisException('响度分析超时，请重试');
      if (exit != 0) {
        throw const LoudnessAnalysisException('无法分析此音频文件，请检查文件是否完整');
      }
      if (observedMicros <= 0 ||
          (cue?.endSeconds != null &&
              observedMicros / 1000000 < expected - .02)) {
        throw const LoudnessAnalysisException('歌曲范围超出音频文件，请检查分轨信息');
      }
      final after = await source.stat();
      if (resolved != await source.resolveSymbolicLinks() ||
          before.size != after.size ||
          before.modified != after.modified ||
          after.type != FileSystemEntityType.file) {
        throw const LoudnessAnalysisException('分析期间源文件已改变，请重新分析');
      }
      cancellation.check();
      final result =
          parseLoudnessSummary(tail, analyzedSeconds: observedMicros / 1000000);
      onProgress?.call(1);
      return result;
    } on LoudnessAnalysisException {
      rethrow;
    } on ProcessException {
      if (executable == null) FfmpegRuntime.shared.invalidate();
      throw const LoudnessAnalysisException('请先安装或修复音频工具');
    } on FileSystemException {
      throw const LoudnessAnalysisException('无法读取本地音频文件');
    } finally {
      timer?.cancel();
      cancellation._stop = null;
      // On unexpected stream errors, still stop and reap the child before
      // allowing another scan. Ordinary completion is already reaped above.
      if (process != null) {
        process.kill();
        await process.exitCode;
      }
      _running = false;
    }
  }
}
