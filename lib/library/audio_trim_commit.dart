import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_sidecar.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/lyric/audio_trim_lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/src/rust/api/audio_trim.dart' as native;
import 'package:dan_player/taskbar_progress.dart';
import 'package:path/path.dart' as p;

/// Native hooks separate irreversible file publication from index refresh.
/// Tests use isolated fixtures and never instantiate the user's library.
class AudioTrimOperations {
  const AudioTrimOperations({
    required this.prepare,
    required this.metadata,
    required this.commit,
    required this.synchronize,
    this.releasePlayback,
    this.restorePlayback,
    this.releaseTemporary,
    this.resolveTool = audioToolPath,
  });
  final Future<String> Function(String source) prepare;
  final Future<String> Function(
      String source, String temporary, AudioTrimRequest request) metadata;
  final Future<String> Function(String source, String temporary,
      AudioTrimRequest request, String fingerprint) commit;
  final Future<void> Function(
          Audio source, AudioTrimRequest request, Map<String, dynamic> audio)
      synchronize;
  final Future<Object?> Function(String source)? releasePlayback;
  final void Function(Object? ticket, double? startOffset)? restorePlayback;
  final Future<void> Function(String temporary)? releaseTemporary;
  final Future<String> Function(String executable) resolveTool;
}

final _nativeTrimOperations = AudioTrimOperations(
  prepare: (source) => native.prepareAudioTrim(sourcePath: source),
  metadata: (source, temporary, request) => native.finishAudioTrimMetadata(
      sourcePath: source,
      temporaryPath: temporary,
      preserveMetadata: request.preserveMetadata,
      startSeconds: request.startSeconds,
      endSeconds: request.endSeconds,
      title: request.title,
      artist: request.artist,
      album: request.album),
  commit: (source, temporary, request, fingerprint) => native.commitAudioTrim(
      sourcePath: source,
      temporaryPath: temporary,
      destinationPath: request.destinationPath,
      overwrite: request.overwrite,
      expectedFingerprint: fingerprint),
  synchronize: synchronizeTrimmedAudio,
  releaseTemporary: (temporary) =>
      native.releaseAudioTrim(temporaryPath: temporary),
  releasePlayback: (source) async => PlayService.playbackReady.value
      ? PlayService.instance.playbackService.prepareAudioDeletion(source)
      : null,
  restorePlayback: (ticket, offset) {
    if (ticket is PlaybackAudioDeletionTicket &&
        PlayService.playbackReady.value) {
      PlayService.instance.playbackService.cancelAudioDeletion(ticket,
          restoredPosition: offset == null
              ? null
              : (ticket.position - offset).clamp(0, double.infinity));
    }
  },
);

Future<AudioTrimResult> performAudioTrim(
  Audio audio,
  AudioTrimRequest request, {
  void Function(double)? onProgress,
  AudioTrimCancellation? cancellation,
  AudioTrimOperations? operations,
}) async {
  final cancel = cancellation ?? AudioTrimCancellation();
  TaskbarProgressTask? taskbar;
  void report(double value) {
    taskbar?.update(value);
    // A detached UI listener must not turn a successful disk commit into an
    // apparent failure or leave a running child process without an owner.
    try {
      onProgress?.call(value);
    } catch (_) {}
  }

  try {
    return await LibraryMutationGate.shared.run(() {
      taskbar = TaskbarProgress.instance.begin();
      return _performAudioTrim(
          audio, request, cancel, operations ?? _nativeTrimOperations, report);
    });
  } on LibraryMutationBusy {
    throw const AudioTrimException('busy', '曲库操作正在进行，请稍后再裁剪');
  } finally {
    taskbar?.dispose();
  }
}

