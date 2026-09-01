import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/data/app_data_location.dart';
import 'package:path/path.dart' as path;

const _backupFormat = 'dan-player-cache-backup';
const _backupVersion = 1;
const _tokenPrefix = '@dan-player-backup/';

class CacheBackupException implements Exception {
  const CacheBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CacheBackupResult {
  const CacheBackupResult({required this.fileCount, required this.songCount});
  final int fileCount;
  final int songCount;
}

class CacheRestoreResult {
  const CacheRestoreResult({
    required this.destination,
    required this.fileCount,
    required this.restoredSongs,
    required this.missingSongs,
    required this.restartRequired,
  });

  final Directory destination;
  final int fileCount;
  final int restoredSongs;
  final int missingSongs;
  final bool restartRequired;
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
  }) async {
    try {
      final result = await Isolate.run(() => _exportBackupOnWorker(
          source.absolute.path, destination.absolute.path));
      return CacheBackupResult(fileCount: result[0], songCount: result[1]);
    } on CacheBackupException {
      rethrow;
    } catch (error) {
      throw CacheBackupException('Could not create backup: $error');
    }
  }

  static Future<List<int>> _exportBackupOnWorker(
      String sourceDirectory, String destinationFile) async {
    final source = Directory(sourceDirectory);
    final destination = File(destinationFile);
    if (!await source.exists()) {
      throw const CacheBackupException('The app data directory does not exist');
    }
    final sourcePath = path.normalize(source.absolute.path);
    final destinationPath = path.normalize(destination.absolute.path);
    if (path.isWithin(sourcePath, destinationPath)) {
      throw const CacheBackupException(
          'A backup cannot be written inside the app data directory');
    }

    final temporary =
        await Directory.systemTemp.createTemp('dan-player-backup-');
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

      await for (final entity
          in source.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: source.path);
        if (!_shouldIncludeCacheEntry(relative)) continue;
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
      };
      await File(path.join(temporary.path, 'manifest.json'))
          .writeAsString(json.encode(manifest), flush: true);

      await destination.parent.create(recursive: true);
      final partial = File(
          '$destinationPath.${pid}_${DateTime.now().microsecondsSinceEpoch}.partial');
      final zip = ZipFileEncoder();
      try {
        zip.create(partial.path, level: ZipFileEncoder.GZIP);
        // `ZipFileEncoder.addDirectory` in archive 3.x starts every file write
        // concurrently against one encoder. Entries can then receive another
        // file's bytes. This is already running in a worker isolate, so write
        // sequentially for deterministic, corruption-free archives.
        await for (final entity
            in temporary.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final archiveName = _portableRelative(
              path.relative(entity.path, from: temporary.path));
          await zip.addFile(entity, archiveName, ZipFileEncoder.GZIP);
        }
        await zip.close();
      } catch (_) {
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
      await _atomicReplaceFile(partial, destination);
      return <int>[payloadFiles.length, encoder.songManifest.length];
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
  }) async {
    Map<String, Object?> transaction;
    try {
      transaction = await Isolate.run(() => _restoreBackupOnWorker(
            backup.absolute.path,
            destination.absolute.path,
            currentData.absolute.path,
          ));
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
    );
  }

  static Future<Map<String, Object?>> _restoreBackupOnWorker(String backupFile,
      String destinationDirectory, String currentDirectory) async {
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
    InputFileStream? input;
    try {
      await extraction.create(recursive: true);
      input = InputFileStream(backup.path);
      final archive = ZipDecoder().decodeBuffer(input, verify: true);
      _validateArchive(archive);
      extractArchiveToDiskSync(archive, extraction.path);
      await archive.clear();
      await input.close();
      input = null;

      final manifestFile = File(path.join(extraction.path, 'manifest.json'));
      final manifestValue = await _tryReadJson(manifestFile);
      if (manifestValue is! Map ||
          manifestValue['format'] != _backupFormat ||
          manifestValue['version'] != _backupVersion) {
        throw const CacheBackupException('Unsupported or damaged backup');
      }
      final manifest =
          manifestValue.map((key, value) => MapEntry(key.toString(), value));
      final payload = Directory(path.join(extraction.path, 'payload'));
      final files = await _verifyPayload(payload, manifest['files']);

      final catalog = await _CurrentLibraryCatalog.read(currentData);
      final decoder = _PortablePathDecoder(
        destination: destination,
        manifest: manifest,
        catalog: catalog,
      );
      await for (final entity
          in payload.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: payload.path);
        if (!_looksLikeJson(relative)) continue;
        final decoded = await _tryReadJson(entity);
        if (decoded == null) {
          throw CacheBackupException(
              'A cache document is damaged: ${path.basename(relative)}');
        }
        final restored = decoder.convert(decoded);
        await entity.writeAsString(
            json.encode(identical(restored, _dropValue) ? null : restored),
            flush: true);
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
      };
    } catch (error) {
      if (await staged.exists()) await staged.delete(recursive: true);
      if (error is CacheBackupException) rethrow;
      throw CacheBackupException('Could not restore backup: $error');
    } finally {
      if (input != null) await input.close();
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
    'collections.json',
    'custom_audio_order.json',
    'lyric_source.json',
    'online_library.json',
    'playback_state.json',
    'playback_statistics.json',
  };
  static const _cacheDirectoryMarkers = <String>{
    'covers',
    'metadata_preview',
    'imported-assets',
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

  Future<Object?> convert(Object? value) async {
    if (value is String) return _convertString(value);
    if (value is List) {
      return Future.wait<Object?>([for (final item in value) convert(item)]);
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final convertedKey = await _convertString(entry.key.toString());
        result[convertedKey] = await convert(entry.value);
      }
      return result;
    }
    return value;
  }

  Future<String> _convertString(String value) async {
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
      if (known != null) return known;
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
      if (known != null) return known;
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
  }

  final Directory destination;
  final _CurrentLibraryCatalog catalog;
  final Map<String, Map<String, Object?>> songs = {};
  final Map<String, _CurrentRoot> rootMatches = {};
  final Set<String> _resolved = {};
  final Set<String> _missing = {};
  final Map<String, String> _resolvedPaths = {};

  int get restoredSongs => _resolved.length;
  int get missingSongs => _missing.length;

  Object? convert(Object? value) {
    if (value is String) return _convertString(value);
    if (value is List) {
      final result = <Object?>[];
      for (final item in value) {
        final converted = convert(item);
        if (!identical(converted, _dropValue)) result.add(converted);
      }
      return result;
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final convertedKey = _convertString(entry.key.toString());
        if (identical(convertedKey, _dropValue)) continue;
        final converted = convert(entry.value);
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

  Object _convertString(String value) {
    if (!value.startsWith(_tokenPrefix)) return value;
    if (value.startsWith('${_tokenPrefix}cache/')) {
      final encoded = value.substring('${_tokenPrefix}cache/'.length);
      final relative = Uri.decodeComponent(encoded);
      if (!_isSafeRelative(relative)) return _dropValue;
      return path.normalize(path.join(destination.path, relative));
    }
    if (value == '${_tokenPrefix}cache') return destination.path;
    if (value.startsWith('${_tokenPrefix}root-directory/')) {
      final rest = value.substring('${_tokenPrefix}root-directory/'.length);
      final separator = rest.indexOf('/');
      if (separator <= 0) return _dropValue;
      final id = rest.substring(0, separator);
      final relative = Uri.decodeComponent(rest.substring(separator + 1));
      if (!_isSafeRelative(relative)) return _dropValue;
      final root = rootMatches[id];
      if (root == null) return _dropValue;
      final directory = path.normalize(path.join(root.path, relative));
      return Directory(directory).existsSync() ? directory : _dropValue;
    }
    if (value.startsWith('${_tokenPrefix}root/')) {
      final id = value.substring('${_tokenPrefix}root/'.length);
      return rootMatches[id]?.path ?? _dropValue;
    }
    if (value.startsWith('${_tokenPrefix}song/')) {
      return _resolvedPaths[value] ?? _dropValue;
    }
    return _dropValue;
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
      segment == 'updates' ||
      segment.startsWith('.dan-player-restore-') ||
      segment.startsWith('.dan-player-pending-') ||
      segment.startsWith('.dan-player-previous-') ||
      segment.startsWith('.dan-player-before-restore-'))) {
    return false;
  }
  final lower = portable.toLowerCase();
  return !lower.endsWith('.tmp') &&
      !lower.endsWith('.partial') &&
      !lower.endsWith('.exe') &&
      !lower.endsWith('.msi') &&
      !lower.endsWith('.msix') &&
      !lower.endsWith('.msixbundle');
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
        _containsAbsolutePath(entry.value));
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

void _validateArchive(Archive archive) {
  final names = <String>{};
  var total = 0;
  for (final file in archive.files) {
    final name = _portableRelative(file.name);
    final comparisonName = name.toLowerCase();
    if (!_isSafeRelative(name) ||
        file.isSymbolicLink ||
        !names.add(comparisonName)) {
      throw const CacheBackupException('Unsafe or duplicated backup entry');
    }
    if (name != 'manifest.json' &&
        name != 'payload' &&
        !name.startsWith('payload/')) {
      throw const CacheBackupException('Unexpected backup entry');
    }
    total += file.size;
    if (file.size > 1024 * 1024 * 1024 || total > 4 * 1024 * 1024 * 1024) {
      throw const CacheBackupException('Backup is too large to restore safely');
    }
  }
  if (!names.contains('manifest.json')) {
    throw const CacheBackupException('Backup manifest is missing');
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
        descriptor['sha256'] != await _fileDigest(entity)) {
      throw const CacheBackupException('Backup payload verification failed');
    }
    actual.add(relative);
  }
  if (actual.length != expected.length || !actual.containsAll(expected.keys)) {
    throw const CacheBackupException('Backup payload is incomplete');
  }
  return actual.length;
}
