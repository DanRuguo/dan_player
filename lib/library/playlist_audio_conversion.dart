import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_trim.dart';

enum PlaylistFolderExportFormat {
  original,
  mp3,
  opus,
  flac;

  String get extension => switch (this) {
        original => '',
        mp3 => '.mp3',
        opus => '.opus',
        flac => '.flac',
      };
}

enum PlaylistFolderExportQuality { compact, standard, high }

class PlaylistFolderExportOptions {
  const PlaylistFolderExportOptions({
    this.format = PlaylistFolderExportFormat.original,
    this.quality = PlaylistFolderExportQuality.standard,
  });

  final PlaylistFolderExportFormat format;
  final PlaylistFolderExportQuality quality;
  bool get convertsAudio => format != PlaylistFolderExportFormat.original;
  int? get bitrateKbps => switch (format) {
        PlaylistFolderExportFormat.mp3 => [128, 192, 320][quality.index],
        PlaylistFolderExportFormat.opus => [96, 128, 192][quality.index],
        _ => null,
      };
}

class PlaylistFolderExportException implements Exception {
  const PlaylistFolderExportException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Immutable values captured before the export dialog or native picker opens.
/// CUE identifiers, rather than their common physical source, identify outputs.
class PlaylistAudioExportSource {
  PlaylistAudioExportSource({
    required this.identity,
    required this.path,
    required this.title,
    required this.artist,
    required this.duration,
    required Map<String, String> tags,
    this.startFrame,
    this.endFrame,
  }) : tags = Map.unmodifiable(tags);

  final String identity, path, title, artist;
  final int duration;
  final Map<String, String> tags;
  final int? startFrame, endFrame;
  bool get isCue => startFrame != null;
}

class _AudioInfo {
  const _AudioInfo(this.duration, this.sampleRate, this.channels, this.codec);
  final double duration;
  final int sampleRate, channels;
  final String codec;