Future<AudioTrimResult> _performAudioTrim(
    Audio audio,
    AudioTrimRequest request,
    AudioTrimCancellation cancellation,
    AudioTrimOperations operations,
    void Function(double)? onProgress) async {
  if (!audio.canEditLocalFile) {
    throw const AudioTrimException('local', '仅支持裁剪独立的本地歌曲文件');
  }
  cancellation.check();
  final prepared = jsonDecode(await operations.prepare(audio.path)) as Map;
  final fingerprint = prepared['fingerprint'] as String;
  final info = await probeAudioForTrim(audio.path,
      cancellation: cancellation, resolve: operations.resolveTool);
  validateAudioTrimRequest(info, request);
  if (request.overwrite !=
      p.equals(p.normalize(audio.path), p.normalize(request.destinationPath))) {
    throw const AudioTrimException('destination', '覆盖只能保存到原文件，副本必须使用其他文件名');
  }
  final destination = File(request.destinationPath);
  if (!request.overwrite && await destination.exists()) {
    throw const AudioTrimException('exists', '此文件名已存在，请换一个名称保存副本');
  }
  if (!await destination.parent.exists()) {
    throw const AudioTrimException('directory', '保存文件夹不存在，请重新选择');
  }
  cancellation.check();
  // A private sibling directory gives ffmpeg exclusive output ownership and
  // keeps the final rename on the destination volume. No original is opened
  // for writing until the verified native commit.
  final work = await destination.parent.createTemp('.dan-player-trim-');
  final temporary = File(p.join(work.path, 'audio${info.outputExtension}'));
  Object? playbackTicket;
  PreparedTrimLyrics? lyrics;
  var committed = false;
  var libraryUpdated = false;
  try {
    lyrics = await prepareTrimmedAudioLyrics(audio.path, request);
    cancellation.check();
    onProgress?.call(0);
    final selected = request.endSeconds - request.startSeconds;
    await runAudioTool('ffmpeg',
        audioTrimEncoderArguments(audio.path, temporary.path, info, request),
        cancellation: cancellation,
        resolve: operations.resolveTool, onLine: (line) {
      if (line.startsWith('out_time_us=')) {
        final value = double.tryParse(line.substring(12));
        if (value != null) {
          onProgress?.call((value / 1000000 / selected * .8).clamp(0, .8));
        }
      }
    });
    cancellation.check();
    final actual = await probeAudioForTrim(temporary.path,
        cancellation: cancellation, resolve: operations.resolveTool);
    // Compressed codecs include a small encoder priming/padding interval in
    // the container duration. Decoded sample content is cut by ffmpeg.
    if ((actual.duration - selected).abs() > .15 ||
        actual.sampleRate != info.sampleRate ||
        actual.channels != info.channels) {
      throw const AudioTrimException('verify', '裁剪结果校验失败，原文件未被修改');
    }
    onProgress?.call(.86);
    // Decode the complete encoded audio before metadata transfer. Legacy
    // Lyrics3 tails are not audio and ffmpeg can mistake them for bad frames.
    // Native transfer separately verifies unchanged audio and stream properties.
    await runAudioTool(
        'ffmpeg',
        [
          '-v',
          'error',
          '-xerror',
          '-nostdin',
          '-protocol_whitelist',
          'file,pipe',
          '-i',
          temporary.path,
          '-map',
          '0:a:0',
          '-threads',
          '2',
          '-f',
          'null',
          '-'
        ],
        cancellation: cancellation,
        resolve: operations.resolveTool);
    cancellation.check();
    await operations.metadata(audio.path, temporary.path, request);
    cancellation.check();
    if (request.overwrite) {
      playbackTicket = await operations.releasePlayback?.call(audio.path);
    }
    cancellation.beginCommit();
    onProgress?.call(.94);
    // Publish the prepared lyric first, retaining its rollback copy. A failed
    // audio commit below restores it before playback can reopen the source.
    await lyrics?.commit();
    final receipt = jsonDecode(await operations.commit(
            audio.path, temporary.path, request, fingerprint))
        as Map<String, dynamic>;
    committed = true;
    final savedPath = receipt['path'] as String;
    final savedAudio = Map<String, dynamic>.from(receipt['audio'] as Map);
    final backup = receipt['backupPath'] as String?;
    String? warning = lyrics?.unsupported == true ||
            (receipt['warnings'] is List &&
                (receipt['warnings'] as List).isNotEmpty)
        ? '部分歌词格式无法自动对齐，已保留原文，请手动校准'
        : null;
    libraryUpdated = true;
    try {
      await operations.synchronize(audio, request, savedAudio);
    } catch (_) {
      libraryUpdated = false;
      warning = [if (warning != null) warning, '歌曲已保存，但曲库刷新未完成，请刷新曲库；不要重复覆盖']
          .join('\n');
    }
    if (libraryUpdated && backup != null && backup.isNotEmpty) {
      // The native API returns only the unique backup it reserved. Keep it
      // if app synchronization failed so recovery remains possible.
      try {
        await File(backup).delete();
      } catch (_) {
        warning =
            [if (warning != null) warning, '歌曲已保存，原文件的恢复副本仍保留在原文件夹'].join('\n');
      }
    }
    String? lyricCleanup;
    try {
      lyricCleanup = await lyrics?.dispose(keepBackup: !libraryUpdated);
    } catch (_) {
      lyricCleanup = '歌曲已保存，原文件的恢复副本仍保留在原文件夹';
    }
    if (lyricCleanup != null) {
      warning = [if (warning != null) warning, lyricCleanup].join('\n');
    }
    lyrics = null;
    onProgress?.call(1);
    return AudioTrimResult(
        path: savedPath,
        duration: actual.duration,
        libraryUpdated: libraryUpdated,
        warning: warning);
  } catch (_) {
    if (!committed) {
      final rollbackWarning = await lyrics?.rollback();
      if (rollbackWarning != null) {
        throw AudioTrimException('lyricsRollback', rollbackWarning);
      }
    }
    rethrow;
  } finally {
    try {
      operations.restorePlayback
          ?.call(playbackTicket, committed ? request.startSeconds : null);
    } catch (_) {}
    try {
      await operations.releaseTemporary?.call(temporary.path);
    } catch (_) {}
    try {
      await lyrics?.dispose(keepBackup: committed && !libraryUpdated);
    } catch (_) {}
    // Delete only known transaction files; never recursively delete a user
    // chosen directory or a file referenced by the source metadata.
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
    try {
      await work.delete();
    } catch (_) {}
  }
}

