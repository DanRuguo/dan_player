part of 'cache_backup_service.dart';

class _MusicFolder {
  _MusicFolder(this.id, this.label);
  final String id;
  final String label;
  final List<File> files = [];
  int bytes = 0;
}

class _MusicInventory {
  _MusicInventory(this.folders);
  final List<_MusicFolder> folders;

  static Future<_MusicInventory> read(Object? index) async {
    final candidates = <String, String>{};
    void visit(Object? value) {
      if (value is Map) {
        final candidate = value['path'];
        if (candidate is String &&
            path.isAbsolute(candidate) &&
            _looksLikeAudioPath(candidate)) {
          candidates[path.normalize(candidate).toLowerCase()] = candidate;
        }
        // A CUE entry's displayed path is virtual. Its physical source and cue
        // sheet must travel together and the source is included only once.
        final cue = value['cue_track'];
        if (cue is Map) {
          for (final item in cue.values) {
            if (item is String &&
                path.isAbsolute(item) &&
                (_looksLikeAudioPath(item) ||
                    path.extension(item).toLowerCase() == '.cue')) {
              candidates[path.normalize(item).toLowerCase()] = item;
            }
          }
        }
        for (final child in value.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
        }
      }
    }

    visit(index);
    final folders = <String, _MusicFolder>{};
    final sorted = candidates.values.toList()..sort();
    for (final candidate in sorted) {
      final file = File(candidate);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      // Links are not copied: backup covers indexed regular local sources.
      if (await FileSystemEntity.type(candidate, followLinks: false) !=
          FileSystemEntityType.file) continue;
      final parent = path.dirname(candidate);
      final folder = folders.putIfAbsent(
          parent.toLowerCase(),
          () => _MusicFolder(
              'f${sha256.convert(utf8.encode(parent.toLowerCase())).toString().substring(0, 16)}',
              parent));
      folder.files.add(file);
      folder.bytes += stat.size;
    }
    return _MusicInventory(folders.values.toList());
  }
}

bool _isMusicPayload(String value) =>
    value.replaceAll('\\', '/').startsWith('restored-music/');

String? _backgroundAssetId(String value) {
  final match = RegExp(r'^background-images/([a-f0-9]{64})\.png$')
      .firstMatch(value.replaceAll('\\', '/'));
  return match?.group(1);
}

String? _backgroundAssetReference(Object? value) {
  if (value is! Map) return null;
  final id = value['customImageId'];
  return id is String && RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(id)
      ? 'background-images/$id'
      : null;
}

BackupContents _contentsFromManifest(Map<String, Object?> manifest) {
  final legacy = manifest['version'] == 1;
  final components = legacy
      ? {...BackupComponent.values}
      : {
          for (final component in BackupComponent.values)
            if ((manifest['components'] as List? ?? [])
                .contains(component.name))
              component,
        };
  final music = <BackupMusicFolder>[];
  final ids = <String>{};
  final tokens = <String>{};
  final musicPaths = <String>{};
  final payload = <String, Map>{
    for (final file in manifest['files'] as List? ?? const [])
      if (file is Map && file['path'] is String) file['path'] as String: file,
  };
  for (final raw in manifest['music'] as List? ?? const []) {
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['name'] is! String ||
        raw['files'] is! List ||
        !RegExp(r'^f[0-9a-f]{1,16}$').hasMatch(raw['id'] as String) ||
        !ids.add(raw['id'] as String)) {
      throw const CacheBackupException('Invalid music folder manifest');
    }
    var bytes = 0;
    for (final entry in raw['files'] as List) {
      if (entry is! Map ||
          entry['path'] is! String ||
          entry['token'] is! String ||
          entry['size'] is! int ||
          (entry['size'] as int) < 0) {
        throw const CacheBackupException('Invalid music entry manifest');
      }
      final relative = entry['path'] as String;
      final token = entry['token'] as String;
      if (!_isSafeRelative(relative) ||
          !relative.startsWith('restored-music/${raw['id']}/') ||
          path.posix.split(relative).length != 3 ||
          !musicPaths.add(relative.toLowerCase()) ||
          !tokens.add(token) ||
          payload[relative]?['size'] != entry['size'] ||
          (!token.startsWith('${_tokenPrefix}song/') &&
              !token.startsWith('${_tokenPrefix}root-file/')) ||
          (token.startsWith('${_tokenPrefix}song/') &&
              !(manifest['songs'] as Map? ?? {}).containsKey(token))) {
        throw const CacheBackupException(
            'Music manifest does not match its payload');
      }
      bytes += entry['size'] as int;
    }
    music.add(BackupMusicFolder(
        id: raw['id'] as String,
        name: raw['name'] as String,
        songCount: (raw['files'] as List).length,
        bytes: bytes));
  }
  if (payload.keys
      .where(_isMusicPayload)
      .any((value) => !musicPaths.contains(value.toLowerCase()))) {
    throw const CacheBackupException('Music payload has no folder descriptor');
  }
  return BackupContents(
      components: components,
      musicFolders: music,
      legacy: legacy,
      encrypted: manifest['encrypted'] == true,
      createdAt: DateTime.tryParse(manifest['createdAt']?.toString() ?? ''));
}

