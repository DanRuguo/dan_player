import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:path/path.dart' as p;

/// Cancellation ends an encoder/decoder process, never an in-progress commit.
class AudioTrimCancellation {
  bool _cancelled = false;
  bool _committing = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  bool get canCancel => !_committing;
  void cancel() {
    if (_committing || _cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void check() {
    if (_cancelled) throw const AudioTrimException('cancelled', '已取消裁剪');
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
    if (_cancelled) listener();
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void beginCommit() {
    check();
    _committing = true;
  }
}

class AudioTrimException implements Exception {
  const AudioTrimException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class AudioTrimInfo {
  const AudioTrimInfo(
      {required this.duration,
      required this.formatLabel,
      required this.outputExtension,
      required this.canOverwrite,
      this.limitation,
      this.codec = '',
      this.muxer = '',
      this.bitrate,
      this.sampleRate,
      this.channels});
  final double duration;
  final String formatLabel;
  final String outputExtension;
  final bool canOverwrite;
  final String? limitation;
  final String codec;
  final String muxer;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
}

class AudioTrimRequest {
  const AudioTrimRequest(
      {required this.destinationPath,
      required this.startSeconds,
      required this.endSeconds,
      this.overwrite = false,
      this.preserveMetadata = true,
      this.title,
      this.artist,
      this.album});
  final String destinationPath;
  final double startSeconds;
  final double endSeconds;
  final bool overwrite;
  final bool preserveMetadata;
  final String? title;
  final String? artist;
  final String? album;
}

class AudioTrimResult {
  const AudioTrimResult(
      {required this.path,
      required this.duration,
      this.libraryUpdated = true,
      this.warning});
  final String path;
  final double duration;
  final bool libraryUpdated;
  final String? warning;
}

/// Resolved once from explicit PATH entries or an installed optional module.
Future<String> audioToolPath(String executable) async {
  if (!const {'ffmpeg', 'ffprobe', 'ffplay'}.contains(executable)) {
    throw ArgumentError.value(executable, 'executable');
  }
  if (!await FfmpegRuntime.shared.ensure()) {
    throw const AudioTrimException('tools', '请先安装或修复裁剪组件');
  }
  return FfmpegRuntime.shared.path(executable);
}

/// Bounded output, explicit argv, no shell and no interactive console. The
/// child is always reaped before its temporary files may be deleted.
Future<String> runAudioTool(
  String executable,
  List<String> arguments, {
  AudioTrimCancellation? cancellation,
  void Function(String)? onLine,
  Duration timeout = const Duration(minutes: 30),
  Future<String> Function(String) resolve = audioToolPath,
}) async {
  cancellation?.check();
  final tool = await resolve(executable);
  final Process process;
  try {
    process = await Process.start(tool, arguments, runInShell: false);
  } on ProcessException {
    FfmpegRuntime.shared.invalidate();
    throw const AudioTrimException('tools', '请先安装或修复裁剪组件');
  }
  void stop() => process.kill();
  cancellation?.addListener(stop);
  var timedOut = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    stop();
  });
  var output = '';
  var errors = '';
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    onLine?.call(line);
    if (output.length < 1024 * 1024) output += '$line\n';
  }).asFuture<void>();
  final stderrDone = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen((part) {
    errors += part;
    if (errors.length > 32768) errors = errors.substring(errors.length - 32768);
  }).asFuture<void>();
  try {
    final exit = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    cancellation?.check();
    if (timedOut) {
      throw const AudioTrimException('timeout', '音频处理超时，原文件未被修改');
    }
    if (exit != 0) {
      if (exit < 0 || exit > 255) {
        FfmpegRuntime.shared.invalidate();
        throw const AudioTrimException('tools', '请先安装或修复裁剪组件');
      }
      // Native stderr may contain user paths. Keep it out of persistent logs
      // and present a stable, translatable error in the dialog.
      throw AudioTrimException(
          'process',
          errors.contains('Permission denied')
              ? '文件被占用或没有写入权限，原文件未被修改'
              : '无法处理此音频文件，请检查文件是否完整');
    }
    return output;
  } finally {
    timer.cancel();
    cancellation?.removeListener(stop);
  }
}

