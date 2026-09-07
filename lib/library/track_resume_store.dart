import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:path/path.dart' as p;

class TrackResumePosition {
  const TrackResumePosition(
      {required this.track,
      this.stableTrackId,
      required this.positionMs,
      required this.durationMs,
      required this.updatedMs});
  final String track;
  final String? stableTrackId;
  final int positionMs, durationMs, updatedMs;
  Map<String, Object> toJson() => {
        'track': track,
        if (stableTrackId != null) 'stableTrackId': stableTrackId!,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedMs': updatedMs
      };

  static TrackResumePosition? fromJson(Object? value) {
    if (value is! Map) return null;
    final track = value['track'];
    final position = value['positionMs'];
    final duration = value['durationMs'];
    final updated = value['updatedMs'];
    final key = track is String ? TrackResumeStore.trackKey(track) : null;
    if (key == null ||
        position is! int ||
        duration is! int ||
        updated is! int ||
        position < 10000 ||
        duration <= 20000 ||
        position >= duration - 10000 ||
        duration > 365 * 24 * 60 * 60 * 1000 ||
        updated < 0) {
      return null;
    }
    return TrackResumePosition(
        track: key,
        stableTrackId: value['stableTrackId'] is String &&
                TrackIdentityRegistry.isTrackId(
                    value['stableTrackId'] as String)
            ? value['stableTrackId'] as String
            : null,
        positionMs: position,
        durationMs: duration,
        updatedMs: updated);
  }
}

