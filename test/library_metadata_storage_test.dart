import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path, {String artist = 'Artist', String album = 'Album'}) =>
    Audio('Track $path', artist, album, 1, 120, 320, 44100, path, 1, 1, path,
        language: 'en');

LibraryStatisticsScanner _scanner(LocalAudioFileInspector inspector) =>
    LibraryStatisticsScanner(
        windowsPaths: true,
        inspectFile: inspector,
        readLyrics: (_) async => null);

Map<(String, String), (int, int)> _albums(LibraryStatisticsSnapshot snapshot) =>
    {
      for (final item in snapshot.largestAlbums)
        (item.artist, item.title): (item.files, item.bytes),
    };

Map<String, (int, int)> _artists(LibraryStatisticsSnapshot snapshot) => {
      for (final item in snapshot.largestArtists)
        item.title: (item.files, item.bytes),
    };

void main() {
  test(
      'metadata storage aggregates every verified file before selecting top six',
      () async {
    final tracks = [
      for (var i = 1; i <= 9; i++)
        _audio('C:\\music\\part-$i.flac',
            artist: 'Collected', album: 'Complete'),
      _audio(r'C:\music\large.flac', artist: 'Single', album: 'One'),
    ];
    var inspections = 0;
    final snapshot = await _scanner((path) async {
      inspections++;
      final index = tracks.indexWhere((audio) => audio.path == path);
      return LocalAudioFileInfo.available(index == 9 ? 40 : index + 1);
    }).scan(tracks);
    expect(inspections, 10);
    expect(snapshot.totalLocalBytes, 85);
    expect(snapshot.largestFiles, hasLength(6));
    expect(snapshot.largestFiles.any((item) => item.bytes == 1), isFalse);
    expect(snapshot.largestAlbums.first.title, 'Complete');
    expect(_albums(snapshot), {
      ('Collected', 'Complete'): (9, 45),
      ('Single', 'One'): (1, 40),
    });
    expect(_artists(snapshot), {'Collected': (9, 45), 'Single': (1, 40)});
  });

  test('album identity is the trimmed tuple and artist credits stay complete',
      () async {
    final tracks = [
      _audio(r'C:\music\a.flac', artist: ' A/B ', album: ' C '),
      _audio(r'C:\music\b.flac', artist: 'A/B', album: 'C'),
      _audio(r'C:\music\c.flac', artist: 'A', album: 'B/C'),
      _audio(r'C:\music\d.flac', artist: 'A / B', album: 'C'),
      _audio(r'C:\music\e.flac', artist: 'A/B', album: 'Other'),
    ];
    final snapshot =
        await _scanner((_) async => const LocalAudioFileInfo.available(10))
            .scan(tracks);
    expect(_albums(snapshot), {
      ('A/B', 'C'): (2, 20),
      ('A', 'B/C'): (1, 10),
      ('A / B', 'C'): (1, 10),
      ('A/B', 'Other'): (1, 10),
    });
    expect(
        _artists(snapshot), {'A/B': (3, 30), 'A': (1, 10), 'A / B': (1, 10)});
    expect(snapshot.largestArtists.fold(0, (sum, item) => sum + item.bytes),
        snapshot.totalLocalBytes,
        reason: 'A cooperative credit must not duplicate its physical bytes');
  });

  test('unverified and online entries contribute no metadata storage',
      () async {
    final tracks = [
      for (final name in [
        'positive',
        'zero',
        'missing',
        'denied',
        'negative',
        'throw'
      ])
        _audio('C:\\music\\$name.flac',
            artist: name == 'positive' || name == 'zero' ? 'Verified' : name),
      Audio.online(
          provider: 'qq',
          id: 'online',
          title: 'Remote',
          artist: 'Remote artist',
          album: 'Remote album',
          duration: 120),
    ];
    final inspected = <String>[];
    final snapshot = await _scanner((path) async {
      inspected.add(path);
      if (path.endsWith('positive.flac')) {
        return const LocalAudioFileInfo.available(37);
      }
      if (path.endsWith('zero.flac')) {
        return const LocalAudioFileInfo.available(0);
      }
      if (path.endsWith('missing.flac')) {
        return const LocalAudioFileInfo.missing();
      }
      if (path.endsWith('denied.flac')) {
        return const LocalAudioFileInfo.inaccessible();
      }
      if (path.endsWith('negative.flac')) {
        return const LocalAudioFileInfo.available(-1);
      }
      throw StateError('Injected inspector failure');
    }).scan(tracks);
    expect(inspected, hasLength(6));
    expect(snapshot.onlineTracks, 1);
    expect(snapshot.measuredLocalTracks, 2);
    expect(snapshot.missingLocalTracks, 1);
    expect(snapshot.inaccessibleLocalTracks, 3);
    expect(snapshot.totalLocalBytes, 37);
    expect(_albums(snapshot), {('Verified', 'Album'): (2, 37)});
    expect(_artists(snapshot), {'Verified': (2, 37)});
  });

  test('path and physical aliases keep the first descriptor credit only',
      () async {
    final tracks = [
      _audio(r'C:\music\first.flac', artist: 'First', album: 'Original'),
      _audio(r'c:\MUSIC\FIRST.flac', artist: 'Path duplicate', album: 'Wrong'),
      _audio(r'C:\alias\second.flac',
          artist: 'Physical duplicate', album: 'Wrong'),
    ];
    var inspections = 0;
    final snapshot = await _scanner((_) async {
      inspections++;
      return const LocalAudioFileInfo.available(19,
          resolvedPath: r'C:\real\song.flac');
    }).scan(tracks);
    expect(inspections, 2);
    expect(snapshot.duplicateEntries, 2);
    expect(snapshot.measuredLocalTracks, 1);
    expect(_albums(snapshot), {('First', 'Original'): (1, 19)});
    expect(_artists(snapshot), {'First': (1, 19)});
  });

  test('artist and album metadata are frozen before the first filesystem await',
      () async {
    final audio =
        _audio(r'C:\music\pending.flac', artist: 'Captured', album: 'Before');
    final info = Completer<LocalAudioFileInfo>();
    String? inspectedPath;
    final reading = _scanner((path) {
      inspectedPath = path;
      return info.future;
    }).scan([audio]);
    audio.artist = 'Edited';
    audio.album = 'After';
    audio.path = r'C:\music\edited.flac';
    info.complete(const LocalAudioFileInfo.available(27));
    final snapshot = await reading;
    expect(inspectedPath, r'C:\music\pending.flac');
    expect(_albums(snapshot), {('Captured', 'Before'): (1, 27)});
    expect(_artists(snapshot), {'Captured': (1, 27)});
  });

  test('metadata top six are ordered immutable detached snapshots', () async {
    final tracks = [
      for (var i = 1; i <= 9; i++)
        _audio('C:\\music\\$i.flac', artist: 'Artist $i', album: 'Album $i'),
    ];
    final snapshot = await _scanner((path) async =>
        LocalAudioFileInfo.available(
            tracks.indexWhere((audio) => audio.path == path) + 1)).scan(tracks);
    expect(snapshot.totalLocalBytes, 45);
    expect(
        snapshot.largestAlbums.map((item) => item.bytes), [9, 8, 7, 6, 5, 4]);
    expect(
        snapshot.largestArtists.map((item) => item.bytes), [9, 8, 7, 6, 5, 4]);
    expect(() => snapshot.largestAlbums.clear(), throwsUnsupportedError);
    expect(() => snapshot.largestArtists.add(snapshot.largestArtists.first),
        throwsUnsupportedError);
    tracks.last.artist = 'Changed';
    tracks.last.album = 'Changed';
    expect(snapshot.largestAlbums.first.artist, 'Artist 9');
    expect(snapshot.largestAlbums.first.title, 'Album 9');
    expect(snapshot.largestArtists.first.title, 'Artist 9');
  });

  test('empty and case insensitive UNKNOWN metadata preserve unassigned bytes',
      () async {
    final tracks = [
      for (final (i, value)
          in ['', '  ', 'UNKNOWN', ' unknown ', 'UnKnOwN'].indexed)
        _audio('C:\\music\\unknown-$i.flac', artist: value, album: value),
      _audio(r'C:\music\known.flac',
          artist: 'Unknown Artist', album: 'Unknown Album'),
    ];
    final snapshot =
        await _scanner((_) async => const LocalAudioFileInfo.available(11))
            .scan(tracks);
    expect(_albums(snapshot),
        {('', ''): (5, 55), ('Unknown Artist', 'Unknown Album'): (1, 11)});
    expect(_artists(snapshot), {'': (5, 55), 'Unknown Artist': (1, 11)});
    expect(snapshot.totalLocalBytes, 66);
  });

  test('older snapshot constructors keep empty immutable metadata rankings',
      () {
    final snapshot = LibraryStatisticsSnapshot(
        localTracks: 0,
        onlineTracks: 0,
        measuredLocalTracks: 0,
        missingLocalTracks: 0,
        inaccessibleLocalTracks: 0,
        totalLocalBytes: 0,
        duplicateEntries: 0,
        languageCounts: const {},
        taggedLanguageCounts: const {},
        inferredLanguageCounts: const {},
        formats: const [],
        largestFiles: const [],
        scannedAt: DateTime(2026, 10, 8));
    expect(snapshot.largestAlbums, isEmpty);
    expect(snapshot.largestArtists, isEmpty);
    expect(() => snapshot.largestAlbums.clear(), throwsUnsupportedError);
    expect(() => snapshot.largestArtists.clear(), throwsUnsupportedError);
  });
}
