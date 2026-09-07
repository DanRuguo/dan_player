import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';

class TrackPlaybackStatistics {
  TrackPlaybackStatistics({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.online,
    this.playCount = 0,
    this.completedCount = 0,
    this.skippedCount = 0,
    this.listenMilliseconds = 0,
    this.lastPlayedAt = 0,
    this.legacyUnassigned = false,
    this.candidateTrackIds = const [],
    this.legacyIds = const [],
  });

  final String id;
  String title;
  String artist;
  String album;
  bool online;
  int playCount;
  int completedCount;
  int skippedCount;
  int listenMilliseconds;
  int lastPlayedAt;
  bool legacyUnassigned;
  List<String> candidateTrackIds;
  List<String> legacyIds;

  factory TrackPlaybackStatistics.fromMap(Map map) => TrackPlaybackStatistics(
        id: map["id"]?.toString() ?? "",
        title: map["title"]?.toString() ?? "UNKNOWN",
        artist: map["artist"]?.toString() ?? "UNKNOWN",
        album: map["album"]?.toString() ?? "UNKNOWN",
        online: map["online"] == true,
        playCount: (map["playCount"] as num?)?.toInt() ?? 0,
        completedCount: (map["completedCount"] as num?)?.toInt() ?? 0,
        skippedCount: (map["skippedCount"] as num?)?.toInt() ?? 0,
        listenMilliseconds: (map["listenMilliseconds"] as num?)?.toInt() ?? 0,
        lastPlayedAt: (map["lastPlayedAt"] as num?)?.toInt() ?? 0,
        legacyUnassigned: map['legacyUnassigned'] == true,
        candidateTrackIds:
            (map['candidateTrackIds'] as List?)?.whereType<String>().toList() ??
                const [],
        legacyIds: (map['legacyIds'] as List?)?.whereType<String>().toList() ??
            const [],
      );

  Map<String, Object> toMap() => {
        "id": id,
        "title": title,
        "artist": artist,
        "album": album,
        "online": online,
        "playCount": playCount,
        "completedCount": completedCount,
        "skippedCount": skippedCount,
        "listenMilliseconds": listenMilliseconds,
        "lastPlayedAt": lastPlayedAt,
        if (legacyUnassigned) 'legacyUnassigned': true,
        if (candidateTrackIds.isNotEmpty)
          'candidateTrackIds': candidateTrackIds,
        if (legacyIds.isNotEmpty) 'legacyIds': legacyIds,
      };
}

class PlaybackStatistics extends ChangeNotifier {
  PlaybackStatistics._({DateTime Function()? clock, bool persist = true})
      : _clock = clock ?? DateTime.now,
        _persist = persist;

  /// A fully isolated recorder: no timers, path-provider calls or file writes.
  /// The same legacy snapshot parser is used by the on-disk recorder.
  @visibleForTesting
  factory PlaybackStatistics.inMemory({
    DateTime Function()? clock,
    Map<String, Object?>? initialData,
  }) {
    final statistics = PlaybackStatistics._(clock: clock, persist: false);
    if (initialData != null) statistics._restoreSnapshot(initialData);
    return statistics;
  }

  static final PlaybackStatistics instance = PlaybackStatistics._();

  final DateTime Function() _clock;
  final bool _persist;

  final Map<String, TrackPlaybackStatistics> tracks = {};
  final Map<String, int> dailyMilliseconds = {};
  final List<int> hourlyMilliseconds = List.filled(24, 0);

  Audio? _activeAudio;
  String? _activeId;
  DateTime? _lastTick;
  double _sessionMediaMilliseconds = 0;
  double _playbackRate = 1.0;
  int _lastNotifyMilliseconds = 0;
  Timer? _saveTimer;
  Future<void> _writeQueue = Future.value();
  bool _preserveBackup = false;
  bool _storageWritable = true;
  int _loadedVersion = 1;
  String? storageWarning;

  int get legacyUnassignedCount =>
      tracks.values.where((track) => track.legacyUnassigned).length;

