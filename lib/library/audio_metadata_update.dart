import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
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
  });

  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String? picturePath;
}

class AudioMetadataEditException implements Exception {
  const AudioMetadataEditException(this.code, this.message);

  factory AudioMetadataEditException.fromNative(Object error) {
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

  @override
  String toString() => message;
}

Future<Audio> applyAudioMetadataEdit(
  Audio audio,
  AudioMetadataEdit edit,
) async {
  final oldPath = audio.path;
  final fileName = edit.fileName.trim();
  final title = edit.title.trim();
  final artist = edit.artist.trim().isEmpty ? "UNKNOWN" : edit.artist.trim();
  final album = edit.album.trim().isEmpty ? "UNKNOWN" : edit.album.trim();
  final picturePath = edit.picturePath?.trim();
  final changesPicture = picturePath != null && picturePath.isNotEmpty;

  if (path_util.basename(oldPath) == fileName &&
      audio.title == title &&
      audio.artist == artist &&
      audio.album == album &&
      !changesPicture) {
    return audio;
  }

  final String newPath;
  try {
    newPath = await updateAudioMetadata(
      path: oldPath,
      fileName: fileName,
      title: title,
      artist: artist,
      album: album,
      picturePath: changesPicture ? picturePath : null,
    );
  } catch (error) {
    throw AudioMetadataEditException.fromNative(error);
  }
  final stat = await File(newPath).stat();
  final modified = stat.modified.millisecondsSinceEpoch ~/ 1000;

  await CoverCache.instance.invalidate(oldPath);
  if (newPath != oldPath) {
    await CoverCache.instance.invalidate(newPath);
  }

  audio.applyEditedMetadata(
    newPath: newPath,
    newTitle: title,
    newArtist: artist,
    newAlbum: album,
    newModified: modified,
  );

  AudioLibrary.instance.rebuildDerivedCollections();

  final customOrderChanged =
      oldPath != newPath && customAudioOrder.replacePath(oldPath, newPath);
  final playlistsChanged = replaceAudioInPlaylists(oldPath, newPath, audio);
  PlayService.instance.playbackService.replaceAudioReference(oldPath, audio);

  await AudioLibrary.instance.saveIndex();
  if (newPath != oldPath) {
    await SongCommentAssociationStore.instance.movePath(oldPath, newPath);
  }
  if (customOrderChanged) {
    await saveCustomAudioOrder();
  }
  if (playlistsChanged) {
    await savePlaylists();
  }
  unawaited(AudioSearchIndex.instance.ensureBuilt());

  return audio;
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
