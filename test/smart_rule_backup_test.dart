import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const service = CacheBackupService();
const onlyRules = BackupSelection(components: {BackupComponent.playlists});

Future<void> writeJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(value));
}

Future<Directory> restore(
    File backup, Directory current, Directory destination) async {
  Directory? staged;
  await service.restoreBackup(
      backup: backup,
      destination: destination,
      currentData: current,
      activateLocation: (_, value) async => staged = value);
  return staged!;
}

Map<String, Object?> index(String root, String song) => {
      'version': 113,
      'roots': [root],
      'folders': [
        {
          'path': root,
          'audios': [
            {'path': song, 'title': 'Song', 'duration': 180, 'file_size': 3}
          ]
        }
      ]
    };

Future<File> alteredArchive(
    File original, File output, Map<String, Object?> document) async {
  final archive = ZipDecoder().decodeBytes(await original.readAsBytes());
  final bytes = utf8.encode(jsonEncode(document));
  final manifest = jsonDecode(
          utf8.decode(archive.findFile('manifest.json')!.content as List<int>))
      as Map;
  for (final descriptor in manifest['files'] as List) {
    if (descriptor['path'] == 'smart_playlists.json') {
      descriptor['size'] = bytes.length;
      descriptor['sha256'] = sha256.convert(bytes).toString();
    }
  }
  final result = Archive();
  for (final file in archive.files) {
    final content = file.name == 'payload/smart_playlists.json'
        ? bytes
        : file.name == 'manifest.json'
            ? utf8.encode(jsonEncode(manifest))
            : file.content as List<int>;
    result.addFile(ArchiveFile(file.name, content.length, content));
  }
  await output.writeAsBytes(ZipEncoder().encode(result)!);
  return output;
}

