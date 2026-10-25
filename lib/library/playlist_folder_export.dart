import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/data/stream_file_transfer.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/playlist_audio_conversion.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:path/path.dart' as p;

export 'package:dan_player/library/playlist_audio_conversion.dart'
    show
        PlaylistFolderExportFormat,
        PlaylistFolderExportQuality,
        PlaylistFolderExportOptions,
        PlaylistFolderExportException;

final _windows = p.Context(style: p.Style.windows);

class PlaylistFolderExportPlan {
  PlaylistFolderExportPlan._(this._candidates, this._unsupported, this.options)
      : _sources = List.unmodifiable(_candidates
            .where((source) => options.convertsAudio || !source.isCue)) {
    entries = List.unmodifiable(_sources.map((source) => M3uEntry(source.path,
        title: '${source.artist} - ${source.title}',
        duration: source.duration)));
  }

  final List<PlaylistAudioExportSource> _candidates, _sources;
  final int _unsupported;
  final PlaylistFolderExportOptions options;
  late final List<M3uEntry> entries;
  int get skipped => _unsupported + _candidates.length - _sources.length;
  int get uniqueFileCount =>
      _sources.map((source) => source.identity).toSet().length;
  int get cueTrackCount => _sources.where((source) => source.isCue).length;
  int get availableCueTrackCount =>
      _candidates.where((source) => source.isCue).length;
  int get availableEntryCount => _candidates.length;

  /// Re-select a format without re-reading mutable library metadata.
  PlaylistFolderExportPlan withOptions(PlaylistFolderExportOptions options) =>
      PlaylistFolderExportPlan._(_candidates, _unsupported, options);
}

/// Capture mutable library metadata before any confirmation or native picker.
/// Keep CUE candidates so the confirmation can enable conversion later.
PlaylistFolderExportPlan snapshotPlaylistFolderExport(
  List<Audio> audios, {
  PlaylistFolderExportOptions options = const PlaylistFolderExportOptions(),
}) {
  if (audios.length > m3uMaxEntries) {
    throw const FormatException('导出文件夹超过 20000 项，请拆分后导出。');
  }
  final candidates = <PlaylistAudioExportSource>[];
  for (final audio in audios) {
    if (!audio.isLocal || !isM3uLocalAudioPath(audio.localFilePath)) {
      continue;
    }
    var source = audio.localFilePath;
    if (source.toLowerCase().startsWith('file:')) {
      source = Uri.parse(source).toFilePath(windows: true);
    }
    source = _windows.normalize(source);
    final cue = audio.cueTrack;
    final tags = <String, String>{
      // Local display titles deliberately use filenames. Preserve the actual
      // embedded title when writing tags, independently of that UI policy.
      'title': audio.title.trim().isEmpty ? audio.displayTitle : audio.title,
      'artist': audio.artist,
      'album': audio.album,
      if (audio.albumArtist?.isNotEmpty == true)
        'album_artist': audio.albumArtist!,
      if (audio.composer?.isNotEmpty == true) 'composer': audio.composer!,
      if (audio.language?.isNotEmpty == true) 'language': audio.language!,
      if (audio.track > 0 || cue != null)
        'track': '${cue?.number ?? audio.track}',
      if (audio.discNumber case final disc?) 'disc': '$disc',
    };
    candidates.add(PlaylistAudioExportSource(
      identity: cue == null
          ? source.toLowerCase()
          : '${cue.identity.toLowerCase()}|${source.toLowerCase()}|${cue.startFrame}|${cue.endFrame}',
      path: source,
      title: audio.displayTitle,
      artist: audio.artist,
      duration: audio.duration,
      tags: tags,
      startFrame: cue?.startFrame,
      endFrame: cue?.endFrame,
    ));
  }
  return PlaylistFolderExportPlan._(List.unmodifiable(candidates),
      audios.length - candidates.length, options);
}

class PlaylistFolderExportCancelled implements Exception {
  const PlaylistFolderExportCancelled();
}

class PlaylistFolderExportCancellation {
  bool _cancelled = false;
  final _audio = AudioTrimCancellation();
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    _audio.cancel();
  }

  void _check() {
    if (_cancelled) throw const PlaylistFolderExportCancelled();
  }
}

