part of 'cache_backup_service.dart';

class _BackupWorkerControl {
  const _BackupWorkerControl(this.cancellationPath, this.events);
  final String cancellationPath;
  final SendPort events;
  Future<void> check(String phase, [int completed = 0, int total = 0]) async {
    if (await File(cancellationPath).exists())
      throw const CacheBackupCancelled();
    events.send([phase, completed, total]);
  }
}

Future<T> _runBackupOperation<T>(BackupOperation? operation,
    Future<T> Function(_BackupWorkerControl) worker) async {
  final temporary =
      await Directory.systemTemp.createTemp('dan-player-backup-job-');
  final cancelled = File(path.join(temporary.path, 'cancel'));
  final receive = ReceivePort();
  final subscription = receive.listen((event) {
    if (event is List && event.length == 3) {
      operation?.onProgress?.call(
          BackupProgress(event[0] as String, event[1] as int, event[2] as int));
    }
  });
  operation?.cancelWorker = () async {
    await cancelled.writeAsString('cancel');
  };
  try {
    if (operation?.isCancelled ?? false) throw const CacheBackupCancelled();
    final control = _BackupWorkerControl(cancelled.path, receive.sendPort);
    return await Isolate.run(() => worker(control));
  } finally {
    if (operation != null) operation.cancelWorker = null;
    await subscription.cancel();
    receive.close();
    await temporary.delete(recursive: true);
  }
}

Future<File> _openBackupEnvelope(File backup, Directory temporary,
    String? password, _BackupWorkerControl control) async {
  if (!await BackupEncryption.isEncrypted(backup)) return backup;
  if (password == null) throw const CacheBackupPasswordRequired();
  final plain = File(path.join(temporary.path, 'authenticated.zip'));
  try {
    await BackupEncryption.decrypt(backup, plain, password,
        checkpoint: (done, total) => control.check('decrypt', done, total));
  } on CacheBackupCancelled {
    rethrow;
  } catch (_) {
    throw const CacheBackupException(
        'Password is incorrect or backup is damaged');
  }
  return plain;
}