Map<String, String> _selectedMusicPaths(Map<String, Object?> manifest,
    BackupSelection selection, Directory destination,
    {required String musicBatch}) {
  _contentsFromManifest(manifest);
  final result = <String, String>{};
  final filePaths = <String>{};
  for (final raw in manifest['music'] as List? ?? const []) {
    final folder = raw as Map;
    final id = folder['id'] as String;
    for (final entry in folder['files'] as List) {
      if (entry is! Map ||
          entry['path'] is! String ||
          entry['token'] is! String) {
        throw const CacheBackupException('Invalid music entry manifest');
      }
      final relative = entry['path'] as String;
      if (!_isSafeRelative(relative) ||
          !relative.startsWith('restored-music/$id/') ||
          path.posix.split(relative).length != 3 ||
          !filePaths.add(relative.toLowerCase())) {
        throw const CacheBackupException('Unsafe music destination');
      }
      if (selection.includesFolder(id)) {
        result[entry['token'] as String] = path.normalize(path.join(
            destination.path,
            'restored-music',
            musicBatch,
            relative.substring('restored-music/'.length)));
      }
    }
  }
  return result;
}

Future<void> _copyReferencedCacheAssets(Object? value, Directory source,
    Directory payload, _BackupWorkerControl control) async {
  if (value is String && value.startsWith('${_tokenPrefix}cache/')) {
    final relative =
        Uri.decodeComponent(value.substring('${_tokenPrefix}cache/'.length));
    if (!_isSafeRelative(relative) ||
        _looksLikeJson(relative) ||
        !_shouldIncludeCacheEntry(relative)) return;
    final input = File(path.join(source.path, relative));
    final output = File(path.join(payload.path, relative));
    if (await input.exists() && !await output.exists()) {
      await _checkedCopy(input, output, control);
    }
  } else if (value is Map) {
    final background = _backgroundAssetReference(value);
    if (background != null) {
      final sourceFile = File(path.join(source.path, background));
      if (!await sourceFile.exists() ||
          await _fileDigest(sourceFile) != _backgroundAssetId(background)) {
        throw const CacheBackupException(
            'Custom background is missing or damaged');
      }
      await _copyReferencedCacheAssets(
          '${_tokenPrefix}cache/${Uri.encodeComponent(background)}',
          source,
          payload,
          control);
    }
    for (final child in value.values) {
      await _copyReferencedCacheAssets(child, source, payload, control);
    }
  } else if (value is List) {
    for (final child in value) {
      await _copyReferencedCacheAssets(child, source, payload, control);
    }
  }
}

Future<void> _checkedCopy(
    File source, File destination, _BackupWorkerControl control) async {
  await control.check('copy');
  final before = await source.stat();
  if (before.type != FileSystemEntityType.file) {
    throw const CacheBackupException(
        'A selected source is no longer available');
  }
  await destination.parent.create(recursive: true);
  final output = await destination.open(mode: FileMode.write);
  var copied = 0;
  try {
    await for (final bytes in source.openRead()) {
      await control.check('copy', copied, before.size);
      await output.writeFrom(bytes);
      copied += bytes.length;
    }
    await output.flush();
  } finally {
    await output.close();
  }
  final after = await source.stat();
  if (before.size != copied ||
      before.size != after.size ||
      before.modified != after.modified) {
    throw const CacheBackupException('A selected source changed during backup');
  }
}

Future<void> _mergeUnselectedCurrent(
    Directory current,
    Directory payload,
    Directory target,
    BackupSelection selection,
    _BackupWorkerControl control) async {
  if (!await current.exists()) return;
  final currentReferences = <String>{};
  await for (final entity
      in current.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = path.relative(entity.path, from: current.path);
    if (_looksLikeJson(relative) &&
        !selection.components.contains(backupComponentForPath(relative))) {
      currentReferences.addAll(referencedCurrentCacheAssets(
          await _tryReadJson(entity), current.path));
    }
  }
  Object? remap(Object? value) {
    if (value is String &&
        path.isAbsolute(value) &&
        _isInsideOrSame(current.path, value)) {
      return path.join(target.path, path.relative(value, from: current.path));
    }
    if (value is List) return value.map(remap).toList();
    if (value is Map)
      return {
        for (final entry in value.entries)
          remap(entry.key.toString()) as String: remap(entry.value)
      };
    return value;
  }

  await for (final entity
      in current.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = path.relative(entity.path, from: current.path);
    if (!_shouldIncludeCacheEntry(relative) && !_isMusicPayload(relative))
      continue;
    final component = backupComponentForPath(relative);
    final referenced =
        currentReferences.contains(_portableRelative(relative).toLowerCase());
    if (!_isMusicPayload(relative) &&
        selection.components.contains(component) &&
        !referenced) continue;
    final output = File(path.join(payload.path, relative));
    if (await output.exists() && !referenced) continue;
    await _checkedCopy(entity, output, control);
    if (_looksLikeJson(relative)) {
      final decoded = await _tryReadJson(output);
      if (decoded == null)
        throw const CacheBackupException('Current data is damaged');
      await output.writeAsString(json.encode(remap(decoded)), flush: true);
    }
  }
}