class PlaylistFolderExportProgress {
  const PlaylistFolderExportProgress(
      {required this.copiedFiles,
      required this.totalFiles,
      required this.completedBytes,
      required this.totalBytes,
      this.preparing = false,
      this.converting = false,
      this.currentTitle,
      this.currentFraction = 0});
  final int copiedFiles, totalFiles, completedBytes, totalBytes;
  final bool preparing, converting;
  final String? currentTitle;
  final double currentFraction;
  double? get fraction => preparing
      ? null
      : converting
          ? totalFiles == 0
              ? 0
              : ((copiedFiles + currentFraction) / totalFiles).clamp(0.0, 1.0)
          : totalBytes > 0
              ? (completedBytes / totalBytes).clamp(0.0, 1.0)
              : totalFiles == 0
                  ? 0
                  : copiedFiles / totalFiles;
}

class PlaylistFolderExportResult {
  const PlaylistFolderExportResult(
      {required this.directory,
      required this.playlistFile,
      required this.entryCount,
      required this.copiedFiles,
      required this.skipped});
  final Directory directory;
  final File playlistFile;
  final int entryCount, copiedFiles, skipped;
}

/// Copy sequentially with disk backpressure into a newly owned staging folder.
/// Repeated occurrences keep their order in M3U but share one copied file.
/// A completed folder is exposed only after all audio and M3U writes succeed.
Future<PlaylistFolderExportResult> runPlaylistFolderExport(
  PlaylistFolderExportPlan plan,
  Directory parent, {
  String name = 'Dan Player',
  required PlaylistFolderExportCancellation cancellation,
  void Function(PlaylistFolderExportProgress)? onProgress,
  Future<String> Function(String) resolveTool = audioToolPath,
}) async {
  cancellation._check();
  if (plan.entries.isEmpty) {
    throw const FormatException('所选歌曲中没有可导出的本地文件。');
  }
  final sources = <String, PlaylistAudioExportSource>{};
  for (final source in plan._sources) {
    sources.putIfAbsent(source.identity, () => source);
  }
  final stats = <String, FileStat>{};
  var totalBytes = 0, completedBytes = 0, copiedFiles = 0;
  void publish(
      {bool preparing = false,
      int currentBytes = 0,
      String? currentTitle,
      double currentFraction = 0}) {
    // A detached UI must not interrupt process ownership or disk publication.
    try {
      onProgress?.call(PlaylistFolderExportProgress(
          copiedFiles: copiedFiles,
          totalFiles: sources.length,
          completedBytes: completedBytes + currentBytes,
          totalBytes: totalBytes,
          preparing: preparing,
          converting: plan.options.convertsAudio,
          currentTitle: currentTitle,
          currentFraction: currentFraction));
    } catch (_) {}
  }

  publish(preparing: true);
  for (final entry in sources.entries) {
    cancellation._check();
    final stat = await File(entry.value.path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Audio file is unavailable', entry.value.path);
    }
    stats[entry.key] = stat;
    totalBytes += stat.size;
  }
  cancellation._check();
  // Resolve the user's selected parent once; cleanup only owns its direct
  // fresh child, never a source path or an arbitrary caller-provided folder.
  final parentPath = await parent.resolveSymbolicLinks();
  var staging = await Directory(parentPath).createTemp('.dan-export-');
  var ownsStaging = true;
  try {
    final names = <String, String>{};
    var index = 0;
    for (final entry in sources.entries) {
      final source = entry.value;
      final fileName = plan.options.convertsAudio
          ? '${_cleanName(source.isCue ? source.title : _windows.basenameWithoutExtension(source.path))}${plan.options.format.extension}'
          : _windows.basename(source.path);
      names[entry.key] = '${(++index).toString().padLeft(5, '0')}_'
          '${_safeFileName(fileName)}';
    }
    final playlistPath = p.join(staging.path, 'playlist.m3u8');
    // Validate the complete M3U before copying any music (including UTF-8
    // byte limits). Every generated reference points inside this folder.
    final exportedEntries = [
      for (var i = 0; i < plan.entries.length; i++)
        M3uEntry(p.join(staging.path, names[plan._sources[i].identity]!),
            title: plan.entries[i].title, duration: plan.entries[i].duration)
    ];
    late final String m3u;
    try {
      m3u = await _encodePlaylist(exportedEntries, playlistPath);
    } on FormatException catch (error) {
      if (error.message == '歌单文件超过 2 MiB，无法导入。') {
        throw const FormatException('导出歌单超过 2 MiB，请减少歌曲或缩短名称后重试。');
      }
      rethrow;
    }
    publish();
    for (final entry in sources.entries) {
      cancellation._check();
      final source = File(entry.value.path);
      final expected = stats[entry.key]!;
      final before = await source.stat();
      _checkUnchanged(expected, before);
      final output = p.join(staging.path, names[entry.key]!);
      if (plan.options.convertsAudio) {
        publish(currentTitle: entry.value.title);
        try {
          await convertPlaylistAudio(entry.value, output, plan.options,
              cancellation: cancellation._audio,
              resolveTool: resolveTool,
              onProgress: (fraction) => publish(
                  currentTitle: entry.value.title, currentFraction: fraction));
        } on AudioTrimException catch (error) {
          cancellation._check();
          throw switch (error.code) {
            'tools' => const PlaylistFolderExportException(
                'tools', '音频转换需要 FFmpeg 组件，请先安装或修复。'),
            'timeout' => const PlaylistFolderExportException(
                'timeout', '音频转换超时，未生成目标文件夹。'),
            _ => const PlaylistFolderExportException(
                'process', '音频转换失败，请检查源文件是否完整或选择其他格式。'),
          };
        }
        cancellation._check();
        _checkUnchanged(expected, await source.stat());
        completedBytes += expected.size;
        copiedFiles++;
        publish();
        continue;
      }
      final sink = File(output).openWrite();
      var closed = false;
      try {
        final received = await writeStreamToFileSink(source.openRead(), sink,
            checkCurrent: cancellation._check,
            total: expected.size,
            onProgress: (received, _) => publish(currentBytes: received));
        await sink.flush();
        await sink.close();
        closed = true;
        cancellation._check();
        _checkUnchanged(expected, await source.stat());
        if (received != expected.size) {
          throw const FormatException('复制期间源文件发生变化，请重新导出。');
        }
      } finally {
        if (!closed) {
          // Consume a sink error without obscuring the original copy error.
          try {
            await sink.close();
          } catch (_) {}
        }
      }
      completedBytes += expected.size;
      copiedFiles++;
      publish();
    }
    cancellation._check();
    await File(playlistPath).writeAsString(m3u, flush: true);
    cancellation._check();
    final base = _safeFolderName(name);
    // Existing folders are never merged or overwritten. Windows rename also
    // refuses a target created between the existence check and the commit.
    var suffix = 1;
    var target = p.join(parentPath, base);
    while (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      cancellation._check();
      target = p.join(parentPath, '$base (${++suffix})');
    }
    cancellation._check();
    final resultDirectory = await staging.rename(target);
    ownsStaging = false;
    return PlaylistFolderExportResult(
        directory: resultDirectory,
        playlistFile: File(p.join(target, 'playlist.m3u8')),
        entryCount: plan.entries.length,
        copiedFiles: copiedFiles,
        skipped: plan.skipped);
  } finally {
    if (ownsStaging && await staging.exists()) {
      final resolved = await staging.resolveSymbolicLinks();
      if (p.dirname(resolved) == parentPath &&
          p.basename(resolved).startsWith('.dan-export-') &&
          await FileSystemEntity.type(staging.path, followLinks: false) ==
              FileSystemEntityType.directory) {
        await staging.delete(recursive: true);
      }
    }
  }
}

// Keep the worker closure outside the copy operation's context. Its progress
// callback may own a Flutter route, which must never be sent to an isolate.
Future<String> _encodePlaylist(List<M3uEntry> entries, String playlistPath) =>
    Isolate.run(() => encodeM3u(entries, playlistPath: playlistPath));

void _checkUnchanged(FileStat expected, FileStat actual) {
  if (actual.type != FileSystemEntityType.file ||
      expected.size != actual.size ||
      expected.modified != actual.modified) {
    throw const FormatException('复制期间源文件发生变化，请重新导出。');
  }
}

String _safeFolderName(String value) {
  final cleaned = _cleanName(value);
  return cleaned.isEmpty ? 'Dan Player' : _limitName(cleaned, 80);
}

String _safeFileName(String value) {
  final extension = _windows.extension(value);
  final stem = _cleanName(_windows.basenameWithoutExtension(value));
  return '${_limitName(stem.isEmpty ? 'audio' : stem, 90)}$extension';
}

String _cleanName(String value) {
  var name = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
          caseSensitive: false)
      .hasMatch(name)) {
    name = '_$name';
  }
  return name;
}

String _limitName(String value, int length) =>
    String.fromCharCodes(value.runes.take(length));
