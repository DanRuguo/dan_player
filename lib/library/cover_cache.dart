import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path_util;

class CoverCacheEntry {
  const CoverCacheEntry(this.path, this.modified, {this.fingerprint});

  final String path;
  final int modified;
  final String? fingerprint;
}

/// Stores resized cover images so Rust does not repeatedly decode embedded art.
class CoverCache {
  CoverCache._(
      {Directory? directory,
      this.maxEntries = 256,
      this.maxConcurrentReads = 2,
      this.maxDiskFiles = 2048,
      this.maxDiskBytes = 256 * 1024 * 1024,
      this.failureRetryDelay = const Duration(seconds: 30),
      DateTime Function()? clock})
      : assert(maxEntries >= 0),
        assert(maxConcurrentReads > 0),
        assert(maxDiskFiles >= 0),
        assert(maxDiskBytes >= 0),
        _clock = clock ?? DateTime.now,
        _dir = directory;

  /// Isolated caches let tests exercise limits without touching app data.
  factory CoverCache.forTesting(
          {required Directory directory,
          int maxEntries = 256,
          int maxConcurrentReads = 2,
          int maxDiskFiles = 2048,
          int maxDiskBytes = 256 * 1024 * 1024,
          Duration failureRetryDelay = const Duration(seconds: 30),
          DateTime Function()? clock}) =>
      CoverCache._(
          directory: directory,
          maxEntries: maxEntries,
          maxConcurrentReads: maxConcurrentReads,
          maxDiskFiles: maxDiskFiles,
          maxDiskBytes: maxDiskBytes,
          failureRetryDelay: failureRetryDelay,
          clock: clock);

  static final CoverCache instance = CoverCache._();
  // v3 uses cover-aware, no-upscale Lanczos thumbnails. Never reuse an old
  // contain/Triangle thumbnail whose shorter edge is already too small.
  static const int _schemaVersion = 3;

  final int maxEntries;
  final int maxConcurrentReads;
  final int maxDiskFiles;
  final int maxDiskBytes;
  final Duration failureRetryDelay;
  final DateTime Function() _clock;

  Directory? _dir;
  final Map<String, Future<ImageProvider?>> _inflight = {};
  final LinkedHashMap<String, Future<ImageProvider?>> _ready = LinkedHashMap();
  final LinkedHashMap<String, DateTime> _negativeUntil = LinkedHashMap();
  final Queue<Completer<void>> _readWaiters = Queue();
  int _activeReads = 0;
  final Map<String, int> _generations = {};
  int _epoch = 0;

  int get cachedProviderCount => _ready.length;
  int get activeReadCount => _activeReads;

