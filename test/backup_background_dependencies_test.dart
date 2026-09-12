import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/data/app_data_location.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = CacheBackupService();
  const settingsOnly = BackupSelection(components: {BackupComponent.settings});
  late Directory parent, sandbox, source, current;
  late File pointer;
  late List<int> mainPng, presetPng, currentPng;
  late String mainId, presetId, currentId;

  Future<void> writeJson(Directory root, String name, Object value) async {
    final file = File(path.join(root.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  Future<Map> readJson(Directory root, String name) async =>
      jsonDecode(await File(path.join(root.path, name)).readAsString()) as Map;

  Future<void> image(Directory root, String id, List<int> bytes) async {
    final file = File(path.join(root.path, 'background-images', id));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> assertFixedImage(
      Directory root, String id, List<int> bytes) async {
    final directory = Directory(path.join(root.path, 'background-images'));
    final store = BackgroundImageStore(directory: () async => directory);
    final provider = await store.imageFor(id);
    expect(provider, isA<FileImage>(),
        reason: 'The production fixed-ID locator must still find $id');
    final file = (provider as FileImage).file;
    expect(file.path, path.join(directory.path, id));
    expect(await file.readAsBytes(), bytes);
    expect('${sha256.convert(bytes)}.png', id);
  }

  Future<Directory> restore(File backup, BackupSelection selection) async {
    final destination = Directory(path.join(sandbox.path, 'restored'));
    final store = AppDataLocationStore(pointer);
    await service.restoreBackup(
        backup: backup,
        destination: destination,
        currentData: current,
        selection: selection,
        activateLocation: (target, staged) => store.schedule(
            nextPath: target.path,
            currentPath: current.path,
            stagedPath: staged.path));
    expect(await store.activatePendingOrReadActive(), destination.path);
    return destination;
  }

  setUp(() async {
    parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    sandbox = await parent.createTemp('backup-background-dependencies-');
    source = await Directory(path.join(sandbox.path, 'source')).create();
    current = await Directory(path.join(sandbox.path, 'current')).create();
    pointer = File(path.join(sandbox.path, 'pointer', 'location.json'));
    // Real PNG assets, read only. Managed background IDs are the SHA256 of
    // encoded PNG bytes, matching BackgroundImageStore's production contract.
    mainPng =
        await File('assets/images/RCE_logo_transparent.png').readAsBytes();
    presetPng = await File('assets/branding/danruguo_light.png').readAsBytes();
    currentPng = await File('assets/images/RCE_logo_white.png').readAsBytes();
    mainId = '${sha256.convert(mainPng)}.png';
    presetId = '${sha256.convert(presetPng)}.png';
    currentId = '${sha256.convert(currentPng)}.png';
    await image(source, mainId, mainPng);
    await image(source, presetId, presetPng);
    await image(current, currentId, currentPng);
    final before = PerformanceSnapshot.capture(
        const RenderingPreferences(),
        BackgroundPreferences(
            mini: BackgroundAppearance(
                source: BackgroundSource.customImage, customImageId: presetId)),
        const PlayerExperiencePreferences(),
        true);
    await writeJson(source, 'settings.json', {
      'Backgrounds': BackgroundPreferences(
              main: BackgroundAppearance(
                  source: BackgroundSource.customImage, customImageId: mainId))
          .toMap(),
      'PerformancePreset':
          PerformancePresetState(mode: PerformanceMode.economy, before: before)
              .toMap(),
    });
    await writeJson(source, 'index.json', {'roots': [], 'folders': []});
    await writeJson(current, 'settings.json', {
      'Backgrounds': BackgroundPreferences(
              main: BackgroundAppearance(
                  source: BackgroundSource.customImage,
                  customImageId: currentId))
          .toMap(),
    });
    await writeJson(current, 'playlists.json', {
      'name': 'Current playlist',
      'cover': path.join(current.path, 'background-images', currentId),
    });
    await writeJson(current, 'playback_statistics.json', {'plays': 42});
  });

  tearDown(() async {
    final base = await parent.resolveSymbolicLinks();
    final target = await sandbox.resolveSymbolicLinks();
    if (!path.isWithin(base, target) ||
        !path.basename(target).startsWith('backup-background-dependencies-')) {
      throw StateError('Unexpected fixture path');
    }
    await Directory(target).delete(recursive: true);
  });

  for (final fullBackup in [false, true]) {
    test(
        'settings-only restore keeps live and preset background IDs from fullBackup=$fullBackup',
        () async {
      final backup = File(path.join(sandbox.path, 'settings.bak'));
      await service.exportBackup(
          source: source,
          destination: backup,
          selection: fullBackup ? const BackupSelection() : settingsOnly);
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      expect(archive.findFile('payload/background-images/$mainId'), isNotNull);
      expect(
          archive.findFile('payload/background-images/$presetId'), isNotNull);
      final restored = await restore(backup, settingsOnly);
      final settings = await readJson(restored, 'settings.json');
      expect(
          BackgroundPreferences.fromMap(settings['Backgrounds'])
              .main
              .customImageId,
          mainId);
      expect(
          PerformancePresetState.fromMap(settings['PerformancePreset'])
              .before!
              .backgrounds
              .mini
              .customImageId,
          presetId);
      await assertFixedImage(restored, mainId, mainPng);
      await assertFixedImage(restored, presetId, presetPng);
      await assertFixedImage(restored, currentId, currentPng);
      expect((await readJson(restored, 'playlists.json'))['cover'],
          path.join(restored.path, 'background-images', currentId));
      expect(
          await readJson(restored, 'playback_statistics.json'), {'plays': 42});
    });
  }

  test(
      'resources-only restore preserves the current settings fixed-ID background dependency',
      () async {
    final backup = File(path.join(sandbox.path, 'all.bak'));
    await service.exportBackup(source: source, destination: backup);
    final restored = await restore(
        backup, const BackupSelection(components: {BackupComponent.resources}));
    final settings = await readJson(restored, 'settings.json');
    expect(
        BackgroundPreferences.fromMap(settings['Backgrounds'])
            .main
            .customImageId,
        currentId);
    await assertFixedImage(restored, currentId, currentPng);
    await assertFixedImage(restored, mainId, mainPng);
    await assertFixedImage(restored, presetId, presetPng);
  });

  test(
      'self-consistent ZIP with wrong PNG bytes for a fixed ID cannot overwrite valid current image',
      () async {
    await image(current, mainId, mainPng);
    final backup = File(path.join(sandbox.path, 'valid.bak'));
    await service.exportBackup(
        source: source, destination: backup, selection: settingsOnly);
    final original = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final manifest = jsonDecode(utf8.decode(
        original.findFile('manifest.json')!.content as List<int>)) as Map;
    // Keep ZIP CRC and manifest SHA256 self-consistent. Only the managed
    // content-addressed filename can reveal this invalid replacement.
    final replacement = presetPng;
    for (final descriptor in (manifest['files'] as List).cast<Map>()) {
      if (descriptor['path'] == 'background-images/$mainId') {
        descriptor['size'] = replacement.length;
        descriptor['sha256'] = sha256.convert(replacement).toString();
      }
    }
    final forged = Archive();
    for (final entry in original.files) {
      if (!entry.isFile) continue;
      final List<int> bytes = entry.name == 'manifest.json'
          ? utf8.encode(jsonEncode(manifest))
          : entry.name == 'payload/background-images/$mainId'
              ? replacement
              : List<int>.from(entry.content as List<int>);
      forged.addFile(ArchiveFile(entry.name, bytes.length, bytes));
    }
    final damaged = File(path.join(sandbox.path, 'wrong-id.bak'));
    await damaged.writeAsBytes(ZipEncoder().encode(forged)!);
    var activated = false;
    final destination = Directory(path.join(sandbox.path, 'target'));
    await expectLater(
        service.restoreBackup(
            backup: damaged,
            destination: destination,
            currentData: current,
            selection: settingsOnly,
            activateLocation: (_, __) async => activated = true),
        throwsA(isA<CacheBackupException>()));
    expect(activated, isFalse);
    expect(await destination.exists(), isFalse);
    await assertFixedImage(current, mainId, mainPng);
    await assertFixedImage(current, currentId, currentPng);
  });
}
