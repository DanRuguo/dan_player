import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
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

  final newPath = await updateAudioMetadata(
    path: oldPath,
    fileName: fileName,
    title: title,
    artist: artist,
    album: album,
    picturePath: changesPicture ? picturePath : null,
  );
  final stat = await File(newPath).stat();
  final modified = stat.modified.millisecondsSinceEpoch ~/ 1000;

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
  bool collectionsChanged = false;
  if (oldPath != newPath) {
    for (final collection in userCollections) {
      if (collection.replacePath(oldPath, newPath)) {
        collectionsChanged = true;
      }
    }
  }

  final playlistsChanged = replaceAudioInPlaylists(oldPath, newPath, audio);
  PlayService.instance.playbackService.replaceAudioReference(oldPath, audio);

  await AudioLibrary.instance.saveIndex();
  if (customOrderChanged) {
    await saveCustomAudioOrder();
  }
  if (collectionsChanged) {
    await saveCollections();
  }
  if (playlistsChanged) {
    await savePlaylists();
  }

  return audio;
}

bool replaceAudioInPlaylists(String oldPath, String newPath, Audio audio) {
  bool changed = false;
  for (final playlist in PLAYLISTS) {
    bool playlistChanged = false;
    final updated = <String, Audio>{};
    for (final entry in playlist.audios.entries) {
      if (entry.key == oldPath || entry.value.path == oldPath) {
        updated[newPath] = audio;
        playlistChanged = true;
      } else {
        updated[entry.key] = entry.value;
      }
    }
    if (playlistChanged) {
      playlist.audios = updated;
      changed = true;
    }
  }
  return changed;
}
