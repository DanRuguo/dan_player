import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as path_util;

const String albumCollectionId = "__albums__";

final CustomAudioOrder customAudioOrder = CustomAudioOrder();

/// Read-only legacy projections for old route payloads. The Playlist tree is
/// the only editable/persisted source; collection files remain untouched.
List<UserCollection> get userCollections => List.unmodifiable([
      for (final playlist in playlistTree.allPlaylists)
        if (playlist.legacyCollectionKey != null)
          UserCollection(
            id: playlist.legacyCollectionId ?? playlist.id,
            name: playlist.name,
            audioPaths: List.unmodifiable([
              for (final entry in playlist.entries)
                if (entry.audio != null) entry.audio!.path,
            ]),
            imagePath: playlist.imagePath,
            createdAt: playlist.createdAt,
            modifiedAt: playlist.modifiedAt,
          ),
    ]);

Map<String, Audio> get _audioByPath => AudioLibrary.instance.audioByPath;

List<Audio> _defaultTimeSortedAudios() {
  final audios = List<Audio>.from(AudioLibrary.instance.audioCollection);
  audios.sort((a, b) {
    final created = b.created.compareTo(a.created);
    if (created != 0) return created;

    final modified = b.modified.compareTo(a.modified);
    if (modified != 0) return modified;

    return a.displayTitle.localeCompareTo(b.displayTitle);
  });
  return audios;
}

class CustomAudioOrder {
  List<String> _paths = [];

  List<String> get paths => List.unmodifiable(_paths);

  void rebuildDefault() {
    _paths = _defaultTimeSortedAudios().map((audio) => audio.path).toList();
  }

  bool sanitize({bool rebuildWhenBroken = false}) {
    if (rebuildWhenBroken || _paths.isEmpty) {
      rebuildDefault();
      return true;
    }

    bool changed = false;
    final seen = <String>{};
    final sanitized = <String>[];

    for (final path in _paths) {
      // Temporary source loss must not erase a user's ordering. Explicit
      // deletion uses removePath; rendering simply skips unavailable objects.
      if (seen.add(path)) {
        sanitized.add(path);
      } else {
        changed = true;
      }
    }

    final known = sanitized.toSet();
    final newAudios = _defaultTimeSortedAudios()
        .where((audio) => !known.contains(audio.path))
        .map((audio) => audio.path);
    sanitized.addAll(newAudios);

    if (sanitized.length != _paths.length) changed = true;
    _paths = sanitized;
    return changed;
  }

  void applyTo(List<Audio> list) {
    sanitize();
    final byPath = _audioByPath;
    final ordered = <Audio>[];

    for (final path in _paths) {
      final audio = byPath[path];
      if (audio != null) ordered.add(audio);
    }

    list
      ..clear()
      ..addAll(ordered);
  }

  Future<void> setFromAudios(List<Audio> audios) async {
    final previous = List<String>.of(_paths);
    final incoming = audios.map((audio) => audio.path).toList();
    final supplied = incoming.toSet();
    final byPath = _audioByPath;
    var next = 0;
    _paths = [
      for (final previousPath in previous)
        if (!supplied.contains(previousPath) &&
            !byPath.containsKey(previousPath))
          previousPath
        else if (next < incoming.length)
          incoming[next++],
      ...incoming.skip(next),
    ];
    try {
      await saveCustomAudioOrder(rethrowOnError: true);
    } catch (error, trace) {
      _paths = previous;
      applyTo(audios);
      LOGGER.e(error, stackTrace: trace);
      showTextOnSnackBar('自定义顺序保存失败，原有顺序已恢复。');
    }
  }

  bool replacePath(String oldPath, String newPath) {
    bool changed = false;
    _paths = _paths.map((path) {
      if (path == oldPath) {
        changed = true;
        return newPath;
      }
      return path;
    }).toList();
    return changed;
  }

  bool removePath(String removedPath) {
    final before = _paths.length;
    _paths.removeWhere((path) => path_util.equals(path, removedPath));
    return _paths.length != before;
  }