  int get totalListenMilliseconds =>
      tracks.values.fold(0, (sum, item) => sum + item.listenMilliseconds);
  int get totalPlayCount =>
      tracks.values.fold(0, (sum, item) => sum + item.playCount);
  int get totalCompletedCount =>
      tracks.values.fold(0, (sum, item) => sum + item.completedCount);
  int get totalSkippedCount =>
      tracks.values.fold(0, (sum, item) => sum + item.skippedCount);

  /// All tied peak hours are returned, in local clock order. Empty records have
  /// no peak rather than incorrectly reporting midnight as the favorite hour.
  List<int> get mostActiveHours {
    final maximum = hourlyMilliseconds.fold(0, math.max);
    if (maximum == 0) return const [];
    return [
      for (var hour = 0; hour < hourlyMilliseconds.length; hour++)
        if (hourlyMilliseconds[hour] == maximum) hour,
    ];
  }

  List<TrackPlaybackStatistics> get topByPlayCount {
    final values = tracks.values.toList()
      ..sort((a, b) {
        final count = b.playCount.compareTo(a.playCount);
        return count != 0
            ? count
            : b.listenMilliseconds.compareTo(a.listenMilliseconds);
      });
    return values;
  }

  List<TrackPlaybackStatistics> get topByListeningTime {
    final values = tracks.values.toList()
      ..sort((a, b) => b.listenMilliseconds.compareTo(a.listenMilliseconds));
    return values;
  }

