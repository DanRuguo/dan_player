import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/data/snapshot3_upgrade.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:async';

import 'package:archive/archive_io.dart' hide ZLibEncoder, ZLibDecoder;
import 'package:crypto/crypto.dart';
import 'package:dan_player/data/app_data_location.dart';
import 'package:dan_player/data/backup_encryption.dart';
import 'package:dan_player/data/backup_selection.dart';
import 'package:dan_player/data/backup_restore_preservation.dart';
import 'package:path/path.dart' as path;

export 'backup_selection.dart';
part 'cache_backup_archive.dart';
part 'cache_backup_music.dart';

const _backupFormat = 'dan-player-cache-backup';
const _backupVersion = 2;
const _tokenPrefix = '@dan-player-backup/';

class CacheBackupException implements Exception {
  const CacheBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CacheBackupCancelled extends CacheBackupException {
  const CacheBackupCancelled() : super('Backup operation cancelled');
}

class CacheBackupPasswordRequired extends CacheBackupException {
  const CacheBackupPasswordRequired() : super('Password required');
}

class CacheBackupEncryptionTooLarge extends CacheBackupException {
  const CacheBackupEncryptionTooLarge()
      : super('Encrypted backup must be smaller than 64 GiB');
}

class CacheBackupResult {
  const CacheBackupResult(
      {required this.fileCount, required this.songCount, this.musicCount = 0});
  final int fileCount;
  final int songCount;
  final int musicCount;
}

class CacheRestoreResult {
  const CacheRestoreResult({
    required this.destination,
    required this.fileCount,
    required this.restoredSongs,
    required this.missingSongs,
    required this.restartRequired,
    this.musicCount = 0,
  });

  final Directory destination;
  final int fileCount;
  final int restoredSongs;
  final int missingSongs;
  final bool restartRequired;
  final int musicCount;
}

typedef CacheLocationActivator = Future<void> Function(
    Directory directory, Directory stagedDirectory);

/// Portable backup of the complete app-data tree.
///
/// The container is a ZIP with a `.bak` extension. JSON documents are rewritten
/// before they enter the container: library files use root-relative tokens and
/// app-data references use cache-relative tokens. External referenced assets
/// (for example a custom font or playlist cover) are copied into the backup.
class CacheBackupService {
  const CacheBackupService();

  Future<CacheBackupResult> exportBackup({
    required Directory source,
    required File destination,
    BackupSelection selection = const BackupSelection(),
    String? password,
    BackupOperation? operation,
  }) =>
      ProtectedJsonStore.withSnapshot(() async {
        try {
          final sourcePath = source.absolute.path;
          final destinationPath = destination.absolute.path;
          final options = selection.toMap();
          final result = await _runBackupOperation(
              operation,
              (control) => _exportBackupOnWorker(
                  sourcePath, destinationPath, options, password, control));
          return CacheBackupResult(
              fileCount: result[0],
              songCount: result[1],
              musicCount: result[2]);
        } on CacheBackupException {
          rethrow;
        } catch (error) {
          throw CacheBackupException('Could not create backup: $error');
        }
      });

  static Future<List<int>> _exportBackupOnWorker(
      String sourceDirectory,
      String destinationFile,
      Map<String, Object?> options,
      String? password,
      _BackupWorkerControl control) async {
    final selection = BackupSelection.fromMap(options);
    if (selection.isEmpty) throw const CacheBackupException('Nothing selected');
    final source = Directory(sourceDirectory);
    final destination = File(destinationFile);
    if (!await source.exists()) {
      throw const CacheBackupException('The app data directory does not exist');
    }
    for (final name in const [
      'metadata_committed.json',
      'metadata_committed.json.tmp',
      'library_migration.json',
      'library_migration.json.migration-tmp',
    ]) {
      if (await File(path.join(source.path, name)).exists()) {
        throw const CacheBackupException(
            'Complete the pending library/metadata synchronization before backup');
      }
    }
    final sourcePath = path.normalize(source.absolute.path);
    final destinationPath = path.normalize(destination.absolute.path);
    if (path.isWithin(sourcePath, destinationPath)) {
      throw const CacheBackupException(
          'A backup cannot be written inside the app data directory');
    }

    await destination.parent.create(recursive: true);
    final temporary =
        await destination.parent.createTemp('.dan-player-backup-');
    final payload = Directory(path.join(temporary.path, 'payload'));
    await payload.create(recursive: true);
    try {
      final index =
          await _tryReadJson(File(path.join(source.path, 'index.json')));
      final encoder = _PortablePathEncoder(
        sourceRoot: source,
        libraryRoots: _libraryRoots(index),
        payloadRoot: payload,
      );
      encoder.collectSongReferences(index);
      final music = await _MusicInventory.read(index);
      var musicCount = 0;

      await for (final entity
          in source.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: source.path);
        if (!_shouldIncludeCacheEntry(relative)) continue;
        if (!selection.components.contains(backupComponentForPath(relative)))
          continue;
        await control.check('collect');
        if (!_isSafeRelative(relative)) {
          throw const CacheBackupException('Unsafe cache entry path');
        }
        final output = File(path.join(payload.path, relative));
        await output.parent.create(recursive: true);
        final before = await entity.stat();
        final isJson = _looksLikeJson(relative);
        final decoded = isJson ? await _tryReadJson(entity) : null;
        if (isJson && decoded == null) {
          throw CacheBackupException(
              'A cache document is damaged: ${path.basename(relative)}');
        }
        if (isJson) {
          final portable = await encoder.convert(decoded);
          await _copyReferencedCacheAssets(portable, source, payload, control);
          await output.writeAsString(json.encode(portable), flush: true);
          if (_containsAbsolutePath(portable)) {
            throw CacheBackupException(
                'An absolute path remained in ${path.basename(relative)}');
          }
        } else {
          await entity.copy(output.path);
        }
        final after = await entity.stat();
        if (before.type != FileSystemEntityType.file ||
            after.type != FileSystemEntityType.file ||
            before.size != after.size ||
            before.modified != after.modified) {
          throw const CacheBackupException(
              'Cache changed while it was being backed up; please retry');
        }
      }

      final musicManifest = <Map<String, Object?>>[];
      for (final folder in music.folders) {
        if (!selection.includesFolder(folder.id)) continue;
        final files = <Map<String, Object?>>[];
        for (final song in folder.files) {
          final outputRelative =
              'restored-music/${folder.id}/${path.basename(song.path)}';
          if (!_isSafeRelative(outputRelative)) {
            throw CacheBackupException(
                'Unsafe music filename: ${path.basename(song.path)}');
          }
          final output = File(path.join(payload.path, outputRelative));
          await _checkedCopy(song, output, control);
          files.add({
            'path': outputRelative,
            'token': await encoder.convert(song.path),
            'name': path.basename(song.path),
            'size': await song.length(),
          });
          musicCount++;
        }
        musicManifest
            .add({'id': folder.id, 'name': folder.label, 'files': files});
      }

      final payloadFiles = <Map<String, Object?>>[];
      await for (final entity
          in payload.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative =
            _portableRelative(path.relative(entity.path, from: payload.path));
        payloadFiles.add(<String, Object?>{
          'path': relative,
          'size': await entity.length(),
          'sha256': await _fileDigest(entity),
        });
      }
      payloadFiles
          .sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));

