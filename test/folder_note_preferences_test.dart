import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing and malformed records retain unrelated valid notes', () {
    expect(FolderNotePreferences.fromJson(null).toJson(), isEmpty);
    expect(FolderNotePreferences.fromJson({'path': r'C:\Music'}).toJson(),
        isEmpty);
    final notes = FolderNotePreferences.fromJson([
      null,
      {'path': 'relative', 'text': 'bad path'},
      {'path': r'C:\Broken', 'text': 'bad\ntext'},
      {'path': r'C:\Music', 'text': '原文 😀'},
      {'path': r'C:\Numeric', 'text': 123},
    ]);
    expect(notes.noteFor(r'c:/MUSIC'), '原文 😀');
    expect(notes.toJson(), hasLength(1));
  });

  test('Windows key normalizes case slashes dots trailing slash and UNC', () {
    final notes = const FolderNotePreferences()
        .withNote(r'C:\Music\Album\..\Music\', 'Album')
        .withNote(r'\\SERVER\Share\Music', 'Network');
    expect(notes.noteFor(r'c:/music/music'), 'Album');
    expect(notes.noteFor(r'\\server\share\MUSIC\'), 'Network');
    expect(notes.noteFor('relative'), isNull);
  });

  test('same Windows folder replaces one record without changing other notes',
      () {
    final original = const FolderNotePreferences()
        .withNote(r'C:\Music', 'old')
        .withNote(r'D:\Music', 'other');
    final updated = original.withNote(r'c:/music', '  user text  ');
    expect(updated.toJson(), hasLength(2));
    expect(updated.noteFor(r'C:\Music'), '  user text  ');
    expect(updated.noteFor(r'D:\Music'), 'other');
    expect(original.noteFor(r'C:\Music'), 'old');
    expect(FolderNotePreferences.fromJson(updated.toJson()).toJson(),
        updated.toJson());
  });

  test('160 Unicode codepoints accepted and controls or 161 rejected', () {
    final limit = List.filled(160, '😀').join();
    expect(
        const FolderNotePreferences()
            .withNote(r'C:\Music', limit)
            .noteFor(r'C:\Music'),
        limit);
    expect(
        () => const FolderNotePreferences().withNote(r'C:\Music', '$limit😀'),
        throwsFormatException);
    for (final character in ['\n', '\t', '\x00', '\x7f', '\u0085', '\u2028']) {
      expect(
          () => const FolderNotePreferences()
              .withNote(r'C:\Music', 'note${character}x'),
          throwsFormatException);
    }
    expect(() => const FolderNotePreferences().withNote(r'C:Music', 'note'),
        throwsFormatException);
  });

  test('empty draft clears note while source preferences remain immutable', () {
    final original =
        const FolderNotePreferences().withNote(r'C:\Music', 'note');
    expect(original.withNote(r'C:\Music', '   ').toJson(), isEmpty);
    expect(original.noteFor(r'C:\Music'), 'note');
  });

  test(
      'existing library mapping relocates note paths and protects literal text',
      () {
    final notes = const FolderNotePreferences()
        .withNote(r'C:\Music\Album', r'C:\Music\literal remark')
        .withNote(r'F:\Other', 'other');
    final mapped = remapLibraryDocument({'FolderNotes': notes.toJson()},
        LibraryPathMapping(r'C:\Music', r'D:\Collection')) as Map;
    final restored = FolderNotePreferences.fromJson(mapped['FolderNotes']);
    expect(
        restored.noteFor(r'D:\Collection\Album'), r'C:\Music\literal remark');
    expect(restored.noteFor(r'C:\Music\Album'), isNull);
    expect(restored.noteFor(r'F:\Other'), 'other');
  });

  test('AppSettings persists folder notes inside its existing settings JSON',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty,
        reason: 'Use this fixture\'s path-provider injection');
    final parent = Directory(path.join(Directory.current.parent.path, 'tool',
        'qa-local', 'features-2606-oct4', 'folder-notes', 'data'));
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('settings-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final original = AppSettings.instance.folderNotes.value;
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    try {
      final data = await getAppDataDir();
      expect(path.isWithin(fixture.path, data.path), isTrue);
      final folder = path.join(fixture.path, 'Music');
      AppSettings.instance.folderNotes.value =
          const FolderNotePreferences().withNote(folder, 'My music 😀');
      await AppSettings.instance.saveSettings(
          throwOnError: true, captureWindowSize: false, requireCommit: true);
      final stored = jsonDecode(
              await File(path.join(data.path, 'settings.json')).readAsString())
          as Map;
      expect(stored['FolderNotes'],
          AppSettings.instance.folderNotes.value.toJson());
      AppSettings.instance.folderNotes.value = const FolderNotePreferences();
      await AppSettings.readFromJson();
      expect(AppSettings.instance.folderNotes.value.noteFor(folder),
          'My music 😀');
    } finally {
      AppSettings.instance.folderNotes.value = original;
      messenger.setMockMethodCallHandler(channel, null);
      final resolved = await fixture.resolveSymbolicLinks();
      expect(
          path.isWithin(await parent.resolveSymbolicLinks(), resolved), isTrue);
      await Directory(resolved).delete(recursive: true);
    }
  });
}
