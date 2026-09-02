import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as path_util;

class AudioDeletionException implements Exception {
  const AudioDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AudioDeletionOutcome {
  const AudioDeletionOutcome({
    required this.playlistReferencesRemoved,
    required this.persistenceWarnings,
  });

  final int playlistReferencesRemoved;
  final int persistenceWarnings;
  bool get fullyPersisted => persistenceWarnings == 0;
}

/// The single destructive path for local songs. Menus only ask for user
/// confirmation; file validation, playback detachment, model cleanup and
/// persistence are kept here so no view can implement a partial deletion.
class AudioDeletionService {
  AudioDeletionService._();

  static final instance = AudioDeletionService._();

  Future<AudioDeletionOutcome> delete(Audio requested) async {
    try {
      final outcome =
          await LibraryMutationGate.shared.run(() => _delete(requested));
      _scheduleSearchIndexRebuild();
      return outcome;
    } on LibraryMutationBusy {
      throw const AudioDeletionException('曲库正在刷新或保存，请稍后再删除歌曲。');
    }
  }

  void _scheduleSearchIndexRebuild() {
    unawaited(() async {
      try {
        await AudioSearchIndex.instance.ensureBuilt();
      } catch (error, trace) {
        // Search is a derived projection. A later search retries the build, so
        // it must not keep a destructive mutation inside the library gate or
        // turn a successful file deletion into a persistence warning.
        LOGGER.w('[audio deletion] deferred search rebuild failed: $error',
            stackTrace: trace);
      }
    }());
  }

  Future<AudioDeletionOutcome> _delete(Audio requested) async {
    if (requested.isOnline) {
      throw const AudioDeletionException('联网歌曲没有可删除的本地文件。');
    }
    if (playlistsReadBlocked) {
      throw const AudioDeletionException('歌单尚未完整读取。为避免留下无法恢复的引用，暂时不能删除歌曲。');
    }

    final library = AudioLibrary.instance;
    Audio? indexed;
    for (final folder in library.folders) {
      for (final audio in folder.audios) {
        if (audio.isLocal && path_util.equals(audio.path, requested.path)) {
          indexed = audio;
          break;
        }
      }
      if (indexed != null) break;
    }
    if (indexed == null) {
      throw const AudioDeletionException('这首歌曲已不在本地曲库中，请刷新曲库后重试。');
    }

    final indexedAudio = indexed;
    final audioPath = indexedAudio.path;
    if (!path_util.isAbsolute(audioPath)) {
      throw const AudioDeletionException('歌曲文件路径无效，未执行删除。');
    }
    final entityType =
        await FileSystemEntity.type(audioPath, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      throw const AudioDeletionException('歌曲文件已经不存在，请刷新曲库。');
    }
    if (entityType != FileSystemEntityType.file) {
      // Never follow/delete a directory, link, socket or another unexpected
      // source just because an old index record happens to point at it.
      throw const AudioDeletionException('该来源不是可安全删除的本地音乐文件。');
    }
    final currentStat = await File(audioPath).stat();
    final currentModified = currentStat.modified.millisecondsSinceEpoch ~/ 1000;
    if ((indexedAudio.fileSizeBytes != null &&
            indexedAudio.fileSizeBytes != currentStat.size) ||
        (indexedAudio.modified > 0 &&
            indexedAudio.modified != currentModified)) {
      // A menu may remain open while another program replaces the file at the
      // same path. Do not let an earlier confirmation delete new contents.
      throw const AudioDeletionException('歌曲文件在确认期间已被其他程序更改。请刷新曲库并重新确认后再删除。');
    }

    final tree = playlistTree;
    tree.validate();

    PlaybackService? playback;
    PlaybackAudioDeletionTicket? playbackTicket;
    if (PlayService.playbackReady.value) {
      playback = PlayService.instance.playbackService;
      playbackTicket = await playback.prepareAudioDeletion(audioPath);
    }

    try {
      await File(audioPath).delete();
    } on FileSystemException catch (error, trace) {
      if (playbackTicket != null) {
        playback?.cancelAudioDeletion(playbackTicket);
      }
      LOGGER.w('[audio deletion] file delete failed: $error',
          stackTrace: trace);
      throw const AudioDeletionException('无法删除歌曲文件。请确认文件未被其他程序占用，并检查文件夹写入权限。');
    } catch (error, trace) {
      if (playbackTicket != null) {
        playback?.cancelAudioDeletion(playbackTicket);
      }
      LOGGER.e('[audio deletion] unexpected file delete failure: $error',
          stackTrace: trace);
      throw const AudioDeletionException('删除歌曲文件失败，请稍后重试。');
    }

    // The irreversible operation succeeded. Keep every in-memory projection
    // accurate before awaiting persistence, so the UI and playback queue can
    // never continue offering a file which no longer exists.
    final playlistReferences =
        tree.removeAudioReferences(audioPath, prevalidated: true);
    final customOrderChanged = customAudioOrder.removePath(audioPath);
    if (playbackTicket != null) {
      playback?.commitAudioDeletion(playbackTicket);
    }
    library.removeLocalAudio(audioPath);
    final lyricSourceKeys = LYRIC_SOURCES.keys
        .where((key) => path_util.equals(key, audioPath))
        .toList(growable: false);
    for (final key in lyricSourceKeys) {
      LYRIC_SOURCES.remove(key);
    }
    final lyricSourceChanged = lyricSourceKeys.isNotEmpty;

    var warnings = 0;
    Future<void> persist(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (error, trace) {
        warnings++;
        LOGGER.e('[audio deletion] $label persistence failed: $error',
            stackTrace: trace);
      }
    }

    // These stores are independent. Persist them together so a slow cover or
    // playlist write does not unnecessarily extend the destructive operation.
    await Future.wait(<Future<void>>[
      persist('library index', library.saveIndex),
      if (playlistReferences > 0) persist('playlists', savePlaylists),
      if (customOrderChanged)
        persist(
          'custom order',
          () => saveCustomAudioOrder(rethrowOnError: true),
        ),
      if (lyricSourceChanged) persist('lyric source', saveLyricSources),
      persist('comment association',
          () => SongCommentAssociationStore.instance.remove(indexedAudio)),
      persist('cover cache', () => CoverCache.instance.invalidate(audioPath)),
    ]);
    return AudioDeletionOutcome(
      playlistReferencesRemoved: playlistReferences,
      persistenceWarnings: warnings,
    );
  }
}
