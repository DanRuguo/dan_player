import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/app_data_location.dart';
import 'package:dan_player/data/backup_restore_preservation.dart';
import 'package:dan_player/data/backup_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory parent;
  late Directory sandbox;
  late Directory current;
  late Directory staged;
  late File pointer;

  Future<void> write(Directory root, String name, Object value) async {
    final file = File(path.join(root.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  Future<Object?> read(Directory root, String name) async =>
      jsonDecode(await File(path.join(root.path, name)).readAsString());

  setUp(() async {
    parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    sandbox = await parent.createTemp('restore-activation-');
    current = await Directory(path.join(sandbox.path, 'current')).create();
    staged = await Directory(path.join(sandbox.path, 'staged')).create();
    pointer = File(path.join(sandbox.path, 'pointer', 'location.json'));
    await write(staged, appDataReadyMarkerName, {'version': 2});
  });

  tearDown(() async {
    final base = await parent.resolveSymbolicLinks();
    final target = await sandbox.resolveSymbolicLinks();
    if (!path.isWithin(base, target) ||
        !path.basename(target).startsWith('restore-activation-')) {
      throw StateError('Unexpected fixture path');
    }
    await Directory(target).delete(recursive: true);
  });

  for (final sameDirectory in [false, true]) {
    test(
        'deferred selective restore preserves latest live data sameDirectory=$sameDirectory',
        () async {
      final destination = sameDirectory
          ? current
          : Directory(path.join(sandbox.path, 'destination'));
      await write(current, 'settings.json', {'revision': 'before'});
      await write(staged, 'settings.json', {'revision': 'before'});
      await write(staged, 'playlists.json', {'revision': 'before'});
      await write(staged, 'playback_statistics.json', {'plays': 1});
      await write(staged, 'playlists.json.bak', {'deleted': 'stale backup'});
      await write(staged, 'index.json', {'revision': 'selected-backup'});
      await BackupRestorePreservation.writePlan(
          staged: staged,
          source: current,
          selected: {BackupComponent.library},
          protectedPaths: {'index.json'});
      final store = AppDataLocationStore(pointer);
      await store.schedule(
          nextPath: destination.path,
          currentPath: current.path,
          stagedPath: staged.path);

      // Edits after the restore dialog has closed and before the next launch.
      await write(current, 'settings.json', {
        'revision': 'new-theme',
        'cache': path.join(current.path, 'covers', 'latest.png')
      });
      await write(current, 'playlists.json', {'revision': 'new-playlist'});
      await write(current, 'playback_statistics.json', {'plays': 88});
      await write(current, 'index.json', {'revision': 'live-library'});
      expect(await store.activatePendingOrReadActive(), destination.path);
      expect(await read(destination, 'settings.json'), {
        'revision': 'new-theme',
        'cache': path.join(destination.path, 'covers', 'latest.png')
      });
      expect(await read(destination, 'playlists.json'),
          {'revision': 'new-playlist'});
      expect(
          await read(destination, 'playback_statistics.json'), {'plays': 88});
      expect(await read(destination, 'index.json'),
          {'revision': 'selected-backup'});
      expect(
          await File(path.join(destination.path, 'playlists.json.bak'))
              .exists(),
          isFalse);
      expect(
          await File(path.join(
                  destination.path, BackupRestorePreservation.planName))
              .exists(),
          isFalse);
    });
  }

  test('failed unselected JSON refresh leaves active data and target untouched',
      () async {
    final destination =
        await Directory(path.join(sandbox.path, 'destination')).create();
    await write(destination, 'existing.json', {'preserve': true});
    await write(staged, 'index.json', {'revision': 'backup'});
    await BackupRestorePreservation.writePlan(
        staged: staged,
        source: current,
        selected: {BackupComponent.library},
        protectedPaths: {'index.json'});
    final store = AppDataLocationStore(pointer);
    await store.schedule(
        nextPath: destination.path,
        currentPath: current.path,
        stagedPath: staged.path);
    await File(path.join(current.path, 'settings.json'))
        .writeAsString('{broken json');
    expect(await store.activatePendingOrReadActive(), current.path);
    expect(await read(destination, 'existing.json'), {'preserve': true});
    expect(await File(path.join(current.path, 'settings.json')).readAsString(),
        '{broken json');
    final state = jsonDecode(await pointer.readAsString()) as Map;
    expect(state['activePath'], current.path);
    expect(state['pendingPath'], isNull);
    expect(await staged.exists(), isTrue);
  });

  test('changed active root cannot refresh from the wrong preservation source',
      () async {
    final other = await Directory(path.join(sandbox.path, 'other')).create();
    final destination = Directory(path.join(sandbox.path, 'destination'));
    await write(other, 'settings.json', {'revision': 'actual-active'});
    await BackupRestorePreservation.writePlan(
        staged: staged,
        source: current,
        selected: {BackupComponent.library},
        protectedPaths: {});
    final store = AppDataLocationStore(pointer);
    await store.schedule(
        nextPath: destination.path,
        currentPath: other.path,
        stagedPath: staged.path);
    expect(await store.activatePendingOrReadActive(), other.path);
    expect(await destination.exists(), isFalse);
    expect(await read(other, 'settings.json'), {'revision': 'actual-active'});
  });
}
