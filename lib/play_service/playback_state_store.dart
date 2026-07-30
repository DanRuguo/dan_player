import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';

class SavedPlaybackState {
  const SavedPlaybackState({
    required this.queuePaths,
    required this.backupPaths,
    required this.index,
    required this.position,
    required this.shuffle,
  });

  final List<String> queuePaths;
  final List<String> backupPaths;
  final int index;
  final double position;
  final bool shuffle;

  Map<String, Object> toMap() => {
        "version": 1,
        "queuePaths": queuePaths,
        "backupPaths": backupPaths,
        "index": index,
        "position": position,
        "shuffle": shuffle,
      };

  static SavedPlaybackState? fromMap(Map map) {
    final rawQueue = map["queuePaths"];
    if (rawQueue is! List || rawQueue.isEmpty) return null;
    final queue = rawQueue.whereType<String>().toList();
    if (queue.isEmpty) return null;

    final rawBackup = map["backupPaths"];
    final backup =
        rawBackup is List ? rawBackup.whereType<String>().toList() : queue;
    return SavedPlaybackState(
      queuePaths: queue,
      backupPaths: backup.isEmpty ? queue : backup,
      index: map["index"] is int ? map["index"] as int : 0,
      position:
          map["position"] is num ? (map["position"] as num).toDouble() : 0,
      shuffle: map["shuffle"] == true,
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