      final manifest = <String, Object?>{
        'format': _backupFormat,
        'version': _backupVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'roots': encoder.rootManifest,
        'songs': encoder.songManifest,
        'files': payloadFiles,
        'components': selection.components.map((value) => value.name).toList(),
        'music': musicManifest,
      };
      await File(path.join(temporary.path, 'manifest.json'))
          .writeAsString(json.encode(manifest), flush: true);

      await destination.parent.create(recursive: true);
      final partial = File(
          '$destinationPath.${pid}_${DateTime.now().microsecondsSinceEpoch}.partial');
      try {
        final plain = password == null
            ? partial
            : File(path.join(temporary.path, 'archive.zip'));
        await _writeStreamingZip(temporary, plain, control);
        if (password != null) {
          await BackupEncryption.encrypt(plain, partial, password,
              checkpoint: (done, total) =>
                  control.check('encrypt', done, total));
        }
        await control.check('verify');
      } catch (_) {
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
      await _atomicReplaceFile(partial, destination);
      return <int>[
        payloadFiles.length,
        encoder.songManifest.length,
        musicCount
      ];
    } on BackupEncryptionLimitException {
      throw const CacheBackupEncryptionTooLarge();
    } on CacheBackupException {
      rethrow;
    } catch (error) {
      throw CacheBackupException('Could not create backup: $error');
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  Future<CacheRestoreResult> restoreBackup({
    required File backup,
    required Directory destination,
    required Directory currentData,
    CacheLocationActivator? activateLocation,
    BackupSelection? selection,
    String? password,
    BackupOperation? operation,
  }) async {
    Map<String, Object?> transaction;
    try {
      final backupPath = backup.absolute.path;
      final destinationPath = destination.absolute.path;
      final currentPath = currentData.absolute.path;
      final options = selection?.toMap();
      transaction = await _runBackupOperation(
          operation,
          (control) => _restoreBackupOnWorker(backupPath, destinationPath,
              currentPath, options, password, control));
    } on CacheBackupException {
      rethrow;
    } catch (error) {
      throw CacheBackupException('Could not restore backup: $error');
    }
    try {
      final staged = Directory(transaction['staged'] as String);
      if (activateLocation != null) {
        await activateLocation(destination, staged);
      }
    } catch (error) {
      try {
        await Isolate.run(() => _discardPreparedRestore(transaction));
      } catch (rollbackError) {
        throw CacheBackupException(
            'Cache location was not changed and staged cleanup failed: '
            '$rollbackError (original error: $error)');
      }
      if (error is CacheBackupException) rethrow;
      throw CacheBackupException('Cache location was not changed: $error');
    }
    if (activateLocation == null) {
      await Isolate.run(() => _discardPreparedRestore(transaction));
      throw const CacheBackupException(
          'A cache location activator is required for safe restore');
    }
    return CacheRestoreResult(
      destination: destination,
      fileCount: transaction['fileCount'] as int,
      restoredSongs: transaction['restoredSongs'] as int,
      missingSongs: transaction['missingSongs'] as int,
      restartRequired: true,
      musicCount: transaction['musicCount'] as int? ?? 0,
    );
  }

  static Future<Map<String, Object?>> _restoreBackupOnWorker(
      String backupFile,
      String destinationDirectory,
      String currentDirectory,
      Map<String, Object?>? options,
      String? password,
      _BackupWorkerControl control) async {
    final backup = File(backupFile);
    final destination = Directory(destinationDirectory);
    final currentData = Directory(currentDirectory);
    if (!await backup.exists()) {
      throw const CacheBackupException('The selected backup does not exist');
    }
    final targetPath = path.normalize(destination.absolute.path);
    if (!path.isAbsolute(targetPath) ||
        path.equals(targetPath, path.rootPrefix(targetPath))) {
      throw const CacheBackupException('Unsafe restore destination');
    }
    await destination.parent.create(recursive: true);
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final extraction = Directory(
        path.join(destination.parent.path, '.dan-player-restore-$nonce'));
    final staged = Directory(
        path.join(destination.parent.path, '.dan-player-pending-$nonce'));
    try {
      await extraction.create(recursive: true);
      final plain =
          await _openBackupEnvelope(backup, extraction, password, control);
      final manifest = await _readStreamingZip(plain, extraction, control,
          selection: options == null ? null : BackupSelection.fromMap(options));
      final payload = Directory(path.join(extraction.path, 'payload'));
      await payload.create(recursive: true);
      final files = await _verifyPayload(
          payload,
          (manifest['files'] as List)
              .where((item) => (manifest['_extracted'] as Set<String>)
                  .contains((item as Map)['path']))
              .toList());
      final contents = _contentsFromManifest(manifest);
      final requested = options == null
          ? BackupSelection(components: contents.components, includeMusic: true)
          : BackupSelection.fromMap(options);
      final selection = BackupSelection(
          components: requested.components.intersection(contents.components),
          includeMusic: requested.includeMusic,
          musicFolders: requested.musicFolders);
      if (selection.isEmpty)
        throw const CacheBackupException('Nothing selected');
      final musicBatch = 'import-$nonce';
      final restoredMusic = _selectedMusicPaths(
          manifest, selection, destination,
          musicBatch: musicBatch);

      final catalog = await _CurrentLibraryCatalog.read(currentData);
      final dependencies = <String>{};
      void collectDependencies(Object? value) {
        if (value is String && value.startsWith('${_tokenPrefix}cache/')) {
          final relative = Uri.decodeComponent(
              value.substring('${_tokenPrefix}cache/'.length));
          if (_isSafeRelative(relative) && !_looksLikeJson(relative))
            dependencies.add(relative);
        } else if (value is Map) {
          final background = _backgroundAssetReference(value);
          if (background != null) dependencies.add(background);
          for (final item in value.values) {
            collectDependencies(item);
          }
        } else if (value is List) {
          for (final item in value) {
            collectDependencies(item);
          }
        }
      }

      final payloadEntries =
          await payload.list(recursive: true, followLinks: false).toList();
      for (final entity in payloadEntries.whereType<File>()) {
        final relative =
            _portableRelative(path.relative(entity.path, from: payload.path));
        if (_looksLikeJson(relative) &&
            selection.components.contains(backupComponentForPath(relative))) {
          collectDependencies(await _tryReadJson(entity));
        }
      }
      final cacheOverrides = <String, String>{
        for (final dependency in dependencies)
          if (_backgroundAssetId(dependency) == null)
            dependency: path.join('restored-assets', musicBatch, dependency),
      };
      final decoder = _PortablePathDecoder(
          destination: destination,
          manifest: manifest,
          catalog: catalog,
          restoredMusic: restoredMusic,
          cacheOverrides: cacheOverrides);
      for (final entity in payloadEntries.whereType<File>()) {
        final relative = path.relative(entity.path, from: payload.path);
        if (_isMusicPayload(relative)) {
          final targetRelative = path.join('restored-music', musicBatch,
              relative.substring('restored-music/'.length));
          if (!restoredMusic
              .containsValue(path.join(destination.path, targetRelative))) {
            await entity.delete();
          } else {
            final output = File(path.join(payload.path, targetRelative));
            await output.parent.create(recursive: true);
            await entity.rename(output.path);
          }
          continue;
        }
        final assetRelative = cacheOverrides[_portableRelative(relative)];
        if (assetRelative != null) {
          final output = File(path.join(payload.path, assetRelative));
          await output.parent.create(recursive: true);
          await entity.rename(output.path);
          continue;
        }
        if (!selection.components.contains(backupComponentForPath(relative)) &&
            !dependencies.contains(_portableRelative(relative))) {
          await entity.delete();
          continue;
        }
        if (!_looksLikeJson(relative)) continue;
        final decoded = await _tryReadJson(entity);
        if (decoded == null) {
          throw CacheBackupException(
              'A cache document is damaged: ${path.basename(relative)}');
        }
        final restored = decoder.convert(decoded,
            preserveMissing: _preservesMusicReferences(relative));
        final documentName =
            path.basename(relative).replaceFirst(RegExp(r'\.bak$'), '');
        if (['personal_library.json', 'named_queues.json', 'eq_presets.json']
            .contains(documentName))
          Snapshot3Upgrade.validateDocument(documentName, restored);
        await entity.writeAsString(
            json.encode(identical(restored, _dropValue) ? null : restored),
            flush: true);
      }
      // Preserve unselected live data. It remains a snapshot until the next
      // launch atomically installs this complete, verified directory.
      if (options != null) {
        await _mergeUnselectedCurrent(
            currentData, payload, destination, selection, control);
        await BackupRestorePreservation.writePlan(
            staged: payload,
            source: currentData,
            selected: selection.components,
            protectedPaths: {
              ...cacheOverrides.values,
              ...dependencies
                  .where((value) => _backgroundAssetId(value) != null),
              for (final value in restoredMusic.values)
                path.relative(value, from: destination.path),
            });
      }
      await File(path.join(payload.path, appDataReadyMarkerName)).writeAsString(
        json.encode(<String, Object?>{
          'format': _backupFormat,
          'version': _backupVersion,
          'restoredAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );

      await payload.rename(staged.path);
      return <String, Object?>{
        'destination': destination.path,
        'staged': staged.path,
        'fileCount': files,
        'restoredSongs': decoder.restoredSongs,
        'missingSongs': decoder.missingSongs,
        'musicCount': restoredMusic.length,
      };
    } catch (error) {
      if (await staged.exists()) await staged.delete(recursive: true);
      if (error is CacheBackupException) rethrow;
      throw CacheBackupException('Could not restore backup: $error');
    } finally {
      if (await extraction.exists()) await extraction.delete(recursive: true);
    }
  }

  static Future<void> _discardPreparedRestore(
      Map<String, Object?> transaction) async {
    final stagedPath = transaction['staged'];
    if (stagedPath is String) {
      final staged = Directory(stagedPath);
      if (await staged.exists()) await staged.delete(recursive: true);
    }
  }

  Future<BackupContents> inspectBackup(
      {required File backup,
      String? password,
      BackupOperation? operation}) async {
    final backupPath = backup.absolute.path;
    final result = await _runBackupOperation(operation, (control) async {
      final temporary =
          await Directory.systemTemp.createTemp('dan-player-inspect-');
      try {
        final input = File(backupPath);
        final encrypted = await BackupEncryption.isEncrypted(input);
        final plain =
            await _openBackupEnvelope(input, temporary, password, control);
        final manifest = await _readStreamingZip(plain, temporary, control,
            manifestOnly: true);
        return {...manifest, 'encrypted': encrypted};
      } finally {
        await temporary.delete(recursive: true);
      }
    });
    return _contentsFromManifest(result);
  }

  Future<BackupContents> inspectLibrary({required Directory source}) async {
    final sourcePath = source.absolute.path;
    return Isolate.run(() async {
      final index =
          await _tryReadJson(File(path.join(sourcePath, 'index.json')));
      final inventory = await _MusicInventory.read(index);
      return BackupContents(components: {
        ...BackupComponent.values
      }, musicFolders: [
        for (final folder in inventory.folders)
          BackupMusicFolder(
              id: folder.id,
              name: folder.label,
              songCount: folder.files.length,
              bytes: folder.bytes)
      ]);
    });
  }
}

enum CacheRestoreDestinationKind {
  emptySelection,
  recognizedCache,
  childDirectory,
  uniqueChildDirectory,
}

class CacheRestoreDestinationDecision {
  const CacheRestoreDestinationDecision({
    required this.directory,
    required this.kind,
    required this.requiresReplacementConfirmation,
    required this.replacesActiveDirectory,
  });

  final Directory directory;
  final CacheRestoreDestinationKind kind;
  final bool requiresReplacementConfirmation;
  final bool replacesActiveDirectory;
}

/// Resolves a folder-picker result without ever overwriting unrelated files.
class CacheRestoreDestinationPolicy {
  static const _cacheMarkers = <String>{
    'index.json',
    'settings.json',
    'app_preference.json',
    'playlists.json',
    'category_covers.json',
    'collections.json',
    'custom_audio_order.json',
    'lyric_source.json',
    'online_library.json',
    'playback_state.json',
    'playback_statistics.json',
    'track_identities.json',
    'lyric_documents.json',
    'playback_bookmarks.json',
    'track_resume.json',
    'personal_library.json',
    'named_queues.json',
    'eq_presets.json',
    'smart_playlists.json',
  };
  static const _cacheDirectoryMarkers = <String>{
    'covers',
    'metadata_preview',
    'imported-assets',
    'category-covers',
  };

  static Future<CacheRestoreDestinationDecision> decide({
    required Directory selected,
    required Directory currentData,
  }) async {
    final selectedPath = path.normalize(selected.absolute.path);
    final currentPath = path.normalize(currentData.absolute.path);
    if (!path.isAbsolute(selectedPath) ||
        path.equals(selectedPath, path.rootPrefix(selectedPath))) {
      throw const CacheBackupException('Unsafe restore destination');
    }
    if (path.isWithin(currentPath, selectedPath)) {
      throw const CacheBackupException(
          'Choose the active cache folder itself or a folder outside it');
    }
    if (!await selected.exists()) await selected.create(recursive: true);
    if (await _isEmpty(selected)) {
      return _decision(selected, currentPath,
          CacheRestoreDestinationKind.emptySelection, false);
    }
    if (await _isRecognizedCache(selected)) {
      return _decision(selected, currentPath,
          CacheRestoreDestinationKind.recognizedCache, true);
    }

    final child = Directory(path.join(selected.path, 'Dan Player'));
    final childType =
        await FileSystemEntity.type(child.path, followLinks: false);
    if (childType == FileSystemEntityType.notFound ||
        (childType == FileSystemEntityType.directory &&
            await _isEmpty(child))) {
      return _decision(child, currentPath,
          CacheRestoreDestinationKind.childDirectory, false);
    }
    if (childType == FileSystemEntityType.directory &&
        await _isRecognizedCache(child)) {
      return _decision(child, currentPath,
          CacheRestoreDestinationKind.recognizedCache, true);
    }

    var suffix = 1;
    while (true) {
      final name =
          suffix == 1 ? 'Dan Player restored' : 'Dan Player restored $suffix';
      final candidate = Directory(path.join(selected.path, name));
      final candidateType =
          await FileSystemEntity.type(candidate.path, followLinks: false);
      if (candidateType == FileSystemEntityType.notFound ||
          (candidateType == FileSystemEntityType.directory &&
              await _isEmpty(candidate))) {
        return _decision(candidate, currentPath,
            CacheRestoreDestinationKind.uniqueChildDirectory, false);
      }
      suffix++;
      if (suffix > 999) {
        throw const CacheBackupException(
            'Could not find a non-conflicting restore directory');
      }
    }
  }

  static CacheRestoreDestinationDecision _decision(Directory directory,
      String currentPath, CacheRestoreDestinationKind kind, bool confirm) {
    return CacheRestoreDestinationDecision(
      directory: directory,
      kind: kind,
      requiresReplacementConfirmation: confirm,
      replacesActiveDirectory:
          path.equals(path.normalize(directory.absolute.path), currentPath),
    );
  }

  static Future<bool> _isEmpty(Directory directory) async {
    await for (final _ in directory.list(followLinks: false)) {
      return false;
    }
    return true;
  }

  static Future<bool> _isRecognizedCache(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = path.basename(entity.path).toLowerCase();
      if ((entity is File && _cacheMarkers.contains(name)) ||
          (entity is Directory && _cacheDirectoryMarkers.contains(name))) {
        return true;
      }
    }
    return false;
  }
}

class _PortablePathEncoder {
  _PortablePathEncoder({
    required this.sourceRoot,
    required List<String> libraryRoots,
    required this.payloadRoot,
  }) : roots = <_SourceRoot>[
          for (var i = 0; i < libraryRoots.length; i++)
            _SourceRoot('r$i', path.normalize(libraryRoots[i])),
        ]..sort((a, b) => b.path.length.compareTo(a.path.length));

  final Directory sourceRoot;
  final Directory payloadRoot;
  final List<_SourceRoot> roots;
  final Map<String, Map<String, Object?>> songManifest = {};
  final Map<String, String> _songTokensByPath = {};
  final Map<String, String> _externalAssets = {};
  int _externalCounter = 0;

  List<Map<String, Object?>> get rootManifest => <Map<String, Object?>>[
        for (final root in roots)
          <String, Object?>{
            'id': root.id,
            'name': path.basename(root.path),
            'songCount': songManifest.values
                .where((song) => song['root'] == root.id)
                .length,
          }
      ];

  void collectSongReferences(Object? value) {
    if (value is Map) {
      final rawPath = value['path'];
      if (rawPath is String) {
        final root = _rootFor(rawPath);
        if (root != null &&
            !path.equals(path.normalize(rawPath), root.path) &&
            (value['file_size'] is num || _looksLikeAudioPath(rawPath))) {
          final relative =
              _portableRelative(path.relative(rawPath, from: root.path));
          final token = _songToken(root.id, relative);
          songManifest.putIfAbsent(
              token,
              () => <String, Object?>{
                    'root': root.id,
                    'relativePath': relative,
                    'name': path.basename(rawPath),
                    if (value['file_size'] is num)
                      'size': (value['file_size'] as num).toInt(),
                  });
          _songTokensByPath[path.normalize(rawPath).toLowerCase()] = token;
        }
      }
      for (final entry in value.entries) {
        collectSongReferences(entry.key);
        collectSongReferences(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        collectSongReferences(item);
      }
    }
  }

  Future<Object?> convert(Object? value, {bool aliasOnly = false}) async {
    if (value is String) return _convertString(value, aliasOnly: aliasOnly);
    if (value is List) {
      return Future.wait<Object?>(
          [for (final item in value) convert(item, aliasOnly: aliasOnly)]);
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final convertedKey = await _convertString(entry.key.toString());
        if (const {'tags', 'label', 'name', 'backup'}.contains(entry.key)) {
          result[convertedKey] = entry.value;
          continue;
        }
        result[convertedKey] = await convert(entry.value,
            aliasOnly: aliasOnly || entry.key == 'aliases');
      }
      return result;
    }
    return value;
  }

  Future<String> _convertString(String value, {bool aliasOnly = false}) async {
    final cue = _cueIdentityParts(value);
    if (cue != null) {
      final portableCue = await _convertString(cue.$1, aliasOnly: aliasOnly);
      return 'cue://track/${Uri.encodeComponent(portableCue)}/${cue.$2}';
    }
    if (!path.isAbsolute(value)) return value;
    final normalized = path.normalize(value);
    if (_isInsideOrSame(sourceRoot.path, normalized)) {
      final relative =
          _portableRelative(path.relative(normalized, from: sourceRoot.path));
      return '$_tokenPrefix${relative.isEmpty ? 'cache' : 'cache/${Uri.encodeComponent(relative)}'}';
    }
    final root = _rootFor(normalized);
    if (root != null) {
      if (path.equals(normalized, root.path)) {
        return '${_tokenPrefix}root/${root.id}';
      }
      final relative =
          _portableRelative(path.relative(normalized, from: root.path));
      final known = _songTokensByPath[normalized.toLowerCase()];
      if (known != null) {
        if (!aliasOnly) songManifest[known]?.remove('aliasOnly');
        return known;
      }
      if (path.extension(normalized).toLowerCase() == '.cue') {
        return '${_tokenPrefix}root-file/${root.id}/'
            '${Uri.encodeComponent(relative)}';
      }
      // A scan folder can legally contain dots (or even end in an audio-like
      // suffix). Prefer a real directory over extension heuristics so its
      // folder record is not mistaken for a missing song.
      if (await Directory(normalized).exists()) {
        return '${_tokenPrefix}root-directory/${root.id}/'
            '${Uri.encodeComponent(relative)}';
      }
      if (_looksLikeAudioPath(normalized)) {
        final token = _songToken(root.id, relative);
        songManifest.putIfAbsent(
            token,
            () => <String, Object?>{
                  'root': root.id,
                  'relativePath': relative,
                  'name': path.basename(normalized),
                  if (aliasOnly) 'aliasOnly': true,
                });
        _songTokensByPath[normalized.toLowerCase()] = token;
        return token;
      }
    }

    final file = File(normalized);
    // A stale playlist can still point at a playable file after its scan root
    // was removed from the library. It is still music, not a cache asset: keep
    // only a portable matching hint and never copy its bytes into the backup.
    if (_looksLikeAudioPath(normalized)) {
      final key = normalized.toLowerCase();
      final known = _songTokensByPath[key];
      if (known != null) {
        if (!aliasOnly) songManifest[known]?.remove('aliasOnly');
        return known;
      }
      final id = _externalCounter++;
      final name = path.basename(normalized);
      int? size;
      try {
        if (await file.exists()) size = await file.length();
      } catch (_) {
        // Name-only matching is still safe; restore requires a unique result.
      }
      final token = _songToken('unbound', '$id-$name');
      songManifest[token] = <String, Object?>{
        'root': 'unbound',
        'relativePath': name,
        'name': name,
        if (aliasOnly) 'aliasOnly': true,
        if (size != null) 'size': size,
      };
      _songTokensByPath[key] = token;
      return token;
    }
    if (await file.exists()) {
      final known = _externalAssets[normalized.toLowerCase()];
      if (known != null) return known;
      final safeName =
          path.basename(normalized).replaceAll(RegExp(r'[^\w. -]'), '_');
      final relative = _portableRelative(
          path.join('imported-assets', '${_externalCounter++}-$safeName'));
      final output = File(path.join(payloadRoot.path, relative));
      await output.parent.create(recursive: true);
      final before = await file.stat();
      await file.copy(output.path);
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const CacheBackupException(
            'A referenced asset changed during backup; please retry');
      }
      final token = '${_tokenPrefix}cache/${Uri.encodeComponent(relative)}';
      _externalAssets[normalized.toLowerCase()] = token;
      return token;
    }
    final id = _externalCounter++;
    return '${_tokenPrefix}unresolved/$id';
  }

  _SourceRoot? _rootFor(String candidate) {
    final normalized = path.normalize(candidate);
    for (final root in roots) {
      if (_isInsideOrSame(root.path, normalized)) return root;
    }
    return null;
  }
}

class _PortablePathDecoder {
  _PortablePathDecoder({
    required this.destination,
    required Map<String, Object?> manifest,
    required this.catalog,
    Map<String, String> restoredMusic = const {},
    this.cacheOverrides = const {},
  }) {
    final rawSongs = manifest['songs'];
    if (rawSongs is Map) {
      for (final entry in rawSongs.entries) {
        if (entry.value is Map) {
          songs[entry.key.toString()] = (entry.value as Map)
              .map((key, value) => MapEntry(key.toString(), value));
        }
      }
    }
    _matchRoots();
    _resolveSongs();
    _resolvedPaths.addAll(restoredMusic);
    _resolved.addAll(restoredMusic.keys);
    _missing.removeAll(restoredMusic.keys);
    for (final entry in restoredMusic.entries) {
      final descriptor = songs[entry.key];
      if (descriptor == null) continue;
      final rootId = descriptor['root'] as String?;
      final relative = descriptor['relativePath'] as String?;
      if (rootId == null || relative == null) continue;
      _restoredDirectories['$rootId/${path.posix.dirname(relative)}'] =
          path.dirname(entry.value);
      // Song paths resolve individually; folder/root records use the common
      // music restore root so subsequent scans also find restored folders.
      rootMatches[rootId] =
          _CurrentRoot(path.dirname(path.dirname(entry.value)), {}, {});
    }
  }

  final Directory destination;
  final _CurrentLibraryCatalog catalog;
  final Map<String, String> cacheOverrides;
  final Map<String, Map<String, Object?>> songs = {};
  final Map<String, _CurrentRoot> rootMatches = {};
  final Set<String> _resolved = {};
  final Set<String> _missing = {};
  final Map<String, String> _resolvedPaths = {};
  final Map<String, String> _restoredDirectories = {};
  final Set<String> _ambiguous = {};

  int get restoredSongs => _resolved.length;
  int get missingSongs => _missing.length;

  Object? convert(Object? value, {bool preserveMissing = false}) {
    if (value is String) {
      return _convertString(value, preserveMissing: preserveMissing);
    }
    if (value is List) {
      final result = <Object?>[];
      for (final item in value) {
        final converted = convert(item, preserveMissing: preserveMissing);
        if (!identical(converted, _dropValue)) result.add(converted);
      }
      return result;
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final convertedKey = _convertString(entry.key.toString(),
            preserveMissing: preserveMissing);
        if (identical(convertedKey, _dropValue)) continue;
        final converted =
            const {'tags', 'label', 'name', 'backup'}.contains(entry.key)
                ? entry.value
                : convert(entry.value, preserveMissing: preserveMissing);
        if (identical(converted, _dropValue)) {
          if (entry.key == 'path' || entry.key == 'audio') return _dropValue;
          continue;
        }
        result[convertedKey as String] = converted;
      }
      return result;
    }
    return value;
  }

  Object _convertString(String value, {bool preserveMissing = false}) {
    if (_resolvedPaths.containsKey(value)) return _resolvedPaths[value]!;
    final cue = _cueIdentityParts(value);
    if (cue != null) {
      final restoredCue =
          _convertString(cue.$1, preserveMissing: preserveMissing);
      if (restoredCue is! String) return _dropValue;
      return 'cue://track/${Uri.encodeComponent(path.windows.normalize(restoredCue).toLowerCase())}/${cue.$2}';
    }
    if (!value.startsWith(_tokenPrefix)) return value;
    if (value.startsWith('${_tokenPrefix}cache/')) {
      final encoded = value.substring('${_tokenPrefix}cache/'.length);
      final relative = Uri.decodeComponent(encoded);
      if (!_isSafeRelative(relative)) return _dropValue;
      return path.normalize(
          path.join(destination.path, cacheOverrides[relative] ?? relative));
    }
    if (value == '${_tokenPrefix}cache') return destination.path;
    if (value.startsWith('${_tokenPrefix}root-directory/') ||
        value.startsWith('${_tokenPrefix}root-file/')) {
      final isFile = value.startsWith('${_tokenPrefix}root-file/');
      final prefix = isFile
          ? '${_tokenPrefix}root-file/'
          : '${_tokenPrefix}root-directory/';
      final rest = value.substring(prefix.length);
      final separator = rest.indexOf('/');
      if (separator <= 0) return _dropValue;
      final id = rest.substring(0, separator);
      final relative = Uri.decodeComponent(rest.substring(separator + 1));
      if (!_isSafeRelative(relative)) return _dropValue;
      final restoredDirectory = _restoredDirectories['$id/$relative'];
      if (!isFile && restoredDirectory != null) return restoredDirectory;
      final root = rootMatches[id];
      if (root == null && !preserveMissing) return _dropValue;
      final location =
          path.normalize(path.join(root?.path ?? _missingRoot(id), relative));
      return preserveMissing ||
              (isFile
                  ? File(location).existsSync()
                  : Directory(location).existsSync())
          ? location
          : _dropValue;
    }
    if (value.startsWith('${_tokenPrefix}root/')) {
      final id = value.substring('${_tokenPrefix}root/'.length);
      return _restoredDirectories['$id/.'] ??
          rootMatches[id]?.path ??
          (preserveMissing ? _missingRoot(id) : _dropValue);
    }
    if (value.startsWith('${_tokenPrefix}song/')) {
      final resolved = _resolvedPaths[value];
      if (resolved != null) return resolved;
      if (!preserveMissing) return _dropValue;
      final descriptor = songs[value];
      final root = descriptor?['root'];
      final relative = descriptor?['relativePath'];
      if (root is! String ||
          relative is! String ||
          !_isSafeRelative(relative)) {
        return _dropValue;
      }
      // Keep the row and occurrence position. A missing file is not evidence
      // that its identity, lyrics, bookmarks or historical counters vanished.
      return path.normalize(path.join(
          _ambiguous.contains(value)
              ? _missingRoot(root)
              : rootMatches[root]?.path ?? _missingRoot(root),
          relative));
    }
    if (preserveMissing && value.startsWith('${_tokenPrefix}unresolved/')) {
      final id = value.substring('${_tokenPrefix}unresolved/'.length);
      if (_isSafeRelative(id)) return path.join(_missingRoot('unresolved'), id);
    }
    return _dropValue;
  }

  String _missingRoot(String id) {
    final safeId = RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)
        ? id
        : sha256.convert(utf8.encode(id)).toString().substring(0, 16);
    return path.join(destination.path, 'missing-library', safeId);
  }

