import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/data/stream_file_transfer.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:path/path.dart' as p;

final _windows = p.Context(style: p.Style.windows);

class PlaylistFolderExportPlan {
  PlaylistFolderExportPlan._(List<M3uEntry> entries, this.skipped)
      : entries = List.unmodifiable(entries),
        uniqueFileCount =
            entries.map((e) => e.path.toLowerCase()).toSet().length;

  final List<M3uEntry> entries;
  final int skipped;
  final int uniqueFileCount;
}

/// Capture mutable library metadata before any confirmation or native picker.
/// CUE occurrences cannot be copied as separate recordings without conversion.
PlaylistFolderExportPlan snapshotPlaylistFolderExport(List<Audio> audios) {
  if (audios.length > m3uMaxEntries) {
    throw const FormatException('导出文件夹超过 20000 项，请拆分后导出。');
  }
  final entries = <M3uEntry>[];
  for (final audio in audios) {
    if (!audio.isLocal ||
        audio.isCueTrack ||
        !isM3uLocalAudioPath(audio.path)) {
      continue;
    }
    var source = audio.path;
    if (source.toLowerCase().startsWith('file:')) {
      source = Uri.parse(source).toFilePath(windows: true);
    }
    entries.add(M3uEntry(_windows.normalize(source),
        title: '${audio.artist} - ${audio.displayTitle}',
        duration: audio.duration));
  }
  return PlaylistFolderExportPlan._(entries, audios.length - entries.length);
}

class PlaylistFolderExportCancelled implements Exception {
  const PlaylistFolderExportCancelled();
}

class PlaylistFolderExportCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
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
      this.preparing = false});
  final int copiedFiles, totalFiles, completedBytes, totalBytes;
  final bool preparing;
  double? get fraction => preparing
      ? null
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
}) async {
  cancellation._check();
  if (plan.entries.isEmpty) {
    throw const FormatException('所选歌曲中没有可导出的本地文件。');
  }
  final sources = <String, M3uEntry>{};
  for (final entry in plan.entries) {
    sources.putIfAbsent(entry.path.toLowerCase(), () => entry);
  }
  final stats = <String, FileStat>{};
  var totalBytes = 0, completedBytes = 0, copiedFiles = 0;
  void publish({bool preparing = false, int currentBytes = 0}) {
    onProgress?.call(PlaylistFolderExportProgress(
        copiedFiles: copiedFiles,
        totalFiles: sources.length,
        completedBytes: completedBytes + currentBytes,
        totalBytes: totalBytes,
        preparing: preparing));
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
      names[entry.key] = '${(++index).toString().padLeft(5, '0')}_'
          '${_safeFileName(_windows.basename(entry.value.path))}';
    }
    final playlistPath = p.join(staging.path, 'playlist.m3u8');
    // Validate the complete M3U before copying any music (including UTF-8
    // byte limits). Every generated reference points inside this folder.
    final exportedEntries = [
      for (final entry in plan.entries)
        M3uEntry(p.join(staging.path, names[entry.path.toLowerCase()]!),
            title: entry.title, duration: entry.duration)
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
      final sink = File(p.join(staging.path, names[entry.key]!)).openWrite();
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
