import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _local(String path) => Audio(
      'Track',
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'test',
      language: 'en',
    );

Audio _online(String id) => Audio.online(
      provider: 'qq',
      id: id,
      title: 'Online',
      artist: 'Artist',
      album: 'Album',
      duration: 180,
      bitrate: 320,
    );

LibraryStatisticsScanner _scanner({
  LocalAudioFileInspector? inspectFile,
  bool windowsPaths = true,
}) =>
    LibraryStatisticsScanner(
      windowsPaths: windowsPaths,
      inspectFile:
          inspectFile ?? (_) async => const LocalAudioFileInfo.available(100),
      readLyrics: (_) async => throw StateError('reliable tags need no LRC IO'),
    );

void main() {
  test('groups direct parent paths, not basename or recursive ancestors',
      () async {
    final snapshot = await _scanner().scan([
      _local(r'D:\Music\Same\first.mp3'),
      _local(r'D:\Music\Same\second.mp3'),
      _local(r'E:\Music\Same\other.mp3'),
      _local(r'D:\Music\Same\Child\nested.mp3'),
    ]);
    expect(snapshot.localFolderCount, 3);
    final folders = {
      for (final folder in snapshot.folders) folder.path: folder
    };
    expect(
        folders.keys,
        unorderedEquals([
          r'D:\Music\Same',
          r'E:\Music\Same',
          r'D:\Music\Same\Child',
        ]));
    expect(folders[r'D:\Music\Same']!.fileCount, 2);
    expect(folders[r'D:\Music\Same']!.bytes, 200);
    expect(folders[r'D:\Music\Same\Child']!.fileCount, 1);
    expect(folders.containsKey(r'D:\Music'), isFalse);
  });

  test(
      'different drives, UNC servers, shares and filesystem roots stay distinct',
      () async {
    final snapshot = await _scanner().scan([
      _local(r'C:\Music\Mix\one.mp3'),
      _local(r'D:\Music\Mix\two.mp3'),
      _local(r'\\server-a\share\Mix\three.mp3'),
      _local(r'\\server-b\share\Mix\four.mp3'),
      _local(r'\\server-a\other\Mix\five.mp3'),
      _local(r'D:\root.mp3'),
    ]);
    expect(snapshot.localFolderCount, 6);
    expect(
        snapshot.folders.map((folder) => folder.path),
        containsAll([
          r'C:\Music\Mix',
          r'D:\Music\Mix',
          r'\\server-a\share\Mix',
          r'\\server-b\share\Mix',
          r'\\server-a\other\Mix',
          'D:\\',
        ]));
  });

  test('Windows case, slash and dot normalization reuse existing track dedupe',
      () async {
    var calls = 0;
    final snapshot = await _scanner(inspectFile: (_) async {
      calls++;
      return const LocalAudioFileInfo.available(7);
    }).scan([
      _local(r'D:\Music\Mix\one.mp3'),
      _local('d:/music/MIX/./one.mp3'),
      _local('d:/music/mix/sub/../two.mp3'),
    ]);
    expect(calls, 2);
    expect(snapshot.duplicateEntries, 1);
    expect(snapshot.localFolderCount, 1);
    final folder = snapshot.folders.single;
    expect(folder.path, r'D:\Music\Mix');
    expect(folder.fileCount, 2);
    expect(folder.bytes, 14);
  });

  test('POSIX case-sensitive directories remain separate', () async {
    final snapshot = await _scanner(windowsPaths: false).scan([
      _local('/music/Mix/one.mp3'),
      _local('/music/mix/two.mp3'),
      _local('/music/Mix/nested/../three.mp3'),
    ]);
    expect(snapshot.localFolderCount, 2);
    expect(snapshot.folders.first.path, '/music/Mix');
    expect(snapshot.folders.first.fileCount, 2);
  });

  test(
      'physical aliases keep the first library directory without double-counting',
      () async {
    final snapshot = await _scanner(
      inspectFile: (_) async => const LocalAudioFileInfo.available(120,
          resolvedPath: r'D:\Original\one.mp3'),
    ).scan([
      _local(r'D:\Links\first.mp3'),
      _local(r'E:\Other links\second.mp3'),
    ]);
    expect(snapshot.duplicateEntries, 1);
    expect(snapshot.folders.single.path, r'D:\Links');
    expect(snapshot.folders.single.fileCount, 1);
    expect(snapshot.folders.single.bytes, 120);
  });

  test(
      'missing, denied, failed and invalid measurements keep counts but not bytes',
      () async {
    final snapshot = await _scanner(inspectFile: (path) async {
      if (path.endsWith('missing.mp3')) {
        return const LocalAudioFileInfo.missing();
      }
      if (path.endsWith('denied.mp3')) {
        return const LocalAudioFileInfo.inaccessible();
      }
      if (path.endsWith('invalid.mp3')) {
        return const LocalAudioFileInfo.available(-10);
      }
      if (path.endsWith('throw.mp3')) throw StateError('access denied');
      return const LocalAudioFileInfo.available(0);
    }).scan([
      for (final name in ['missing', 'denied', 'invalid', 'throw', 'empty'])
        _local('D:\\Music\\$name.mp3')..fileSizeBytes = 999999,
    ]);
    final folder = snapshot.folders.single;
    expect(folder.fileCount, 5);
    expect(folder.measuredFileCount, 1);
    expect(folder.missingFileCount, 1);
    expect(folder.inaccessibleFileCount, 3);
    expect(folder.bytes, 0);
    expect(snapshot.totalLocalBytes, 0);
    expect(
        folder.fileCount,
        folder.measuredFileCount +
            folder.missingFileCount +
            folder.inaccessibleFileCount);
  });

  test('remote and legacy URL entries do not create folders or perform disk IO',
      () async {
    var calls = 0;
    final snapshot = await _scanner(inspectFile: (_) async {
      calls++;
      return const LocalAudioFileInfo.available(999);
    }).scan([
      _online('one'),
      _online('one'),
      _local('online://legacy/song'),
      _local('https://example.invalid/song.mp3'),
    ]);
    expect(calls, 0);
    expect(snapshot.onlineTracks, 3);
    expect(snapshot.localFolderCount, 0);
    expect(snapshot.folders, isEmpty);
    expect(
        snapshot.folderDistribution(FolderDistributionMetric.songCount).entries,
        isEmpty);
  });

  test('quantity and space percentages use distinct local-only denominators',
      () async {
    final snapshot = await _scanner(inspectFile: (path) async {
      if (path.contains('Missing')) return const LocalAudioFileInfo.missing();
      return LocalAudioFileInfo.available(path.contains('Large') ? 300 : 50);
    }).scan([
      _local(r'D:\Small\a.mp3'),
      _local(r'D:\Small\b.mp3'),
      _local(r'D:\Large\c.mp3'),
      _local(r'D:\Missing\d.mp3'),
      _online('remote'),
    ]);
    final byCount =
        snapshot.folderDistribution(FolderDistributionMetric.songCount);
    final byBytes =
        snapshot.folderDistribution(FolderDistributionMetric.storageBytes);
    expect(byCount.total, 4);
    expect(byBytes.total, 400);
    expect(byCount.entries.first.path, r'D:\Small');
    expect(byBytes.entries.first.path, r'D:\Large');
    expect(byCount.percentageOf(byCount.entries.first), 50);
    expect(byBytes.percentageOf(byBytes.entries.first), 75);
    expect(
        byBytes.percentageOf(
            byBytes.entries.firstWhere((entry) => entry.path == r'D:\Missing')),
        0);
    expect(
        byCount.entries
            .fold<double>(0, (sum, item) => sum + byCount.percentageOf(item)),
        100);
    expect(
        byBytes.entries
            .fold<double>(0, (sum, item) => sum + byBytes.percentageOf(item)),
        100);
  });

  test('empty and zero-byte distributions have finite zero space percentages',
      () async {
    final empty = await _scanner().scan([]);
    expect(empty.localFolderCount, 0);
    expect(
        empty.folderDistribution(FolderDistributionMetric.storageBytes).total,
        0);
    final zeros = await _scanner(
            inspectFile: (_) async => const LocalAudioFileInfo.available(0))
        .scan([_local(r'D:\One\a.mp3'), _local(r'D:\Two\b.mp3')]);
    final bytes =
        zeros.folderDistribution(FolderDistributionMetric.storageBytes);
    final count = zeros.folderDistribution(FolderDistributionMetric.songCount);
    expect(bytes.entries.map(bytes.percentageOf), everyElement(0.0));
    expect(count.entries.map(count.percentageOf), everyElement(50.0));
  });

  test('top seven plus other preserves every count and byte in both metrics',
      () async {
    final snapshot = await _scanner(
      inspectFile: (path) async =>
          LocalAudioFileInfo.available(path.contains('Folder0') ? 1000 : 1),
    ).scan([
      for (var folder = 0; folder < 10; folder++)
        for (var song = 0; song <= folder; song++)
          _local('D:\\Folder$folder\\$song.mp3'),
    ]);
    expect(snapshot.localFolderCount, 10);
    for (final metric in FolderDistributionMetric.values) {
      final distribution = snapshot.folderDistribution(metric);
      expect(distribution.entries, hasLength(8));
      expect(distribution.entries.last.isOther, isTrue);
      expect(distribution.entries.last.folderCount, 3);
      expect(
          distribution.entries.fold(0, (sum, entry) => sum + entry.fileCount),
          55);
      expect(distribution.entries.fold(0, (sum, entry) => sum + entry.bytes),
          1054);
      expect(
          distribution.entries.fold<double>(
              0, (sum, entry) => sum + distribution.percentageOf(entry)),
          closeTo(100, 1e-9));
    }
    expect(
        snapshot
            .folderDistribution(FolderDistributionMetric.songCount)
            .entries
            .first
            .path,
        r'D:\Folder9');
    expect(
        snapshot
            .folderDistribution(FolderDistributionMetric.storageBytes)
            .entries
            .first
            .path,
        r'D:\Folder0');
  });

  test('tie order and aggregation are stable, immutable and validate top N',
      () async {
    final snapshot = await _scanner().scan([
      _local(r'D:\C\one.mp3'),
      _local(r'D:\A\two.mp3'),
      _local(r'D:\B\three.mp3'),
    ]);
    final distribution = snapshot
        .folderDistribution(FolderDistributionMetric.songCount, maxFolders: 1);
    expect(distribution.entries.first.path, r'D:\A');
    expect(distribution.entries.last.folderCount, 2);
    expect(distribution.entries.last.fileCount, 2);
    expect(() => snapshot.folders.clear(), throwsUnsupportedError);
    expect(() => distribution.entries.clear(), throwsUnsupportedError);
    expect(
        () => snapshot.folderDistribution(FolderDistributionMetric.songCount,
            maxFolders: 0),
        throwsRangeError);
  });

  test('a pending scan freezes the directory before metadata changes',
      () async {
    final result = Completer<LocalAudioFileInfo>();
    final audio = _local(r'D:\Before\one.mp3');
    final scan = _scanner(inspectFile: (_) => result.future).scan([audio]);
    audio.path = r'E:\After\renamed.mp3';
    result.complete(const LocalAudioFileInfo.available(3));
    expect((await scan).folders.single.path, r'D:\Before');
  });

  test(
      'large folder snapshots bound the legend and metric switching adds no IO',
      () async {
    var calls = 0;
    final snapshot = await _scanner(inspectFile: (_) async {
      calls++;
      return const LocalAudioFileInfo.available(10);
    }).scan([
      for (var index = 0; index < 2000; index++)
        _local('D:\\Folder$index\\song.mp3')
    ]);
    for (var index = 0; index < 20; index++) {
      final distribution = snapshot
          .folderDistribution(FolderDistributionMetric.values[index % 2]);
      expect(distribution.entries, hasLength(8));
      expect(distribution.entries.last.folderCount, 1993);
    }
    expect(calls, 2000);
    expect(snapshot.localTracks, 2000);
    expect(snapshot.totalLocalBytes, 20000);
  });
}
