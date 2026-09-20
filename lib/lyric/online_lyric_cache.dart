import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:path/path.dart' as path;

/// Disposable online results, separate from user edits and calibrated copies.
/// Only raw timestamps are saved; each consumer receives a fresh lyric model.
class OnlineLyricCache {
  OnlineLyricCache({Future<Directory> Function()? directory})
      : _directory = directory ??
            (() async => Directory(path.join(
                (await getAppDataDir()).path, 'cache', 'online_lyrics')));

  static final instance = OnlineLyricCache();
  final Future<Directory> Function() _directory;
  final _pending = <String, Future<LyricSnapshot?>>{};
  static const maxEntryBytes = 2 * 1024 * 1024;
  static const maxTotalBytes = 64 * 1024 * 1024;
  DateTime? _lastPrune;

  Future<Lyric?> resolve(String identity, Future<Lyric?> Function() fetch,
      {bool refresh = false}) async {
    final key = sha256.convert(utf8.encode(identity)).toString();
    // Serialize a forced refresh after a pending lookup so the older response
    // cannot overwrite the new choice. Ordinary readers share the same fetch.
    final previous = _pending[key];
    if (!refresh && previous != null) {
      return (await previous)?.toLyric();
    }
    final future = () async {
      if (refresh && previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      return _resolve(key, fetch, refresh);
    }();
    _pending[key] = future;
    try {
      return (await future)?.toLyric();
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<LyricSnapshot?> _resolve(
      String key, Future<Lyric?> Function() fetch, bool refresh) async {
    File? file;
    try {
      file = File(path.join((await _directory()).path, '$key.json'));
      if (!refresh && await file.exists()) {
        if (await file.length() <= maxEntryBytes) {
          final value =
              LyricSnapshot.fromJson(jsonDecode(await file.readAsString()));
          if (value != null && value.toLyric().lines.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // Missing, corrupt or inaccessible cache never prevents lyric playback.
    }
    final lyric = await fetch();
    if (lyric == null || lyric.lines.isEmpty) return null;
    final snapshot = LyricSnapshot.capture(lyric);
    if (file != null) {
      File? temporary;
      try {
        final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
        if (bytes.length <= maxEntryBytes) {
          await file.parent.create(recursive: true);
          temporary = File(
              '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(file.path);
          await _prune(file.parent, file.path);
        }
      } catch (_) {
        // A read-only/full disk should still display the fetched lyrics.
      } finally {
        try {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        } catch (_) {}
      }
    }
    return snapshot;
  }

  Future<void> _prune(Directory directory, String keep) async {
    final now = DateTime.now();
    if (_lastPrune != null &&
        now.difference(_lastPrune!) < const Duration(minutes: 10)) {
      return;
    }
    _lastPrune = now;
    final entries = <(File, FileStat)>[];
    var size = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final stat = await entry.stat();
      size += stat.size;
      entries.add((entry, stat));
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in entries) {
      if (size <= maxTotalBytes) break;
      if (file.path == keep) continue;
      await file.delete();
      size -= stat.size;
    }
  }
}
