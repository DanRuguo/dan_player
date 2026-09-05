import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/utils.dart';

class SavedPlaybackState {
  const SavedPlaybackState({
    required this.queuePaths,
    required this.backupPaths,
    required this.index,
    required this.position,
    required this.shuffle,
    this.cueTracks = const [],
  });

  final List<String> queuePaths;
  final List<String> backupPaths;
  final int index;
  final double position;
  final bool shuffle;

  /// CUE entries may outlive the playlist they were imported into. Retain
  /// their independent source coordinates without adding them to the scanner.
  final List<Audio> cueTracks;

  Map<String, Object> toMap() => {
        "version": 1,
        "queuePaths": queuePaths,
        "backupPaths": backupPaths,
        "index": index,
        "position": position,
        "shuffle": shuffle,
        if (cueTracks.isNotEmpty)
          'cueTracks': [for (final audio in cueTracks) audio.toMap()],
      };

  static SavedPlaybackState? fromMap(Map map) {
    final rawQueue = map["queuePaths"];
    if (rawQueue is! List || rawQueue.isEmpty) return null;
    final queue = rawQueue.whereType<String>().toList();
    if (queue.isEmpty) return null;

    final rawBackup = map["backupPaths"];
    final backup =
        rawBackup is List ? rawBackup.whereType<String>().toList() : queue;
    final cueTracks = <Audio>[];
    final rawCue = map['cueTracks'];
    if (rawCue is List) {
      for (final item in rawCue.whereType<Map>()) {
        try {
          final audio = Audio.fromMap(item);
          if (audio.isCueTrack) cueTracks.add(audio);
        } on FormatException {
          // A broken optional descriptor must not discard the surviving queue.
        } on TypeError {
          // Old/corrupt optional metadata can contain an unexpected value type.
        }
      }
    }
    return SavedPlaybackState(
      queuePaths: queue,
      backupPaths: backup.isEmpty ? queue : backup,
      index: map["index"] is int ? map["index"] as int : 0,
      position:
          map["position"] is num ? (map["position"] as num).toDouble() : 0,
      shuffle: map["shuffle"] == true,
      cueTracks: List.unmodifiable(cueTracks),
    );
  }
}

class PlaybackStateStore {
  PlaybackStateStore._();

  static Future<File> _file([String suffix = ""]) async {
    final supportPath = (await getAppDataDir()).path;
    return File("$supportPath\\playback_state.json$suffix");
  }

  static Future<void> save(SavedPlaybackState state) async {
    final target = await _file();
    final temporary = await _file(".tmp");
    final backup = await _file(".bak");

    try {
      await temporary.writeAsString(
        json.encode(state.toMap()),
        flush: true,
      );
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      try {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
      } catch (_) {}
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
  }

  static Future<SavedPlaybackState?> load() async {
    final target = await _file();
    final backup = await _file(".bak");
    for (final file in [target, backup]) {
      try {
        if (!await file.exists()) continue;
        final decoded = json.decode(await file.readAsString());
        if (decoded is Map) {
          final state = SavedPlaybackState.fromMap(decoded);
          if (state != null) return state;
        }
      } catch (err, trace) {
        LOGGER.e(err, stackTrace: trace);
      }
    }
    return null;
  }
}
