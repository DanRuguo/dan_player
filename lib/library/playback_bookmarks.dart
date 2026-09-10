import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class PlaybackBookmark {
  const PlaybackBookmark({
    required this.id,
    required this.track,
    required this.label,
    required this.positionMs,
    this.endMs,
  });

  final String id;
  final String track;
  final String label;
  final int positionMs;
  final int? endMs;

  double get position => positionMs / 1000;
  double? get end => endMs == null ? null : endMs! / 1000;

  bool fitsDuration(double duration) =>
      duration.isFinite &&
      duration > 0 &&
      position < duration &&
      (end == null || end! <= duration);

  Map<String, Object?> toJson() => {
        'id': id,
        'track': track,
        'label': label,
        'positionMs': positionMs,
        if (endMs != null) 'endMs': endMs,
      };

  static PlaybackBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final track = value['track'];
    final label = value['label'];
    final position = value['positionMs'];
    final end = value['endMs'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 100 ||
        track is! String ||
        track.isEmpty ||
        track.length > 4096 ||
        label is! String ||
        label.trim().isEmpty ||
        label.length > 80 ||
        position is! int ||
        position < 0 ||
        (end != null && (end is! int || end - position < 1000))) {
      return null;
    }
    return PlaybackBookmark(
        id: id,
        track: PlaybackBookmarkStore.trackKey(track),
        label: label,
        positionMs: position,
        endMs: end as int?);
  }
}

/// Explicit user bookmarks, separate from the automatic last-session position.
/// File operations are serialized; memory changes only after the snapshot saves.
class PlaybackBookmarkStore {
  PlaybackBookmarkStore(this.file);
  final File file;
  static final changes = ValueNotifier<int>(0);
  static Future<PlaybackBookmarkStore>? _instance;
  static Future<PlaybackBookmarkStore> get instance => _instance ??= () async {
        final directory = await getAppDataDir();
        return PlaybackBookmarkStore(
            File(path.join(directory.path, 'playback_bookmarks.json')));
      }();

  static const maxPerTrack = 100;
  static const maxEntries = 5000;
  static const maxFileBytes = 2 * 1024 * 1024;
  static int _serial = 0;
  bool _loaded = false;
  bool _recoveredBackup = false;
  List<PlaybackBookmark> _items = [];
  Future<void> _pending = Future.value();

  static String trackKey(String localPath) =>
      path.windows.normalize(localPath).toLowerCase();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    Object? failure;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > maxFileBytes) {
          throw const FormatException('Bookmark file is too large');
        }
        final data = jsonDecode(await candidate.readAsString());
        if (data is Map && data['version'] is int && data['version'] > 1) {
          throw UnsupportedError('Bookmarks were created by a newer version');
        }
        if (data is! Map ||
            data['version'] != 1 ||
            data['bookmarks'] is! List) {
          throw const FormatException('Invalid bookmark file');
        }
        final entries = data['bookmarks'] as List;
        if (entries.length > maxEntries) {
          throw const FormatException('Too many bookmarks');
        }
        final ids = <String>{};
        final items = <PlaybackBookmark>[];
        for (final entry in entries) {
          final bookmark = PlaybackBookmark.fromJson(entry);
          // A cache restore can remove a missing song's path. Keep the other
          // songs' bookmarks readable even when that individual entry is stale.
          if (bookmark == null || !ids.add(bookmark.id)) continue;
          items.add(bookmark);
        }
        _items = items;
        _loaded = true;
        _recoveredBackup = candidate.path != file.path;
        return;
      } on UnsupportedError {
        // A downgrade must not restore an older backup over newer user data.
        rethrow;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) throw failure;
    _loaded = true;
  }

  Future<List<PlaybackBookmark>> forTrack(String localPath,
          {String? stableTrackId}) =>
      _exclusive(() async {
        await _load();
        final key = trackKey(localPath);
        final legacyIsUnique = stableTrackId == null ||
            TrackIdentityRegistry.instance.resolvePath(localPath) ==
                stableTrackId;
        return List.unmodifiable(_items.where((item) =>
            (stableTrackId != null && item.track == stableTrackId) ||
            (legacyIsUnique && item.track == key)));
      });

  Future<void> relocatePath(String oldPath, String newPath) =>
      _exclusive(() async {
        await _load();
        final before = trackKey(oldPath), after = trackKey(newPath);
        if (!_items.any((item) => item.track == before)) return;
        await _save([
          for (final item in _items)
            if (item.track == before)
              PlaybackBookmark(
                  id: item.id,
                  track: after,
                  label: item.label,
                  positionMs: item.positionMs,
                  endMs: item.endMs)
            else
              item
        ]);
      });

  Future<void> _save(List<PlaybackBookmark> next) async {
    final data = jsonEncode({
      'version': 1,
      'bookmarks': next.map((item) => item.toJson()).toList(),
    });
    if (utf8.encode(data).length > maxFileBytes) {
      throw StateError('Bookmark storage limit reached');
    }
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    try {
      await temporary.writeAsString(data, flush: true);
      if (!_recoveredBackup && await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      await temporary.rename(file.path);
      _items = next;
      _recoveredBackup = false;
      changes.value++;
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> add({
    required String localPath,
    String? stableTrackId,
    required String label,
    required double position,
    double? end,
  }) =>
      _exclusive(() async {
        await _load();
        final key = stableTrackId ?? trackKey(localPath);
        if (stableTrackId != null) {
          if (!TrackIdentityRegistry.isTrackId(stableTrackId)) {
            throw ArgumentError('Invalid track identity');
          }
          await TrackIdentityRegistry.instance.flush();
        }
        if (!position.isFinite || (end != null && !end.isFinite)) {
          throw ArgumentError('Invalid bookmark position');
        }
        final bookmark = PlaybackBookmark(
            id: '${DateTime.now().microsecondsSinceEpoch}-${_serial++}',
            track: key,
            label: label.trim(),
            positionMs: (position * 1000).round(),
            endMs: end == null ? null : (end * 1000).round());
        if (PlaybackBookmark.fromJson(bookmark.toJson()) == null) {
          throw ArgumentError('Invalid bookmark');
        }
        if (_items.length >= maxEntries ||
            _items.where((item) => item.track == key).length >= maxPerTrack) {
          throw StateError('Bookmark storage limit reached');
        }
        await _save([..._items, bookmark]);
      });

  Future<void> rename(String id, String label) => _exclusive(() async {
        await _load();
        final name = label.trim();
        if (name.isEmpty || name.length > 80) {
          throw ArgumentError('Invalid bookmark name');
        }
        await _save([
          for (final item in _items)
            if (item.id == id)
              PlaybackBookmark(
                  id: item.id,
                  track: item.track,
                  label: name,
                  positionMs: item.positionMs,
                  endMs: item.endMs)
            else
              item,
        ]);
      });

  Future<List<PlaybackBookmark>> all() => _exclusive(() async {
        await _load();
        return List.unmodifiable(_items);
      });
  Future<void> removeMany(Set<String> ids) => _exclusive(() async {
        await _load();
        await _save(_items.where((item) => !ids.contains(item.id)).toList());
      });

  Future<void> remove(String id) => _exclusive(() async {
        await _load();
        await _save(_items.where((item) => item.id != id).toList());
      });
}