  Map toMap() => {
        "version": 1,
        "paths": _paths,
      };

  bool tryReadFromMap(Map map) {
    final paths = map["paths"];
    if (paths is! List || paths.any((item) => item is! String)) {
      return false;
    }

    _paths = List<String>.from(paths);
    sanitize();
    return true;
  }
}

class UserCollection {
  UserCollection({
    required this.id,
    required this.name,
    required this.audioPaths,
    this.imagePath,
    required this.createdAt,
    required this.modifiedAt,
  });

  String id;
  String name;
  List<String> audioPaths;
  String? imagePath;
  int createdAt;
  int modifiedAt;

  List<Audio> get audios {
    final byPath = _audioByPath;
    return [
      for (final path in audioPaths)
        if (byPath[path] != null) byPath[path]!,
    ];
  }

  bool sanitize() {
    final byPath = _audioByPath;
    final seen = <String>{};
    final sanitized = <String>[];

    for (final path in audioPaths) {
      if (byPath.containsKey(path) && seen.add(path)) {
        sanitized.add(path);
      }
    }

    final changed = sanitized.length != audioPaths.length;
    audioPaths = sanitized;
    return changed;
  }

  bool replacePath(String oldPath, String newPath) {
    bool changed = false;
    audioPaths = audioPaths.map((path) {
      if (path == oldPath) {
        changed = true;
        return newPath;
      }
      return path;
    }).toList();
    if (changed) {
      modifiedAt = DateTime.now().millisecondsSinceEpoch;
    }
    return changed;
  }

  Map toMap() => {
        "id": id,
        "name": name,
        "audioPaths": audioPaths,
        "imagePath": imagePath,
        "createdAt": createdAt,
        "modifiedAt": modifiedAt,
      };

