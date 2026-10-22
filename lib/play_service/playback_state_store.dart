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
    this.queueCueTracks = const {},
    this.backupCueTracks = const {},
  });

  final List<String> queuePaths;
  final List<String> backupPaths;
  final int index;
  final double position;
  final bool shuffle;

  /// CUE entries may outlive the playlist they were imported into. Retain
  /// their independent source coordinates without adding them to the scanner.
  final List<Audio> cueTracks;

  /// The same CUE path/track number can occur with different source ranges
  /// after a sheet is edited. Preserve the segment selected for each slot.
  /// The path-only descriptors above remain available to older versions.
  final Map<int, Audio> queueCueTracks;
  final Map<int, Audio> backupCueTracks;

  Map<String, Object> toMap() => {
        "version": 1,
        "queuePaths": queuePaths,
        "backupPaths": backupPaths,
        "index": index,
        "position": position,
        "shuffle": shuffle,
        if (cueTracks.isNotEmpty)
          'cueTracks': [for (final audio in cueTracks) audio.toMap()],
        if (queueCueTracks.isNotEmpty)
          'queueCueTracks': {
            for (final entry in queueCueTracks.entries)
              entry.key.toString(): entry.value.toMap(),
          },
        if (backupCueTracks.isNotEmpty)
          'backupCueTracks': {
            for (final entry in backupCueTracks.entries)
              entry.key.toString(): entry.value.toMap(),
          },
      };

  static SavedPlaybackState? fromMap(Map map) {
    final rawQueue = map["queuePaths"];
    if (rawQueue is! List || rawQueue.isEmpty) return null;
    final savedIndex = map["index"] is int ? map["index"] as int : 0;
    final queue = <String>[];
    final queueIndices = <int, int>{};
    var currentIndex = -1;
    for (var i = 0; i < rawQueue.length; i++) {
      final path = rawQueue[i];
      if (path is! String || path.isEmpty) continue;
      // Keep the saved occurrence while recovering valid entries. Filtering
      // an invalid prefix must not attach its successor's position to a
      // different track, or silently select the first duplicate instead.
      if (i == savedIndex) currentIndex = queue.length;
      queueIndices[i] = queue.length;
      queue.add(path);
    }
    if (queue.isEmpty) return null;

    final rawBackup = map["backupPaths"];
    final backup = <String>[];
    final backupIndices = <int, int>{};
    if (rawBackup is List) {
      for (var i = 0; i < rawBackup.length; i++) {
        final path = rawBackup[i];
        if (path is! String || path.isEmpty) continue;
        backupIndices[i] = backup.length;
        backup.add(path);
      }
    }
    final queueCueTracks =
        _cueTracksByIndex(map['queueCueTracks'], rawQueue, queueIndices);
    final backupCueTracks = backup.isEmpty
        ? queueCueTracks
        : _cueTracksByIndex(
            map['backupCueTracks'], rawBackup as List, backupIndices);
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
        } on UnsupportedError {
          // JSON exponents can overflow to infinity, which cannot become int.
        }
      }
    }
    final rawPosition = map['position'];
    return SavedPlaybackState(
      queuePaths: queue,
      backupPaths: backup.isEmpty ? queue : backup,
      index: currentIndex,
      position: currentIndex >= 0 &&
              rawPosition is num &&
              rawPosition.isFinite &&
              rawPosition >= 0
          ? rawPosition.toDouble()
          : 0,
      shuffle: map["shuffle"] == true,
      cueTracks: List.unmodifiable(cueTracks),
      queueCueTracks: queueCueTracks,
      backupCueTracks: backupCueTracks,
    );
  }

  static Map<int, Audio> _cueTracksByIndex(
      Object? raw, List paths, Map<int, int> filteredIndices) {
    final result = <int, Audio>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries) {
      final key = entry.key;
      final index = key is String ? int.tryParse(key) : null;
      final filteredIndex = filteredIndices[index];
      if (index == null || filteredIndex == null || entry.value is! Map) {
        continue;
      }
      try {
        final audio = Audio.fromMap(entry.value as Map);
        if (audio.isCueTrack &&
            audio.path == paths[index] &&
            audio.path == audio.cueTrack!.identity) {
          result[filteredIndex] = audio;
        }
      } on FormatException {
        // Ignore only this optional slot and retain the legacy path fallback.
      } on TypeError {
        // Malformed optional metadata must not discard other queue entries.
      } on UnsupportedError {
        // A non-finite numeric tag cannot be converted to an integer.
      }
    }
    return Map.unmodifiable(result);
  }
}

class PlaybackStateStore {
  PlaybackStateStore._();

  // A successful fallback means the primary was unreadable. Keep that known-
  // good backup through the next save instead of rotating the damaged primary
  // over it. The path guards independent isolated profiles in one process.
  static String? _recoveredBackupPath;

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
      if (_recoveredBackupPath == backup.path && await backup.exists()) {
        if (await target.exists()) await target.delete();
      } else {
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      _recoveredBackupPath = null;
      // Retain the previous completed session. load() already knows how to
      // recover it when the newest file is later damaged or only half-written.
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      try {
        if (!await target.exists() && await backup.exists()) {
          await backup.copy(target.path);
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
          if (state != null) {
            _recoveredBackupPath =
                file.path == backup.path ? backup.path : null;
            return state;
          }
        }
      } catch (err, trace) {
        LOGGER.e(err, stackTrace: trace);
      }
    }
    return null;
  }
}
