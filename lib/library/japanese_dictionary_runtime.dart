import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:path/path.dart' as p;

const japaneseDictionaryFileName = 'ipadic-reading.bin.gz';
const japaneseDictionaryBytes = 7180257;
const japaneseDictionarySha256 =
    'a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43';

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
  FileStat? _readyStat;
  Future<String?>? _pending;

  Future<Directory> get installDirectory async =>
      installRoot ??
      Directory(
          p.join((await getAppDataDir()).path, 'tools', 'japanese_readings'));

  void invalidate() {
    _ready = null;
    _readyStat = null;
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

  Future<bool> validateDirectory(String directory) async {
    final file = File(p.join(directory, japaneseDictionaryFileName));
    try {
      if (await FileSystemEntity.isLink(directory) ||
          await FileSystemEntity.isLink(file.path) ||
          await file.length() != japaneseDictionaryBytes) {
        return false;
      }
      return (await sha256.bind(file.openRead()).first).toString() ==
          japaneseDictionarySha256;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _discover() async {
    if (_ready != null) {
      final now = await File(_ready!).stat();
      if (now.type == FileSystemEntityType.file &&
          now.size == _readyStat?.size &&
          now.modified == _readyStat?.modified) {
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
      if (!await validateDirectory(directory)) continue;
      final file = File(p.join(directory, japaneseDictionaryFileName));
      _readyStat = await file.stat();
      return _ready = file.path;
    }
    return null;
  }
}
