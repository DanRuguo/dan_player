import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:path/path.dart' as path;

/// Unified disposable lyric snapshots, separate from user edits/calibration.
/// The historical class/directory name remains compatible with existing data.
/// Only raw timestamps are saved; each consumer receives a fresh lyric model.
class OnlineLyricCache {
  OnlineLyricCache({
    Future<Directory> Function()? directory,
    int totalBytesLimit = maxTotalBytes,
  })  : _totalBytesLimit = totalBytesLimit,
        _directory = directory ??
            (() async => Directory(path.join(
                (await getAppDataDir()).path, 'cache', 'online_lyrics')));

  static final instance = OnlineLyricCache();
  final Future<Directory> Function() _directory;
  final int _totalBytesLimit;

  /// Committed identities; an empty set invalidates all entries after eviction.
  final changes = ValueNotifier<Set<String>>(const {});
  final _pending = <String, _PendingLyricLookup>{};
  static const maxEntryBytes = 2 * 1024 * 1024;
  static const maxTotalBytes = 64 * 1024 * 1024;
  Future<void> _pendingWrite = Future.value();
  String? _inventoryDirectory;
  DateTime? _lastReconcile;
  int _knownTotalBytes = 0;
  final _inventory = <String, (int, DateTime)>{};

  /// Read a saved result without starting or waiting for a provider request.
  /// Automatic playback must still reach local lyrics during a slow refresh.
  Future<Lyric?> read(String identity,
      {String Function()? legacyIdentity}) async {
    final key = sha256.convert(utf8.encode(identity)).toString();
    try {
      final file = File(path.join((await _directory()).path, '$key.json'));
      if (await file.exists() && await file.length() <= maxEntryBytes) {
        final snapshot =
            LyricSnapshot.fromJson(jsonDecode(await file.readAsString()));
        final lyric = snapshot?.toLyric();
        if (lyric != null && hasLyricContent(lyric)) return lyric;
      }
    } catch (_) {}
    if (legacyIdentity == null) return null;
    final legacy = await read(legacyIdentity());
    if (legacy == null) return null;
    // Promotion is maintenance, not part of playback. It can join an active
    // manual refresh, whose newer snapshot must win without delaying old lyrics.
    resolve(identity, () async => legacy).ignore();
    return legacy;
  }

  Future<Lyric?> resolve(String identity, Future<Lyric?> Function() fetch,
      {bool refresh = false, bool Function()? shouldStore}) async {
    final key = sha256.convert(utf8.encode(identity)).toString();
    // Serialize a forced refresh after a pending lookup so the older response
    // cannot overwrite the new choice. Ordinary readers share the same fetch.
    final pending = _pending[key];
    // A playback generation or manual choice may already have superseded the
    // owner. Its provider can still be running, but cannot commit its result.
    final previous = pending?.isCurrent == true ? pending : null;
    if (!refresh && previous != null) {
      LyricSnapshot? snapshot;
      try {
        snapshot = await previous.future;
      } catch (_) {
        if (previous.isCurrent) rethrow;
      }
      if (shouldStore?.call() == false) return null;
      if (!previous.isCurrent) {
        return resolve(identity, fetch, shouldStore: shouldStore);
      }
      return snapshot?.toLyric();
    }
    final future = () async {
      if (refresh && previous != null) {
        try {
          await previous.future;
        } catch (_) {}
      }
      return _resolve(key, identity, fetch, refresh, shouldStore);
    }();
    final lookup = _PendingLyricLookup(future, shouldStore);
    _pending[key] = lookup;
    try {
      return (await future)?.toLyric();
    } finally {
      if (identical(_pending[key], lookup)) _pending.remove(key);
    }
  }

