import 'dart:convert';
import 'dart:io';

import 'package:dan_player/lyric/lyric_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory storage;

  setUp(() async {
    LYRIC_SOURCES.clear();
    storage = await Directory.systemTemp.createTemp('dan-player-lyric-source-');
  });

  tearDown(() async {
    LYRIC_SOURCES.clear();
    if (await storage.exists()) await storage.delete(recursive: true);
  });

  test('online audio rejects a persisted local lyric source', () {
    expect(
      isLyricSourceCompatible(
        isOnline: true,
        source: LyricSourceType.local,
      ),
      isFalse,
    );
    expect(
      isLyricSourceCompatible(
        isOnline: true,
        source: LyricSourceType.netease,
      ),
      isTrue,
    );
  });

  test('local audio still accepts local and online lyric sources', () {
    for (final source in LyricSourceType.values) {
      expect(
        isLyricSourceCompatible(isOnline: false, source: source),
        isTrue,
      );
    }
  });

  test('QQ source keeps numeric ID and MID while reading legacy records', () {
    final current = LyricSource(
      LyricSourceType.qq,
      qqSongId: 42,
      qqSongMid: 'MID42',
    );
    final restored = LyricSource.fromMap(current.toMap());
    expect(restored.qqSongId, 42);
    expect(restored.qqSongMid, 'MID42');

    final legacyNumeric = LyricSource.fromMap({'source': 'qq', 'id': '43'});
    expect(legacyNumeric.qqSongId, 43);
    expect(legacyNumeric.qqSongMid, isNull);

    final legacyMid = LyricSource.fromMap({'source': 'qq', 'id': 'OLD_MID'});
    expect(legacyMid.qqSongId, isNull);
    expect(legacyMid.qqSongMid, 'OLD_MID');
  });

  test('LRCLIB source persists its stable numeric record ID', () {
    final current = LyricSource(LyricSourceType.lrclib, lrclibId: 38005804);
    final restored = LyricSource.fromMap(current.toMap());

    expect(restored.source, LyricSourceType.lrclib);
    expect(restored.lrclibId, 38005804);
    expect(
      restored.matches(
        candidateSource: LyricSourceType.lrclib,
        candidateLrclibId: 38005804,
      ),
      isTrue,
    );
  });

  test('one corrupt record does not discard valid or temporarily missing paths',
      () async {
    final primary = File('${storage.path}\\lyric_source.json');
    await primary.writeAsString(jsonEncode({
      r'Z:\offline-drive\song.mp3': {
        'source': 'netease',
        'id': '123',
      },
      r'C:\Music\broken.mp3': {
        'source': 'qq',
        'id': null,
      },
      'online://qq/MID': {
        'source': 'local',
        'id': null,
      },
    }));

    await readLyricSources(storageDirectory: storage);

    expect(LYRIC_SOURCES.keys, [r'Z:\offline-drive\song.mp3']);
    expect(
      LYRIC_SOURCES[r'Z:\offline-drive\song.mp3']!.neteaseSongId,
      '123',
    );
  });

  test('a corrupt primary index falls back to the last good backup', () async {
    final primary = File('${storage.path}\\lyric_source.json');
    final backup = File('${primary.path}.bak');
    await primary.writeAsString('{not json');
    await backup.writeAsString(jsonEncode({
      r'C:\Music\song.mp3': {
        'source': 'qq',
        'id': 77,
        'mid': 'MID77',
      },
    }));

    await readLyricSources(storageDirectory: storage);

    expect(LYRIC_SOURCES, hasLength(1));
    expect(LYRIC_SOURCES.values.single.qqSongId, 77);
    expect(LYRIC_SOURCES.values.single.qqSongMid, 'MID77');
  });

  test('successful replacement retains the previous file as a backup',
      () async {
    const path = r'C:\Music\song.mp3';
    LYRIC_SOURCES[path] = LyricSource(
      LyricSourceType.netease,
      neteaseSongId: 'old',
    );
    await saveLyricSources(storageDirectory: storage);

    LYRIC_SOURCES[path] = LyricSource(
      LyricSourceType.netease,
      neteaseSongId: 'new',
    );
    await saveLyricSources(storageDirectory: storage);

    final primary = File('${storage.path}\\lyric_source.json');
    final backup = File('${primary.path}.bak');
    final currentJson = jsonDecode(await primary.readAsString()) as Map;
    final backupJson = jsonDecode(await backup.readAsString()) as Map;
    expect((currentJson[path] as Map)['id'], 'new');
    expect((backupJson[path] as Map)['id'], 'old');
  });

  test('failed atomic save restores the previous in-memory association',
      () async {
    const path = r'C:\Music\song.mp3';
    final previous = LyricSource(
      LyricSourceType.netease,
      neteaseSongId: 'old',
    );
    LYRIC_SOURCES[path] = previous;

    // A directory at the destination makes the final same-directory rename
    // fail without touching any real user data.
    await Directory('${storage.path}\\lyric_source.json').create();
    await expectLater(
      persistLyricSource(
        path,
        LyricSource(LyricSourceType.netease, neteaseSongId: 'new'),
        storageDirectory: storage,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(identical(LYRIC_SOURCES[path], previous), isTrue);
  });
}
