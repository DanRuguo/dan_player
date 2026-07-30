import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path_util;

class CoverCacheEntry {
  const CoverCacheEntry(this.path, this.modified);

  final String path;
  final int modified;
}

/// Stores resized cover images so Rust does not repeatedly decode embedded art.
class CoverCache {
  CoverCache._();

  static final CoverCache instance = CoverCache._();
  static const int _schemaVersion = 2;

  Directory? _dir;
  final Map<String, Future<ImageProvider?>> _inflight = {};
  final Map<String, int> _generations = {};
  int _epoch = 0;

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
  ) {
    final generation = _generations[audioPath] ?? 0;
    return "v${_schemaVersion}_${stableHash(audioPath)}_${modified}_"
        "e${_epoch}g${generation}_${width}x$height.png";
  }

  Future<ImageProvider?> imageFor({
    required String audioPath,
    required int modified,
    required int width,
    required int height,
    required Future<Uint8List?> Function() produce,
  }) {
    final key = _fileName(audioPath, modified, width, height);
    final existing = _inflight[key];
    if (existing != null) return existing;

    final request = _loadOrCreate(key, produce);
    _inflight[key] = request;
    request.whenComplete(() => _inflight.remove(key));
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

      final bytes = await produce();
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
          "v${_schemaVersion}_${stableHash(entry.path)}_${entry.modified}_",
      };
      final dir = await _cacheDir();
      var removed = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = path_util.basename(entity.path);
        final isValid = validPrefixes.any((prefix) => name.startsWith(prefix));
        if (name.endsWith(".tmp") || !isValid) {
          try {
            await entity.delete();
            removed++;
          } catch (_) {}
        }
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
