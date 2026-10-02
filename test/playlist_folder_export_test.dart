import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:dan_player/library/playlist_folder_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('dan-folder-export-');
  });
  tearDown(() async {
    if (await fixture.exists()) await fixture.delete(recursive: true);
  });
  Audio audio(String path, {String title = 'Title'}) => Audio.fromMap(
      {'path': path, 'title': title, 'artist': 'Artist', 'duration': 12});
  Future<File> source(String relative, List<int> bytes) async {
    final file = File(p.join(fixture.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  test('folder carries audio and relative M3U in exact occurrence order',
      () async {
    final first = await source('a/same.flac', [1, 2, 3]);
    final second = await source('b/same.flac', [4, 5]);
    final item = audio(first.path, title: 'First');
    final plan = snapshotPlaylistFolderExport([item, audio(second.path), item]);
    final frozenTitles = plan.entries.map((entry) => entry.title).toList();
    item.title = 'Edited after click';
    item.path = 'C:/unavailable/new.flac';
    final output = await Directory(p.join(fixture.path, 'out')).create();
    final progress = <PlaylistFolderExportProgress>[];
    final result = await runPlaylistFolderExport(plan, output,
        name: 'Mix',
        cancellation: PlaylistFolderExportCancellation(),
        onProgress: progress.add);
    expect(result.entryCount, 3);
    expect(result.copiedFiles, 2);
    final text = await result.playlistFile.readAsString();
    expect(text, isNot(contains(fixture.path)));
    final entries = (await readM3uFile(result.playlistFile)).entries;
    expect(entries.map((e) => e.title), frozenTitles);
    expect(entries.first.path, entries.last.path);
    expect(entries.first.path, isNot(entries[1].path));
    expect(await File(entries.first.path).readAsBytes(), [1, 2, 3]);
    expect(await File(entries[1].path).readAsBytes(), [4, 5]);
    expect(await first.readAsBytes(), [1, 2, 3]);
    expect(progress.last.completedBytes, 5);
    expect(progress.last.fraction, 1);
    expect(await output.list().toList(), hasLength(1));
  });

  test('online and CUE are skipped, empty and oversized requests are explicit',
      () async {
    final local = audio('C:/Music/single.flac');
    final cue = parseCue(
        'FILE "disc.flac" WAVE\n TRACK 01 AUDIO\n'
        ' INDEX 01 00:00:00\n',
        cuePath: 'C:/Music/disc.cue');
    final cueAudio = Audio.fromMap({
      'path': cue.entries.first.reference.identity,
      'cue_track': cue.entries.first.reference.toMap()
    });
    final online = Audio.fromMap(
        {'path': 'online://qq/1', 'online_provider': 'qq', 'online_id': '1'});
    final plan = snapshotPlaylistFolderExport([online, cueAudio, local]);
    expect(plan.skipped, 2);
    expect(plan.uniqueFileCount, 1);
    expect(plan.entries.single.path, contains('single.flac'));
    expect(
        () =>
            snapshotPlaylistFolderExport(List.filled(m3uMaxEntries + 1, local)),
        throwsFormatException);
    await expectLater(
        runPlaylistFolderExport(
            snapshotPlaylistFolderExport([online, cueAudio]), fixture,
            cancellation: PlaylistFolderExportCancellation()),
        throwsFormatException);
    expect(await fixture.list().isEmpty, isTrue);
  });

  test('existing folder and same name file survive with safe new output name',
      () async {
    final file = await source('source/normal.flac', [8]);
    final output = await Directory(p.join(fixture.path, 'out')).create();
    final existing = await Directory(p.join(output.path, '_CON')).create();
    await File(p.join(existing.path, 'keep.txt')).writeAsString('untouched');
    await File(p.join(output.path, '_CON (2)')).writeAsString('also untouched');
    final result = await runPlaylistFolderExport(
        snapshotPlaylistFolderExport([audio(file.path)]), output,
        name: 'CON. ', cancellation: PlaylistFolderExportCancellation());
    expect(p.basename(result.directory.path), '_CON (3)');
    expect(await File(p.join(existing.path, 'keep.txt')).readAsString(),
        'untouched');
    expect(await File(p.join(output.path, '_CON (2)')).readAsString(),
        'also untouched');
    expect(await output.list().toList(), hasLength(3));
  });

  test('cancellation during streamed copy removes only owned staging',
      () async {
    final file = await source('source/large.wav', List.filled(1024 * 1024, 7));
    final output = await Directory(p.join(fixture.path, 'out')).create();
    final keep = await source('out/keep.txt', [9]);
    final cancellation = PlaylistFolderExportCancellation();
    await expectLater(
        runPlaylistFolderExport(
            snapshotPlaylistFolderExport([audio(file.path)]), output,
            cancellation: cancellation, onProgress: (progress) {
          if (progress.completedBytes > 0) cancellation.cancel();
        }),
        throwsA(isA<PlaylistFolderExportCancelled>()));
    expect(await output.list().toList(), hasLength(1));
    expect(await keep.readAsBytes(), [9]);
    expect(await file.length(), 1024 * 1024);
  });

  test('source edits abort without publishing a partial folder', () async {
    final file = await source('source/edit.wav', List.filled(256 * 1024, 7));
    final output = await Directory(p.join(fixture.path, 'out')).create();
    var changed = false;
    await expectLater(
        runPlaylistFolderExport(
            snapshotPlaylistFolderExport([audio(file.path)]), output,
            cancellation: PlaylistFolderExportCancellation(),
            onProgress: (progress) {
          if (!changed && progress.completedBytes > 0) {
            changed = true;
            file.setLastModifiedSync(DateTime.utc(2020));
          }
        }),
        throwsFormatException);
    expect(changed, isTrue);
    expect(await output.list().isEmpty, isTrue);
  });

  test('missing source fails before staging; pre-cancel does not write',
      () async {
    final plan = snapshotPlaylistFolderExport(
        [audio(p.join(fixture.path, 'missing.flac'))]);
    await expectLater(
        runPlaylistFolderExport(plan, fixture,
            cancellation: PlaylistFolderExportCancellation()),
        throwsA(isA<FileSystemException>()));
    final cancelled = PlaylistFolderExportCancellation()..cancel();
    await expectLater(
        runPlaylistFolderExport(plan, fixture, cancellation: cancelled),
        throwsA(isA<PlaylistFolderExportCancelled>()));
    expect(await fixture.list().isEmpty, isTrue);
  });

  test('UTF-8 playlist overflow is rejected before any music is copied',
      () async {
    final file = await source('source/oversize.flac', [1, 2]);
    final item = audio(file.path)..artist = '艺' * 3000;
    final output = await Directory(p.join(fixture.path, 'out')).create();
    var copyStarted = false;
    await expectLater(
        runPlaylistFolderExport(
            snapshotPlaylistFolderExport(List.filled(300, item)), output,
            cancellation: PlaylistFolderExportCancellation(),
            onProgress: (progress) {
          copyStarted |= !progress.preparing;
        }),
        throwsFormatException);
    expect(copyStarted, isFalse);
    expect(await output.list().isEmpty, isTrue);
    expect(await file.readAsBytes(), [1, 2]);
  });

  test('progress callbacks can own UI-like unsendable objects', () async {
    final file = await source('source/worker.flac', [3, 4]);
    final output = await Directory(p.join(fixture.path, 'out')).create();
    final port = ReceivePort();
    var updates = 0;
    try {
      final result = await runPlaylistFolderExport(
          snapshotPlaylistFolderExport([audio(file.path)]), output,
          cancellation: PlaylistFolderExportCancellation(), onProgress: (_) {
        expect(port.isBroadcast, isFalse);
        updates++;
      });
      expect(updates, greaterThan(0));
      final entry = (await readM3uFile(result.playlistFile)).entries.single;
      expect(await File(entry.path).readAsBytes(), [3, 4]);
    } finally {
      port.close();
    }
  });
}
