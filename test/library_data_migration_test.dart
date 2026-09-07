import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_metadata_journal.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root, data, before, after;
  late LibraryPathMapping mapping;
  late String oldSong, newSong;
  Future<void> write(String name, Object value) =>
      File(p.join(data.path, name)).writeAsString(jsonEncode(value));
  Future<dynamic> read(String name) async =>
      jsonDecode(await File(p.join(data.path, name)).readAsString());
  setUp(() async {
    final base = Directory(
        Platform.environment['DAN_PLAYER_DATA_DIR'] ?? 'build/qa-migration');
    await base.create(recursive: true);
    root = await base.createTemp('mapping-');
    data = await Directory(p.join(root.path, 'data')).create();
    before = await Directory(p.join(root.path, 'old')).create();
    after = await Directory(p.join(root.path, 'new')).create();
    oldSong = p.join(before.absolute.path, 'song.flac');
    newSong = p.join(after.absolute.path, 'song.flac');
    await File(newSong).writeAsBytes([1, 2, 3]);
    mapping = LibraryPathMapping(before.absolute.path, after.absolute.path);
    await write('index.json', {
      'version': 112,
      'roots': [before.absolute.path],
      'folders': [
        {
          'path': before.absolute.path,
          'audios': [
            {
              'path': oldSong,
              'title': 'Before',
              'artist': 'Artist',
              'album': 'Album',
              'file_size': 3
            },
          ]
        }
      ]
    });
    await write('playlists.json', {
      'entries': [
        {'id': 'first', 'path': oldSong},
        {'id': 'second', 'path': oldSong}
      ]
    });
    await write('playback_statistics.json', {
      'totalPlayCount': 7,
      'totalListeningMs': 55000,
      'tracks': {
        'local:stable': {'playCount': 7, 'listeningMs': 55000}
      }
    });
    await write('track_identities.json', {
      'version': 1,
      'records': [
        {
          'trackId': 'local:stable',
          'path': oldSong,
          'aliases': [p.join(before.absolute.path, 'older.flac')]
        }
      ]
    });
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('pending metadata commit blocks relocation and rollback scheduling',
      () async {
    final service = LibraryDataMigration(data);
    final journal = AudioMetadataJournal(data);
    for (final suffix in ['', '.tmp']) {
      final pending = File('${journal.file.path}$suffix');
      await pending.writeAsString('{}');
      expect(await journal.hasPending, isTrue);
      await expectLater(service.schedule(mapping), throwsFormatException);
      await expectLater(service.scheduleRestore(), throwsFormatException);
      expect(await service.hasPending, isFalse);
      await pending.delete();
    }
    expect(await journal.hasPending, isFalse);
  });

  test('preview is read-only and preserves duplicate occurrences on restart',
      () async {
    final service = LibraryDataMigration(data);
    final report = await service.preview(mapping);
    expect(report.canApply, isTrue);
    expect(report.matches, 1);
    await service.schedule(mapping);
    expect((await read('playlists.json'))['entries'][0]['path'], oldSong);
    await LibraryDataMigration(data).recover();
    final entries = (await read('playlists.json'))['entries'] as List;
    expect(entries.map((e) => e['id']), ['first', 'second']);
    expect(entries.map((e) => e['path']), [newSong, newSong]);
    final id = (await read('track_identities.json'))['records'][0];
    expect(id['trackId'], 'local:stable');
    expect(id['aliases'], contains(oldSong));
    expect((await read('playback_statistics.json'))['totalListeningMs'], 55000);
    expect(await File(oldSong).exists(), isFalse,
        reason: 'No media move occurred.');
    expect(await service.hasPending, isFalse);
  });

  test('interrupted cross-file commit replays once before loaders run',
      () async {
    await LibraryDataMigration(data).schedule(mapping);
    final broken = LibraryDataMigration(data, afterReplace: (count) async {
      if (count == 1) throw const FileSystemException('Injected power loss');
    });
    await expectLater(broken.recover(), throwsA(isA<FileSystemException>()));
    expect(await broken.hasPending, isTrue);
    await LibraryDataMigration(data).recover();
    await LibraryDataMigration(data).recover();
    expect((await read('playlists.json'))['entries'].length, 2);
    expect((await read('playlists.json'))['entries'][1]['path'], newSong);
    expect((await read('playback_statistics.json'))['totalPlayCount'], 7);
  });

  test('snapshot rollback restores the whole batch and its old totals',
      () async {
    final originalIndex =
        await File(p.join(data.path, 'index.json')).readAsString();
    final service = LibraryDataMigration(data);
    await service.schedule(mapping);
    await service.recover();
    await write('playback_statistics.json', {'totalPlayCount': 99});
    await service.restorePrevious();
    expect(await File(p.join(data.path, 'index.json')).readAsString(),
        originalIndex);
    expect((await read('playback_statistics.json'))['totalPlayCount'], 7);
    expect((await read('playlists.json'))['entries'][0]['path'], oldSong);
  });

  test('corrupt staged file fails before touching another authoritative file',
      () async {
    final service = LibraryDataMigration(data);
    await service.schedule(mapping);
    await expectLater(
        LibraryDataMigration(data, afterReplace: (_) async {
          throw StateError('Interrupted');
        }).recover(),
        throwsStateError);
    final intent = await read('library_migration.json');
    await File(p.join(data.path, 'library_migrations', intent['id'], 'after',
            'playlists.json'))
        .writeAsString('broken');
    final beforeRetry =
        await File(p.join(data.path, 'playlists.json')).readAsString();
    await expectLater(service.recover(), throwsFormatException);
    expect(await File(p.join(data.path, 'playlists.json')).readAsString(),
        beforeRetry);
    await service.restorePrevious();
    expect((await read('playlists.json'))['entries'][0]['path'], oldSong);
  });

  test('missing source at destination never applies partial mapping', () async {
    await File(newSong).delete();
    final service = LibraryDataMigration(data);
    expect((await service.preview(mapping)).missing, 1);
    await expectLater(service.schedule(mapping), throwsFormatException);
    expect(await service.hasPending, isFalse);
  });

  test(
      'changed file size and target already in library need explicit resolution',
      () async {
    await File(newSong).writeAsBytes([4]);
    expect((await LibraryDataMigration(data).preview(mapping)).conflicts,
        isNotEmpty);
    final index = await read('index.json');
    index['folders'][0]['audios'].add({'path': newSong, 'title': 'Other'});
    await write('index.json', index);
    expect(
        (await LibraryDataMigration(data).preview(mapping)).canApply, isFalse);
  });

  test('pending operation can be cancelled without changing any document',
      () async {
    final service = LibraryDataMigration(data);
    await service.schedule(mapping);
    await service.cancelPending();
    await service.recover();
    expect((await read('playlists.json'))['entries'][0]['path'], oldSong);
  });

  test('CUE URI and CD frames map while human lyric content stays intact', () {
    final cue =
        'cue://track/${Uri.encodeComponent(p.windows.join(before.absolute.path, 'album.cue').toLowerCase())}/2';
    final result = remapLibraryDocument({
      cue: {
        'cue_path': p.join(before.absolute.path, 'album.cue'),
        'start_frame': 451,
        'end_frame': 899,
        'originalText': oldSong,
        'edited': {'text': oldSong},
        'history': [
          {'path': oldSong}
        ]
      },
      'online': 'online://qq/123',
    }, mapping) as Map;
    final next = result[mapping.apply(cue)] as Map;
    expect(next['start_frame'], 451);
    expect(next['end_frame'], 899);
    expect(next['originalText'], oldSong);
    expect(next['edited']['text'], oldSong);
    expect(next['history'][0]['path'], newSong);
    expect(result['online'], 'online://qq/123');
  });

  test('root prefix is component bounded and overlapping mappings are rejected',
      () {
    final sample = LibraryPathMapping(r'C:\Music', r'D:\Albums');
    expect(sample.apply(r'C:\Musical\track.flac'), r'C:\Musical\track.flac');
    expect(sample.apply(r'c:\MUSIC\track.flac'), r'D:\Albums\track.flac');
    expect(() => LibraryPathMapping(r'C:\Music', r'C:\Music\new'),
        throwsFormatException);
  });

  test(
      'confirmed native edit recovers metadata and relationships without rewriting media',
      () async {
    final journal = AudioMetadataJournal(data);
    await journal.record(
        oldPath: oldSong,
        newPath: newSong,
        title: 'After',
        artist: 'Edited artist',
        album: 'Edited album');
    await journal.recover();
    final audio = (await read('index.json'))['folders'][0]['audios'][0];
    expect(audio['title'], 'After');
    expect(audio['path'], newSong);
    expect((await read('playlists.json'))['entries'][0]['path'], newSong);
    expect(await File(newSong).readAsBytes(), [1, 2, 3]);
    expect(await journal.file.exists(), isFalse);
    await journal.recover();
  });

  test('metadata recovery preserves corrupt primary and maps usable backups',
      () async {
    await write('custom_audio_order.json.bak', {
      'version': 1,
      'paths': [oldSong]
    });
    await File(p.join(data.path, 'custom_audio_order.json'))
        .writeAsString('damaged');
    await write('track_resume.json.bak', {
      'version': 1,
      'entries': [
        {'path': oldSong}
      ]
    });
    final journal = AudioMetadataJournal(data);
    await journal.record(
        oldPath: oldSong,
        newPath: newSong,
        title: 'After',
        artist: 'Artist',
        album: 'Album');
    await journal.recover();
    expect((await read('custom_audio_order.json'))['paths'], [newSong]);
    expect((await read('custom_audio_order.json.bak'))['paths'], [newSong]);
    expect((await read('track_resume.json'))['entries'][0]['path'], newSong);
    final batches = Directory(p.join(data.path, 'library_migrations'));
    final preserved = await batches
        .list(recursive: true)
        .where((entry) =>
            entry is File &&
            p.basename(entry.path) == 'custom_audio_order.json' &&
            p.basename(p.dirname(entry.path)) == 'before')
        .toList();
    expect(preserved, hasLength(1));
    expect(await File(preserved.single.path).readAsString(), 'damaged');
    expect(await journal.hasPending, isFalse);
  });
}