  Future<LyricSnapshot?> _resolve(
      String key,
      String identity,
      Future<Lyric?> Function() fetch,
      bool refresh,
      bool Function()? shouldStore) async {
    File? file;
    try {
      file = File(path.join((await _directory()).path, '$key.json'));
      if (!refresh && await file.exists()) {
        if (await file.length() <= maxEntryBytes) {
          final value =
              LyricSnapshot.fromJson(jsonDecode(await file.readAsString()));
          if (value != null && hasLyricContent(value.toLyric())) return value;
        }
      }
    } catch (_) {
      // Missing, corrupt or inaccessible cache never prevents lyric playback.
    }
    final lyric = await fetch();
    if (lyric == null || !hasLyricContent(lyric)) return null;
    if (shouldStore?.call() == false) return null;
    final snapshot = LyricSnapshot.capture(lyric);
    if (file == null) return snapshot;
    // Provider work and saved reads stay concurrent. Only atomic commits and
    // their shared byte inventory use the same order, as comments snapshots do.
    final write = _pendingWrite
        .then((_) => _write(file!, identity, snapshot, shouldStore));
    _pendingWrite =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }

  Future<LyricSnapshot?> _write(File file, String identity,
      LyricSnapshot snapshot, bool Function()? shouldStore) async {
    File? temporary;
    try {
      // The owner was checked before enqueueing and is checked again after
      // the temporary write, immediately before its atomic commit.
      final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
      if (bytes.length > maxEntryBytes || bytes.length > _totalBytesLimit) {
        return snapshot;
      }
      final existed = await file.parent.exists();
      await file.parent.create(recursive: true);
      final now = DateTime.now();
      if (!existed ||
          _inventoryDirectory != file.parent.path ||
          _lastReconcile == null ||
          now.difference(_lastReconcile!) >= const Duration(minutes: 10)) {
        await _reconcile(file.parent);
      }
      if (await file.exists() &&
          await file.length() == bytes.length &&
          listEquals(await file.readAsBytes(), bytes)) {
        if (shouldStore?.call() == false) return null;
        await _prune(file.path);
        return snapshot;
      }
      temporary = File(
          '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (shouldStore?.call() == false) return null;
      await temporary.rename(file.path);
      final committed = await file.stat();
      if (committed.type != FileSystemEntityType.file) {
        throw const FileSystemException('Lyric cache commit disappeared');
      }
      // Replace the recorded size, not an externally damaged old file's size.
      // The inventory already counted the old snapshot at its previous length.
      _knownTotalBytes += committed.size - (_inventory[file.path]?.$1 ?? 0);
      _inventory[file.path] = (committed.size, committed.modified);
      changes.value = {identity};
      await _prune(file.path);
    } catch (_) {
      _inventoryDirectory = null;
      _lastReconcile = null;
      _inventory.clear();
      _knownTotalBytes = 0;
      // A read-only/full disk should still display the fetched lyrics.
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
    return snapshot;
  }

  Future<void> _reconcile(Directory directory) async {
    final inventory = <String, (int, DateTime)>{};
    var size = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final stat = await entry.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      size += stat.size;
      inventory[entry.path] = (stat.size, stat.modified);
    }
    _inventory
      ..clear()
      ..addAll(inventory);
    _knownTotalBytes = size;
    _inventoryDirectory = directory.path;
    _lastReconcile = DateTime.now();
  }

  Future<void> _prune(String keep) async {
    if (_knownTotalBytes <= _totalBytesLimit) return;
    final entries = _inventory.entries.toList()
      ..sort((a, b) => a.value.$2.compareTo(b.value.$2));
    var removed = false;
    for (final entry in entries) {
      if (_knownTotalBytes <= _totalBytesLimit) break;
      if (entry.key == keep) continue;
      final file = File(entry.key);
      if (await file.exists()) await file.delete();
      _inventory.remove(entry.key);
      _knownTotalBytes -= entry.value.$1;
      removed = true;
    }
    if (removed) changes.value = <String>{};
  }
}

class _PendingLyricLookup {
  const _PendingLyricLookup(this.future, this.shouldStore);

  final Future<LyricSnapshot?> future;
  final bool Function()? shouldStore;
  bool get isCurrent => shouldStore?.call() ?? true;
}
