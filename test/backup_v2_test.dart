import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/data/backup_encryption.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory sandbox, source, current;
  late File musicA, musicB;
  const service = CacheBackupService();
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('dan-backup-v2-test-');
    source = await Directory(path.join(sandbox.path, 'source')).create();
    current = await Directory(path.join(sandbox.path, 'current')).create();
    musicA = File(path.join(sandbox.path, '音乐 A', 'same.mp3'));
    musicB = File(path.join(sandbox.path, 'Music B', 'same.mp3'));
    await musicA.parent.create();
    await musicB.parent.create();
    await musicA.writeAsBytes([1, 2, 3, 4]);
    await musicB.writeAsBytes([8, 7, 6]);
    await _json(source, 'index.json', {
      'roots': [musicA.parent.path, musicB.parent.path],
      'folders': [
        for (final music in [musicA, musicB])
          {
            'path': music.parent.path,
            'audios': [
              {'path': music.path, 'file_size': await music.length()}
            ],
          }
      ],
    });
    await _json(source, 'settings.json', {
      'theme': 'backup',
      'nested': {'symbols': '😺'}
    });
    await _json(source, 'playlists.json', {
      'songs': [
        {'path': musicA.path},
        {'path': musicB.path}
      ]
    });
    await _json(source, 'playback_statistics.json', {'seconds': 987});
    await _json(current, 'settings.json', {'theme': 'current'});
    await _json(current, 'playback_statistics.json', {'seconds': 123});
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test(
      'all backup separates same-named files, restores one folder and preserves unselected current state',
      () async {
    final backup = File(path.join(sandbox.path, 'all.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection: const BackupSelection(includeMusic: true));
    final contents = await service.inspectBackup(backup: backup);
    expect(contents.musicFolders, hasLength(2));
    expect(contents.musicCount, 2);
    final wanted = contents.musicFolders
        .singleWhere((folder) => folder.name == musicA.parent.path);
    Directory? staged;
    final destination = Directory(path.join(sandbox.path, 'restored'));
    final result = await service.restoreBackup(
        backup: backup,
        destination: destination,
        currentData: current,
        selection: BackupSelection(
            components: {BackupComponent.library, BackupComponent.playlists},
            includeMusic: true,
            musicFolders: {wanted.id}),
        activateLocation: (_, value) async => staged = value);
    expect(result.musicCount, 1);
    expect(await musicA.readAsBytes(), [1, 2, 3, 4]);
    expect(await musicB.readAsBytes(), [8, 7, 6]);
    expect(await _read(staged!, 'settings.json'), {'theme': 'current'});
    expect(await _read(staged!, 'playback_statistics.json'), {'seconds': 123});
    final files = (await staged!.list(recursive: true).toList())
        .whereType<File>()
        .where((file) => file.path.endsWith('.mp3'));
    expect(files, hasLength(1));
    expect(await files.single.readAsBytes(), [1, 2, 3, 4]);
    final index = await _read(staged!, 'index.json') as Map;
    final audios = (index['folders'] as List)
        .expand((folder) => (folder as Map)['audios'] as List)
        .cast<Map>();
    final restoredAudio = audios.firstWhere(
        (item) => (item['path'] as String).contains('restored-music'));
    final restoredFolder = (index['folders'] as List).cast<Map>().firstWhere(
        (folder) => (folder['audios'] as List)
            .any((audio) => (audio as Map)['path'] == restoredAudio['path']));
    expect(
        restoredFolder['path'], path.dirname(restoredAudio['path'] as String));
    expect(path.isWithin(destination.path, restoredAudio['path'] as String),
        isTrue);
    expect(await current.exists(), isTrue);
    expect(await destination.exists(), isFalse);
  });

  test(
      'settings-only backup includes referenced asset but no music or unrelated cache',
      () async {
    final cover = File(path.join(source.path, 'backgrounds', 'custom.png'));
    await cover.parent.create();
    await cover.writeAsBytes([9, 9, 9]);
    await _json(source, 'settings.json', {'customBackground': cover.path});
    final backup = File(path.join(sandbox.path, 'settings.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection:
            const BackupSelection(components: {BackupComponent.settings}));
    final info = await service.inspectBackup(backup: backup);
    expect(info.components, {BackupComponent.settings});
    expect(info.musicCount, 0);
    Directory? staged;
    final target = Directory(path.join(sandbox.path, 'target'));
    await service.restoreBackup(
        backup: backup,
        destination: target,
        currentData: current,
        selection:
            const BackupSelection(components: {BackupComponent.settings}),
        activateLocation: (_, value) async => staged = value);
    final assetPath = (await _read(staged!, 'settings.json')
        as Map)['customBackground'] as String;
    expect(assetPath, contains('restored-assets'));
    expect(
        await File(path.join(
                staged!.path, path.relative(assetPath, from: target.path)))
            .readAsBytes(),
        [9, 9, 9]);
    expect(await _read(staged!, 'playback_statistics.json'), {'seconds': 123});
    expect(path.isWithin(target.path, assetPath), isTrue);
  });

  test('restoring settings from a full backup excludes all music payload files',
      () async {
    final backup = File(path.join(sandbox.path, 'all.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection: const BackupSelection(includeMusic: true));
    Directory? staged;
    final result = await service.restoreBackup(
        backup: backup,
        destination: Directory(path.join(sandbox.path, 'target')),
        currentData: current,
        selection:
            const BackupSelection(components: {BackupComponent.settings}),
        activateLocation: (_, value) async => staged = value);
    expect(result.musicCount, 0);
    expect(
        (await staged!.list(recursive: true).toList())
            .whereType<File>()
            .any((file) => file.path.endsWith('.mp3')),
        isFalse);
    expect(await _read(staged!, 'settings.json'), {
      'theme': 'backup',
      'nested': {'symbols': '😺'}
    });
  });

  test(
      'music-only restoration retains all current cache and old restored songs',
      () async {
    final old =
        File(path.join(current.path, 'restored-music', 'previous', 'old.mp3'));
    await old.parent.create(recursive: true);
    await old.writeAsBytes([42]);
    final backup = File(path.join(sandbox.path, 'music.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection: const BackupSelection(components: {}, includeMusic: true));
    Directory? staged;
    await service.restoreBackup(
        backup: backup,
        destination: current,
        currentData: current,
        selection: const BackupSelection(components: {}, includeMusic: true),
        activateLocation: (_, value) async => staged = value);
    expect(await _read(staged!, 'settings.json'), {'theme': 'current'});
    expect(await old.readAsBytes(), [42]);
    expect(
        await File(path.join(
                staged!.path, 'restored-music', 'previous', 'old.mp3'))
            .readAsBytes(),
        [42]);
    expect(
        (await staged!.list(recursive: true).toList())
            .whereType<File>()
            .where((file) => file.path.endsWith('.mp3')),
        hasLength(3));
  });

  test(
      'Unicode, leading/trailing spaces, symbols and emoji password round trip and reject wrong password',
      () async {
    const password = ' 密码😺 あ 한글 \\ / \$ "\'!\n ';
    final backup = File(path.join(sandbox.path, 'encrypted.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        password: password,
        selection:
            const BackupSelection(components: {BackupComponent.settings}));
    expect(await BackupEncryption.isEncrypted(backup), isTrue);
    await expectLater(service.inspectBackup(backup: backup),
        throwsA(isA<CacheBackupPasswordRequired>()));
    await expectLater(
        service.inspectBackup(backup: backup, password: password.trim()),
        throwsA(isA<CacheBackupException>()));
    final contents =
        await service.inspectBackup(backup: backup, password: password);
    expect(contents.encrypted, isTrue);
    Directory? staged;
    await service.restoreBackup(
        backup: backup,
        password: password,
        destination: Directory(path.join(sandbox.path, 'target')),
        currentData: current,
        activateLocation: (_, value) async => staged = value);
    expect((await _read(staged!, 'settings.json') as Map)['theme'], 'backup');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'header, ciphertext and final tag changes never extract or activate data',
      () async {
    final backup = File(path.join(sandbox.path, 'encrypted.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        password: 'symbols+#中文',
        selection:
            const BackupSelection(components: {BackupComponent.settings}));
    final original = await backup.readAsBytes();
    for (final offset in [12, 50, original.length - 1]) {
      final tampered = File(path.join(sandbox.path, 'tampered-$offset.bak'));
      final bytes = [...original];
      bytes[offset] ^= 1;
      await tampered.writeAsBytes(bytes);
      var activated = false;
      await expectLater(
          service.restoreBackup(
              backup: tampered,
              password: 'symbols+#中文',
              destination: Directory(path.join(sandbox.path, 'target')),
              currentData: current,
              activateLocation: (_, __) async => activated = true),
          throwsA(isA<CacheBackupException>()));
      expect(activated, isFalse);
    }
    expect(await _read(current, 'settings.json'), {'theme': 'current'});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'cancellation while copying keeps old archive and cleans temporary payload',
      () async {
    final backup = File(path.join(sandbox.path, 'existing.bak'));
    await backup.writeAsBytes([8, 8]);
    final operation = BackupOperation();
    await operation.cancel();
    await expectLater(
        service.exportBackup(
            source: source,
            destination: backup,
            operation: operation,
            selection: const BackupSelection(includeMusic: true)),
        throwsA(isA<CacheBackupCancelled>()));
    expect(await backup.readAsBytes(), [8, 8]);
    expect(
        (await sandbox.list().toList()).where(
            (entity) => path.basename(entity.path).startsWith('.dan-player')),
        isEmpty);
  });

  test('old v1 ZIP remains readable and reports data-only contents', () async {
    final backup = File(path.join(sandbox.path, 'legacy.bak'));
    await service.exportBackup(source: source, destination: backup);
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final manifest = archive.findFile('manifest.json')!;
    final jsonManifest =
        json.decode(utf8.decode(manifest.content as List<int>)) as Map;
    jsonManifest['version'] = 1;
    jsonManifest.remove('components');
    jsonManifest.remove('music');
    final encoded = utf8.encode(json.encode(jsonManifest));
    archive.addFile(ArchiveFile('manifest.json', encoded.length, encoded));
    await backup.writeAsBytes(ZipEncoder().encode(archive)!);
    final info = await service.inspectBackup(backup: backup);
    expect(info.legacy, isTrue);
    expect(info.musicCount, 0);
    expect(info.components, {...BackupComponent.values});
  });

  test(
      'noncanonical archive aliases are rejected before any payload extraction',
      () async {
    final file = File(path.join(sandbox.path, 'unsafe.bak'));
    for (final name in [
      'payload/a/../settings.json',
      'payload/./settings.json',
      'payload//settings.json',
      'payload/.dan-player-restore-preserve.json',
      'payload/.DAN-PLAYER-RESTORE-PRESERVE.JSON'
    ]) {
      final archive = Archive()
        ..addFile(ArchiveFile.string('manifest.json', '{}'))
        ..addFile(ArchiveFile.string(name, '{}'));
      await file.writeAsBytes(ZipEncoder().encode(archive)!);
      await expectLater(service.inspectBackup(backup: file),
          throwsA(isA<CacheBackupException>()));
    }
  });

  test(
      'cancel during a streaming music copy cleans up without replacing existing backup',
      () async {
    await musicA.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 7));
    final backup = File(path.join(sandbox.path, 'cancel.bak'));
    await backup.writeAsBytes([7, 1]);
    late BackupOperation job;
    job = BackupOperation(onProgress: (progress) {
      if (progress.phase == 'copy' &&
          progress.completed > 0 &&
          !job.isCancelled) {
        unawaited(job.cancel());
      }
    });
    await expectLater(
        service.exportBackup(
            source: source,
            destination: backup,
            selection: const BackupSelection(includeMusic: true),
            operation: job),
        throwsA(isA<CacheBackupCancelled>()));
    expect(await backup.readAsBytes(), [7, 1]);
    expect(
        (await sandbox.list().toList()).where(
            (entity) => path.basename(entity.path).startsWith('.dan-player')),
        isEmpty);
  });

  test(
      'selected settings assets cannot replace resources used by unselected playlists',
      () async {
    final oldCover =
        File(path.join(current.path, 'imported-assets', '0-cover.png'));
    await oldCover.parent.create();
    await oldCover.writeAsBytes([1]);
    await _json(current, 'playlists.json', {'imagePath': oldCover.path});
    final backupCover =
        File(path.join(source.path, 'imported-assets', '0-cover.png'));
    await backupCover.parent.create();
    await backupCover.writeAsBytes([2]);
    await _json(source, 'settings.json', {'background': backupCover.path});
    final backup = File(path.join(sandbox.path, 'collision.bak'));
    await service.exportBackup(source: source, destination: backup);
    Directory? staged;
    final target = Directory(path.join(sandbox.path, 'target'));
    await service.restoreBackup(
        backup: backup,
        destination: target,
        currentData: current,
        selection:
            const BackupSelection(components: {BackupComponent.settings}),
        activateLocation: (_, value) async => staged = value);
    final settings = await _read(staged!, 'settings.json') as Map;
    final playlist = await _read(staged!, 'playlists.json') as Map;
    expect(settings['background'], isNot(playlist['imagePath']));
    for (final pair in [
      (settings['background'] as String, 2),
      (playlist['imagePath'] as String, 1)
    ]) {
      expect(
          await File(path.join(
                  staged!.path, path.relative(pair.$1, from: target.path)))
              .readAsBytes(),
          [pair.$2]);
    }
  });

  test(
      'missing music payload reference and duplicate song token are rejected on inspection',
      () async {
    final backup = File(path.join(sandbox.path, 'music.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection: const BackupSelection(includeMusic: true));
    final original = await backup.readAsBytes();
    for (final missing in [true, false]) {
      final archive = ZipDecoder().decodeBytes(original);
      final manifest = json.decode(utf8.decode(
          archive.findFile('manifest.json')!.content as List<int>)) as Map;
      final folders = manifest['music'] as List;
      final first = ((folders[0] as Map)['files'] as List)[0] as Map;
      final second = ((folders[1] as Map)['files'] as List)[0] as Map;
      if (missing) {
        first['path'] =
            'restored-music/${(folders[0] as Map)['id']}/not-present.mp3';
      } else {
        second['token'] = first['token'];
      }
      final bytes = utf8.encode(json.encode(manifest));
      archive.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
      await backup.writeAsBytes(ZipEncoder().encode(archive)!);
      await expectLater(service.inspectBackup(backup: backup),
          throwsA(isA<CacheBackupException>()));
    }
  });
  test('authenticated encryption spans chunks and final partial block',
      () async {
    final input = File(path.join(sandbox.path, 'cipher-input'));
    final random = Random(19);
    final bytes = List<int>.generate(700013, (_) => random.nextInt(256));
    await input.writeAsBytes(bytes);
    final encrypted = File(path.join(sandbox.path, 'cipher-output'));
    final decoded = File(path.join(sandbox.path, 'decoded'));
    await BackupEncryption.encrypt(input, encrypted, 'multi chunk 🔑');
    await BackupEncryption.decrypt(encrypted, decoded, 'multi chunk 🔑');
    expect(await decoded.readAsBytes(), bytes);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
      'CUE tracks share one physical source and restore real source/sheet paths',
      () async {
    final cue = File(path.join(musicA.parent.path, 'disc.cue'));
    await cue.writeAsString(
        'FILE "same.mp3" MP3\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n');
    await _json(source, 'index.json', {
      'roots': [musicA.parent.path],
      'folders': [
        {
          'path': musicA.parent.path,
          'audios': [
            for (var number = 1; number <= 2; number++)
              {
                'path': CueTrackReference(
                        cuePath: cue.path,
                        sourcePath: musicA.path,
                        number: number,
                        startFrame: number * 75)
                    .identity,
                'cue_track': CueTrackReference(
                        cuePath: cue.path,
                        sourcePath: musicA.path,
                        number: number,
                        startFrame: number * 75)
                    .toMap(),
              }
          ],
        }
      ],
    });
    final backup = File(path.join(sandbox.path, 'cue.bak'));
    final result = await service.exportBackup(
        source: source,
        destination: backup,
        selection: const BackupSelection(includeMusic: true));
    expect(result.musicCount, 2,
        reason: 'One source plus one CUE sheet, not one source per track');
    Directory? staged;
    final target = Directory(path.join(sandbox.path, 'cue-target'));
    await service.restoreBackup(
        backup: backup,
        destination: target,
        currentData: current,
        selection: const BackupSelection(includeMusic: true),
        activateLocation: (_, value) async => staged = value);
    final index = await _read(staged!, 'index.json') as Map;
    final audios = (((index['folders'] as List).first as Map)['audios'] as List)
        .cast<Map>();
    expect(audios, hasLength(2));
    for (final audio in audios) {
      final restored = CueTrackReference.fromMap(audio['cue_track'] as Map);
      for (final filePath in [restored.cuePath, restored.sourcePath]) {
        expect(
            await File(path.join(
                    staged!.path, path.relative(filePath, from: target.path)))
                .exists(),
            isTrue);
      }
    }
  });
}

Future<void> _json(Directory directory, String name, Object value) async {
  await File(path.join(directory.path, name)).writeAsString(json.encode(value));
}

Future<Object?> _read(Directory directory, String name) async =>
    json.decode(await File(path.join(directory.path, name)).readAsString());