  // Lossy containers can count encoder delay and tail padding that the decoder
  // removes. Keep this separate from the precise duration of a bounded CUE
  // range and from lossless PCM/FLAC inputs; converting to FLAC does not make a
  // lossy source's container duration sample-accurate.
  double get durationPadding => switch (codec) {
        'mp1' || 'mp2' || 'mp3' => 2304 / sampleRate,
        'aac' => 2048 / sampleRate,
        'opus' => .12,
        'vorbis' || 'wmav1' || 'wmav2' || 'wmapro' => 8192 / sampleRate,
        _ => 0,
      };
}

Future<_AudioInfo> _probe(
  String path,
  AudioTrimCancellation cancellation,
  Future<String> Function(String) resolveTool,
) async {
  final output = await runAudioTool(
    'ffprobe',
    [
      '-v',
      'error',
      '-protocol_whitelist',
      'file,pipe',
      '-show_entries',
      'format=duration:stream=codec_type,codec_name,duration,sample_rate,channels:stream_disposition=attached_pic',
      '-of',
      'json',
      '-i',
      path,
    ],
    cancellation: cancellation,
    resolve: resolveTool,
    timeout: const Duration(seconds: 45),
  );
  final data = jsonDecode(output) as Map<String, dynamic>;
  final streams = (data['streams'] as List? ?? const []).whereType<Map>();
  final audio = streams.where((stream) => stream['codec_type'] == 'audio');
  if (audio.length != 1 ||
      streams.any((stream) =>
          stream['codec_type'] != 'audio' &&
          !(stream['codec_type'] == 'video' &&
              (stream['disposition'] as Map?)?['attached_pic'] == 1))) {
    throw const PlaylistFolderExportException(
        'streams', '音频转换仅支持单音轨文件，不支持视频或额外数据流。');
  }
  final stream = audio.single;
  final duration = double.tryParse('${stream['duration']}') ??
      double.tryParse('${(data['format'] as Map?)?['duration']}');
  final rate = int.tryParse('${stream['sample_rate']}');
  final channels = int.tryParse('${stream['channels']}');
  if (duration == null ||
      !duration.isFinite ||
      duration <= 0 ||
      rate == null ||
      rate <= 0 ||
      channels == null ||
      channels <= 0) {
    throw const PlaylistFolderExportException('duration', '无法读取有效的歌曲时长或音频参数。');
  }
  return _AudioInfo(duration, rate, channels, '${stream['codec_name']}');
}

/// Re-encode one physical file or CUE range to a fresh, privately owned output.
/// This never invokes trim's replacement transaction or changes the library.
Future<void> convertPlaylistAudio(
  PlaylistAudioExportSource source,
  String output,
  PlaylistFolderExportOptions options, {
  required AudioTrimCancellation cancellation,
  required Future<String> Function(String) resolveTool,
  required void Function(double) onProgress,
}) async {
  final input = await _probe(source.path, cancellation, resolveTool);
  final startSample = source.startFrame == null
      ? 0
      : (source.startFrame! * input.sampleRate / 75).round();
  final endSample = source.endFrame == null
      ? null
      : (source.endFrame! * input.sampleRate / 75).round();
  final start = startSample / input.sampleRate;
  final end = endSample == null ? input.duration : endSample / input.sampleRate;
  if (startSample < 0 || end <= start || end > input.duration + .001) {
    throw const PlaylistFolderExportException('cue', 'CUE 分轨范围无效或超出源音频时长。');
  }
  final duration = end - start;
  final format = options.format;
  final codec = switch (format) {
    PlaylistFolderExportFormat.mp3 => 'libmp3lame',
    PlaylistFolderExportFormat.opus => 'libopus',
    PlaylistFolderExportFormat.flac => 'flac',
    PlaylistFolderExportFormat.original => throw ArgumentError('No conversion'),
  };
  final rate = switch (format) {
    PlaylistFolderExportFormat.mp3 => 44100,
    PlaylistFolderExportFormat.opus => 48000,
    _ => input.sampleRate,
  };
  final channels = format == PlaylistFolderExportFormat.flac
      ? input.channels
      : input.channels.clamp(1, 2);
  final arguments = <String>[
    '-hide_banner', '-loglevel', 'error', '-xerror', '-nostdin', '-n',
    '-protocol_whitelist', 'file,pipe',
    '-i', source.path,
    '-map', '0:a:0',
    '-map_metadata', '-1', '-map_chapters', '-1', '-vn', '-sn', '-dn',
    if (source.isCue) ...[
      '-af',
      'atrim=start_sample=$startSample'
          '${endSample == null ? '' : ':end_sample=$endSample'},asetpts=PTS-STARTPTS',
    ],
    '-c:a', codec,
    '-ar', '$rate', '-ac', '$channels',
    if (options.bitrateKbps case final bitrate?) ...['-b:a', '${bitrate}k'],
    if (format == PlaylistFolderExportFormat.opus) ...['-vbr', 'on'],
    if (format == PlaylistFolderExportFormat.flac) ...[
      '-compression_level',
      '5'
    ],
    // Explicit basic text tags avoid copying whole-disc CUESHEET/lyrics with
    // wrong timestamps into a split recording, or implying artwork transfer.
    for (final tag in source.tags.entries) ...[
      '-metadata',
      '${tag.key}=${tag.value}',
    ],
    '-threads', '2', '-progress', 'pipe:1', '-nostats',
    '-f', format == PlaylistFolderExportFormat.opus ? 'opus' : format.name,
    output,
  ];
  double? encodedSeconds;
  await runAudioTool('ffmpeg', arguments,
      cancellation: cancellation, resolve: resolveTool, onLine: (line) {
    if (line.startsWith('out_time_us=')) {
      final micros = double.tryParse(line.substring(12));
      if (micros != null && micros.isFinite) {
        encodedSeconds = micros / 1000000;
        onProgress((micros / 1000000 / duration * .95).clamp(0, .95));
      }
    }
  });
  cancellation.check();
  if (await File(output).length() <= 0) {
    throw const PlaylistFolderExportException('verify', '导出音频校验失败，未生成目标文件夹。');
  }
  final actual = await _probe(output, cancellation, resolveTool);
  // MP3/Opus containers can include encoder priming. Sample-exact CUE cuts
  // happen before encoding; lossless boundary tests compare decoded PCM.
  final sourcePadding = endSample == null ? input.durationPadding : 0.0;
  final tolerance =
      (format == PlaylistFolderExportFormat.flac ? .002 : .15) + sourcePadding;
  if (actual.codec != format.name ||
      actual.sampleRate != rate ||
      actual.channels != channels ||
      (actual.duration - duration).abs() > tolerance ||
      (format == PlaylistFolderExportFormat.flac &&
          (encodedSeconds == null ||
              (actual.duration - encodedSeconds!).abs() > .002))) {
    throw const PlaylistFolderExportException('verify', '导出音频校验失败，未生成目标文件夹。');
  }
  onProgress(1);
}