  void _resolveSongs() {
    for (final entry in songs.entries) {
      final value = entry.key;
      final descriptor = entry.value;
      final rootId = descriptor['root']?.toString();
      final relative = descriptor['relativePath']?.toString();
      if (rootId == null || relative == null || !_isSafeRelative(relative)) {
        _missing.add(value);
        continue;
      }
      String? resolved =
          rootMatches[rootId]?.audioByRelative[_comparisonRelative(relative)];
      resolved ??= catalog.uniqueRelative(relative);
      final size = descriptor['size'] is num
          ? (descriptor['size'] as num).toInt()
          : null;
      resolved ??= catalog.uniqueSignature(
          descriptor['name']?.toString() ?? path.basename(relative), size);
      if (resolved != null && File(resolved).existsSync()) {
        _resolved.add(value);
        _resolvedPaths[value] = resolved;
      } else {
        _missing.add(value);
      }
    }
    // A unique filename in the destination does not justify merging two
    // different original file instances into that one surviving file.
    final owners = <String, List<String>>{};
    for (final entry in _resolvedPaths.entries) {
      if (songs[entry.key]?['aliasOnly'] == true) continue;
      owners
          .putIfAbsent(path.normalize(entry.value).toLowerCase(), () => [])
          .add(entry.key);
    }
    for (final tokens in owners.values.where((tokens) => tokens.length > 1)) {
      for (final token in tokens) {
        _ambiguous.add(token);
        _missing.add(token);
        _resolved.remove(token);
        _resolvedPaths.remove(token);
      }
    }
  }