Future<void> _writeStreamingZip(
    Directory source, File destination, _BackupWorkerControl control) async {
  final output = OutputFileStream(destination.path);
  final encoder = ZipEncoder()..startEncode(output);
  // archive 3.x materializes uncompressed input before Deflate. Precompress
  // each entry with dart:io's bounded native zlib stream, then pass raw Deflate
  // bytes through the ZIP encoder (including ZIP64 sizes) without recompressing.
  final scratch = await source.parent.createTemp('.dan-player-deflate-');
  try {
    final entries = <File>[];
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is File && !path.equals(entity.path, destination.path))
        entries.add(entity);
    }
    var completed = 0;
    for (final file in entries) {
      await control.check('compress', completed, entries.length);
      final relative =
          _portableRelative(path.relative(file.path, from: source.path));
      final compressed = File(path.join(scratch.path, 'entry.deflate'));
      var crc = 0;
      var bytesRead = 0;
      Stream<List<int>> checkedInput() async* {
        await for (final chunk in file.openRead()) {
          await control.check('compress', bytesRead, await file.length());
          bytesRead += chunk.length;
          crc = getCrc32(chunk, crc);
          yield chunk;
        }
      }

      final sink = compressed.openWrite();
      try {
        await sink.addStream(
            checkedInput().transform(ZLibEncoder(raw: true, level: 9)));
        await sink.flush();
      } finally {
        await sink.close();
      }
      final stream = InputFileStream(compressed.path);
      try {
        final entry =
            ArchiveFile(relative, bytesRead, stream, ArchiveFile.DEFLATE)
              ..crc32 = crc;
        encoder.addFile(entry);
      } finally {
        await stream.close();
      }
      completed++;
    }
    encoder.endEncode();
  } finally {
    await output.close();
    await scratch.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _readStreamingZip(
    File file, Directory output, _BackupWorkerControl control,
    {bool manifestOnly = false, BackupSelection? selection}) async {
  final input = InputFileStream(file.path);
  try {
    final zip = ZipDirectory.read(input);
    if (zip.fileHeaders.length > 200000)
      throw const CacheBackupException('Too many backup entries');
    final names = <String>{};
    var total = 0;
    ZipFileHeader? manifestEntry;
    for (final header in zip.fileHeaders) {
      final local = header.file;
      final name = header.filename;
      final mode = (header.externalFileAttributes ?? 0) >> 16;
      final size = header.uncompressedSize ?? -1;
      final music = name.startsWith('payload/restored-music/');
      if (!_isSafeRelative(name) ||
          name.contains('\\') ||
          name.toLowerCase().endsWith(BackupRestorePreservation.planName) ||
          path.posix.normalize(name).replaceFirst(RegExp(r'/$'), '') !=
              name.replaceFirst(RegExp(r'/$'), '') ||
          !names.add(name.toLowerCase()) ||
          local == null ||
          local.filename != name ||
          (mode & 0xF000) == 0xA000 ||
          (local.flags & 1) != 0 ||
          !const [0, 8].contains(local.compressionMethod) ||
          size < 0 ||
          size > (music ? 32 * 1024 * 1024 * 1024 : 1024 * 1024 * 1024) ||
          (name != 'manifest.json' &&
              name != 'payload' &&
              !name.startsWith('payload/'))) {
        throw const CacheBackupException(
            'Unsafe, unsupported or duplicated backup entry');
      }
      total += size;
      if (total > 1024 * 1024 * 1024 * 1024)
        throw const CacheBackupException('Backup exceeds safety limit');
      if (name == 'manifest.json') manifestEntry = header;
    }
    if (manifestEntry == null ||
        (manifestEntry.uncompressedSize ?? 0) > 16 * 1024 * 1024) {
      throw const CacheBackupException(
          'Backup manifest is missing or too large');
    }
    final manifestFile = File(path.join(output.path, 'manifest.json'));
    await _extractStreamingEntry(manifestEntry, manifestFile, control);
    final raw = await _tryReadJson(manifestFile);
    if (raw is! Map ||
        raw['format'] != _backupFormat ||
        !const [1, 2].contains(raw['version'])) {
      throw const CacheBackupException('Unsupported or damaged backup');
    }
    final manifest = raw.map((key, value) => MapEntry(key.toString(), value));
    _contentsFromManifest(manifest);
    final expected = <String, Map>{};
    if (manifest['files'] is! List)
      throw const CacheBackupException('Backup file list is missing');
    for (final rawFile in manifest['files'] as List) {
      if (rawFile is! Map ||
          rawFile['path'] is! String ||
          rawFile['size'] is! int ||
          rawFile['sha256'] is! String ||
          !_isSafeRelative(rawFile['path'] as String) ||
          expected.containsKey((rawFile['path'] as String).toLowerCase())) {
        throw const CacheBackupException('Invalid backup file list');
      }
      expected[(rawFile['path'] as String).toLowerCase()] = rawFile;
    }
    final actual = <String>{};
    final extracted = <String>{};
    final available = _contentsFromManifest(manifest).components;
    final selectedComponents =
        selection?.components.intersection(available) ?? available;
    final neededAssets = <String>{};
    void assets(Object? value) {
      if (value is String && value.startsWith('${_tokenPrefix}cache/')) {
        final relative = Uri.decodeComponent(
            value.substring('${_tokenPrefix}cache/'.length));
        if (_isSafeRelative(relative) && !_looksLikeJson(relative))
          neededAssets.add(relative);
      } else if (value is Map) {
        final background = _backgroundAssetReference(value);
        if (background != null) neededAssets.add(background);
        for (final child in value.values) {
          assets(child);
        }
      } else if (value is List) {
        for (final child in value) {
          assets(child);
        }
      }
    }

    if (!manifestOnly) {
      for (final header in zip.fileHeaders) {
        if (!header.filename.startsWith('payload/')) continue;
        final relative = header.filename.substring('payload/'.length);
        if (_looksLikeJson(relative) &&
            selectedComponents.contains(backupComponentForPath(relative))) {
          final descriptor = expected[relative.toLowerCase()];
          if (descriptor == null ||
              descriptor['size'] != header.uncompressedSize) {
            throw const CacheBackupException(
                'Backup manifest does not match its contents');
          }
          final destination = File(path.join(output.path, header.filename));
          await _extractStreamingEntry(header, destination, control);
          assets(await _tryReadJson(destination));
          extracted.add(relative);
        }
      }
    }
    for (final header in zip.fileHeaders) {
      if (header.filename == 'manifest.json' ||
          header.filename.endsWith('/') ||
          header.filename == 'payload') continue;
      final relative = header.filename.substring('payload/'.length);
      final descriptor = expected[relative.toLowerCase()];
      if (descriptor == null || descriptor['size'] != header.uncompressedSize) {
        throw const CacheBackupException(
            'Backup manifest does not match its contents');
      }
      actual.add(relative.toLowerCase());
      final musicParts = relative.split('/');
      final selectedMusic = _isMusicPayload(relative) &&
          musicParts.length == 3 &&
          (selection?.includesFolder(musicParts[1]) ?? true);
      if (!manifestOnly &&
          !extracted.contains(relative) &&
          (selectedMusic ||
              (!_isMusicPayload(relative) &&
                  (selectedComponents
                          .contains(backupComponentForPath(relative)) ||
                      neededAssets.contains(relative))))) {
        await _extractStreamingEntry(
            header, File(path.join(output.path, header.filename)), control);
        extracted.add(relative);
      }
    }
    if (actual.length != expected.length)
      throw const CacheBackupException('Backup payload is incomplete');
    return {...manifest, '_extracted': extracted};
  } finally {
    await input.close();
  }
}

Future<void> _extractStreamingEntry(
    ZipFileHeader header, File output, _BackupWorkerControl control) async {
  await output.parent.create(recursive: true);
  final raw = header.file!.rawContent!;
  Stream<List<int>> chunks() async* {
    while (!raw.isEOS) {
      await control.check('restore');
      yield raw
          .readBytes(raw.length < 65536 ? raw.length : 65536)
          .toUint8List();
    }
  }

  var stream = chunks();
  if (header.file!.compressionMethod == 8)
    stream = stream.transform(ZLibDecoder(raw: true));
  final sink = await output.open(mode: FileMode.write);
  var count = 0;
  var crc = 0;
  try {
    await for (final bytes in stream) {
      count += bytes.length;
      if (count > header.uncompressedSize!)
        throw const CacheBackupException(
            'Backup entry expanded beyond declared size');
      crc = getCrc32(bytes, crc);
      await sink.writeFrom(bytes);
      await control.check('restore', count, header.uncompressedSize!);
    }
    if (count != header.uncompressedSize || crc != header.crc32) {
      throw const CacheBackupException('Backup entry checksum failed');
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
}