  Future<Uint8List?> _produceBounded(
      Future<Uint8List?> Function() produce) async {
    if (_activeReads >= maxConcurrentReads) {
      final waiter = Completer<void>();
      _readWaiters.add(waiter);
      await waiter.future;
    } else {
      _activeReads++;
    }
    try {
      return await produce();
    } finally {
      if (_readWaiters.isEmpty) {
        _activeReads--;
      } else {
        _readWaiters.removeFirst().complete();
      }
    }
  }

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final support = await getAppDataDir();
    _dir = await Directory(path_util.join(support.path, "covers"))
        .create(recursive: true);
    return _dir!;
  }

  static String stableHash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  String _fileName(
    String audioPath,
    int modified,
    int width,
    int height,
    String? fingerprint,
  ) {
    final generation = _generations[audioPath] ?? 0;
    return "v${_schemaVersion}_${stableHash(audioPath)}_${_stamp(modified, fingerprint)}_"
        "e${_epoch}g${generation}_${width}x$height.png";
  }

  static String _stamp(int modified, String? fingerprint) => fingerprint == null
      ? '$modified'
      : '${modified}f${stableHash(fingerprint)}';

  Future<ImageProvider?> imageFor({
    required String audioPath,
    required int modified,
    String? fingerprint,
    required int width,
    required int height,
    required Future<Uint8List?> Function() produce,
  }) {
    final key = _fileName(audioPath, modified, width, height, fingerprint);
    final retryAt = _negativeUntil.remove(key);
    if (retryAt != null && retryAt.isAfter(_clock())) {
      _negativeUntil[key] = retryAt;
      return Future<ImageProvider?>.value(null);
    }
    final cached = _ready.remove(key);
    if (cached != null) {
      _ready[key] = cached;
      return cached;
    }
    final existing = _inflight[key];
    if (existing != null) return existing;

    final request = _loadOrCreate(key, produce);
    _inflight[key] = request;
    request.then<void>((image) {
      if (!identical(_inflight[key], request)) return;
      _inflight.remove(key);
      // FileImage keeps no decoded/source bytes alive. A disk-write fallback
      // MemoryImage belongs only to its current widget / Flutter ImageCache.
      if (image != null && image is! MemoryImage) {
        _negativeUntil.remove(key);
        _ready[key] = request;
        while (_ready.length > maxEntries) {
          _ready.remove(_ready.keys.first);
        }
      } else if (image == null && failureRetryDelay > Duration.zero) {
        _negativeUntil[key] = _clock().add(failureRetryDelay);
        while (_negativeUntil.length > (maxEntries == 0 ? 16 : maxEntries)) {
          _negativeUntil.remove(_negativeUntil.keys.first);
        }
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_inflight[key], request)) {
        _inflight.remove(key);
        if (failureRetryDelay > Duration.zero) {
          _negativeUntil[key] = _clock().add(failureRetryDelay);
        }
      }
    });
    return request;
  }

  Future<ImageProvider?> _loadOrCreate(
    String key,
    Future<Uint8List?> Function() produce,
  ) async {
    try {
      final dir = await _cacheDir();
      final file = File(path_util.join(dir.path, key));
      if (await file.exists()) {
        if (await file.length() > 0) return FileImage(file);
        await file.delete();
      }

      final bytes = await _produceBounded(produce);
      if (bytes == null || bytes.isEmpty) return null;
      if (!_inflight.containsKey(key)) {
        return MemoryImage(bytes);
      }

      final temporary = File("${file.path}.tmp");
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
        return FileImage(file);
      } catch (err) {
        LOGGER.w("[cover cache] write failed: $err");
        if (await temporary.exists()) {
          unawaited(temporary.delete().catchError((_) => temporary));
        }
        return MemoryImage(bytes);
      }
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      return null;
    }
  }

  Future<void> prune(Iterable<CoverCacheEntry> validEntries) async {
    try {
      final validPrefixes = <String>{
        for (final entry in validEntries)
          "v${_schemaVersion}_${stableHash(entry.path)}_${_stamp(entry.modified, entry.fingerprint)}_",
      };
      final dir = await _cacheDir();
      var removed = 0;
      final survivors = <({File file, int bytes, DateTime modified})>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = path_util.basename(entity.path);
        final epochMarker = name.indexOf('_e');
        final prefix =
            epochMarker < 0 ? '' : name.substring(0, epochMarker + 1);
        final isValid = validPrefixes.contains(prefix);
        if (name.endsWith(".tmp") || !isValid) {
          try {
            await entity.delete();
            removed++;
          } catch (_) {}
        } else {
          try {
            final stat = await entity.stat();
            survivors.add((
              file: entity,
              bytes: stat.size < 0 ? 0 : stat.size,
              modified: stat.modified,
            ));
          } catch (_) {}
        }
      }
      survivors.sort((a, b) => a.modified.compareTo(b.modified));
      var bytes = survivors.fold<int>(0, (sum, item) => sum + item.bytes);
      var files = survivors.length;
      for (final item in survivors) {
        if (files <= maxDiskFiles && bytes <= maxDiskBytes) break;
        // Never remove a file currently being produced/read by this process.
        final name = path_util.basename(item.file.path);
        if (_inflight.containsKey(name)) continue;
        try {
          await item.file.delete();
          files--;
          bytes -= item.bytes;
          _ready.remove(name);
          removed++;
        } catch (_) {}
      }
      if (removed > 0) {
        LOGGER.i("[cover cache] pruned $removed stale files");
      }
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  Future<void> invalidate(String audioPath) async {
    _generations[audioPath] = (_generations[audioPath] ?? 0) + 1;
    final hash = stableHash(audioPath);
    _inflight.removeWhere((key, _) => key.contains("_${hash}_"));
    _ready.removeWhere((key, _) => key.contains("_${hash}_"));
    _negativeUntil.removeWhere((key, _) => key.contains("_${hash}_"));

    try {
      final dir = await _cacheDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = path_util.basename(entity.path);
        if (!name.contains("_${hash}_") && !name.startsWith("${hash}_")) {
          continue;
        }
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  Future<void> clear() async {
    _epoch++;
    _generations.clear();
    _inflight.clear();
    _ready.clear();
    _negativeUntil.clear();

    try {
      final dir = await _cacheDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }
}