void main() {
  late Directory sandbox;
  setUp(() async =>
      sandbox = await Directory.systemTemp.createTemp('dan-smart-backup-'));
  tearDown(() async => sandbox.delete(recursive: true));

  test(
      'unbound existing and missing folder rules round trip exactly without collecting assets',
      () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final folder =
        await Directory(p.join(sandbox.path, 'outside-root')).create();
    final absent = p.join(sandbox.path, 'not-mounted', 'future.flac');
    final music = File(p.join(folder.path, 'untouched.flac'));
    await music.writeAsBytes([1, 2, 3]);
    final rule = SmartPlaylist(
        id: 'folders',
        name: 'Dormant folder rules',
        condition: SmartCondition.group([
          SmartCondition.term(SmartField.folderWithin, folder.path),
          SmartCondition.term(SmartField.folderWithin, absent, exclude: true),
        ], any: true));
    await SmartPlaylistStore(File(p.join(source.path, 'smart_playlists.json')))
        .upsert(rule);
    final backup = File(p.join(sandbox.path, 'folders.bak'));
    final exported =
        await service.exportBackup(source: source, destination: backup);
    expect(exported.songCount, 0);
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final portable = jsonDecode(utf8.decode(archive
        .findFile('payload/smart_playlists.json')!
        .content as List<int>));
    for (final leaf
        in portable['playlists'][0]['condition']['children'] as List) {
      expect(leaf['value'], startsWith('@dan-player-backup/folder-reference/'));
    }
    expect(archive.files.any((file) => file.name.contains('imported-assets')),
        isFalse);
    final staged = await restore(
        backup, source, Directory(p.join(sandbox.path, 'restored')));
    expect(
        (await SmartPlaylistStore(
                    File(p.join(staged.path, 'smart_playlists.json')))
                .list())
            .single
            .toJson(),
        rule.toJson());
    expect(await music.readAsBytes(), [1, 2, 3]);
    expect(await Directory(absent).exists(), isFalse);
  });

  test(
      'known-root folder rules relocate including absent folders with audio-like names',
      () async {
    final oldRoot = await Directory(p.join(sandbox.path, 'old-music')).create();
    final newRoot = await Directory(p.join(sandbox.path, 'new-music')).create();
    final oldSong = File(p.join(oldRoot.path, 'song.flac'));
    final newSong = File(p.join(newRoot.path, 'song.flac'));
    await oldSong.writeAsBytes([1, 2, 3]);
    await newSong.writeAsBytes([1, 2, 3]);
    final source = Directory(p.join(sandbox.path, 'source'));
    final current = Directory(p.join(sandbox.path, 'current'));
    await writeJson(File(p.join(source.path, 'index.json')),
        index(oldRoot.path, oldSong.path));
    await writeJson(File(p.join(current.path, 'index.json')),
        index(newRoot.path, newSong.path));
    final missing = p.join(oldRoot.path, 'NotYet', 'Album.mp3');
    final rule = SmartPlaylist(
        id: 'bound',
        name: 'Imported folders',
        condition: SmartCondition.group([
          SmartCondition.term(SmartField.folderWithin, oldRoot.path),
          SmartCondition.term(SmartField.folderWithin, missing),
        ], any: true));
    await SmartPlaylistStore(File(p.join(source.path, 'smart_playlists.json')))
        .upsert(rule);
    final backup = File(p.join(sandbox.path, 'relocation.bak'));
    final exported =
        await service.exportBackup(source: source, destination: backup);
    expect(exported.songCount, 1,
        reason: 'A folder rule is never a song reference.');
    final staged = await restore(
        backup, current, Directory(p.join(sandbox.path, 'restored')));
    final restored = (await SmartPlaylistStore(
                File(p.join(staged.path, 'smart_playlists.json')))
            .list())
        .single;
    expect(restored.condition!.children.map((term) => term.value),
        [newRoot.path, p.join(newRoot.path, 'NotYet', 'Album.mp3')]);
    expect(await oldSong.readAsBytes(), [1, 2, 3]);
    expect(await newSong.readAsBytes(), [1, 2, 3]);
    expect(await Directory(missing).exists(), isFalse);
  });

  test(
      'path-like title artist album tag and token-like text stay literal and collect no files',
      () async {
    final source = await Directory(p.join(sandbox.path, 'source')).create();
    final external = File(p.join(sandbox.path, 'private.bin'));
    await external.writeAsBytes([8, 9, 10]);
    final secret = File(p.join(source.path, 'secret.bin'));
    await secret.writeAsBytes([4, 5, 6]);
    final rule = SmartPlaylist(
        id: 'literal',
        name: 'Literal text',
        condition: SmartCondition.group([
          for (final field in [
            SmartField.titleContains,
            SmartField.artistContains,
            SmartField.albumContains,
            SmartField.personalTag,
            SmartField.composerContains,
            SmartField.albumArtistContains,
            SmartField.languageIs,
            SmartField.fileNameContains,
          ])
            SmartCondition.term(field, external.path),
          const SmartCondition.term(
              SmartField.titleContains, '@dan-player-backup/cache/secret.bin'),
        ], any: true));
    await SmartPlaylistStore(File(p.join(source.path, 'smart_playlists.json')))
        .upsert(rule);
    final backup = File(p.join(sandbox.path, 'literal.bak'));
    final exported = await service.exportBackup(
        source: source, destination: backup, selection: onlyRules);
    expect(exported.songCount, 0);
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    expect(archive.files.map((file) => file.name),
        unorderedEquals(['manifest.json', 'payload/smart_playlists.json']));
    final portable = jsonDecode(utf8.decode(archive
        .findFile('payload/smart_playlists.json')!
        .content as List<int>));
    expect(portable['playlists'][0]['condition']['children'][0]['value'],
        external.path);
    final staged = await restore(
        backup, source, Directory(p.join(sandbox.path, 'restored')));
    expect(
        (await SmartPlaylistStore(
                    File(p.join(staged.path, 'smart_playlists.json')))
                .list())
            .single
            .toJson(),
        rule.toJson());
    expect(await external.readAsBytes(), [8, 9, 10]);
    expect(await secret.readAsBytes(), [4, 5, 6]);
    expect(await File(p.join(staged.path, 'secret.bin')).exists(), isFalse);
  });

  test(
      'future source schema refuses export and preserves previous backup and source data',
      () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final file = File(p.join(source.path, 'smart_playlists.json'));
    await writeJson(file, {'version': 5, 'playlists': []});
    final before = await file.readAsString();
    final backup = File(p.join(sandbox.path, 'previous.bak'));
    await backup.writeAsString('previous valid backup');
    await expectLater(service.exportBackup(source: source, destination: backup),
        throwsA(isA<CacheBackupException>()));
    expect(await backup.readAsString(), 'previous valid backup');
    expect(await file.readAsString(), before);
  });

  test(
      'future or malicious restored rules refuse activation and preserve live and destination data',
      () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final file = File(p.join(source.path, 'smart_playlists.json'));
    const valid = SmartPlaylist(
        id: 'old',
        name: 'Old',
        condition: SmartCondition.term(SmartField.titleContains, 'night'));
    await SmartPlaylistStore(file).upsert(valid);
    final before = await file.readAsString();
    final backup = File(p.join(sandbox.path, 'valid.bak'));
    await service.exportBackup(source: source, destination: backup);
    final target =
        await Directory(p.join(sandbox.path, 'destination')).create();
    final keep = File(p.join(target.path, 'keep.txt'));
    await keep.writeAsString('keep destination');
    final invalid = <Map<String, Object?>>[
      {
        'version': 5,
        'playlists': [valid.toJson()]
      },
      {
        'version': 3,
        'playlists': [
          {
            ...valid.toJson(),
            'condition': {
              'field': 'folderWithin',
              'value': '@dan-player-backup/folder-reference/relative',
              'exclude': false
            }
          }
        ]
      },
      {
        'version': 3,
        'playlists': [
          {
            ...valid.toJson(),
            'condition': {
              'field': 'folderWithin',
              'value': '@dan-player-backup/folder-reference/%GG',
              'exclude': false
            }
          }
        ]
      },
      {
        'version': 3,
        'playlists': [
          {
            ...valid.toJson(),
            'condition': {
              'field': 'unknown',
              'value': r'C:\private\asset.bin',
              'exclude': false
            }
          }
        ]
      },
    ];
    for (var i = 0; i < invalid.length; i++) {
      final bad = await alteredArchive(
          backup, File(p.join(sandbox.path, 'bad-$i.bak')), invalid[i]);
      var activated = false;
      await expectLater(
          service.restoreBackup(
              backup: bad,
              destination: target,
              currentData: source,
              activateLocation: (_, __) async => activated = true),
          throwsA(isA<CacheBackupException>()));
      expect(activated, isFalse);
      expect(await keep.readAsString(), 'keep destination');
      expect(await file.readAsString(), before);
    }
    expect(
        await sandbox
            .list()
            .where((entry) =>
                p.basename(entry.path).startsWith('.dan-player-pending-'))
            .toList(),
        isEmpty);
  });
}
