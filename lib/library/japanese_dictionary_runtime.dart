import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:path/path.dart' as p;

const japaneseDictionaryFileName = 'ipadic-reading.bin.gz';
const japaneseDictionaryBytes = 7180257;
const japaneseDictionarySha256 =
    'a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43';

/// These authenticated files form one data component and must be siblings.
const japaneseDictionaryDataFiles = <({String name, int bytes, String sha256})>[
  (
    name: japaneseDictionaryFileName,
    bytes: japaneseDictionaryBytes,
    sha256: japaneseDictionarySha256,
  ),
  (
    name: 'supplemental-reading-v1.json.gz',
    bytes: 3618558,
    sha256: 'f4bf033fb622280875be6199d20d44fe2307310ea41b403a37f30c6b3a23a772',
  ),
  (
    name: 'kanji-reading-v1.json.gz',
    bytes: 106686,
    sha256: '18c12298210019c8b620287b0c995ca30d8fad73542ef46d395736f4e29e49d3',
  ),
];

/// Do not discover or install through a directory link, including an ancestor
/// junction. Missing directories are allowed only before creating an install.
Future<bool> isJapaneseDictionaryDirectoryPathSafe(String directory,
    {bool allowMissing = false}) async {
  try {
    var current = p.normalize(p.absolute(directory));
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          !(allowMissing && type == FileSystemEntityType.notFound)) {
        return false;
      }
      final parent = p.dirname(current);
      if (p.equals(parent, current)) return true;
      current = parent;
    }
  } catch (_) {
    return false;
  }
}

class JapaneseDictionaryUnavailable implements Exception {
  const JapaneseDictionaryUnavailable();
}

/// Discovers existing, authenticated data only. Downloads always belong to an
/// explicit UI action. The native loader verifies the same hash before parsing.
class JapaneseDictionaryRuntime {
  JapaneseDictionaryRuntime({this.installRoot, this.applicationDirectory});
  static final shared = JapaneseDictionaryRuntime();
  final Directory? installRoot, applicationDirectory;
  String? _ready;
  Map<String, FileStat>? _readyStats;
  Future<String?>? _pending;

  Future<Directory> get installDirectory async =>
      installRoot ??
      Directory(
          p.join((await getAppDataDir()).path, 'tools', 'japanese_readings'));

  void invalidate() {
    _ready = null;
    _readyStats = null;
  }

  Future<bool> ensure({bool force = false}) async {
    if (force) {
      // An installation may finish while the previous missing-file scan is
      // still in flight. Join that scan, then verify the new bytes separately.
      final pending = _pending;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // A previous location's failure must not prevent a fresh discovery.
        }
      }
      invalidate();
    }
    return await dictionaryPath() != null;
  }

  Future<bool> inspect() => ensure();

  Future<String?> dictionaryPath() =>
      _pending ??= _discover().whenComplete(() => _pending = null);

  Future<bool> validateDirectory(String directory) async =>
      await _authenticatedStats(directory) != null;

  Future<Map<String, FileStat>?> _dataStats(String directory) async {
    try {
      if (!await isJapaneseDictionaryDirectoryPathSafe(directory)) return null;
      final stats = <String, FileStat>{};
      for (final data in japaneseDictionaryDataFiles) {
        final file = File(p.join(directory, data.name));
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          return null;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file || stat.size != data.bytes) {
          return null;
        }
        stats[data.name] = stat;
      }
      return stats;
    } catch (_) {
      return null;
    }
  }

  bool _sameStats(Map<String, FileStat> a, Map<String, FileStat> b) =>
      japaneseDictionaryDataFiles.every((data) {
        final before = a[data.name], after = b[data.name];
        return before != null &&
            after != null &&
            before.type == after.type &&
            before.size == after.size &&
            before.modified == after.modified &&
            before.changed == after.changed &&
            before.mode == after.mode;
      });

  Future<Map<String, FileStat>?> _authenticatedStats(String directory) async {
    final before = await _dataStats(directory);
    if (before == null) return null;
    try {
      for (final data in japaneseDictionaryDataFiles) {
        final file = File(p.join(directory, data.name));
        if ((await sha256.bind(file.openRead()).first).toString() !=
            data.sha256) {
          return null;
        }
      }
      // Cache only the snapshot whose bytes were checked. A file changed or
      // replaced during verification must be rediscovered on a later call.
      final after = await _dataStats(directory);
      return after != null && _sameStats(before, after) ? after : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _discover() async {
    if (_ready != null) {
      final now = await _dataStats(p.dirname(_ready!));
      if (now != null && _readyStats != null && _sameStats(_readyStats!, now)) {
        return _ready;
      }
      invalidate();
    }
    final app =
        applicationDirectory?.path ?? p.dirname(Platform.resolvedExecutable);
    final portable = await _discoverDirectories({
      p.join(app, 'tool', 'japanese_readings'),
      p.join(app, 'tools', 'japanese_readings'),
    });
    if (portable != null) return portable;
    return _discoverDirectories({(await installDirectory).path});
  }

  Future<String?> _discoverDirectories(Iterable<String> directories) async {
    for (final directory in directories) {
      final stats = await _authenticatedStats(directory);
      if (stats == null) continue;
      final file = File(p.join(directory, japaneseDictionaryFileName));
      _readyStats = stats;
      return _ready = file.path;
    }
    return null;
  }
}
