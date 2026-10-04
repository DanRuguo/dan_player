import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/app_data_location.dart';
import 'package:dan_player/data/folder_move_transaction.dart';
import 'package:dan_player/library/music_folder_move.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root, source, target, data;
  late File journal;
  Future<void> jsonFile(Directory parent, String name, Object value) async {
    final file = File(p.join(parent.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  Future<dynamic> read(Directory parent, String name) async =>
      jsonDecode(await File(p.join(parent.path, name)).readAsString());
  setUp(() async {
    root = await Directory(p.normalize(Directory.systemTemp.path))
        .createTemp('folder-cut-');
    source = await Directory(p.join(root.path, 'old')).create();
    target = Directory(p.join(root.path, 'new'));
    data = await Directory(p.join(root.path, 'data')).create();
    journal = File(p.join(root.path, 'move.json'));
    await Directory(p.join(source.path, 'nested', 'empty'))
        .create(recursive: true);
    await File(p.join(source.path, 'nested', '音乐.flac'))
        .writeAsBytes(List.generate(16000, (i) => i % 251));
    await File(p.join(source.path, 'nested', '音乐.lrc'))
        .writeAsString('[00:01]保留完整歌词');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  for (final copy in [false, true]) {
    test(
        '${copy ? 'cross-volume' : 'same-volume'} cut preserves all files and empty directories',
        () async {
      final move = FolderMoveTransaction(journal, forceCopy: copy);
      await move.schedule(source, target);
      var commits = 0;
      await move.recover(commit: (from, to) async {
        commits++;
        expect(await source.exists(), copy);
        expect(await File(p.join(to, 'nested', '音乐.lrc')).readAsString(),
            '[00:01]保留完整歌词');
      });
      expect(commits, 1);
      expect(await source.exists(), false);
      expect(await Directory(p.join(target.path, 'nested', 'empty')).exists(),
          true);
      expect((await move.read())['phase'], 'done');
      await move.finish();
      expect(await journal.exists(), false);
    });
  }

  test(
      'rejects existing, nested and journal-inside destinations before mutations',
      () async {
    await target.create();
    await expectLater(FolderMoveTransaction(journal).schedule(source, target),
        throwsA(isA<FileSystemException>()));
    await expectLater(
        FolderMoveTransaction(journal)
            .schedule(source, Directory(p.join(source.path, 'child'))),
        throwsA(isA<FileSystemException>()));
    await expectLater(
        FolderMoveTransaction(File(p.join(source.path, 'journal.json')))
            .schedule(source, Directory(p.join(root.path, 'outside'))),
        throwsA(isA<FileSystemException>()));
    final outside = Directory(p.join(root.path, 'outside'));
    await expectLater(
        FolderMoveTransaction(File(p.join(outside.path, 'journal.json')))
            .schedule(source, outside),
        throwsA(isA<FileSystemException>()));
    expect(await outside.exists(), false);
    expect(await journal.exists(), false);
    expect(await File(p.join(source.path, 'journal.json')).exists(), false);
  });

  test(
      'restart between same-volume rename and installed phase resumes the owned tree',
      () async {
    final move = FolderMoveTransaction(journal, onPhase: (phase) async {
      if (phase == 'installed') throw StateError('simulated interruption');
    });
    await move.schedule(source, target);
    await expectLater(
        move.recover(commit: (_, unusedTarget) async {}), throwsStateError);
    expect(await source.exists(), false);
    await FolderMoveTransaction(journal)
        .recover(commit: (_, unusedTarget) async {});
    expect((await FolderMoveTransaction(journal).read())['phase'], 'done');
  });

  test('cross-volume commit failure keeps originals and replays on restart',
      () async {
    final move = FolderMoveTransaction(journal, forceCopy: true);
    await move.schedule(source, target);
    await expectLater(
        move.recover(
            commit: (_, unusedTarget) async =>
                throw StateError('mapping failed')),
        throwsStateError);
    expect(await source.exists(), true);
    expect((await move.read())['phase'], 'committing');
    await FolderMoveTransaction(journal)
        .recover(commit: (_, unusedTarget) async {});
    expect(await source.exists(), false);
  });

  test(
      'restart after a partial committed cut preserves delivery and completes remaining files',
      () async {
    final move =
        FolderMoveTransaction(journal, forceCopy: true, onPhase: (phase) async {
      if (phase == 'committed') {
        await File(p.join(source.path, 'nested', '音乐.flac')).delete();
        throw StateError('interrupted after first source removal');
      }
    });
    await move.schedule(source, target);
    var commits = 0;
    await expectLater(move.recover(commit: (_, unusedTarget) async {
      commits++;
    }), throwsStateError);
    expect(await File(p.join(source.path, 'nested', '音乐.lrc')).exists(), true);
    await FolderMoveTransaction(journal).recover(
        commit: (_, unusedTarget) async {
      commits++;
    });
    expect(commits, 1);
    expect(await source.exists(), false);
    expect(
        await File(p.join(target.path, 'nested', '音乐.flac')).length(), 16000);
    expect(await File(p.join(target.path, 'nested', '音乐.lrc')).readAsString(),
        '[00:01]保留完整歌词');
  });

  test(
      'interrupted data commit permits only mapped documents and retains immutable artwork',
      () async {
    await jsonFile(source, 'settings.json',
        {'background': p.join(source.path, 'nested', '音乐.lrc')});
    final move = FolderMoveTransaction(journal, forceCopy: true);
    await move.schedule(source, target);
    bool canChange(String name) => name == 'settings.json';
    await expectLater(
        move.recover(
            commitMayChange: canChange,
            commit: (_, to) async {
              await jsonFile(Directory(to), 'settings.json',
                  {'background': p.join(to, 'nested', '音乐.lrc')});
              throw StateError('crash after mapping');
            }),
        throwsStateError);
    await FolderMoveTransaction(journal).recover(
        commitMayChange: canChange, commit: (_, unusedTarget) async {});
    expect(await source.exists(), false);
    expect((await read(target, 'settings.json'))['background'],
        p.join(target.path, 'nested', '音乐.lrc'));
  });

  test('a source edit with identical size and timestamp is never cut',
      () async {
    final song = File(p.join(source.path, 'nested', '音乐.flac'));
    final stamp = await song.lastModified();
    final move =
        FolderMoveTransaction(journal, forceCopy: true, onPhase: (phase) async {
      if (phase == 'installed') {
        await song.writeAsBytes(List.filled(16000, 9));
        await song.setLastModified(stamp);
      }
    });
    await move.schedule(source, target);
    await expectLater(
        move.recover(commit: (_, unusedTarget) async {}), throwsStateError);
    expect(await song.exists(), true);
    expect((await song.readAsBytes()).first, 9);
    expect(await File(p.join(source.path, 'nested', '音乐.lrc')).exists(), true);
  });

  test('new source siblings after copy abort without cutting originals',
      () async {
    final move =
        FolderMoveTransaction(journal, forceCopy: true, onPhase: (phase) async {
      if (phase == 'staged') {
        await File(p.join(source.path, 'new.txt'))
            .writeAsString('external addition');
      }
    });
    await move.schedule(source, target);
    await expectLater(
        move.recover(commit: (_, unusedTarget) async {}), throwsStateError);
    expect(await File(p.join(source.path, 'new.txt')).exists(), true);
    expect(await File(p.join(source.path, 'nested', '音乐.flac')).exists(), true);
  });

  test(
      'physical music move synchronizes index, duplicate playlist order, stable identity and bookmarks',
      () async {
    final song = p.join(source.path, 'nested', '音乐.flac');
    await jsonFile(data, 'index.json', {
      'version': 112,
      'roots': [source.path],
      'folders': [
        {
          'path': p.join(source.path, 'nested'),
          'audios': [
            {'path': song, 'track_id': 'local:keep', 'file_size': 16000}
          ]
        }
      ]
    });
    await jsonFile(data, 'playlists.json', {
      'entries': [
        {'id': 'one', 'path': song},
        {'id': 'two', 'path': song}
      ]
    });
    await jsonFile(data, 'track_identities.json', {
      'records': [
        {'trackId': 'local:keep', 'path': song, 'aliases': []}
      ]
    });
    await jsonFile(data, 'playback_bookmarks.json', {
      'bookmarks': [
        {'path': song, 'position': 17000}
      ]
    });
    await jsonFile(data, 'settings.json', {
      'FolderNotes': [
        {'path': source.path, 'text': source.path}
      ]
    });
    final move = MusicFolderMove(data,
        forceCopy: true, pendingDataChange: () async => false);
    await move.schedule(source, target);
    await move.recover();
    final index = await read(data, 'index.json');
    expect(index['roots'], [target.path]);
    expect(index['folders'][0]['audios'][0]['path'],
        p.join(target.path, 'nested', '音乐.flac'));
    final playlist = await read(data, 'playlists.json');
    expect(playlist['entries'].map((e) => e['id']).toList(), ['one', 'two']);
    expect(playlist['entries'][0]['path'], playlist['entries'][1]['path']);
    expect((await read(data, 'track_identities.json'))['records'][0]['trackId'],
        'local:keep');
    expect(
        (await read(data, 'playback_bookmarks.json'))['bookmarks'][0]
            ['position'],
        17000);
    expect((await read(data, 'settings.json'))['FolderNotes'], [
      {'path': target.path, 'text': source.path}
    ]);
    expect(await source.exists(), false);
  });

  test(
      'moving the whole data root promotes its pointer and rebases managed assets only',
      () async {
    await jsonFile(source, 'settings.json',
        {'background': p.join(source.path, 'nested', '音乐.lrc')});
    await jsonFile(source, 'index.json', {
      'roots': [p.join(root.path, 'external-music')],
      'folders': []
    });
    final pointer = File(p.join(root.path, 'support', 'data_location.json'));
    final store = AppDataLocationStore(pointer);
    await store.scheduleMove(source, target);
    expect(await store.activatePendingOrReadActive(), target.path);
    expect((await read(target, 'settings.json'))['background'],
        p.join(target.path, 'nested', '音乐.lrc'));
    expect((await read(target, 'index.json'))['roots'],
        [p.join(root.path, 'external-music')]);
    expect(await source.exists(), false);
    expect(await store.activatePendingOrReadActive(), target.path);
  });

  test(
      'moving a nested folder enrolls the new root so later scans retain its tracks',
      () async {
    final nested = Directory(p.join(source.path, 'nested'));
    final song = p.join(nested.path, '音乐.flac');
    await jsonFile(data, 'index.json', {
      'version': 112,
      'roots': [source.path],
      'folders': [
        {
          'path': nested.path,
          'audios': [
            {'path': song, 'file_size': 16000}
          ]
        }
      ]
    });
    final move = MusicFolderMove(data, pendingDataChange: () async => false);
    await move.schedule(nested, target);
    await move.recover();
    expect(
        (await read(data, 'index.json'))['roots'], [source.path, target.path]);
    expect(await File(p.join(target.path, '音乐.flac')).exists(), true);
  });

  test(
      'music and data restore/move intents are mutually exclusive in both directions',
      () async {
    final music = MusicFolderMove(data, pendingDataChange: () async => true);
    await expectLater(music.schedule(source, target), throwsStateError);
    expect(await music.pending, false);
    final pointer = File(p.join(root.path, 'support', 'location.json'));
    final store = AppDataLocationStore(pointer);
    await File(p.join(source.path, 'music_folder_move.json'))
        .writeAsString('{}');
    await expectLater(store.scheduleMove(source, target), throwsStateError);
    await File(p.join(source.path, appDataReadyMarkerName))
        .writeAsString('ready');
    await expectLater(
        store.schedule(
            nextPath: target.path,
            currentPath: source.path,
            stagedPath: source.path),
        throwsStateError);
    expect(await pointer.exists(), false);
  });
}
