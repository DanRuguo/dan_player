import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('portable cache backup', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('dan-player-cache-test-');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('maps songs, preserves missing occurrences, and keeps assets',
        () async {
      final oldMusic = Directory(path.join(sandbox.path, 'old', 'Music'));
      final newMusic = Directory(path.join(sandbox.path, 'new', 'Renamed'));
      final oldAlbum = Directory(path.join(oldMusic.path, 'Album'));
      final newAlbum = Directory(path.join(newMusic.path, 'Album'));
      await oldAlbum.create(recursive: true);
      await newAlbum.create(recursive: true);
      final oldSong = File(path.join(oldAlbum.path, 'song.mp3'));
      final missingSong = File(path.join(oldAlbum.path, 'missing.mp3'));
      final newSong = File(path.join(newAlbum.path, 'song.mp3'));
      await oldSong.writeAsBytes([1, 2, 3]);
      await missingSong.writeAsBytes([4, 5]);
      await newSong.writeAsBytes([1, 2, 3]);
      final externalCover = File(path.join(sandbox.path, 'cover.png'));
      await externalCover.writeAsBytes([9, 8, 7]);

      final source = Directory(path.join(sandbox.path, 'source'));
      await source.create();
      final oldIndex = _index(oldMusic.path, oldAlbum.path, [
        _audio(oldSong.path, 3),
        _audio(missingSong.path, 2),
      ]);
      await _json(File(path.join(source.path, 'index.json')), oldIndex);
      await _json(File(path.join(source.path, 'playlists.json')), {
        'entries': [
          {
            'audio': _audio(oldSong.path, 3),
          },
          {
            'audio': _audio(missingSong.path, 2),
          },
        ],
        'imagePath': externalCover.path,
      });
      await File(path.join(source.path, 'cover-cache.bin'))
          .writeAsBytes([6, 6]);
      await Directory(path.join(source.path, 'updates')).create();
      await File(path.join(source.path, 'updates', 'setup.exe'))
          .writeAsBytes([7]);
      await File(path.join(source.path, 'write.partial')).writeAsBytes([8]);

      final current = Directory(path.join(sandbox.path, 'current'));
      await current.create();
      await _json(
          File(path.join(current.path, 'index.json')),
          _index(newMusic.path, newAlbum.path, [
            _audio(newSong.path, 3),
          ]));

      final backup = File(path.join(sandbox.path, 'portable.bak'));
      final exported = await const CacheBackupService()
          .exportBackup(source: source, destination: backup);
      expect(exported.songCount, 2);

      Directory? staged;
      final target = Directory(path.join(sandbox.path, 'restored'));
      final restored = await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: target,
        currentData: current,
        activateLocation: (directory, stagedDirectory) async {
          expect(directory.path, target.path);
          staged = stagedDirectory;
        },
      );
      expect(restored.restoredSongs, 1);
      expect(restored.missingSongs, 1);
      expect(staged, isNotNull);
      expect(await target.exists(), isFalse,
          reason: 'activation is deferred until the next process');

      final restoredIndex = json.decode(
              await File(path.join(staged!.path, 'index.json')).readAsString())
          as Map;
      final folder = (restoredIndex['folders'] as List).single as Map;
      expect(folder['path'], newAlbum.path);
      final audios = folder['audios'] as List;
      expect(audios, hasLength(2));
      expect((audios.first as Map)['path'], newSong.path);
      expect((audios.last as Map)['path'],
          path.join(newAlbum.path, 'missing.mp3'));

      final playlist = json.decode(
          await File(path.join(staged!.path, 'playlists.json'))
              .readAsString()) as Map;
      expect(playlist['entries'], hasLength(2));
      final imagePath = playlist['imagePath'] as String;
      expect(path.isWithin(target.path, imagePath), isTrue);
      final stagedImage = File(
          path.join(staged!.path, path.relative(imagePath, from: target.path)));
      expect(await stagedImage.readAsBytes(), [9, 8, 7]);
      expect(
          await File(path.join(staged!.path, 'cover-cache.bin')).readAsBytes(),
          [6, 6]);
      expect(
          await File(path.join(staged!.path, 'updates', 'setup.exe')).exists(),
          isFalse);
      expect(await File(path.join(staged!.path, 'write.partial')).exists(),
          isFalse);

      final allJson = await _allJsonText(staged!);
      expect(allJson, isNot(contains(oldMusic.path)));
    });

    test('damaged backup changes neither target nor activation pointer',
        () async {
      final current = Directory(path.join(sandbox.path, 'current'));
      final target = Directory(path.join(sandbox.path, 'target'));
      await current.create();
      await target.create();
      await File(path.join(target.path, 'keep.txt')).writeAsString('old');
      final damaged = File(path.join(sandbox.path, 'damaged.bak'));
      await damaged.writeAsString('not a zip');
      var activated = false;
      await expectLater(
        const CacheBackupService().restoreBackup(
          backup: damaged,
          destination: target,
          currentData: current,
          activateLocation: (_, __) async => activated = true,
        ),
        throwsA(anything),
      );
      expect(activated, isFalse);
      expect(
          await File(path.join(target.path, 'keep.txt')).readAsString(), 'old');
    });

    test('damaged source JSON leaves an existing backup untouched', () async {
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      await _json(File(path.join(source.path, 'index.json')), {
        'version': 113,
        'roots': <String>[],
        'folders': <Object>[],
      });
      await File(path.join(source.path, 'settings.json'))
          .writeAsString('{incomplete');
      final destination = File(path.join(sandbox.path, 'existing.bak'));
      await destination.writeAsString('previous-good-backup');

      await expectLater(
        const CacheBackupService()
            .exportBackup(source: source, destination: destination),
        throwsA(isA<CacheBackupException>()),
      );
      expect(await destination.readAsString(), 'previous-good-backup');
      expect(
        await sandbox
            .list()
            .where((entity) => entity.path.endsWith('.partial'))
            .isEmpty,
        isTrue,
      );
    });

    test('declared scan roots ignore stale folders outside those roots',
        () async {
      final oldRoot = await Directory(path.join(sandbox.path, 'old-root'))
          .create(recursive: true);
      final oldAlbum = await Directory(path.join(oldRoot.path, 'Album'))
          .create(recursive: true);
      final oldSong = File(path.join(oldAlbum.path, 'song.mp3'));
      await oldSong.writeAsBytes([1, 2, 3]);

      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      await _json(File(path.join(source.path, 'index.json')),
          _index(oldRoot.path, oldAlbum.path, [_audio(oldSong.path, 3)]));
      final backup = File(path.join(sandbox.path, 'portable.bak'));
      await const CacheBackupService()
          .exportBackup(source: source, destination: backup);

      final declaredRoot = await Directory(path.join(sandbox.path, 'new-root'))
          .create(recursive: true);
      final staleAlbum =
          await Directory(path.join(sandbox.path, 'stale', 'Album'))
              .create(recursive: true);
      final staleSong = File(path.join(staleAlbum.path, 'song.mp3'));
      await staleSong.writeAsBytes([1, 2, 3]);
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      await _json(File(path.join(current.path, 'index.json')), {
        'version': 113,
        'roots': [declaredRoot.path],
        'folders': [
          {
            'path': staleAlbum.path,
            'audios': [_audio(staleSong.path, 3)]
          },
        ],
      });

      Directory? staged;
      final result = await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: Directory(path.join(sandbox.path, 'target')),
        currentData: current,
        activateLocation: (_, stagedDirectory) async =>
            staged = stagedDirectory,
      );
      expect(result.restoredSongs, 0);
      expect(result.missingSongs, 1);
      final restoredIndex = json.decode(
              await File(path.join(staged!.path, 'index.json')).readAsString())
          as Map;
      final retained = (restoredIndex['folders'] as List).single as Map;
      expect(retained['audios'], hasLength(1));
      expect(retained['path'], contains('missing-library'));
    });

    test('stale music outside scan roots is referenced but never copied',
        () async {
      final libraryRoot =
          await Directory(path.join(sandbox.path, 'library')).create();
      final staleSong = File(path.join(sandbox.path, 'stale.dsf'));
      await staleSong.writeAsBytes(List<int>.filled(4096, 0x5a));
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      await _json(
        File(path.join(source.path, 'index.json')),
        _index(
          libraryRoot.path,
          libraryRoot.path,
          const <Map<String, Object?>>[],
        ),
      );
      await _json(File(path.join(source.path, 'playlists.json')), {
        'entries': [
          {
            'audio': _audio(staleSong.path, await staleSong.length()),
          },
        ],
      });

      final backup = File(path.join(sandbox.path, 'stale-reference.bak'));
      await const CacheBackupService()
          .exportBackup(source: source, destination: backup);
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      expect(
        archive.files
            .where((entry) => entry.name.toLowerCase().endsWith('.dsf')),
        isEmpty,
      );

      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      await _json(
        File(path.join(current.path, 'index.json')),
        _index(
          libraryRoot.path,
          libraryRoot.path,
          const <Map<String, Object?>>[],
        ),
      );
      Directory? staged;
      final result = await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: Directory(path.join(sandbox.path, 'restored')),
        currentData: current,
        activateLocation: (_, prepared) async => staged = prepared,
      );
      expect(result.restoredSongs, 0);
      expect(result.missingSongs, 1);
      final playlist = json.decode(
          await File(path.join(staged!.path, 'playlists.json'))
              .readAsString()) as Map;
      expect(playlist['entries'], hasLength(1));
      expect(((playlist['entries'] as List).single as Map)['audio']['path'],
          contains('missing-library'));
    });

    test('stable identities, missing CUE, lyrics and old totals survive backup',
        () async {
      final music =
          await Directory(path.join(sandbox.path, 'oldMusic')).create();
      final newMusic =
          await Directory(path.join(sandbox.path, 'newMusic')).create();
      final song = File(path.join(music.path, 'song.mp3'));
      final movedSong = File(path.join(newMusic.path, 'song.mp3'));
      await song.writeAsBytes([1, 2, 3]);
      await movedSong.writeAsBytes([1, 2, 3]);
      final cue = CueTrackReference(
          cuePath: path.join(music.path, 'album.cue'),
          sourcePath: path.join(music.path, 'album.flac'),
          number: 2,
          startFrame: 15001,
          endFrame: 30003);
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      final registry = TrackIdentityRegistry.inMemory();
      await registry.initialize(directory: source);
      final songId = registry.idFor(song.path);
      final cueId = registry.idFor(cue.identity, cue: cue);
      await registry.flush();
      final identities = registry.toMap();
      ((identities['records'] as List).first as Map)['aliases'] = [
        path.join(sandbox.path, 'previous', 'song.mp3')
      ];
      await _json(
          File(path.join(source.path, 'track_identities.json')), identities);
      await _json(
          File(path.join(source.path, 'index.json')),
          _index(music.path, music.path, [
            {..._audio(song.path, 3), 'track_id': songId},
            {
              ..._audio(cue.identity, 100),
              'track_id': cueId,
              'cue_track': cue.toMap()
            },
          ]));
      await _json(File(path.join(source.path, 'lyric_documents.json')), {
        'version': 1,
        'documents': {
          cueId: {
            'trackId': cueId,
            'path': cue.identity,
            'locked': true,
            'original': '[00:01.00]Original',
            'text': '[00:01.00]Edited',
            'offsetMilliseconds': 321,
          }
        },
      });
      await _json(File(path.join(source.path, 'playback_statistics.json')), {
        'version': 2,
        'tracks': [
          {'id': songId, 'playCount': 7, 'listenMilliseconds': 12345},
          {
            'id': 'local:legacy-unassigned',
            'playCount': 9,
            'listenMilliseconds': 45678,
            'legacyUnassigned': true,
            'candidateTrackIds': [songId, cueId]
          },
        ],
        'days': {'2026-09-07': 58023},
      });
      await _json(
          File(path.join(
              source.path, 'library_migrations', 'batch', 'manifest.json')),
          {'privatePath': song.path});
      await _json(File(path.join(source.path, 'library_migration_last.json')),
          {'batch': 'batch'});
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      await _json(File(path.join(current.path, 'index.json')),
          _index(newMusic.path, newMusic.path, [_audio(movedSong.path, 3)]));
      final backup = File(path.join(sandbox.path, 'identities.bak'));
      await const CacheBackupService()
          .exportBackup(source: source, destination: backup);
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      expect(
          archive.files
              .where((entry) => entry.name.contains('library_migration')),
          isEmpty);
      Directory? staged;
      await const CacheBackupService().restoreBackup(
          backup: backup,
          destination: Directory(path.join(sandbox.path, 'restored')),
          currentData: current,
          activateLocation: (_, ready) async => staged = ready);
      final restoredRegistry = jsonDecode(
          await File(path.join(staged!.path, 'track_identities.json'))
              .readAsString()) as Map;
      expect(
          (restoredRegistry['records'] as List)
              .map((entry) => entry['trackId'])
              .toSet(),
          {songId, cueId});
      expect(((restoredRegistry['records'] as List).first as Map)['aliases'],
          hasLength(1));
      final restoredIndex = jsonDecode(
              await File(path.join(staged!.path, 'index.json')).readAsString())
          as Map;
      final restoredCue =
          ((restoredIndex['folders'] as List).single['audios'] as List).last
              as Map;
      final cueReference = CueTrackReference.fromMap(restoredCue['cue_track']);
      expect(restoredCue['path'], cueReference.identity);
      expect(cueReference.startFrame, 15001);
      expect(cueReference.endFrame, 30003);
      final restoredLyrics = jsonDecode(
          await File(path.join(staged!.path, 'lyric_documents.json'))
              .readAsString()) as Map;
      expect(restoredLyrics['documents'][cueId]['path'], cueReference.identity);
      expect(restoredLyrics['documents'][cueId]['locked'], isTrue);
      expect(restoredLyrics['documents'][cueId]['offsetMilliseconds'], 321);
      final stats = jsonDecode(
          await File(path.join(staged!.path, 'playback_statistics.json'))
              .readAsString()) as Map;
      expect(
          (stats['tracks'] as List)
              .fold<int>(0, (total, row) => total + row['playCount'] as int),
          16);
      expect(stats['days']['2026-09-07'], 58023);
      final stableReload = TrackIdentityRegistry.inMemory();
      await stableReload.initialize(directory: staged!);
      expect(stableReload.idFor(movedSong.path), songId,
          reason: 'A historical alias is not another physical recording.');
      expect(
          stableReload.idFor(cueReference.identity, cue: cueReference), cueId);
    });

    test('two canonical recordings never collapse onto one destination file',
        () async {
      final music =
          await Directory(path.join(sandbox.path, 'oldMusic')).create();
      final newMusic =
          await Directory(path.join(sandbox.path, 'newMusic')).create();
      final survivor = File(path.join(newMusic.path, 'song.mp3'));
      await survivor.writeAsBytes([1, 2, 3]);
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      await _json(
          File(path.join(source.path, 'index.json')),
          _index(music.path, music.path, [
            {
              ..._audio(path.join(music.path, 'A', 'song.mp3'), 3),
              'track_id': 'first-id'
            },
            {
              ..._audio(path.join(music.path, 'B', 'song.mp3'), 3),
              'track_id': 'second-id'
            },
          ]));
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      await _json(File(path.join(current.path, 'index.json')),
          _index(newMusic.path, newMusic.path, [_audio(survivor.path, 3)]));
      final backup = File(path.join(sandbox.path, 'recordings.bak'));
      await const CacheBackupService()
          .exportBackup(source: source, destination: backup);
      Directory? staged;
      final restored = await const CacheBackupService().restoreBackup(
          backup: backup,
          destination: Directory(path.join(sandbox.path, 'restored')),
          currentData: current,
          activateLocation: (_, ready) async => staged = ready);
      expect(restored.restoredSongs, 0);
      expect(restored.missingSongs, 2);
      final index = jsonDecode(
              await File(path.join(staged!.path, 'index.json')).readAsString())
          as Map;
      final rows = (index['folders'] as List).single['audios'] as List;
      expect(rows.map((row) => row['track_id']), ['first-id', 'second-id']);
      final paths = rows.map((row) => row['path']).toSet();
      expect(paths, hasLength(2));
      expect(paths, isNot(contains(survivor.path)));
    });

    test(
        'pending metadata commit blocks export instead of rewriting its journal',
        () async {
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      await _json(File(path.join(source.path, 'metadata_committed.json')),
          {'path': 'pending'});
      await expectLater(
          const CacheBackupService().exportBackup(
              source: source,
              destination: File(path.join(sandbox.path, 'pending.bak'))),
          throwsA(isA<CacheBackupException>()));
      await File(path.join(source.path, 'metadata_committed.json'))
          .rename(path.join(source.path, 'metadata_committed.json.tmp'));
      await expectLater(
          const CacheBackupService().exportBackup(
              source: source,
              destination: File(path.join(sandbox.path, 'pending-temp.bak'))),
          throwsA(isA<CacheBackupException>()));
    });

    test('archive path traversal is rejected before extraction', () async {
      final malicious = File(path.join(sandbox.path, 'malicious.bak'));
      final zip = ZipFileEncoder()..create(malicious.path);
      zip.addArchiveFile(ArchiveFile.string(
          'manifest.json',
          json.encode({
            'format': 'dan-player-cache-backup',
            'version': 1,
            'files': [],
          })));
      zip.addArchiveFile(ArchiveFile.string('../escape.txt', 'bad'));
      zip.closeSync();
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      await expectLater(
        const CacheBackupService().restoreBackup(
          backup: malicious,
          destination: Directory(path.join(sandbox.path, 'target')),
          currentData: current,
          activateLocation: (_, __) async {},
        ),
        throwsA(anything),
      );
      expect(
          await File(path.join(sandbox.path, 'escape.txt')).exists(), isFalse);
    });

    test('Windows-special and case-colliding archive paths are rejected',
        () async {
      final unsafeEntrySets = <List<String>>[
        ['payload/cover.jpg:preview'],
        ['payload/CON.txt'],
        ['payload/trailing.'],
        ['payload/Duplicate.json', 'payload/duplicate.json'],
      ];
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      for (var index = 0; index < unsafeEntrySets.length; index++) {
        final malicious =
            File(path.join(sandbox.path, 'windows-unsafe-$index.bak'));
        final zip = ZipFileEncoder()..create(malicious.path);
        zip.addArchiveFile(ArchiveFile.string(
            'manifest.json',
            json.encode({
              'format': 'dan-player-cache-backup',
              'version': 1,
              'files': [],
            })));
        for (final name in unsafeEntrySets[index]) {
          zip.addArchiveFile(ArchiveFile.string(name, 'bad'));
        }
        zip.closeSync();

        await expectLater(
          const CacheBackupService().restoreBackup(
            backup: malicious,
            destination:
                Directory(path.join(sandbox.path, 'unsafe-target-$index')),
            currentData: current,
            activateLocation: (_, __) async {},
          ),
          throwsA(anything),
          reason: 'must reject ${unsafeEntrySets[index]}',
        );
      }
    });
  });

  group('restore destination policy', () {
    late Directory sandbox;
    late Directory current;

    setUp(() async {
      sandbox =
          await Directory.systemTemp.createTemp('dan-player-policy-test-');
      current =
          await Directory(path.join(sandbox.path, 'Documents', 'Dan Player'))
              .create(recursive: true);
      await File(path.join(current.path, 'index.json')).writeAsString('{}');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('empty folder itself becomes cache root', () async {
      final empty = await Directory(path.join(sandbox.path, 'empty')).create();
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: empty, currentData: current);
      expect(decision.directory.path, empty.path);
      expect(decision.kind, CacheRestoreDestinationKind.emptySelection);
      expect(decision.requiresReplacementConfirmation, isFalse);
    });

    test('recognized cache asks before replacement, including active cache',
        () async {
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: current, currentData: current);
      expect(decision.directory.path, current.path);
      expect(decision.requiresReplacementConfirmation, isTrue);
      expect(decision.replacesActiveDirectory, isTrue);
    });

    test('legacy cache resource folders also require confirmation', () async {
      final legacy =
          await Directory(path.join(sandbox.path, 'legacy-cache')).create();
      await Directory(path.join(legacy.path, 'covers')).create();
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: legacy, currentData: current);
      expect(decision.directory.path, legacy.path);
      expect(decision.kind, CacheRestoreDestinationKind.recognizedCache);
      expect(decision.requiresReplacementConfirmation, isTrue);
    });

    test('ordinary nonempty folder uses Dan Player child', () async {
      final parent =
          await Directory(path.join(sandbox.path, 'ordinary')).create();
      await File(path.join(parent.path, 'notes.txt')).writeAsString('keep');
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: parent, currentData: current);
      expect(decision.directory.path, path.join(parent.path, 'Dan Player'));
      expect(decision.kind, CacheRestoreDestinationKind.childDirectory);
    });

    test('unrelated child conflict receives a unique directory', () async {
      final parent =
          await Directory(path.join(sandbox.path, 'conflict')).create();
      await File(path.join(parent.path, 'notes.txt')).writeAsString('keep');
      final child =
          await Directory(path.join(parent.path, 'Dan Player')).create();
      await File(path.join(child.path, 'unrelated.txt')).writeAsString('keep');
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: parent, currentData: current);
      expect(decision.directory.path,
          path.join(parent.path, 'Dan Player restored'));
      expect(decision.kind, CacheRestoreDestinationKind.uniqueChildDirectory);
    });

    test('a same-named file is never mistaken for an available directory',
        () async {
      final parent =
          await Directory(path.join(sandbox.path, 'file-conflict')).create();
      await File(path.join(parent.path, 'notes.txt')).writeAsString('keep');
      await File(path.join(parent.path, 'Dan Player')).writeAsString('keep');
      final decision = await CacheRestoreDestinationPolicy.decide(
          selected: parent, currentData: current);
      expect(decision.directory.path,
          path.join(parent.path, 'Dan Player restored'));
      expect(decision.kind, CacheRestoreDestinationKind.uniqueChildDirectory);
    });
  });
}

Map<String, Object?> _audio(String audioPath, int size) => {
      'kind': 'local',
      'title': path.basenameWithoutExtension(audioPath),
      'path': audioPath,
      'file_size': size,
    };

Map<String, Object?> _index(
        String root, String folder, List<Map<String, Object?>> audios) =>
    {
      'version': 1,
      'roots': [root],
      'folders': [
        {'path': folder, 'audios': audios}
      ],
    };

Future<void> _json(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(json.encode(value));
}

Future<String> _allJsonText(Directory directory) async {
  final buffer = StringBuffer();
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
      buffer.write(await entity.readAsString());
    }
  }
  return buffer.toString();
}
