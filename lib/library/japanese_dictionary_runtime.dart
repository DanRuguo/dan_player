import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:path/path.dart' as p;

const japaneseDictionaryFileName = 'ipadic-reading.bin.gz';
const japaneseDictionaryBytes = 5185623;
const japaneseDictionarySha256 =
    'bc2e100b3d11e41038dd3fbaacfbd843c081a3d18c6105320220b36a667b7ee9';

typedef JapaneseDictionaryFileSpec = ({String name, int bytes, String sha256});

/// Current compacted data component (DANIPAD3 + DANJPSUP v2).
const japaneseDictionaryDataFiles = <JapaneseDictionaryFileSpec>[
  (
    name: japaneseDictionaryFileName,
    bytes: japaneseDictionaryBytes,
    sha256: japaneseDictionarySha256,
  ),
  (
    name: 'supplemental-reading-v2.bin.gz',
    bytes: 1839924,
    sha256: '474cc3a94a8c270bf1512c32849ee85df2ef83cda130f1b9b331aa9b0134b74d',
  ),
  (
    name: 'kanji-reading-v1.json.gz',
    bytes: 106686,
    sha256: '18c12298210019c8b620287b0c995ca30d8fad73542ef46d395736f4e29e49d3',
  ),
];

/// Legacy v26.1.1 component retained so previously installed copies remain
/// valid without forced redownloading.
const japaneseDictionaryLegacyDataFiles = <JapaneseDictionaryFileSpec>[
  (
    name: japaneseDictionaryFileName,
    bytes: 7180257,
    sha256: 'a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43',
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

const _acceptedManifests = <List<JapaneseDictionaryFileSpec>>[
  japaneseDictionaryDataFiles,
  japaneseDictionaryLegacyDataFiles,
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

Future<bool> _canWriteJapaneseToolSubdirectory(String appDir) async {
  if (!await isJapaneseDictionaryDirectoryPathSafe(appDir)) return false;
  final toolRoot = Directory(p.join(appDir, 'tool'));
  if (!await isJapaneseDictionaryDirectoryPathSafe(toolRoot.path,
      allowMissing: true)) {
    return false;
  }
  Directory? probe;
  try {
    await toolRoot.create(recursive: true);
    probe = await toolRoot.createTemp('.danplayer-jp-probe-');
    return true;
  } catch (_) {
    return false;
  } finally {
    if (probe != null) {
      try {
        if (await probe.exists()) await probe.delete(recursive: true);
      } catch (_) {}
    }
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
  List<JapaneseDictionaryFileSpec>? _readyManifest;
  Future<String?>? _pending;

  bool get ready => _ready != null;

  /// Installs into `<appDir>/tool/japanese_readings` beside the player
  /// executable when writable, falling back to `<AppDataDir>/tool/japanese_readings`
  /// only when the application directory is read-only.
  Future<Directory> get installDirectory async {
    if (installRoot != null) return installRoot!;
    if (applicationDirectory != null) {
      if (await _canWriteJapaneseToolSubdirectory(applicationDirectory!.path)) {
        return Directory(
            p.join(applicationDirectory!.path, 'tool', 'japanese_readings'));
      }
    } else if (Platform.environment['FLUTTER_TEST'] != 'true') {
      final appDir = p.dirname(Platform.resolvedExecutable);
      if (await _canWriteJapaneseToolSubdirectory(appDir)) {
        return Directory(p.join(appDir, 'tool', 'japanese_readings'));
      }
    }
    return Directory(
        p.join((await getAppDataDir()).path, 'tool', 'japanese_readings'));
  }

  void invalidate() {
    _ready = null;
    _readyStats = null;
    _readyManifest = null;
  }

  Future<bool> ensure({bool force = false}) async {
    if (force) {
      final pending = _pending;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {}
      }
      invalidate();
    }
    return await dictionaryPath() != null;
  }

  Future<bool> inspect() => ensure(force: true);

  Future<String?> dictionaryPath() =>
      _pending ??= _discover().whenComplete(() => _pending = null);

  Future<bool> validateDirectory(String directory) async =>
      await _authenticatedStats(directory) != null;

  Future<Map<String, FileStat>?> _dataStatsForManifest(
    String directory,
    List<JapaneseDictionaryFileSpec> manifest,
  ) async {
    try {
      if (!await isJapaneseDictionaryDirectoryPathSafe(directory)) return null;
      final stats = <String, FileStat>{};
      for (final data in manifest) {
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

  bool _sameStats(
    List<JapaneseDictionaryFileSpec> manifest,
    Map<String, FileStat> a,
    Map<String, FileStat> b,
  ) =>
      manifest.every((data) {
        final before = a[data.name], after = b[data.name];
        return before != null &&
            after != null &&
            before.type == after.type &&
            before.size == after.size &&
            before.modified == after.modified &&
            before.changed == after.changed &&
            before.mode == after.mode;
      });

  Future<(List<JapaneseDictionaryFileSpec>, Map<String, FileStat>)?>
      _authenticatedStats(String directory) async {
    for (final manifest in _acceptedManifests) {
      final before = await _dataStatsForManifest(directory, manifest);
      if (before == null) continue;
      try {
        var matched = true;
        for (final data in manifest) {
          final file = File(p.join(directory, data.name));
          if ((await sha256.bind(file.openRead()).first).toString() !=
              data.sha256) {
            matched = false;
            break;
          }
        }
        if (!matched) continue;
        final after = await _dataStatsForManifest(directory, manifest);
        if (after != null && _sameStats(manifest, before, after)) {
          return (manifest, after);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _discover() async {
    if (_ready != null && _readyManifest != null && _readyStats != null) {
      final now =
          await _dataStatsForManifest(p.dirname(_ready!), _readyManifest!);
      if (now != null && _sameStats(_readyManifest!, _readyStats!, now)) {
        return _ready;
      }
      invalidate();
    }
    final app =
        applicationDirectory?.path ?? p.dirname(Platform.resolvedExecutable);
    final candidates = <String>{
      p.join(app, 'tool', 'japanese_readings'),
      p.join(app, 'tools', 'japanese_readings'),
      (await installDirectory).path,
    };
    try {
      final dataDir = (await getAppDataDir()).path;
      candidates.add(p.join(dataDir, 'tool', 'japanese_readings'));
      candidates.add(p.join(dataDir, 'tools', 'japanese_readings'));
    } catch (_) {}
    return _discoverDirectories(candidates);
  }

  Future<String?> _discoverDirectories(Iterable<String> directories) async {
    for (final directory in directories) {
      final verified = await _authenticatedStats(directory);
      if (verified == null) continue;
      final file = File(p.join(directory, japaneseDictionaryFileName));
      _readyManifest = verified.$1;
      _readyStats = verified.$2;
      return _ready = file.path;
    }
    return null;
  }
}