  void _matchRoots() {
    final byRoot = <String, List<String>>{};
    for (final descriptor in songs.values) {
      final root = descriptor['root']?.toString();
      final relative = descriptor['relativePath']?.toString();
      if (root != null && relative != null && _isSafeRelative(relative)) {
        (byRoot[root] ??= <String>[]).add(relative);
      }
    }
    for (final entry in byRoot.entries) {
      var best = 0;
      _CurrentRoot? selected;
      var tied = false;
      for (final current in catalog.roots) {
        var score = 0;
        for (final relative in entry.value) {
          if (current.audioByRelative
              .containsKey(_comparisonRelative(relative))) {
            score++;
          }
        }
        if (score > best) {
          best = score;
          selected = current;
          tied = false;
        } else if (score > 0 && score == best) {
          tied = true;
        }
      }
      if (best > 0 && !tied && selected != null) {
        rootMatches[entry.key] = selected;
      }
    }
  }
}

class _CurrentLibraryCatalog {
  _CurrentLibraryCatalog(this.roots);
  final List<_CurrentRoot> roots;

  static Future<_CurrentLibraryCatalog> read(Directory data) async {
    final decoded =
        await _tryReadJson(File(path.join(data.path, 'index.json')));
    final rootPaths = _libraryRoots(decoded);
    final hasDeclaredRoots = _hasDeclaredLibraryRoots(decoded);
    final builders = <String, _CurrentRootBuilder>{
      for (final root in rootPaths)
        path.normalize(root): _CurrentRootBuilder(path.normalize(root)),
    };
    if (decoded is Map && decoded['folders'] is List) {
      for (final rawFolder in decoded['folders'] as List) {
        if (rawFolder is! Map || rawFolder['path'] is! String) continue;
        final folderPath = path.normalize(rawFolder['path'] as String);
        if (!path.isAbsolute(folderPath)) continue;
        _CurrentRootBuilder? owner;
        for (final builder in builders.values) {
          if (_isInsideOrSame(builder.path, folderPath) &&
              (owner == null || builder.path.length > owner.path.length)) {
            owner = builder;
          }
        }
        // A current index's declared roots are authoritative. A stale folder
        // outside them must never become an independent matching root. Legacy
        // indexes have no roots, so their persisted folders remain the only
        // safe boundaries available for relative matching.
        if (owner == null && hasDeclaredRoots) continue;
        owner ??= builders.putIfAbsent(
            folderPath, () => _CurrentRootBuilder(folderPath));
        final rawAudios = rawFolder['audios'];
        if (rawAudios is List) {
          for (final rawAudio in rawAudios) {
            if (rawAudio is! Map || rawAudio['path'] is! String) continue;
            final audioPath = path.normalize(rawAudio['path'] as String);
            if (!_isInsideOrSame(owner.path, audioPath)) continue;
            final relative =
                _comparisonRelative(path.relative(audioPath, from: owner.path));
            owner.audios[relative] = audioPath;
            owner.sizes[audioPath] = rawAudio['file_size'] is num
                ? (rawAudio['file_size'] as num).toInt()
                : null;
          }
        }
      }
    }
    return _CurrentLibraryCatalog(<_CurrentRoot>[
      for (final builder in builders.values)
        _CurrentRoot(builder.path, builder.audios, builder.sizes),
    ]);
  }