  factory UserCollection.fromMap(Map map) {
    final audioPaths = map["audioPaths"];
    if (audioPaths is! List || audioPaths.any((item) => item is! String)) {
      throw const FormatException("Invalid collection audioPaths");
    }

    return UserCollection(
      id: map["id"]?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: map["name"]?.toString() ?? "未命名合集",
      audioPaths: List<String>.from(audioPaths),
      imagePath: map["imagePath"]?.toString(),
      createdAt: map["createdAt"] ?? DateTime.now().millisecondsSinceEpoch,
      modifiedAt: map["modifiedAt"] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class CollectionEntry {
  const CollectionEntry._({
    required this.id,
    required this.name,
    required this.count,
    required this.modifiedAt,
    this.collection,
  });

  final String id;
  final String name;
  final int count;
  final int modifiedAt;
  final UserCollection? collection;

  bool get isAlbumCollection => id == albumCollectionId;

  factory CollectionEntry.albums() => CollectionEntry._(
        id: albumCollectionId,
        name: "专辑",
        count: AudioLibrary.instance.albumCollection.length,
        modifiedAt: 0,
      );

  factory CollectionEntry.user(UserCollection collection) => CollectionEntry._(
        id: collection.id,
        name: collection.name,
        count: collection.audioPaths.length,
        modifiedAt: collection.modifiedAt,
        collection: collection,
      );
}

List<CollectionEntry> allCollectionEntries() => [
      CollectionEntry.albums(),
      ...userCollections.map(CollectionEntry.user),
    ];

Future<void> readCustomAudioOrder() async {
  try {
    final store = await _customOrderStore();
    final paths = await store.read();
    if (paths == null) {
      customAudioOrder.rebuildDefault();
      await store.save(customAudioOrder.paths);
      return;
    }
    customAudioOrder._paths = List<String>.of(paths);
    if (customAudioOrder.sanitize()) await store.save(customAudioOrder.paths);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    // The fallback is only a usable in-memory view. A damaged order remains
    // on disk and further saves are blocked until recovery succeeds.
    customAudioOrder.rebuildDefault();
  }
}

Future<void> saveCustomAudioOrder({bool rethrowOnError = false}) async {
  try {
    await (await _customOrderStore()).save(customAudioOrder.paths);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    if (rethrowOnError) rethrow;
  }
}

CustomAudioOrderPersistence? _orderPersistence;
String? get customAudioOrderStorageWarning => _orderPersistence?.warning;

Future<CustomAudioOrderPersistence> _customOrderStore() async {
  final directory = await getAppDataDir();
  final file = File(path_util.join(directory.path, 'custom_audio_order.json'));
  if (_orderPersistence?.file.path != file.path) {
    _orderPersistence = CustomAudioOrderPersistence(file);
  }
  return _orderPersistence!;
}

/// The v1 order schema remains unchanged. The optional hook exercises commit
/// failures without changing filesystem permissions or real user data.
class CustomAudioOrderPersistence {
  CustomAudioOrderPersistence(this.file, {this.beforeReplace});
  final File file;
  final Future<void> Function()? beforeReplace;
  Future<void> _writes = Future.value();
  Future<List<String>?>? _reading;
  bool _loaded = false;
  bool _writable = true;
  bool _preserveBackup = false;
  String? warning;
  static const maxBytes = 32 * 1024 * 1024;

  Future<List<String>?> read() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  Future<List<String>?> _read() async {
    _loaded = false;
    await _writes;
    _writable = true;
    warning = null;
    _preserveBackup = false;
    Object? firstError;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > maxBytes) {
          throw const FormatException('自定义顺序文件超过 32 MiB。');
        }
        final text = await candidate.readAsString();
        if (utf8.encode(text).length > maxBytes) {
          throw const FormatException('自定义顺序文件超过 32 MiB。');
        }
        final value = jsonDecode(text);
        if (value is! Map ||
            (value['version'] ?? 1) != 1 ||
            value['paths'] is! List ||
            (value['paths'] as List).any((item) => item is! String)) {
          throw const FormatException('自定义顺序文件损坏。');
        }
        final paths = List<String>.from(value['paths']);
        _loaded = true;
        if (candidate.path != file.path) {
          _preserveBackup = true;
          await save(paths);
          warning = '自定义顺序已从备份恢复，损坏文件已保留。';
        }
        return paths;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      _loaded = true;
      _writable = false;
      warning = '自定义顺序读取失败；原文件和备份已保留，恢复前不会覆盖。';
      throw FormatException('$warning $firstError');
    }
    _loaded = true;
    return null;
  }

  Future<void> save(List<String> paths) async {
    final frozen = List<String>.of(paths);
    if (!_loaded) await read();
    if (!_writable) {
      throw StateError(warning ?? 'Custom order storage is protected');
    }
    final snapshot = jsonEncode({'version': 1, 'paths': frozen});
    if (utf8.encode(snapshot).length > maxBytes) {
      throw const FormatException('自定义顺序超过 32 MiB。');
    }
    final result = _writes.then((_) async {
      if (!_writable) throw StateError('Custom order storage is protected');
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      final backup = File('${file.path}.bak');
      await temporary.writeAsString(snapshot, flush: true);
      try {
        await beforeReplace?.call();
        if (!_preserveBackup && await file.exists()) {
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
        } else if (_preserveBackup && await file.exists()) {
          await file.rename(
              '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}');
        }
        await temporary.rename(file.path);
        _preserveBackup = false;
      } catch (_) {
        if (!await file.exists() && await backup.exists()) {
          await backup.copy(file.path);
        }
        rethrow;
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

/// Compatibility entry point. It shares an in-flight read with readPlaylists
/// and never sanitizes or rewrites the legacy collections.json source.
Future<void> readCollections() => readPlaylists();

/// Compatibility save for callers already editing the canonical Playlist tree.
/// Changes to legacy DTOs are not a second editable database.
Future<void> saveCollections() => savePlaylists();

String createCollectionId() => DateTime.now().microsecondsSinceEpoch.toString();
