import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/library_data_migration.dart';
import 'package:dan_player/library/music_folder_move.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root, data, music, movedMusic, other, movedOther;
  Future<void> writeJson(String name, Object value) async {
    await File(p.join(data.path, name)).writeAsString(jsonEncode(value));
  }

  Future<Map<String, dynamic>> readIndex() async =>
      jsonDecode(await File(p.join(data.path, 'index.json')).readAsString())
          as Map<String, dynamic>;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('move-recovery-boundary-');
    data = await Directory(p.join(root.path, 'data')).create();
    music = await Directory(p.join(root.path, 'music')).create();
    movedMusic = Directory(p.join(root.path, 'music-after'));
    other = await Directory(p.join(root.path, 'other')).create();
    movedOther = await Directory(p.join(root.path, 'other-after')).create();
    for (final folder in [music, other, movedOther]) {
      await File(p.join(folder.path, 'song.flac')).writeAsBytes([1, 2, 3]);
    }
    await writeJson('index.json', {
      'version': 112,
      'roots': [music.path, other.path],
      'folders': [
        for (final folder in [music, other])
          {
            'path': folder.path,
            'audios': [
              {'path': p.join(folder.path, 'song.flac'), 'file_size': 3}
            ],
          },
      ],
    });
    await writeJson('playlists.json', {
      'entries': [
        {'id': 'music', 'path': p.join(music.path, 'song.flac')},
        {'id': 'other', 'path': p.join(other.path, 'song.flac')},
      ],
    });
  });
  tearDown(() => root.delete(recursive: true));

  MusicFolderMove move() =>
      MusicFolderMove(data, pendingDataChange: () async => false);
  LibraryPathMapping otherMapping() =>
      LibraryPathMapping(other.path, movedOther.path);

  test('legacy overlapping recovery commits both path mappings before cut',
      () async {
    final migration = LibraryDataMigration(data);
    await migration.schedule(otherMapping());
    final intent =
        await File(p.join(data.path, 'library_migration.json')).readAsBytes();
    await migration.cancelPending();
    await move().schedule(music, movedMusic);
    // Recreate the two legitimate journals an older running build could leave
    // if another relocation was accepted while the move's exit was pending.
    await File(p.join(data.path, 'library_migration.json'))
        .writeAsBytes(intent);
    await move().recover();
    final index = await readIndex();
    expect(index['roots'], [movedMusic.path, movedOther.path]);
    expect(index['folders'][0]['audios'][0]['path'],
        p.join(movedMusic.path, 'song.flac'));
    expect(index['folders'][1]['audios'][0]['path'],
        p.join(movedOther.path, 'song.flac'));
    expect(await music.exists(), false);
    final playlist = jsonDecode(
        await File(p.join(data.path, 'playlists.json')).readAsString());
    expect(playlist['entries'].map((entry) => entry['id']).toList(),
        ['music', 'other']);
    expect(
        playlist['entries'][0]['path'], p.join(movedMusic.path, 'song.flac'));
    expect(await migration.hasPending, false);
  });

  test('ordinary relocation cannot be scheduled after a pending physical cut',
      () async {
    await move().schedule(music, movedMusic);
    final migration = LibraryDataMigration(data);
    await expectLater(
        migration.schedule(otherMapping()), throwsA(isA<FormatException>()));
    expect(await migration.hasPending, false);
    expect(await music.exists(), true);
    expect(await movedMusic.exists(), false);
    expect((await readIndex())['roots'], [music.path, other.path]);
  });

  test('own interrupted mapping resumes without applying a second batch',
      () async {
    final moving = move();
    await moving.schedule(music, movedMusic);
    await expectLater(
      moving.transaction.recover(commit: (from, to) async {
        final interrupted =
            LibraryDataMigration(data, afterReplace: (count) async {
          if (count == 1) throw StateError('simulated interrupted commit');
        });
        await interrupted.scheduleFolderMove(LibraryPathMapping(from, to));
        await interrupted.recover();
      }),
      throwsA(isA<StateError>()),
    );
    final batches = Directory(p.join(data.path, 'library_migrations'));
    final batchCount = await batches.list().length;
    expect(await LibraryDataMigration(data).hasPending, true);
    await move().recover();
    expect(await batches.list().length, batchCount);
    final index = await readIndex();
    expect(index['roots'], [movedMusic.path, other.path]);
    expect(index['folders'][0]['audios'][0]['path'],
        p.join(movedMusic.path, 'song.flac'));
    final playlist = jsonDecode(
        await File(p.join(data.path, 'playlists.json')).readAsString());
    expect(
        playlist['entries'][0]['path'], p.join(movedMusic.path, 'song.flac'));
    expect(playlist['entries'][1]['path'], p.join(other.path, 'song.flac'));
    expect(await music.exists(), false);
    expect(await moving.pending, false);
    expect(await LibraryDataMigration(data).hasPending, false);
  });

  test('migration undo cannot be scheduled after a pending physical cut',
      () async {
    final migration = LibraryDataMigration(data);
    await migration.schedule(otherMapping());
    await migration.recover();
    await move().schedule(music, movedMusic);
    await expectLater(
        migration.scheduleRestore(), throwsA(isA<FormatException>()));
    expect(await migration.hasPending, false);
    expect(await music.exists(), true);
    expect((await readIndex())['roots'], [music.path, movedOther.path]);
  });
}