  String? uniqueRelative(String relative) {
    final candidates = <String>{};
    final key = _comparisonRelative(relative);
    for (final root in roots) {
      final candidate = root.audioByRelative[key];
      if (candidate != null) candidates.add(candidate);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  String? uniqueSignature(String name, int? size) {
    final candidates = <String>{};
    final lower = name.toLowerCase();
    for (final root in roots) {
      for (final entry in root.sizes.entries) {
        if (path.basename(entry.key).toLowerCase() == lower &&
            (size == null || entry.value == size)) {
          candidates.add(entry.key);
        }
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }
}

class _CurrentRoot {
  _CurrentRoot(this.path, this.audioByRelative, this.sizes);
  final String path;
  final Map<String, String> audioByRelative;
  final Map<String, int?> sizes;
}

class _CurrentRootBuilder {
  _CurrentRootBuilder(this.path);
  final String path;
  final Map<String, String> audios = {};
  final Map<String, int?> sizes = {};
}

class _SourceRoot {
  const _SourceRoot(this.id, this.path);
  final String id;
  final String path;
}

final Object _dropValue = Object();

List<String> _libraryRoots(Object? index) {
  final values = <String>{};
  if (index is Map) {
    final rawRoots = index['roots'];
    if (rawRoots is String && path.isAbsolute(rawRoots)) values.add(rawRoots);
    if (rawRoots is List) {
      for (final root in rawRoots) {
        if (root is String && path.isAbsolute(root)) values.add(root);
      }
    }
    final folders = index['folders'];
    if (values.isEmpty && folders is List) {
      for (final folder in folders) {
        if (folder is Map &&
            folder['path'] is String &&
            path.isAbsolute(folder['path'] as String)) {
          values.add(folder['path'] as String);
        }
      }
    }
  }
  return values.map(path.normalize).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

bool _hasDeclaredLibraryRoots(Object? index) {
  if (index is! Map) return false;
  final rawRoots = index['roots'];
  if (rawRoots is String) return path.isAbsolute(rawRoots);
  return rawRoots is List &&
      rawRoots.any((root) => root is String && path.isAbsolute(root));
}

Future<Object?> _tryReadJson(File file) async {
  try {
    if (!await file.exists()) return null;
    return json.decode(await file.readAsString());
  } catch (_) {
    return null;
  }
}

bool _looksLikeJson(String relative) {
  final lower = relative.toLowerCase();
  return lower.endsWith('.json') || lower.endsWith('.json.bak');
}

bool _looksLikeAudioPath(String value) {
  const extensions = <String>{
    '.mp3',
    '.mp2',
    '.mp1',
    '.flac',
    '.m4a',
    '.aac',
    '.adts',
    '.ogg',
    '.opus',
    '.wav',
    '.wave',
    '.aif',
    '.aiff',
    '.aifc',
    '.asf',
    '.wma',
    '.ape',
    '.alac',
    '.ac3',
    '.amr',
    '.3ga',
    '.mpc',
    '.mid',
    '.wv',
    '.wvc',
    '.dsf',
    '.dff',
  };
  return extensions.contains(path.extension(value).toLowerCase());
}

bool _shouldIncludeCacheEntry(String relative) {
  final portable = _portableRelative(relative);
  final segments = portable.toLowerCase().split('/');
  if (segments.any((segment) =>
      segment == BackupRestorePreservation.planName ||
      segment == 'updates' ||
      segment == 'restored-music' ||
      segment == 'library_migrations' ||
      segment.startsWith('.dan-player-restore-') ||
      segment.startsWith('.dan-player-pending-') ||
      segment.startsWith('.dan-player-previous-') ||
      segment.startsWith('.dan-player-before-restore-'))) {
    return false;
  }
  final lower = portable.toLowerCase();
  if (const {
    'library_migration.json',
    'library_migration_last.json',
    'metadata_committed.json'
  }.contains(lower)) {
    return false;
  }
  return !lower.endsWith('.tmp') &&
      !lower.endsWith('.pending') &&
      !lower.endsWith('.migration-tmp') &&
      !lower.endsWith('.partial') &&
      !lower.endsWith('.exe') &&
      !lower.endsWith('.msi') &&
      !lower.endsWith('.msix') &&
      !lower.endsWith('.msixbundle');
}

bool _preservesMusicReferences(String relative) {
  var name = path.basename(relative).toLowerCase();
  if (name.endsWith('.bak')) name = name.substring(0, name.length - 4);
  return const {
    'index.json',
    'playlists.json',
    'collections.json',
    'custom_audio_order.json',
    'playback_state.json',
    'playback_bookmarks.json',
    'track_resume.json',
    'personal_library.json',
    'named_queues.json',
    'eq_presets.json',
    'smart_playlists.json',
    'lyric_source.json',
    'lyric_documents.json',
    'track_identities.json',
    'song_comment_associations.json',
    'playback_statistics.json',
    'playback_statistics.pre-track-id-v1.json',
  }.contains(name);
}

(String, int)? _cueIdentityParts(String value) {
  const prefix = 'cue://track/';
  if (!value.startsWith(prefix)) return null;
  final slash = value.lastIndexOf('/');
  if (slash <= prefix.length) return null;
  final number = int.tryParse(value.substring(slash + 1));
  if (number == null || number < 1 || number > 99) return null;
  try {
    return (Uri.decodeComponent(value.substring(prefix.length, slash)), number);
  } on FormatException {
    return null;
  }
}

String _songToken(String root, String relative) =>
    '${_tokenPrefix}song/$root/${Uri.encodeComponent(relative)}';

String _portableRelative(String value) =>
    path.normalize(value).replaceAll('\\', '/');

String _comparisonRelative(String value) =>
    _portableRelative(value).toLowerCase();

bool _isSafeRelative(String value) {
  if (value.trim().isEmpty || path.isAbsolute(value)) return false;
  final normalized = _portableRelative(value);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('/') ||
      normalized.startsWith('../') ||
      normalized.length > 32767) {
    return false;
  }
  for (final segment in normalized.split('/')) {
    if (!_isSafeWindowsPathSegment(segment)) return false;
  }
  return true;
}

final RegExp _unsafeWindowsPathCharacter = RegExp(r'[\x00-\x1f<>:"|?*]');
final RegExp _windowsNumberedDevice = RegExp(r'^(COM|LPT)[1-9]$');
const Set<String> _windowsDeviceNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'CONIN\$',
  'CONOUT\$',
};

bool _isSafeWindowsPathSegment(String segment) {
  if (segment.isEmpty ||
      segment == '.' ||
      segment == '..' ||
      segment.length > 255 ||
      segment.endsWith('.') ||
      segment.endsWith(' ') ||
      _unsafeWindowsPathCharacter.hasMatch(segment)) {
    return false;
  }
  // Windows reserves these names even when an extension is appended. Reject
  // them before archive extraction so a crafted backup cannot target a device
  // or an NTFS alternate data stream in the temporary directory.
  final stem = segment.split('.').first.toUpperCase();
  return !_windowsDeviceNames.contains(stem) &&
      !_windowsNumberedDevice.hasMatch(stem);
}

bool _isInsideOrSame(String parent, String candidate) =>
    path.equals(path.normalize(parent), path.normalize(candidate)) ||
    path.isWithin(path.normalize(parent), path.normalize(candidate));

bool _containsAbsolutePath(Object? value) {
  if (value is String) return path.isAbsolute(value);
  if (value is List) return value.any(_containsAbsolutePath);
  if (value is Map) {
    return value.entries.any((entry) =>
        _containsAbsolutePath(entry.key.toString()) ||
        (!const {'tags', 'label', 'name', 'backup'}.contains(entry.key) &&
            _containsAbsolutePath(entry.value)));
  }
  return false;
}

Future<String> _fileDigest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _atomicReplaceFile(File temporary, File destination) async {
  final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final previous = File('${destination.path}.$nonce.previous');
  var moved = false;
  var committed = false;
  try {
    if (await destination.exists()) {
      await destination.rename(previous.path);
      moved = true;
    }
    await temporary.rename(destination.path);
    committed = true;
  } catch (_) {
    if (!await destination.exists() && moved && await previous.exists()) {
      await previous.rename(destination.path);
    }
    rethrow;
  } finally {
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
    if (committed && moved && await previous.exists()) {
      try {
        await previous.delete();
      } catch (_) {}
    }
  }
}

Future<int> _verifyPayload(Directory payload, Object? rawFiles) async {
  if (rawFiles is! List) {
    throw const CacheBackupException('Backup file list is missing');
  }
  final expected = <String, Map>{};
  for (final raw in rawFiles) {
    if (raw is! Map || raw['path'] is! String || raw['sha256'] is! String) {
      throw const CacheBackupException('Backup file list is damaged');
    }
    final relative = raw['path'] as String;
    if (!_isSafeRelative(relative) || expected.containsKey(relative)) {
      throw const CacheBackupException('Unsafe or duplicated payload entry');
    }
    expected[relative] = raw;
  }
  final actual = <String>{};
  await for (final entity
      in payload.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative =
        _portableRelative(path.relative(entity.path, from: payload.path));
    final descriptor = expected[relative];
    if (descriptor == null ||
        descriptor['size'] != await entity.length() ||
        descriptor['sha256'] != await _fileDigest(entity) ||
        (_backgroundAssetId(relative) != null &&
            _backgroundAssetId(relative) != descriptor['sha256'])) {
      throw const CacheBackupException('Backup payload verification failed');
    }
    actual.add(relative);
  }
  if (actual.length != expected.length || !actual.containsAll(expected.keys)) {
    throw const CacheBackupException('Backup payload is incomplete');
  }
  return actual.length;
}
