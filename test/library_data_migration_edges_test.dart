import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/cue_track.dart';
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
    final base = Directory(p.normalize(p.absolute(
        Platform.environment['DAN_PLAYER_DATA_DIR'] ??
            p.join('build', 'qa-migration-edges'))));
    await base.create(recursive: true);
    root = await base.createTemp('edge-');
    data = await Directory(p.join(root.path, 'data')).create();
    before = await Directory(p.join(root.path, 'old')).create();
    after = await Directory(p.join(root.path, 'new')).create();
    oldSong = p.join(before.absolute.path, 'song.flac');
    newSong = p.join(after.absolute.path, 'song.flac');
    await File(newSong).writeAsBytes([1, 2, 3]);
    mapping = LibraryPathMapping(before.absolute.path, after.absolute.path);
    await write('index.json', {
      'version': 113,
      'roots': [before.absolute.path],
      'folders': [
        {
          'path': before.absolute.path,
          'audios': [
            {'path': oldSong, 'title': 'Song', 'file_size': 3}
          ]
        }
      ]
    });
  });
  tearDown(() => root.delete(recursive: true));

  test('aliases and arbitrary titles/lyric contents are never path-remapped',
      () {
    final moved = remapLibraryDocument({
      'trackId': 'local:unchanged',
      'path': r'Z:\unrelated\song.flac',
      'aliases': [oldSong],
      'title': oldSong,
      'artist': oldSong,
      'original': {
        'lines': [
          {'text': oldSong}
        ]
      },
      'editedText': oldSong,
      'sourcePath': oldSong,
    }, mapping) as Map;
    expect(moved['aliases'], [oldSong]);
    expect(moved['title'], oldSong);
    expect(moved['artist'], oldSong);
    expect(moved['original']['lines'][0]['text'], oldSong);
    expect(moved['editedText'], oldSong);
    expect(moved['sourcePath'], newSong);
  });

  Future<CueTrackReference> addCue({String nextIndex = '00:10:01'}) async {
    final oldCue = p.join(before.absolute.path, 'album.cue');
    final newCue = p.join(after.absolute.path, 'album.cue');
    final source = p.join(before.absolute.path, 'album.flac');
    await File(p.join(after.absolute.path, 'album.flac'))
        .writeAsBytes([4, 5, 6]);
    await File(newCue).writeAsString('FILE "album.flac" WAVE\n'
        '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n    INDEX 01 $nextIndex\n');
    final cue = CueTrackReference(
        cuePath: oldCue,
        sourcePath: source,
        number: 1,
        startFrame: 0,
        endFrame: 751);
    final index = await read('index.json');
    index['folders'][0]['audios'].add({
      'path': cue.identity,
      'title': 'Segment',
      'file_size': 3,
      'cue_track': cue.toMap()
    });
    await write('index.json', index);
    return cue;
  }

  test('CUE preview reads physical source and verifies exact target CD frames',
      () async {
    final cue = await addCue();
    final service = LibraryDataMigration(data);
    final preview = await service.preview(mapping);
    expect(preview.matches, 2);
    expect(preview.canApply, isTrue);
    await service.schedule(mapping);
    await service.recover();
    final moved = (await read('index.json'))['folders'][0]['audios'][1];
    final restoredCue = CueTrackReference.fromMap(moved['cue_track']);
    expect(moved['path'], restoredCue.identity);
    expect(restoredCue.startFrame, cue.startFrame);
    expect(restoredCue.endFrame, cue.endFrame);
    expect(restoredCue.sourcePath, mapping.apply(cue.sourcePath));
  });

  test(
      'CUE boundary change is a conflict and does not inherit old segment work',
      () async {
    await addCue(nextIndex: '00:11:01');
    final preview = await LibraryDataMigration(data).preview(mapping);
    expect(preview.canApply, isFalse);
    expect(preview.conflicts, contains(contains('分轨边界已变化')));
    expect(await LibraryDataMigration(data).hasPending, isFalse);
  });

  test('offline destination is reported for the complete mapping', () async {
    final rows = [
      for (var i = 0; i < 300; i++)
        {'path': p.join(before.absolute.path, '$i.flac'), 'file_size': 3}
    ];
    final index = await read('index.json');
    index['folders'][0]['audios'] = rows;
    await write('index.json', index);
    await File(newSong).delete();
    await after.delete();
    final preview = await LibraryDataMigration(data).preview(mapping);
    expect(preview.matches, 300);
    expect(preview.missing, 300);
    expect(preview.canApply, isFalse);
  });

  test('cancelled preview never writes an intent or reports an applied mapping',
      () async {
    var checks = 0;
    final service = LibraryDataMigration(data);
    await expectLater(service.preview(mapping, cancelled: () => ++checks >= 2),
        throwsA(isA<LibraryMigrationCancelled>()));
    expect(await service.hasPending, isFalse);
    expect(
        (await read('index.json'))['folders'][0]['audios'][0]['path'], oldSong);
  });

  test(
      'rollback preserves newly-created documents in displaced and resumes interruption',
      () async {
    final service = LibraryDataMigration(data);
    await service.schedule(mapping);
    await service.recover();
    final latest = await read('library_migration_last.json');
    await write('playback_bookmarks.json', {'new': newSong});
    await write('lyric_documents.json', {'userEdited': '[00:01]Keep my work'});
    await write('lyric_documents.json.bak', {'previousRevision': 'keep too'});
    await expectLater(
        LibraryDataMigration(data, afterReplace: (count) async {
          if (count == 1) throw StateError('Interrupted after displacement');
        }).restorePrevious(),
        throwsStateError);
    await service.recover();
    expect(
        (await read('index.json'))['folders'][0]['audios'][0]['path'], oldSong);
    expect(await File(p.join(data.path, 'playback_bookmarks.json')).exists(),
        isFalse);
    expect(await File(p.join(data.path, 'lyric_documents.json')).exists(),
        isFalse);
    final displaced =
        p.join(data.path, 'library_migrations', latest['id'], 'displaced');
    expect(
        jsonDecode(await File(p.join(displaced, 'playback_bookmarks.json'))
            .readAsString())['new'],
        newSong);
    expect(
        jsonDecode(await File(p.join(displaced, 'lyric_documents.json'))
            .readAsString())['userEdited'],
        '[00:01]Keep my work');
    expect(await File(p.join(displaced, 'lyric_documents.json.bak')).exists(),
        isTrue);
    await service.recover();
    expect(Directory(displaced).listSync(), hasLength(3));
  });

  test('manifest changes are detected before rollback can displace user data',
      () async {
    final service = LibraryDataMigration(data);
    await service.schedule(mapping);
    await service.recover();
    await write('lyric_documents.json', {'new': 'keep'});
    final latest = await read('library_migration_last.json');
    final manifest = File(
        p.join(data.path, 'library_migrations', latest['id'], 'manifest.json'));
    final value = jsonDecode(await manifest.readAsString()) as Map;
    value['absent'] = [];
    await manifest.writeAsString(jsonEncode(value));
    await expectLater(service.restorePrevious(), throwsFormatException);
    expect((await read('lyric_documents.json'))['new'], 'keep');
    expect(
        (await read('index.json'))['folders'][0]['audios'][0]['path'], newSong);
  });
}
