import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart'
    show isBackgroundImageId;
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

class CategoryCoverException implements Exception {
  const CategoryCoverException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CategoryCoverRecord {
  const _CategoryCoverRecord({
    required this.kind,
    required this.groupId,
    required this.imageId,
  });

  final MusicCategoryKind kind;
  final String groupId;
  final String imageId;

  String get key => categoryCoverPersistenceKey(kind, groupId);

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'groupId': groupId,
        'imageId': imageId,
      };
}

/// Persists user-selected covers for generated category groups.
///
/// A category identity is derived from metadata, never translated display
/// text or list position. Selected files are routed through the same bounded,
/// decoded, content-addressed copy pipeline as custom background images; the
/// original file can therefore be moved or deleted after the import succeeds.
class CategoryCoverStore extends ChangeNotifier {
  CategoryCoverStore({
    required Future<Directory> Function() dataDirectory,
    BackgroundImageStore? imageStore,
  })  : _dataDirectory = dataDirectory,
        _images = imageStore ??
            BackgroundImageStore(
              directory: () async => Directory(path.join(
                  (await dataDirectory()).path, _managedDirectoryName)),
              persistedIds: () => _readPersistedImageIds(dataDirectory),
              maxStoredImages: 10000,
              maxStoredBytes: 512 * 1024 * 1024,
            );

  static final shared = CategoryCoverStore(dataDirectory: getAppDataDir);

  static const _storeFileName = 'category_covers.json';
  static const _managedDirectoryName = 'category-covers';
  static const _maxStoreBytes = 4 * 1024 * 1024;

  final Future<Directory> Function() _dataDirectory;
  final BackgroundImageStore _images;
  final Map<String, _CategoryCoverRecord> _records = {};
  final LinkedHashMap<String, Future<ImageProvider?>> _providers =
      LinkedHashMap<String, Future<ImageProvider?>>();
  final Set<String> _discardedRecordKeys = <String>{};
  Future<void> _operation = Future<void>.value();
  Future<void>? _loadOperation;
  bool _loaded = false;
  bool _preserveBackup = false;
  Object? _readError;
  int _revision = 0;

  int get revision => _revision;
  bool get isLoaded => _loaded;
  Object? get readError => _readError;

  String? coverIdFor(MusicCategoryGroup group) =>
      _records[group.persistenceKey]?.imageId;

  bool hasCover(MusicCategoryGroup group) => coverIdFor(group) != null;

  Future<ImageProvider?> imageFor(MusicCategoryGroup group) {
    final id = coverIdFor(group);
    if (id == null) return Future<ImageProvider?>.value();
    final cached = _providers.remove(id);
    final result = cached ?? _images.imageFor(id);
    _providers[id] = result;
    while (_providers.length > 256) {
      _providers.remove(_providers.keys.first);
    }
    return result;
  }

  Future<ImageProvider?> reread(MusicCategoryGroup group) async {
    await load();
    final id = coverIdFor(group);
    if (id == null) return null;
    _providers.remove(id);
    final image = await _images.reloadImage(id);
    _providers[id] = Future.value(image);
    while (_providers.length > 256) {
      _providers.remove(_providers.keys.first);
    }
    _revision++;
    notifyListeners();
    return image;
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    final pending = _loadOperation;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _load().whenComplete(() {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    });
    _loadOperation = operation;
    return operation;
  }

