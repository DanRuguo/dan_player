import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/search/lyric_search_index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LyricDocumentStore store;
  late LyricSearchIndex index;
  late List<Audio> audios;
  late ValueNotifier<int> library;
  Audio audio(String name, {CueTrackReference? cue}) => Audio(
      name,
      'QA artist',
      'QA album',
      1,
      120,
      null,
      null,
      cue?.identity ?? '${directory.path}/$name.wav',
      0,
      0,
      null,
      cueTrack: cue);
  Lrc lrc(String text) => Lrc.fromLrcText(text, LrcSource.local)!;
  setUp(() async {
    final base = await Directory(
            '${Platform.environment['DAN_PLAYER_DATA_DIR'] ?? '${Directory.current.path}/build/test-data'}/lyric-search')
        .create(recursive: true);
    directory = await base.createTemp('isolated-');
    store = LyricDocumentStore(storageDirectory: directory);
    await store.load();
    audios = [audio('Synthetic track'), audio('Second synthetic track')];
    library = ValueNotifier(0);
    index = LyricSearchIndex(
        documents: store,
        audios: () => audios,
        libraryRevision: () => library.value,
        libraryChanges: library);
  });
  tearDown(() async {
    index.dispose();
    store.dispose();
    library.dispose();
    await directory.delete(recursive: true);
  });

  test('lyrics-only match joins timed words and searches translations',
      () async {
    await store.select(
        audios.first,
        Qrc([
          QrcLine(
              const Duration(seconds: 2),
              const Duration(seconds: 3),
              [
                QrcWord(const Duration(seconds: 2), const Duration(seconds: 1),
                    'Star'),
                QrcWord(const Duration(seconds: 3), const Duration(seconds: 1),
                    ' light'),
              ],
              '星光落下'),
        ]));
    final joined = await index.search('star LIGHT');
    expect(joined.indexedSongs, 1);
    expect(joined.hits.single.lines.single.text, 'Star light');
    expect((await index.search('星光')).hits.single.song.audio, audios.first);
    expect((await index.search('Synthetic')).hits, isEmpty);
  });

  test('effective revisions, source restores and no-lyrics invalidate one song',
      () async {
    await store.select(audios.first, lrc('[00:01]Original moon'));
    await store.select(audios.last, lrc('[00:01]Unchanged moon'));
    final before = await index.search('moon');
    final untouched = before.hits.last.song;
    await store.edit(audios.first, '[00:01]Manual sun');
    expect(index.isCurrent(before.hits.first.song), isFalse);
    expect(index.isCurrent(untouched), isTrue);
    expect((await index.search('Original')).hits, isEmpty);
    expect((await index.search('sun')).hits.single.song.source, '人工修订');
    await store.restoreOriginal(audios.first);
    expect((await index.search('Original')).hits, hasLength(1));
    await store.setNoLyrics(audios.first, true);
    expect((await index.search('Original')).hits, isEmpty);
    expect(index.indexedSongs, 1);
  });

  test(
      'loaded local lyrics remain readable offline and reload is not a revision',
      () async {
    index.rememberLoadedLocal(audios.first, lrc('[00:12]Offline local line'));
    final hit = (await index.search('offline')).hits.single;
    expect(await File(audios.first.path).exists(), isFalse);
    index.rememberLoadedLocal(audios.first, lrc('[00:12]Offline local line'));
    expect(index.isCurrent(hit.song), isTrue);
    await store.setOffset(audios.first, 500);
    final shifted = (await index.search('offline')).hits.single;
    expect(shifted.song.positionFor(shifted.lines.single),
        const Duration(milliseconds: 12500));
    index.rememberLoadedLocal(audios.first, lrc('[00:12]Changed local line'));
    expect(index.isCurrent(hit.song), isFalse);
    expect((await index.search('offline')).hits, isEmpty);
  });

  test(
      'CUE timestamps apply song offset once and changed bounds have new identity',
      () async {
    final cue = CueTrackReference(
        cuePath: '${directory.path}\\disc.cue',
        sourcePath: '${directory.path}\\disc.wav',
        number: 2,
        startFrame: 15000,
        endFrame: 24000);
    audios = [audio('CUE segment', cue: cue)];
    library.value++;
    await store.select(audios.first, lrc('[00:01]Segment line'));
    await store.setOffset(audios.first, 500);
    for (var i = 0; i < 3; i++) {
      final hit = (await index.search('segment')).hits.single;
      expect(hit.song.positionFor(hit.lines.single),
          const Duration(milliseconds: 1500));
      expect(hit.lines.single.start, const Duration(seconds: 1));
    }
    audios = [
      audio('CUE segment',
          cue: CueTrackReference(
              cuePath: cue.cuePath,
              sourcePath: cue.sourcePath,
              number: 2,
              startFrame: 15500,
              endFrame: 24000))
    ];
    library.value++;
    expect((await index.search('segment')).hits, isEmpty);
  });

  test('plain lyrics never acquire fake seek timestamps', () async {
    await store.select(audios.first, PlainLyric('Plain moon\nAnother moon'));
    await store.setOffset(audios.first, 500);
    final hit = (await index.search('moon')).hits.single;
    expect(hit.lines, hasLength(2));
    expect(
        hit.lines.every((line) => hit.song.positionFor(line) == null), isTrue);
  });

  test('query is bounded and cancelled when a document changes during a yield',
      () async {
    await store.select(
        audios.first, PlainLyric(List.filled(10000, 'Long verse').join('\n')));
    var checked = 0;
    final stale = index.search('absent', checkCancelled: () {
      if (++checked == 2) throw const LyricSearchSuperseded();
    });
    await expectLater(stale, throwsA(isA<LyricSearchSuperseded>()));
    final hits = await index.search('verse', maxLines: 2);
    expect(hits.hits.single.lines, hasLength(2));
    expect(hits.hits.single.moreMatches, isTrue);
    await store.select(audios.last, PlainLyric('Long verse'));
    expect((await index.search('verse', maxSongs: 1)).limited, isTrue);
  });

  test(
      'removal discards derived loaded lyrics without deleting authoritative originals',
      () async {
    await store.select(audios.first, PlainLyric('Saved original'));
    final hit = (await index.search('original')).hits.single;
    final removed = audios.removeAt(0);
    library.value++;
    expect(index.isCurrent(hit.song), isFalse);
    expect((await index.search('original')).hits, isEmpty);
    expect(store.forAudio(removed)!.effective, isNotNull);
  });
}
