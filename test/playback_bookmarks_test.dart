import 'dart:io';
import 'dart:convert';

import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late File file;
  setUp(() async {
    final root = Directory(path.join(Directory.current.parent.path, 'tool',
        'qa-local', 'release-final-bookmarks'));
    await root.create(recursive: true);
    final directory = await root.createTemp('store-');
    file = File(path.join(directory.path, 'playback_bookmarks.json'));
  });

  test(
      'concurrent saves persist names, positions and ranges per normalized track',
      () async {
    final store = PlaybackBookmarkStore(file);
    await Future.wait([
      store.add(
          localPath: r'J:\Music\Canon.flac', label: ' Theme ', position: 12.25),
      store.add(
          localPath: r'J:\Music\Canon.flac',
          label: 'Practice',
          position: 20,
          end: 30),
      store.add(
          localPath: r'J:\Music\Good Time.flac', label: 'Chorus', position: 15),
    ]);
    final entries = await store.forTrack('j:/Music/Canon.flac');
    expect(entries.map((item) => item.label), ['Theme', 'Practice']);
    expect(entries.first.positionMs, 12250);
    expect(entries.last.end, 30);
    await store.rename(entries.first.id, 'Opening');
    await store.remove(entries.last.id);
    final restored =
        await PlaybackBookmarkStore(file).forTrack(r'J:\Music\CANON.flac');
    expect(restored.single.label, 'Opening');
    expect(restored.single.position, 12.25);
    expect((await store.forTrack(r'J:\Music\Good Time.flac')).single.label,
        'Chorus');
  });

  test(
      'failed write preserves disk and memory and does not poison the next save',
      () async {
    final store = PlaybackBookmarkStore(file);
    await store.add(localPath: 'song.flac', label: 'Keep', position: 1);
    final before = await file.readAsString();
    final obstruction = await Directory('${file.path}.tmp').create();
    await expectLater(
        store.add(localPath: 'song.flac', label: 'Failure', position: 2),
        throwsA(isA<FileSystemException>()));
    expect((await store.forTrack('song.flac')).single.label, 'Keep');
    expect(await file.readAsString(), before);
    await obstruction.rename('${file.path}.blocked');
    await store.add(localPath: 'song.flac', label: 'Retry', position: 3);
    expect((await PlaybackBookmarkStore(file).forTrack('song.flac')).length, 2);
  });

  test('backup recovers corruption and invalid timing never modifies the file',
      () async {
    final store = PlaybackBookmarkStore(file);
    await store.add(localPath: 'song.flac', label: 'Backup', position: 1);
    await store.add(localPath: 'song.flac', label: 'Latest', position: 2);
    await file.writeAsString('{truncated');
    final recovered = PlaybackBookmarkStore(file);
    expect((await recovered.forTrack('song.flac')).single.label, 'Backup');
    await recovered.add(
        localPath: 'song.flac', label: 'Recovered', position: 3);
    final before = await file.readAsString();
    for (final position in [double.nan, double.infinity, -1.0]) {
      await expectLater(
          recovered.add(
              localPath: 'song.flac', label: 'Bad', position: position),
          throwsArgumentError);
    }
    await expectLater(
        recovered.add(
            localPath: 'song.flac', label: 'Bad range', position: 3, end: 3.5),
        throwsArgumentError);
    expect(await file.readAsString(), before);
    final result = await PlaybackBookmarkStore(file).forTrack('song.flac');
    expect(result.map((item) => item.label), ['Backup', 'Recovered']);
    expect(result.last.fitsDuration(3), isFalse);
    expect(result.last.fitsDuration(4), isTrue);
  });

  test('restored path casing and an absent song do not hide valid bookmarks',
      () async {
    await file.writeAsString(jsonEncode({
      'version': 1,
      'bookmarks': [
        {
          'id': 'restored',
          'track': r'J:\Restored Music\Canon.flac',
          'label': 'Practice',
          'positionMs': 2500
        },
        {'id': 'missing', 'label': 'Missing song', 'positionMs': 1000},
      ]
    }));
    final restored = await PlaybackBookmarkStore(file)
        .forTrack('j:/restored music/canon.flac');
    expect(restored.single.label, 'Practice');
    expect(restored.single.position, 2.5);
  });

  test('newer bookmark data blocks reads and writes despite an older backup',
      () async {
    final backup = File('${file.path}.bak');
    final newer = jsonEncode({
      'version': 2,
      'bookmarks': [],
      'futureData': {'keep': 'newer-version contents'}
    });
    final older = jsonEncode({
      'version': 1,
      'bookmarks': [
        {
          'id': 'older',
          'track': 'song.flac',
          'label': 'Older bookmark',
          'positionMs': 1000
        }
      ]
    });
    await file.writeAsString(newer);
    await backup.writeAsString(older);
    final before = await file.readAsBytes();
    final backupBefore = await backup.readAsBytes();
    final store = PlaybackBookmarkStore(file);

    await expectLater(store.all(), throwsUnsupportedError);
    await expectLater(store.forTrack('song.flac'), throwsUnsupportedError);
    await expectLater(
        store.add(localPath: 'song.flac', label: 'New', position: 2),
        throwsUnsupportedError);
    await expectLater(store.remove('older'), throwsUnsupportedError);

    expect(await file.readAsBytes(), before);
    expect(await backup.readAsBytes(), backupBefore);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}