AudioTrimInfo audioTrimInfoFromProbe(
    Map<String, dynamic> probe, String source) {
  final streams = (probe['streams'] as List? ?? const []).whereType<Map>();
  final audioStreams =
      streams.where((s) => s['codec_type'] == 'audio').toList();
  if (audioStreams.length != 1) {
    throw const AudioTrimException('streams', '暂不支持裁剪包含多个音轨的文件');
  }
  final stream = audioStreams.single;
  final format = probe['format'] as Map? ?? const {};
  double? number(Object? value) => double.tryParse('$value');
  final duration = number(stream['duration']) ?? number(format['duration']);
  if (duration == null || !duration.isFinite || duration <= .05) {
    throw const AudioTrimException('duration', '无法读取有效的歌曲时长');
  }
  final formatNames = '${format['format_name']}'.split(',');
  final inputCodec = '${stream['codec_name']}';
  final (String muxer, String codec, String extension, String label) choice;
  if (formatNames.contains('mp3')) {
    choice = ('mp3', 'libmp3lame', '.mp3', 'MP3');
  } else if (formatNames.contains('flac')) {
    choice = ('flac', 'flac', '.flac', 'FLAC');
  } else if (formatNames.contains('mov') || formatNames.contains('mp4')) {
    if (!const {'aac', 'alac', 'mp3'}.contains(inputCodec)) {
      throw const AudioTrimException('format', '此音频格式暂不支持安全裁剪');
    }
    choice = (
      'ipod',
      inputCodec == 'alac' ? 'alac' : 'aac',
      '.m4a',
      inputCodec == 'alac' ? 'ALAC' : 'AAC'
    );
  } else if (formatNames.contains('ogg')) {
    if (!const {'opus', 'vorbis', 'flac'}.contains(inputCodec)) {
      throw const AudioTrimException('format', '此音频格式暂不支持安全裁剪');
    }
    choice = (
      'ogg',
      switch (inputCodec) {
        'opus' => 'libopus',
        'vorbis' => 'libvorbis',
        _ => 'flac',
      },
      inputCodec == 'opus' ? '.opus' : '.ogg',
      inputCodec.toUpperCase()
    );
  } else if (formatNames.contains('wav') || formatNames.contains('aiff')) {
    final wave = formatNames.contains('wav');
    if (!inputCodec.startsWith('pcm_')) {
      throw const AudioTrimException('format', '此音频格式暂不支持安全裁剪');
    }
    choice = (
      wave ? 'wav' : 'aiff',
      inputCodec,
      wave ? '.wav' : '.aiff',
      wave ? 'WAV' : 'AIFF'
    );
  } else {
    throw const AudioTrimException('format', '此音频格式暂不支持安全裁剪');
  }
  final (muxer, codec, extension, label) = choice;
  // Reject ordinary video and other streams rather than silently discard
  // them. Cover pictures are retained by the native metadata copier.
  final unsafeStream = streams.any((s) =>
      s['codec_type'] != 'audio' &&
      !(s['codec_type'] == 'video' &&
          (s['disposition'] as Map?)?['attached_pic'] == 1));
  if (unsafeStream) {
    throw const AudioTrimException('streams', '暂不支持裁剪包含视频或额外数据流的文件');
  }
  final sourceExtension = p.extension(source);
  return AudioTrimInfo(
      duration: duration,
      formatLabel: label,
      outputExtension: sourceExtension.isEmpty ? extension : sourceExtension,
      canOverwrite: true,
      codec: codec,
      muxer: muxer,
      bitrate: number(stream['bit_rate'])?.round(),
      sampleRate: number(stream['sample_rate'])?.round(),
      channels: number(stream['channels'])?.round(),
      limitation:
          const {'libmp3lame', 'aac', 'libopus', 'libvorbis'}.contains(codec)
              ? '精确裁剪会重新编码音频；原有的有损格式可能发生细微音质变化'
              : null);
}