  Future<void> initialize() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _writeQueue;
    _activeAudio = null;
    _activeId = null;
    _lastTick = null;
    _sessionMediaMilliseconds = 0;
    _playbackRate = 1.0;
    _lastNotifyMilliseconds = 0;
    _preserveBackup = false;
    _storageWritable = true;
    storageWarning = null;
    tracks.clear();
    dailyMilliseconds.clear();
    hourlyMilliseconds.fillRange(0, hourlyMilliseconds.length, 0);
    if (!_persist) {
      notifyListeners();
      return;
    }
    try {
      final target = await _file();
      final backup = await _file(".bak");
      Object? firstError;
      var loaded = false;
      String? originalContents;
      for (final file in [target, backup]) {
        if (!await file.exists()) continue;
        try {
          final contents = await file.readAsString();
          final decoded = json.decode(contents);
          _restoreSnapshot(decoded);
          originalContents = contents;
          loaded = true;
          if (file.path == backup.path) {
            _preserveBackup = true;
            LOGGER.w("[statistics] recovered from backup");
          }
          break;
        } catch (error) {
          firstError ??= error;
          tracks.clear();
          dailyMilliseconds.clear();
          hourlyMilliseconds.fillRange(0, hourlyMilliseconds.length, 0);
        }
      }
      if (!loaded && firstError != null) throw firstError;
      if (loaded && _loadedVersion < 2) {
        // Keep the original v1 bytes independently of the rotating .bak file.
        // Migration is one statistics-file commit after registry persistence;
        // an interruption can replay it without duplicating counters.
        final migrationBackup = File(
            '${target.parent.path}\\playback_statistics.pre-track-id-v1.json');
        if (!await migrationBackup.exists()) {
          final temporary = File('${migrationBackup.path}.tmp');
          await temporary.writeAsString(originalContents!, flush: true);
          await temporary.rename(migrationBackup.path);
        }
        final previous = snapshot();
        try {
          migrateLegacyIdentities(AudioLibrary.instance.audioCollection);
          await TrackIdentityRegistry.instance.flush();
          await _write();
        } catch (_) {
          tracks.clear();
          dailyMilliseconds.clear();
          hourlyMilliseconds.fillRange(0, hourlyMilliseconds.length, 0);
          _restoreSnapshot(previous);
          rethrow;
        }
      }
    } catch (error, trace) {
      _storageWritable = false;
      storageWarning = '听歌统计读取或迁移失败，原始文件已保留。';
      LOGGER.e("[statistics] failed to load: $error", stackTrace: trace);
    }
    notifyListeners();
  }

  void _restoreSnapshot(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException("Statistics root must be an object");
    }
    final version = decoded['version'] ?? 1;
    if (version is! int || version < 1 || version > 2) {
      throw const FormatException('Unsupported statistics version');
    }
    _loadedVersion = version;
    final trackMaps = decoded["tracks"];
    if (trackMaps != null && trackMaps is! List) {
      throw const FormatException('Statistics tracks must be a list');
    }
    if (trackMaps is List) {
      for (final value in trackMaps) {
        if (value is! Map ||
            value['id'] is! String ||
            (value['id'] as String).isEmpty ||
            tracks.containsKey(value['id'])) {
          throw const FormatException('Invalid or duplicate statistics track');
        }
        final item = TrackPlaybackStatistics.fromMap(value);
        if ([
          item.playCount,
          item.completedCount,
          item.skippedCount,
          item.listenMilliseconds,
          item.lastPlayedAt
        ].any((count) => count < 0)) {
          throw const FormatException('Negative statistics counter');
        }
        tracks[item.id] = item;
      }
    }
    final days = decoded["days"];
    if (days is Map) {
      for (final entry in days.entries) {
        dailyMilliseconds[entry.key.toString()] =
            (entry.value as num?)?.toInt() ?? 0;
      }
    }
    final hours = decoded["hours"];
    if (hours is List) {
      for (var i = 0; i < hourlyMilliseconds.length && i < hours.length; i++) {
        hourlyMilliseconds[i] = (hours[i] as num?)?.toInt() ?? 0;
      }
    }
  }

  String identityFor(Audio audio) {
    if (audio.isOnline) {
      return "online:${audio.onlineProvider}:${audio.onlineId}";
    }
    return audio.stableTrackId;
  }

  static String legacyIdentityFor(Audio audio) {
    if (audio.isOnline) {
      return 'online:${audio.onlineProvider}:${audio.onlineId}';
    }
    String normalize(String value) => value.trim().toLowerCase();
    return "local:${normalize(audio.title)}|${normalize(audio.artist)}|"
        "${normalize(audio.album)}|${audio.duration}";
  }

  /// Exact legacy metadata keys may belong to several physical files. Keep
  /// ambiguous/unmatched history as a single visible legacy bucket forever;
  /// losing one candidate later is not evidence of its historical ownership.
  int migrateLegacyIdentities(Iterable<Audio> library) {
    if (_activeId != null) {
      throw StateError('Finish the playback session before identity migration');
    }
    final candidates = <String, Set<String>>{};
    for (final audio in library) {
      if (audio.isOnline) continue;
      candidates
          .putIfAbsent(legacyIdentityFor(audio), () => {})
          .add(audio.stableTrackId);
    }
    final before = [
      totalPlayCount,
      totalCompletedCount,
      totalSkippedCount,
      totalListenMilliseconds
    ];
    var migrated = 0;
    for (final item in tracks.values.toList()) {
      if (item.online ||
          !item.id.startsWith('local:') ||
          TrackIdentityRegistry.isTrackId(item.id) ||
          item.legacyUnassigned) {
        continue;
      }
      final matching = candidates[item.id] ?? <String>{};
      if (matching.length != 1) {
        item.legacyUnassigned = true;
        item.candidateTrackIds = matching.toList()..sort();
        continue;
      }
      final id = matching.single;
      final existing = tracks[id];
      if (existing == null) {
        tracks[id] = TrackPlaybackStatistics.fromMap({
          ...item.toMap(),
          'id': id,
          'legacyIds': {...item.legacyIds, item.id}.toList(),
        });
      } else {
        existing
          ..playCount += item.playCount
          ..completedCount += item.completedCount
          ..skippedCount += item.skippedCount
          ..listenMilliseconds += item.listenMilliseconds
          ..lastPlayedAt = math.max(existing.lastPlayedAt, item.lastPlayedAt)
          ..legacyIds =
              {...existing.legacyIds, ...item.legacyIds, item.id}.toList();
      }
      tracks.remove(item.id);
      migrated++;
    }
    final after = [
      totalPlayCount,
      totalCompletedCount,
      totalSkippedCount,
      totalListenMilliseconds
    ];
    if (!listEquals(before, after)) {
      throw StateError('Statistics identity migration changed totals');
    }
    _loadedVersion = 2;
    return migrated;
  }

  Map<String, Object?> snapshot() => {
        'version': _loadedVersion,
        'tracks': tracks.values.map((item) => item.toMap()).toList(),
        'days': Map<String, int>.of(dailyMilliseconds),
        'hours': List<int>.of(hourlyMilliseconds),
      };

  void start(Audio audio, {double playbackRate = 1.0}) {
    final id = identityFor(audio);
    if (_activeId == id) {
      final now = _clock();
      // Resume does not create another play. Repeated start commands while
      // already playing must not discard the interval since the last sample.
      if (_lastTick == null) {
        _lastTick = now;
      } else {
        _recordUntil(now);
      }
      _activeAudio = audio;
      _playbackRate = PlaybackRate.sanitize(playbackRate);
      return;
    }
    finish(markCompleted: false, recordOutcome: true);
    _activeAudio = audio;
    _activeId = id;
    _sessionMediaMilliseconds = 0;
    _playbackRate = PlaybackRate.sanitize(playbackRate);
    final now = _clock();
    _lastTick = now;
    final stats = tracks.putIfAbsent(
      id,
      () => TrackPlaybackStatistics(
        id: id,
        title: audio.displayTitle,
        artist: audio.artist,
        album: audio.album,
        online: audio.isOnline,
      ),
    );
    stats
      ..title = audio.displayTitle
      ..artist = audio.artist
      ..album = audio.album
      ..online = audio.isOnline
      ..playCount += 1
      ..lastPlayedAt = now.millisecondsSinceEpoch;
    _lastNotifyMilliseconds = stats.listenMilliseconds;
    _scheduleSave();
    notifyListeners();
  }

  void tick(Audio? audio, PlayerState state, {double playbackRate = 1.0}) {
    // A stopped, paused, buffering or missing source breaks the accounting
    // interval. The next playing sample establishes a new baseline.
    if (audio == null || state != PlayerState.playing) {
      _lastTick = null;
      _playbackRate = PlaybackRate.sanitize(playbackRate);
      return;
    }
    final id = identityFor(audio);
    if (_activeId != id) {
      start(audio, playbackRate: playbackRate);
      return;
    }
    final now = _clock();
    if (_lastTick == null) {
      _lastTick = now;
      _playbackRate = PlaybackRate.sanitize(playbackRate);
      return;
    }
    _recordUntil(now);
    _playbackRate = PlaybackRate.sanitize(playbackRate);
  }

  void _recordUntil(DateTime now) {
    final previous = _lastTick;
    if (previous == null) return;
    final difference = now.difference(previous);
    if (difference.isNegative) {
      // A wall-clock correction must never subtract from saved counters.
      _lastTick = now;
      return;
    }
    final elapsed = difference.inMilliseconds.clamp(0, 2000).toInt();
    if (elapsed == 0) return;
    // Keep sub-millisecond remainders across ordinary samples. After a long
    // suspension/stall only the last two seconds are attributable; never fill
    // the unobserved gap or assign it to the previous hour/day.
    final end = difference.inMilliseconds > 2000
        ? now
        : previous.add(Duration(milliseconds: elapsed));
    _lastTick = end;
    final stats = tracks[_activeId];
    if (stats == null) return;
    stats.listenMilliseconds += elapsed;
    // Listening totals/buckets use wall time, while completion/skip heuristics
    // use actual media consumed. Slow playback must not count half a song as
    // complete just because a full song's worth of wall time has passed.
    _sessionMediaMilliseconds += elapsed * _playbackRate;
    _recordClockBuckets(end, elapsed);
    if (stats.listenMilliseconds - _lastNotifyMilliseconds >= 5000) {
      _lastNotifyMilliseconds = stats.listenMilliseconds;
      notifyListeners();
    }
    _scheduleSave();
  }

  void _recordClockBuckets(DateTime end, int milliseconds) {
    var cursor = end.subtract(Duration(milliseconds: milliseconds));
    while (cursor.isBefore(end)) {
      final nextHour = cursor.isUtc
          ? DateTime.utc(cursor.year, cursor.month, cursor.day, cursor.hour + 1)
          : DateTime(cursor.year, cursor.month, cursor.day, cursor.hour + 1);
      final boundary = nextHour.isBefore(end) ? nextHour : end;
      // Subtract integer epoch values so a boundary with fractional
      // milliseconds cannot lose one millisecond from the combined buckets.
      final amount =
          boundary.millisecondsSinceEpoch - cursor.millisecondsSinceEpoch;
      final day = _dayKey(cursor);
      dailyMilliseconds[day] = (dailyMilliseconds[day] ?? 0) + amount;
      hourlyMilliseconds[cursor.hour] += amount;
      cursor = boundary;
    }
  }

  void pause() {
    _recordUntil(_clock());
    _lastTick = null;
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  void finish({
    required bool markCompleted,
    bool recordOutcome = true,
  }) {
    _recordUntil(_clock());
    final audio = _activeAudio;
    final stats = _activeId == null ? null : tracks[_activeId];
    if (audio != null && stats != null && recordOutcome) {
      final durationMs = audio.duration * 1000;
      final fullThreshold = durationMs <= 0
          ? 90000
          : durationMs <= 10000
              ? (durationMs * 0.9).round()
              : math.min((durationMs * 0.9).round(), durationMs - 5000);
      final completed =
          markCompleted || _sessionMediaMilliseconds >= fullThreshold;
      if (completed) {
        stats.completedCount += 1;
      } else {
        final skipThreshold = durationMs <= 0
            ? 30000
            : math.min((durationMs * 0.5).round(), 30000);
        if (_sessionMediaMilliseconds < skipThreshold) stats.skippedCount += 1;
      }
    }
    _activeAudio = null;
    _activeId = null;
    _lastTick = null;
    _sessionMediaMilliseconds = 0;
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  Future<void> flush({bool finishSession = false}) async {
    if (finishSession) finish(markCompleted: false, recordOutcome: false);
    _saveTimer?.cancel();
    _saveTimer = null;
    await _queueWrite();
  }

  String _dayKey(DateTime value) => "${value.year.toString().padLeft(4, "0")}-"
      "${value.month.toString().padLeft(2, "0")}-"
      "${value.day.toString().padLeft(2, "0")}";

  void _scheduleSave({bool immediate = false}) {
    if (!_persist) return;
    // A playing track ticks continuously; do not postpone its checkpoint on
    // every tick. Pause/finish may still bring an existing checkpoint forward.
    if (!immediate && _saveTimer != null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      immediate
          ? const Duration(milliseconds: 150)
          : const Duration(seconds: 30),
      () {
        _saveTimer = null;
        unawaited(_queueWrite().catchError((Object _) {}));
      },
    );
  }

  Future<File> _file([String suffix = ""]) async {
    final supportPath = (await getAppDataDir()).path;
    return File("$supportPath\\playback_statistics.json$suffix");
  }

  Future<void> _queueWrite() {
    if (!_persist || !_storageWritable) return Future.value();
    _writeQueue = _writeQueue.then(
      (_) => _write(),
      onError: (_) => _write(),
    );
    return _writeQueue;
  }

  Future<void> _write() async {
    try {
      await TrackIdentityRegistry.instance.flush();
      final target = await _file();
      final temporary = await _file(".tmp");
      final backup = await _file(".bak");
      await target.parent.create(recursive: true);
      await temporary.writeAsString(
        const JsonEncoder.withIndent("  ").convert({
          "version": 2,
          "tracks": tracks.values.map((item) => item.toMap()).toList(),
          "days": dailyMilliseconds,
          "hours": hourlyMilliseconds,
        }),
        flush: true,
      );
      try {
        if (!_preserveBackup) {
          if (await backup.exists()) await backup.delete();
          if (await target.exists()) await target.rename(backup.path);
        }
        await temporary.rename(target.path);
        _preserveBackup = false;
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.copy(target.path);
        }
        rethrow;
      } finally {
        if (await temporary.exists()) {
          try {
            await temporary.delete();
          } catch (_) {}
        }
      }
    } catch (error, trace) {
      LOGGER.e("[statistics] failed to save: $error", stackTrace: trace);
      rethrow;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
