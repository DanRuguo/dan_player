import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/play_service/eq_preset_store.dart';
import 'package:dan_player/play_service/named_queue_store.dart';
import 'package:path/path.dart' as p;

/// Runs before stores, playback and folder watchers start. The existing backup
/// format preserves assets and path mappings; the marker commits only afterward.
class Snapshot3Upgrade {
  static void validateDocument(String name, Object? raw) {
    // Historical collection/order stores can be arrays.
    if (name == 'playlists.json' && raw is List) {
      decodePlaylists(raw);
      return;
    }
    const versions = {
      'playlists.json': 4,
      'smart_playlists.json': 2,
      'index.json': 113,
      'personal_library.json': 1,
      'named_queues.json': 1,
      'eq_presets.json': 1,
      'track_identities.json': 1,
      'lyric_documents.json': 1,
      'playback_bookmarks.json': 1,
      'playback_statistics.json': 2,
      'playback_statistics.pre-track-id-v1.json': 2,
    };
    final maxVersion = versions[name];
    if (maxVersion == null) {
      if (raw is! Map && raw is! List)
        throw FormatException('Invalid data document: $name');
      return;
    }
    if (raw is! Map) throw FormatException('Invalid data document: $name');
    final version = raw['version'];
    if (version is int && version > maxVersion) {
      throw UnsupportedError('Newer data format: $name');
    }
    switch (name) {
      case 'personal_library.json':
        PersonalLibrary.validate(Map<String, dynamic>.from(raw));
      case 'named_queues.json':
        NamedQueueStore.validate(Map<String, dynamic>.from(raw));
      case 'eq_presets.json':
        EqPresetStore.validate(Map<String, dynamic>.from(raw));
      case 'playlists.json':
        decodePlaylists(raw);
      case 'smart_playlists.json':
        if (![1, 2].contains(version) || raw['playlists'] is! List)
          throw const FormatException('Invalid smart playlists');
        for (final value in raw['playlists'] as List) {
          SmartPlaylist.fromJson(value);
        }
    }
  }

  static Future<void> prepare(Directory directory) =>
      LibraryMutationGate.shared.run(() async {
        final marker = File(p.join(directory.path, 'snapshot3_upgrade.json'));
        var prepared = false;
        if (await marker.exists()) {
          final saved = jsonDecode(await marker.readAsString());
          if (saved is! Map ||
              saved['version'] != 1 ||
              saved['target'] != '26.0.5-snapshot.3')
            throw const FormatException('Invalid upgrade record');
          prepared = true;
        }
        final files = <File>[];
        for (final name in {
          ...LibraryDataMigration.names,
          'smart_playlists.json'
        }) {
          final file = File(p.join(directory.path, name));
          if (!await file.exists()) continue;
          if (await file.length() > 128 * 1024 * 1024)
            throw FormatException('Data file exceeds capacity: $name');
          try {
            validateDocument(name, jsonDecode(await file.readAsString()));
          } on UnsupportedError {
            rethrow;
          } catch (_) {
            final backup = File('${file.path}.bak');
            if (!await backup.exists()) rethrow;
            validateDocument(name, jsonDecode(await backup.readAsString()));
            // Preserve damaged primary and make the valid backup readable to the
            // existing exporter. A failed rename/copy blocks normal startup.
            await file.rename(
                '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}');
            await backup.copy(file.path);
          }
          files.add(file);
        }
        if (prepared) return;
        final before = <String, String>{};
        for (final file in files) {
          before[file.path] =
              (await sha256.bind(file.openRead()).first).toString();
        }
        final destination = File(p.join(
            directory.parent.path,
            '${p.basename(directory.path)}-upgrade-backups',
            'before-26.0.5-snapshot.3-${DateTime.now().microsecondsSinceEpoch}.zip'));
        await const CacheBackupService()
            .exportBackup(source: directory, destination: destination);
        for (final file in files) {
          if (!await file.exists() ||
              (await sha256.bind(file.openRead()).first).toString() !=
                  before[file.path])
            throw StateError('资料在升级快照期间发生变化，请关闭其他播放器实例后重试');
        }
        final probe = File('${marker.path}.tmp');
        await probe.writeAsString(
            jsonEncode({
              'version': 1,
              'target': '26.0.5-snapshot.3',
              'backup': destination.path,
              'sha256':
                  (await sha256.bind(destination.openRead()).first).toString()
            }),
            flush: true);
        await probe.rename(marker.path);
      });
}