Future<AudioTrimInfo> inspectAudioForTrim(Audio audio,
    {AudioTrimCancellation? cancellation}) async {
  if (!audio.canEditLocalFile) {
    throw const AudioTrimException('local', '仅支持裁剪独立的本地歌曲文件');
  }
  return probeAudioForTrim(audio.path, cancellation: cancellation);
}

Future<AudioTrimInfo> probeAudioForTrim(
  String source, {
  AudioTrimCancellation? cancellation,
  Future<String> Function(String) resolve = audioToolPath,
}) async {
  final text = await runAudioTool(
      'ffprobe',
      [
        '-v',
        'error',
        '-protocol_whitelist',
        'file,pipe',
        '-show_format',
        '-show_streams',
        '-show_entries',
        'format=duration,format_name:stream=codec_type,codec_name,duration,bit_rate,sample_rate,channels:stream_disposition=attached_pic',
        '-of',
        'json',
        '-i',
        source,
      ],
      cancellation: cancellation,
      timeout: const Duration(seconds: 45),
      resolve: resolve);
  return audioTrimInfoFromProbe(
      jsonDecode(text) as Map<String, dynamic>, source);
}

Future<AudioTrimResult> trimAudio(
  Audio audio,
  AudioTrimRequest request, {
  void Function(double)? onProgress,
  AudioTrimCancellation? cancellation,
}) =>
    performAudioTrim(audio, request,
        onProgress: onProgress, cancellation: cancellation);

void validateAudioTrimRequest(AudioTrimInfo info, AudioTrimRequest request) {
  if (!request.startSeconds.isFinite ||
      !request.endSeconds.isFinite ||
      request.startSeconds < 0 ||
      request.endSeconds > info.duration + .001 ||
      request.endSeconds - request.startSeconds < .05) {
    throw const AudioTrimException('range', '请选择有效的裁剪范围，至少保留 0.05 秒');
  }
  if (!p.isAbsolute(request.destinationPath) ||
      p.basename(request.destinationPath).trim().isEmpty) {
    throw const AudioTrimException('destination', '请选择有效的保存位置和文件名');
  }
  if (request.overwrite && !info.canOverwrite) {
    throw const AudioTrimException('overwrite', '此文件只能另存副本');
  }
}

List<String> audioTrimEncoderArguments(String source, String output,
    AudioTrimInfo info, AudioTrimRequest request) {
  validateAudioTrimRequest(info, request);
  final codecOptions = switch (info.codec) {
    'libmp3lame' => ['-q:a', '0'],
    'aac' => ['-b:a', '${(info.bitrate ?? 256000).clamp(128000, 512000)}'],
    'libvorbis' => ['-q:a', '8'],
    'libopus' => ['-b:a', '${(info.bitrate ?? 192000).clamp(96000, 512000)}'],
    'flac' => ['-compression_level', '8'],
    _ => <String>[],
  };
  return [
    '-hide_banner',
    '-loglevel',
    'error',
    '-nostdin',
    '-y',
    '-protocol_whitelist',
    'file,pipe',
    '-ss',
    request.startSeconds.toStringAsFixed(6),
    '-i',
    source,
    '-t',
    (request.endSeconds - request.startSeconds).toStringAsFixed(6),
    '-map',
    '0:a:0',
    '-map_metadata',
    '-1',
    '-map_chapters',
    '-1',
    '-vn',
    '-sn',
    '-dn',
    '-c:a',
    info.codec,
    ...codecOptions,
    '-threads',
    '2',
    '-progress',
    'pipe:1',
    '-nostats',
    '-f',
    info.muxer,
    output,
  ];
}