Future<void> synchronizeTrimmedAudio(Audio source, AudioTrimRequest request,
    Map<String, dynamic> nativeAudio) async {
  final values = Map<String, dynamic>.from(nativeAudio);
  values['path'] = request.destinationPath;
  if (request.overwrite) values['track_id'] = source.stableTrackId;
  final saved = Audio.fromMap(values);
  await synchronizeTrimmedLyricDocument(
      source, saved, request.startSeconds, request.endSeconds,
      preserve: request.preserveMetadata);
  // A shortened recording must not automatically fetch the full song's
  // timeline when it has no saved lyric document.
  await persistLyricSource(saved.path, LyricSource(LyricSourceType.local));
  final library = AudioLibrary.instance;
  library.registerSavedAudio(saved);
  await CoverCache.instance.invalidate(saved.path);
  if (request.overwrite) {
    final playlistsChanged =
        replaceAudioInPlaylists(source.path, saved.path, saved);
    if (PlayService.playbackReady.value) {
      PlayService.instance.playbackService
          .replaceAudioReference(source.path, saved);
    }
    await (await TrackResumeStore.instance).remove(saved.path);
    if (playlistsChanged) await savePlaylists();
  } else if (request.preserveMetadata) {
    final personal = await PersonalLibrary.instance;
    final original = (await personal.snapshot())[source.stableTrackId];
    if (original != null) {
      await personal.apply([saved],
          changeRating: true,
          rating: original.rating,
          changeTags: true,
          addTags: original.tags);
    }
  }
  await library.saveIndex();
  await AudioSearchIndex.instance.ensureBuilt();
}