  Future<void> _load() async {
    final directory = (await _dataDirectory()).absolute;
    final primary = File(path.join(directory.path, _storeFileName));
    final backup = File('${primary.path}.bak');
    Object? firstError;
    Map<String, _CategoryCoverRecord>? loaded;
    var recovered = false;
    var found = false;
    for (final candidate in <File>[primary, backup]) {
      final kind =
          await FileSystemEntity.type(candidate.path, followLinks: false);
      if (kind == FileSystemEntityType.notFound) continue;
      found = true;
      try {
        if (kind != FileSystemEntityType.file ||
            await candidate.length() > _maxStoreBytes) {
          throw const FormatException('分类封面记录不可读');
        }
        final value = jsonDecode(await candidate.readAsString());
        final decoded = _decode(value);
        // A missing/unreadable managed image is not permission to erase a
        // manual choice. Targeted reread can recover it after restoration.
        loaded = decoded;
        recovered = path.equals(candidate.path, backup.path);
        break;
      } catch (error) {
        firstError ??= error;
      }
    }

    _loaded = true;
    if (loaded == null && found) {
      _readError = firstError ?? const FormatException('分类封面记录不可用');
      notifyListeners();
      return;
    }
    _records
      ..clear()
      ..addAll(loaded ?? const <String, _CategoryCoverRecord>{});
    _preserveBackup = recovered;
    _readError = null;
    _revision++;
    notifyListeners();
    if (_discardedRecordKeys.isNotEmpty) {
      try {
        // A structurally valid store remains usable when one managed image was
        // removed outside the app. Rewrite only the surviving records so the
        // missing reference is not re-read on every launch.
        await _commit(Map<String, _CategoryCoverRecord>.of(_records));
      } catch (_) {
        // Rendering already falls back safely. Keep the repair keys so the
        // next successful user mutation retries the same atomic cleanup.
      }
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operation.then((_) async {
      await load();
      if (_readError != null) {
        throw const CategoryCoverException('歌单读取尚未完成，请先修复数据文件并重新读取；原文件没有改动。');
      }
      return action();
    });
    _operation = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> setCover(MusicCategoryGroup group, String sourcePath) =>
      _serial(() async {
        ManagedBackgroundImage imported;
        try {
          imported = await _images.importFile(sourcePath);
        } on BackgroundImageException catch (error) {
          throw CategoryCoverException(error.message);
        }
        // A prior read can have cached a null provider after the managed copy
        // disappeared. Re-importing identical bytes restores the same content
        // id, so invalidate that negative result before publishing the record.
        _providers.remove(imported.id);
        final next = Map<String, _CategoryCoverRecord>.of(_records);
        next[group.persistenceKey] = _CategoryCoverRecord(
          kind: group.kind,
          groupId: group.id,
          imageId: imported.id,
        );
        try {
          await _commit(next);
        } catch (_) {
          await _cleanUnusedBestEffort();
          rethrow;
        }
        await _cleanUnusedBestEffort();
      });

  Future<void> removeCover(MusicCategoryGroup group) => _serial(() async {
        if (!_records.containsKey(group.persistenceKey)) return;
        final next = Map<String, _CategoryCoverRecord>.of(_records)
          ..remove(group.persistenceKey);
        await _commit(next, scrubBackupKeys: <String>{group.persistenceKey});
        await _cleanUnusedBestEffort();
      });

  /// Removes covers for groups of [kind] that no longer contain any songs.
  /// Other kinds remain untouched because some projections (notably language)
  /// are populated lazily and cannot safely be inferred from an inactive tab.
  Future<void> reconcileKind(
          MusicCategoryKind kind, Iterable<MusicCategoryGroup> activeGroups) =>
      _serial(() async {
        final active = <String>{
          for (final group in activeGroups)
            if (group.kind == kind) group.persistenceKey,
        };
        final stale = <String>{
          for (final entry in _records.entries)
            if (entry.value.kind == kind && !active.contains(entry.key))
              entry.key,
        };
        if (stale.isEmpty) return;
        final next = Map<String, _CategoryCoverRecord>.of(_records)
          ..removeWhere((key, _) => stale.contains(key));
        await _commit(next, scrubBackupKeys: stale);
        await _cleanUnusedBestEffort();
      });

  Future<void> _commit(
    Map<String, _CategoryCoverRecord> next, {
    Set<String> scrubBackupKeys = const <String>{},
  }) async {
    final repairKeys = <String>{
      ..._discardedRecordKeys,
      ...scrubBackupKeys,
    };
    final directory = (await _dataDirectory()).absolute;
    await directory.create(recursive: true);
    final primary = File(path.join(directory.path, _storeFileName));
    final backup = File('${primary.path}.bak');
    final temporary = File('${primary.path}.tmp');
    final contents = jsonEncode(<String, Object?>{
      'version': 1,
      'covers': <String, Object?>{
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      },
    });
    await temporary.writeAsString(contents, flush: true);
    try {
      if (_preserveBackup) {
        if (await primary.exists()) await primary.delete();
      } else {
        if (await backup.exists()) await backup.delete();
        if (await primary.exists()) await primary.rename(backup.path);
      }
      await temporary.rename(primary.path);
      _preserveBackup = false;
    } catch (_) {
      if (!await primary.exists() && await backup.exists()) {
        await backup.copy(primary.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }

    _records
      ..clear()
      ..addAll(next);
    final retainedImageIds =
        next.values.map((record) => record.imageId).toSet();
    _providers.removeWhere((id, _) => !retainedImageIds.contains(id));
    _revision++;
    notifyListeners();
    if (repairKeys.isNotEmpty) {
      await _scrubBackup(directory, repairKeys);
      _discardedRecordKeys.removeAll(repairKeys);
    }
  }

  Future<void> _scrubBackup(Directory directory, Set<String> keys) async {
    final backup = File('${path.join(directory.path, _storeFileName)}.bak');
    if (!await backup.exists()) return;
    try {
      final decoded = _decode(jsonDecode(await backup.readAsString()));
      if (!decoded.keys.any(keys.contains)) return;
      decoded.removeWhere((key, _) => keys.contains(key));
      final temporary = File('${backup.path}.scrub.tmp');
      await temporary.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 1,
            'covers': <String, Object?>{
              for (final entry in decoded.entries)
                entry.key: entry.value.toJson(),
            },
          }),
          flush: true);
      await _replaceSingleFile(temporary, backup);
    } catch (_) {
      // Keep a usable recovery snapshot. Cleanup reads both snapshots and will
      // retain its image until a later successful write can scrub the record.
    }
  }

  static Future<void> _replaceSingleFile(File temporary, File target) async {
    final previous = File('${target.path}.previous.tmp');
    try {
      if (await previous.exists()) await previous.delete();
      if (await target.exists()) await target.rename(previous.path);
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _cleanUnusedBestEffort() async {
    try {
      await _images.removeUnused(
          () => _records.values.map((record) => record.imageId).toSet());
    } catch (_) {
      // Cleanup is conservative and retryable; it must never roll back a
      // successfully persisted user selection or make the UI appear to fail.
    }
  }

  static Map<String, _CategoryCoverRecord> _decode(Object? value) {
    if (value is! Map || value['version'] != 1 || value['covers'] is! Map) {
      throw const FormatException('分类封面记录格式无效');
    }
    final covers = value['covers'] as Map;
    if (covers.length > 10000) {
      throw const FormatException('分类封面记录数量异常');
    }
    final result = <String, _CategoryCoverRecord>{};
    for (final entry in covers.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('分类封面条目无效');
      }
      final map = entry.value as Map;
      final kindName = map['kind'];
      final groupId = map['groupId'];
      final imageId = map['imageId'];
      if (kindName is! String ||
          groupId is! String ||
          groupId.isEmpty ||
          groupId.length > 32768 ||
          imageId is! String ||
          !isBackgroundImageId(imageId)) {
        throw const FormatException('分类封面条目字段无效');
      }
      final matches =
          MusicCategoryKind.values.where((kind) => kind.name == kindName);
      if (matches.isEmpty) throw const FormatException('分类封面类型无效');
      final record = _CategoryCoverRecord(
          kind: matches.first, groupId: groupId, imageId: imageId);
      if (entry.key != record.key || result.containsKey(record.key)) {
        throw const FormatException('分类封面身份无效');
      }
      result[record.key] = record;
    }
    return result;
  }

  static Future<Set<String>> _readPersistedImageIds(
      Future<Directory> Function() dataDirectory) async {
    final directory = (await dataDirectory()).absolute;
    final result = <String>{};
    for (final name in <String>[
      _storeFileName,
      '$_storeFileName.bak',
    ]) {
      final file = File(path.join(directory.path, name));
      final kind = await FileSystemEntity.type(file.path, followLinks: false);
      if (kind == FileSystemEntityType.notFound) continue;
      if (kind != FileSystemEntityType.file ||
          await file.length() > _maxStoreBytes) {
        throw const CategoryCoverException('已保存分类封面记录不可读，暂不清理副本。');
      }
      final records = _decode(jsonDecode(await file.readAsString()));
      result.addAll(records.values.map((record) => record.imageId));
    }
    return result;
  }
}
