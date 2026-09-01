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
    final byPath = _audioByPath;
    if (rebuildWhenBroken || _paths.isEmpty) {
      rebuildDefault();
      return true;
    }

    bool changed = false;
    final seen = <String>{};
    final sanitized = <String>[];

    for (final path in _paths) {
      if (byPath.containsKey(path) && seen.add(path)) {
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
    _paths = audios.map((audio) => audio.path).toList();
    await saveCustomAudioOrder();
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
      rebuildDefault();
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
    final supportPath = (await getAppDataDir()).path;
    final file = File("$supportPath\\custom_audio_order.json");
    if (!file.existsSync()) {
      customAudioOrder.rebuildDefault();
      await saveCustomAudioOrder();
      return;
    }

    final map = json.decode(await file.readAsString());
    if (map is! Map || !customAudioOrder.tryReadFromMap(map)) {
      await saveCustomAudioOrder();
      return;
    }

    if (customAudioOrder.sanitize()) {
      await saveCustomAudioOrder();
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    customAudioOrder.rebuildDefault();
    await saveCustomAudioOrder();
  }
}

Future<void> saveCustomAudioOrder({bool rethrowOnError = false}) async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final file = await File("$supportPath\\custom_audio_order.json")
        .create(recursive: true);
    await file.writeAsString(json.encode(customAudioOrder.toMap()));
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    if (rethrowOnError) rethrow;
  }
}

/// Compatibility entry point. It shares an in-flight read with readPlaylists
/// and never sanitizes or rewrites the legacy collections.json source.
Future<void> readCollections() => readPlaylists();

/// Compatibility save for callers already editing the canonical Playlist tree.
/// Changes to legacy DTOs are not a second editable database.
Future<void> saveCollections() => savePlaylists();

String createCollectionId() => DateTime.now().microsecondsSinceEpoch.toString();
