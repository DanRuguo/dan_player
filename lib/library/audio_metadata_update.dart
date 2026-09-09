import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_journal.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/app_settings.dart' show getAppDataDir;
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:path/path.dart' as path_util;

class AudioMetadataEdit {
  const AudioMetadataEdit({
    required this.fileName,
    required this.title,
    required this.artist,
    required this.album,
    this.picturePath,
    this.expectedFingerprint,
    this.preserveEmptyValues = false,
  });

  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String? picturePath;
  final String? expectedFingerprint;
  final bool preserveEmptyValues;
}

class AudioMetadataEditException implements Exception {
  const AudioMetadataEditException(this.code, this.message,
      {this.fileWasUpdated = false});

  factory AudioMetadataEditException.fromNative(Object error) {
    if (error is AudioMetadataEditException) return error;
    var raw = error.toString().trim();
    if (raw.startsWith('AnyhowException(') && raw.endsWith(')')) {
      raw = raw.substring('AnyhowException('.length, raw.length - 1);
    }
    final separator = raw.indexOf('|');
    if (separator > 0) {
      final code = raw.substring(0, separator).trim();
      if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(code)) {
        final message = raw.substring(separator + 1).trim();
        return AudioMetadataEditException(
          code,
          message.isEmpty ? '写入歌曲信息失败，原文件未被替换' : message,
        );
      }
    }
    return AudioMetadataEditException(
      'TAG_UNKNOWN',
      raw.isEmpty ? '写入歌曲信息失败，原文件未被替换' : raw,
    );
  }

  final String code;
  final String message;
  final bool fileWasUpdated;

  String get userMessage => switch (code) {
        'TAG_LIBRARY_SYNC_FAILED' =>
          '歌曲文件已保存，但曲库同步未完成。再次点击保存将先重试同步，不会重复写入相同修改。',
        'TAG_FILE_BUSY' => '文件正在被占用。请先切换当前歌曲并关闭其他占用程序后重试。',
        'TAG_SOURCE_READ_ONLY' => '文件为只读。播放器不会自动修改文件属性。',
        'TAG_ACCESS_DENIED' => '没有文件或所在文件夹的写入权限。播放器不会自动修改权限。',
        'TAG_NO_SPACE' => '磁盘空间不足，无法创建安全写入副本。',
        'TAG_FORMAT_UNSUPPORTED' => '当前实际音频容器暂不支持安全编辑标签；这不代表文件无法播放。原文件未被修改。',
        'TAG_FORMAT_UNKNOWN' ||
        'TAG_PARSE_UNSUPPORTED' ||
        'TAG_LAYOUT_UNSUPPORTED' =>
          '当前标签编辑器无法完整读取此容器或标签组合，已保留原文件。',
        'TAG_EDIT_IN_PROGRESS' => '这首歌曲的信息正在保存，请等待完成。',
        'TAG_LIBRARY_BUSY' => '曲库操作正在进行，请等待刷新或歌曲信息保存完成后重试',
        _ => message,
      };

  @override
  String toString() => message;
}

/// Records a successful native commit separately from its retryable app sync.
/// It never represents an uncommitted/native-failed edit.
class AudioMetadataCommittedEdit {
  AudioMetadataCommittedEdit(this.oldPath, this.newPath, this.edit);

  final String oldPath;
  final String newPath;
  final AudioMetadataEdit edit;
  bool customOrderNeedsSave = false;
  bool playlistsNeedSave = false;
}

typedef AudioMetadataWriter = Future<String> Function(
    String path, AudioMetadataEdit edit);
typedef AudioMetadataSynchronizer = Future<void> Function(
    Audio audio, AudioMetadataCommittedEdit commit);

/// A failed post-commit sync remains retryable even when the in-memory fields
/// already equal the form. Injected operations keep tests away from native
/// files, user settings, libraries and playback initialization.
class AudioMetadataEditCoordinator {
  AudioMetadataEditCoordinator({
    required AudioMetadataWriter write,
    required AudioMetadataSynchronizer synchronize,
    Future<void> Function(AudioMetadataCommittedEdit)? recordCommit,
    Future<void> Function()? clearCommit,
    Audio? Function(String path)? currentAudio,
  })  : _write = write,
        _synchronize = synchronize,
        _currentAudio = currentAudio,
        _recordCommit = recordCommit,
        _clearCommit = clearCommit;

  final AudioMetadataWriter _write;
  final AudioMetadataSynchronizer _synchronize;
  final Audio? Function(String path)? _currentAudio;
  final Future<void> Function(AudioMetadataCommittedEdit)? _recordCommit;
  final Future<void> Function()? _clearCommit;
  final _pending = Expando<AudioMetadataCommittedEdit>();
  final _active = Set<Audio>.identity();
  final _activePaths = <String, int>{};
  Future<void> _syncTail = Future<void>.value();

  String _pathKey(String path) => Platform.isWindows
      ? path_util.normalize(path).toLowerCase()
      : path_util.normalize(path);