/// Automatic positions only; never edits audio or manual bookmarks. Disk
/// writes are serialized, bounded, and commit memory after atomic replacement.
class TrackResumeStore {
  TrackResumeStore(this.file, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final File file;
  final DateTime Function() _clock;
  static const maxEntries = 1000;
  static const maxFileBytes = 1024 * 1024;
  static const captureInterval = Duration(seconds: 10);
  static Future<TrackResumeStore>? _instance;
  static Future<TrackResumeStore> get instance => _instance ??= _openInstance();

  static Future<TrackResumeStore> _openInstance() async {
    try {
      final directory = await getAppDataDir();
      return TrackResumeStore(
          File(p.join(directory.path, 'track_resume.json')));
    } catch (_) {
      _instance = null;
      rethrow;
    }
  }

  Future<void> _pending = Future.value();
  bool _loaded = false, _recoveredBackup = false;
  Map<String, TrackResumePosition> _items = {};
  final Map<String, DateTime> _lastCapture = {};

  static String? trackKey(String track) {
    if (track.isEmpty ||
        track.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(track)) {
      return null;
    }
    if (track.startsWith('cue://track/')) return track;
    if (!p.windows.isAbsolute(track) || p.windows.isRootRelative(track)) {
      return null;
    }
    return p.windows.normalize(track).toLowerCase();
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> flush() => _pending;

  Future<void> relocatePath(String oldPath, String newPath) =>
      _exclusive(() async {
        await _load();
        final before = trackKey(oldPath), after = trackKey(newPath);
        if (before == null ||
            after == null ||
            before == after ||
            !_items.containsKey(before)) {
          return;
        }
        if (_items.containsKey(after)) throw StateError('续播位置存在路径冲突。');
        final item = _items[before]!;
        final next = Map<String, TrackResumePosition>.of(_items)
          ..remove(before);
        next[after] = TrackResumePosition(
            track: after,
            stableTrackId: item.stableTrackId,
            positionMs: item.positionMs,
            durationMs: item.durationMs,
            updatedMs: item.updatedMs);
        await _save(next);
        _lastCapture.remove(before);
      });

  static Future<void> flushIfInitialized() async {
    final pending = _instance;
    if (pending != null) await (await pending).flush();
  }

  Future<void> _load() async {
    if (_loaded) return;
    Object? failure;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > maxFileBytes) {
          throw const FormatException('Resume storage is too large');
        }
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map ||
            decoded['version'] != 1 ||
            decoded['positions'] is! List) {
          throw const FormatException('Invalid resume storage');
        }
        final positions = decoded['positions'] as List;
        if (positions.length > maxEntries) {
          throw const FormatException('Too many resume positions');
        }
        final next = <String, TrackResumePosition>{};
        for (final raw in positions) {
          final item = TrackResumePosition.fromJson(raw);
          if (item != null &&
              (next[item.track]?.updatedMs ?? -1) < item.updatedMs) {
            next[item.track] = item;
          }
        }
        _items = next;
        _recoveredBackup = candidate.path != file.path;
        _loaded = true;
        return;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) throw failure;
    _loaded = true;
  }

  /// Call only for an explicit track choice. A session/seek/bookmark supplies
  /// its own position; automatic advance and repeat keep starting at zero.
  Future<double?> resumePosition(
      {required String track,
      String? stableTrackId,
      required double duration,
      required TrackResumePreferences preferences,
      bool userSelected = true,
      bool hasExplicitPosition = false}) {
    final key = trackKey(track);
    if (!userSelected ||
        hasExplicitPosition ||
        !preferences.accepts(local: key != null, duration: duration)) {
      return Future.value();
    }
    return _exclusive(() async {
      await _load();
      final item = _items[key];
      if (item == null) return null;
      if (stableTrackId != null) {
        // CUE URI/track number alone does not identify a particular frame
        // range. A legacy position has no evidence that its boundaries match.
        if (item.stableTrackId == null && track.startsWith('cue://track/')) {
          return null;
        }
        if (item.stableTrackId != null && item.stableTrackId != stableTrackId) {
          return null;
        }
      }
      final nativeMs = (duration * 1000).round();
      // Replaced/truncated content at the same path must not inherit a wildly
      // different recording's position. Small duration-header corrections fit.
      if ((nativeMs - item.durationMs).abs() > math.max(5000, nativeMs * .02) ||
          item.positionMs >= nativeMs - 10000) {
        return null;
      }
      return item.positionMs / 1000;
    });
  }

  Future<bool> remember(
      {required String track,
      String? stableTrackId,
      required double position,
      required double duration,
      required TrackResumePreferences preferences,
      bool force = false,
      bool completed = false,
      bool segmentLoopActive = false}) {
    final key = trackKey(track);
    if (segmentLoopActive ||
        !position.isFinite ||
        position < 0 ||
        !preferences.accepts(local: key != null, duration: duration)) {
      return Future.value(false);
    }
    final now = _clock();
    final last = _lastCapture[key];
    if (!force &&
        !completed &&
        last != null &&
        !now.isBefore(last) &&
        now.difference(last) < captureInterval) {
      return Future.value(false);
    }
    if (!force && !completed && position < 10) return Future.value(false);
    _lastCapture[key!] = now;
    if (_lastCapture.length > maxEntries) {
      _lastCapture.remove(_lastCapture.keys.first);
    }
    return _exclusive(() async {
      try {
        await _load();
        final next = Map<String, TrackResumePosition>.of(_items);
        if (completed || position < 10 || position >= duration - 10) {
          final existingId = next[key]?.stableTrackId;
          if (existingId != null &&
              stableTrackId != null &&
              existingId != stableTrackId) {
            return false;
          }
          if (next.remove(key) == null) return false;
        } else {
          next[key] = TrackResumePosition(
              track: key,
              stableTrackId: stableTrackId,
              positionMs: (position * 1000).round(),
              durationMs: (duration * 1000).round(),
              updatedMs: now.millisecondsSinceEpoch);
        }
        await _save(next);
        return true;
      } catch (_) {
        if (_lastCapture[key] == now) _lastCapture.remove(key);
        rethrow;
      }
    });
  }

  Future<void> clear() => _exclusive(() async {
        await _save({});
        _lastCapture.clear();
        _loaded = true;
      });

  Future<void> _save(Map<String, TrackResumePosition> input) async {
    final recent = input.values.toList()
      ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    final next = <String, TrackResumePosition>{};
    var bytes = 32;
    for (final item in recent) {
      final itemBytes = utf8.encode(jsonEncode(item.toJson())).length + 1;
      if (next.length >= maxEntries || bytes + itemBytes > maxFileBytes) break;
      next[item.track] = item;
      bytes += itemBytes;
    }
    final contents = jsonEncode({
      'version': 1,
      'positions': next.values.map((item) => item.toJson()).toList()
    });
    if (utf8.encode(contents).length > maxFileBytes) {
      throw StateError('Resume storage limit reached');
    }
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    try {
      await temporary.writeAsString(contents, flush: true);
      if (!_recoveredBackup && await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      if (_recoveredBackup && await file.exists()) await file.delete();
      await temporary.rename(file.path);
      _items = next;
      _recoveredBackup = false;
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
