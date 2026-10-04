import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dan_player/data/backup_restore_preservation.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  const service = CacheBackupService();
  late Directory parent, sandbox, source, current, destination;

  Future<void> write(Directory directory, String name, Object value) async {
    final file = File(path.join(directory.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  Future<Map> read(Directory directory, String name) async =>
      jsonDecode(await File(path.join(directory.path, name)).readAsString())
          as Map;

  setUp(() async {
    parent = await Directory(path.join(Directory.current.parent.path, 'tool',
            'qa-local', 'features-2606-oct4', 'folder-notes', 'data'))
        .create(recursive: true);
    sandbox = await parent.createTemp('backup-');
    source = await Directory(path.join(sandbox.path, 'source')).create();
    current = await Directory(path.join(sandbox.path, 'current')).create();
    destination = Directory(path.join(sandbox.path, 'restored'));
  });
  tearDown(() async {
    final resolved = await sandbox.resolveSymbolicLinks();
    if (!path.isWithin(await parent.resolveSymbolicLinks(), resolved) ||
        !path.basename(resolved).startsWith('backup-')) {
      throw StateError('Refusing to delete a non-fixture path');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test(
      'real backup keeps absolute and token-like folder note text literal while relocating paths',
      () async {
    final literalAsset = File(path.join(source.path, 'covers', 'literal.png'));
    final realAsset = File(path.join(source.path, 'covers', 'actual.png'));
    await literalAsset.parent.create();
    await literalAsset.writeAsBytes([1, 2, 3]);
    await realAsset.writeAsBytes([4, 5, 6]);
    const tokenText = '@dan-player-backup/cache/covers/not-present.png';
    const escapeText = '@dan-player-backup/smart-literal/%25literal';
    final notes = const FolderNotePreferences()
        .withNote(source.path, literalAsset.path)
        .withNote(path.join(source.path, 'other'), tokenText)
        .withNote(path.join(source.path, 'third'), escapeText);
    await write(source, 'settings.json', {
      'FolderNotes': notes.toJson(),
      'customBackground': realAsset.path,
    });
    final backup = File(path.join(sandbox.path, 'notes.bak'));
    final exported = await service.exportBackup(
        source: source,
        destination: backup,
        selection:
            const BackupSelection(components: {BackupComponent.settings}));
    expect(exported.fileCount, 2,
        reason: 'Only settings and the actual image reference are included');
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    expect(archive.findFile('payload/covers/literal.png'), isNull,
        reason: 'A note containing a path must not collect that file');
    expect(archive.findFile('payload/covers/actual.png'), isNotNull);
    final encoded = jsonDecode(utf8.decode(
            archive.findFile('payload/settings.json')!.content as List<int>))
        as Map;
    expect((encoded['FolderNotes'] as List).first['text'], literalAsset.path);
    expect((encoded['FolderNotes'] as List).first['path'],
        '@dan-player-backup/cache');
    expect((encoded['FolderNotes'] as List)[1]['text'],
        startsWith('@dan-player-backup/smart-literal/'));
    Directory? staged;
    await service.restoreBackup(
        backup: backup,
        destination: destination,
        currentData: current,
        selection:
            const BackupSelection(components: {BackupComponent.settings}),
        activateLocation: (_, value) async => staged = value);
    final restored = await read(staged!, 'settings.json');
    final restoredNotes =
        FolderNotePreferences.fromJson(restored['FolderNotes']);
    expect(restoredNotes.noteFor(destination.path), literalAsset.path);
    expect(
        restoredNotes.noteFor(path.join(destination.path, 'other')), tokenText);
    expect(restoredNotes.noteFor(path.join(destination.path, 'third')),
        escapeText);
    expect(restoredNotes.toJson(), hasLength(3));
    expect(restored['customBackground'], isNot(realAsset.path));
    expect(
        path.isWithin(destination.path, restored['customBackground'] as String),
        isTrue);
  });

  test(
      'selective restore and deferred refresh remap note paths but preserve latest literal text',
      () async {
    await write(source, 'index.json', {'roots': [], 'folders': []});
    const tokenText = '@dan-player-backup/cache/covers/user-note.png';
    final initialText = path.join(current.path, 'literal-remark');
    await write(current, 'settings.json', {
      'FolderNotes': const FolderNotePreferences()
          .withNote(current.path, initialText)
          .withNote(path.join(current.path, 'other'), tokenText)
          .toJson(),
      'realPath': path.join(current.path, 'covers', 'real.png'),
    });
    final backup = File(path.join(sandbox.path, 'library.bak'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection:
            const BackupSelection(components: {BackupComponent.library}));
    Directory? staged;
    await service.restoreBackup(
        backup: backup,
        destination: destination,
        currentData: current,
        selection: const BackupSelection(components: {BackupComponent.library}),
        activateLocation: (_, value) async => staged = value);
    final merged = await read(staged!, 'settings.json');
    final mergedNotes = FolderNotePreferences.fromJson(merged['FolderNotes']);
    expect(mergedNotes.noteFor(destination.path), initialText);
    expect(
        mergedNotes.noteFor(path.join(destination.path, 'other')), tokenText);
    expect(
        merged['realPath'], path.join(destination.path, 'covers', 'real.png'));
    final latestText = path.join(current.path, 'latest-remark');
    await write(current, 'settings.json', {
      'FolderNotes': const FolderNotePreferences()
          .withNote(current.path, latestText)
          .withNote(path.join(current.path, 'other'), tokenText)
          .toJson(),
      'realPath': path.join(current.path, 'covers', 'latest.png'),
    });
    await BackupRestorePreservation.refreshBeforeActivation(
        currentData: current, staged: staged!, destination: destination);
    final refreshed = await read(staged!, 'settings.json');
    final refreshedNotes =
        FolderNotePreferences.fromJson(refreshed['FolderNotes']);
    expect(refreshedNotes.noteFor(destination.path), latestText);
    expect(refreshedNotes.noteFor(path.join(destination.path, 'other')),
        tokenText);
    expect(refreshed['realPath'],
        path.join(destination.path, 'covers', 'latest.png'));
    expect(
        (await read(current, 'settings.json'))['FolderNotes'],
        const FolderNotePreferences()
            .withNote(current.path, latestText)
            .withNote(path.join(current.path, 'other'), tokenText)
            .toJson());
  });
}