  Future<Audio> apply(Audio audio, AudioMetadataEdit request) async {
    if (audio.isCueTrack) {
      throw const AudioMetadataEditException(
          'TAG_CUE_READ_ONLY', 'CUE 分轨信息由 CUE 文件提供，不能修改整轨音频。');
    }
    final key = _pathKey(audio.path);
    if (_active.contains(audio) || _activePaths.containsKey(key)) {
      throw const AudioMetadataEditException(
          'TAG_EDIT_IN_PROGRESS', '这首歌曲的信息正在保存，请等待完成。');
    }
    _active.add(audio);
    final lockedPaths = <String>{};
    void lockPath(String path) {
      if (lockedPaths.add(path)) {
        _activePaths.update(path, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    lockPath(key);
    // Different files can share index.json / playlist persistence. Serialize
    // the entire commit+sync, not just the native write or identical paths.
    final previous = _syncTail;
    final completed = Completer<void>();
    _syncTail = completed.future;
    try {
      await previous;
      final picture = request.picturePath?.trim();
      final edit = AudioMetadataEdit(
        fileName: request.preserveEmptyValues
            ? request.fileName
            : request.fileName.trim(),
        title:
            request.preserveEmptyValues ? request.title : request.title.trim(),
        artist: request.preserveEmptyValues
            ? request.artist
            : request.artist.trim().isEmpty
                ? 'UNKNOWN'
                : request.artist.trim(),
        album: request.preserveEmptyValues
            ? request.album
            : request.album.trim().isEmpty
                ? 'UNKNOWN'
                : request.album.trim(),
        picturePath: picture == null || picture.isEmpty ? null : picture,
        expectedFingerprint: request.expectedFingerprint,
        preserveEmptyValues: request.preserveEmptyValues,
      );
      final pending = _pending[audio];
      if (pending != null) {
        final pendingKey = _pathKey(pending.newPath);
        lockPath(pendingKey);
        await _sync(audio, pending);
        // This also avoids writing the same selected cover again on retry.
        if (_sameEdit(pending.edit, edit)) return audio;
      }
      // A form can outlive an automatic library reload. Compare against the
      // current model while preserving the user's requested field values.
      // Fingerprinted batch edits were compared with the actual file during
      // preview. A stale library cache cannot prove that their write is a no-op.
      final current = _currentAudio?.call(audio.path) ?? audio;
      if (edit.expectedFingerprint == null &&
          path_util.basename(current.path) == edit.fileName &&
          current.title == edit.title &&
          current.artist == edit.artist &&
          current.album == edit.album &&
          edit.picturePath == null) {
        if (!identical(current, audio)) {
          audio.applyEditedMetadata(
              newPath: current.path,
              newTitle: current.title,
              newArtist: current.artist,
              newAlbum: current.album,
              newModified: current.modified);
        }
        return audio;
      }
      final oldPath = audio.path;
      final String newPath;
      try {
        newPath = await _write(oldPath, edit);
      } catch (error) {
        throw AudioMetadataEditException.fromNative(error);
      }
      final commit = AudioMetadataCommittedEdit(oldPath, newPath, edit);
      _pending[audio] = commit;
      final newKey = _pathKey(newPath);
      lockPath(newKey);
      await _sync(audio, commit);
      return audio;
    } finally {
      _active.remove(audio);
      for (final path in lockedPaths) {
        final count = _activePaths[path]!;
        if (count == 1) {
          _activePaths.remove(path);
        } else {
          _activePaths[path] = count - 1;
        }
      }
      completed.complete();
    }
  }

  Future<void> _sync(Audio audio, AudioMetadataCommittedEdit commit) async {
    try {
      await _recordCommit?.call(commit);
      // Update identity before any asynchronous app I/O. If stat/index saving
      // fails after a rename, neither the form nor the library should retain a
      // now-missing path and offer to write it again.
      audio.applyEditedMetadata(
        newPath: commit.newPath,
        newTitle: commit.edit.title,
        newArtist: commit.edit.artist,
        newAlbum: commit.edit.album,
        newModified: audio.modified,
      );
      await _synchronize(audio, commit);
      await _clearCommit?.call();
      _pending[audio] = null;
    } catch (_) {
      throw const AudioMetadataEditException(
        'TAG_LIBRARY_SYNC_FAILED',
        '歌曲文件已保存，但曲库同步未完成。再次点击保存将先重试同步，不会重复写入相同修改。',
        fileWasUpdated: true,
      );
    }
  }

  static bool _sameEdit(AudioMetadataEdit a, AudioMetadataEdit b) =>
      a.fileName == b.fileName &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.album == b.album &&
      a.picturePath == b.picturePath;
}

final _metadataEdits = AudioMetadataEditCoordinator(
  write: (path, edit) async {
    final journal = AudioMetadataJournal(await getAppDataDir());
    if (await journal.hasPending) {
      throw const AudioMetadataEditException(
          'TAG_LIBRARY_SYNC_PENDING', '另一首歌曲的文件已保存但关系同步未完成，请先重试该歌曲或重启播放器。');
    }
    return updateAudioMetadata(
      path: path,
      fileName: edit.fileName,
      title: edit.title,
      artist: edit.artist,
      album: edit.album,
      picturePath: edit.picturePath,
      expectedFingerprint: edit.expectedFingerprint,
    );
  },
  synchronize: synchronizeAudioMetadataEdit,
  recordCommit: (commit) async => AudioMetadataJournal(await getAppDataDir())
      .record(
          oldPath: commit.oldPath,
          newPath: commit.newPath,
          title: commit.edit.title,
          artist: commit.edit.artist,
          album: commit.edit.album),
  clearCommit: () async => AudioMetadataJournal(await getAppDataDir()).clear(),
  currentAudio: (path) => AudioLibrary.instance.audioByPath[path],
);

Future<Audio> applyAudioMetadataEdit(
    Audio audio, AudioMetadataEdit edit) async {
  try {
    return await LibraryMutationGate.shared
        .run(() => _metadataEdits.apply(audio, edit));
  } on LibraryMutationBusy {
    throw const AudioMetadataEditException(
        'TAG_LIBRARY_BUSY', '曲库操作正在进行，请等待刷新或歌曲信息保存完成后重试');
  }
}

/// Resolve live library entries after native commit. The editor's Audio may
/// belong to an older index instance, while its draft and retry token survive.
Future<void> synchronizeAudioMetadataEdit(
    Audio audio, AudioMetadataCommittedEdit commit) async {
  final oldPath = commit.oldPath;
  final newPath = commit.newPath;
  final stat = await File(newPath).stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const FileSystemException(
        'The saved audio file is no longer available');
  }
  audio.modified = stat.modified.millisecondsSinceEpoch ~/ 1000;
  audio.fileSizeBytes = stat.size;
  var reference = audio;
  final library = AudioLibrary.instance;
  for (final folder in library.folders) {
    for (final current in folder.audios) {
      if (!current.canEditLocalFile ||
          (!path_util.equals(current.path, oldPath) &&
              !path_util.equals(current.path, newPath))) {
        continue;
      }
      // Keep newly scanned duration/composer/etc. and apply only the fields
      // the native edit committed; a stale editor must not revert other tags.
      if (!identical(current, audio)) {
        current.applyEditedMetadata(
            newPath: newPath,
            newTitle: commit.edit.title,
            newArtist: commit.edit.artist,
            newAlbum: commit.edit.album,
            newModified: audio.modified);
        current.fileSizeBytes = stat.size;
      }
      if (identical(reference, audio)) reference = current;
    }
  }
  await CoverCache.instance.invalidate(oldPath);
  if (newPath != oldPath) await CoverCache.instance.invalidate(newPath);
  library.rebuildDerivedCollections();

  // Latch dirty flags across retries; reapplying an already replaced path may
  // return false even though its first persistence attempt did not complete.
  if (oldPath != newPath && customAudioOrder.replacePath(oldPath, newPath)) {
    commit.customOrderNeedsSave = true;
  }
  if (replaceAudioInPlaylists(oldPath, newPath, reference)) {
    commit.playlistsNeedSave = true;
  }
  if (PlayService.playbackReady.value) {
    PlayService.instance.playbackService
        .replaceAudioReference(oldPath, reference);
    if (newPath != oldPath) {
      PlayService.instance.playbackService.relinkLocalPath(oldPath, newPath);
    }
  }
  await library.saveIndex();
  if (newPath != oldPath) {
    await SongCommentAssociationStore.instance.movePath(oldPath, newPath);
    await (await PlaybackBookmarkStore.instance).relocatePath(oldPath, newPath);
    await (await TrackResumeStore.instance).relocatePath(oldPath, newPath);
    await LyricDocumentStore.instance.relocatePath(oldPath, newPath);
    final source = LYRIC_SOURCES.remove(oldPath);
    if (source != null) {
      LYRIC_SOURCES[newPath] = source;
      await saveLyricSources();
    }
  }
  if (commit.customOrderNeedsSave) {
    await saveCustomAudioOrder(rethrowOnError: true);
  }
  if (commit.playlistsNeedSave) await savePlaylists();
  // Search is derived data, but await its existing chunked rebuild so an error
  // is handled by the same retry boundary instead of becoming unhandled.
  await AudioSearchIndex.instance.ensureBuilt();
}

bool replaceAudioInPlaylists(String oldPath, String newPath, Audio audio) {
  bool changed = false;
  for (final playlist in playlistTree.allPlaylists) {
    // The Audio may already have been mutated in place. The tree retains the
    // old path key until this update and keeps each mixed entry's ID/order.
    if (playlist.replaceAudio(oldPath, audio)) changed = true;
  }
  return changed;
}
