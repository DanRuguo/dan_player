import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/audio_trim_lyric_document.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) =>
    Audio('Sample', 'Artist', 'Album', 1, 120, null, null, path, 0, 0, null);
Duration _ms(int value) => Duration(milliseconds: value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LyricDocumentStore store;
  late Audio source;
  late Audio saved;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-trim-lyric-doc-');
    await TrackIdentityRegistry.instance.initialize(directory: directory);
    source = _audio('${directory.path}/source.mp3');
    saved = _audio('${directory.path}/saved.mp3');
    store = LyricDocumentStore(storageDirectory: directory);
    await store.load();
    LYRIC_SOURCES.clear();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
    LYRIC_SOURCES.clear();
  });

  Future<void> trim(double start, double end,
          {bool preserve = true, bool overwrite = false}) =>
      synchronizeTrimmedLyricDocument(
          source, overwrite ? source : saved, start, end,
          preserve: preserve, documents: store);

  for (final krc in [false, true]) {
    test(
        '${krc ? 'KRC' : 'QRC'} words and translations intersect both bounds '
        'and absorb offset once without changing the source', () async {
      final words = [
        QrcWord(_ms(800), _ms(300), 'before'),
        QrcWord(_ms(1200), _ms(700), 'left'),
        QrcWord(_ms(1900), _ms(400), 'middle'),
        QrcWord(_ms(2300), _ms(900), 'right'),
        QrcWord(_ms(3300), _ms(500), 'after')
      ];
      final Lyric lyric = krc
          ? Krc([KrcLine(_ms(800), _ms(3000), words, '整句译文')])
          : Qrc([QrcLine(_ms(800), _ms(3000), words, '整句译文')]);
      await store.select(source, lyric,
          source: LyricSource(LyricSourceType.kugou, kugouSongHash: 'fixture'),
          locked: true);
      await store.setOffset(source, 500);
      final unchanged = jsonEncode(store.forAudio(source)!.toJson());
      await trim(2, 3);
      final document = store.forAudio(saved)!;
      final line = document.render()!.lines.single as SyncLyricLine;
      expect(line.start, Duration.zero);
      expect(line.length, const Duration(seconds: 1));
      expect(line.translation, '整句译文');
      expect(
          line.words.map((word) => word.content), ['left', 'middle', 'right']);
      expect(
          line.words.map((word) => word.start), [_ms(0), _ms(400), _ms(800)]);
      expect(line.words.map((word) => word.length),
          [_ms(400), _ms(400), _ms(200)]);
      expect(document.offsetMs, 0);
      expect(document.locked, isTrue);
      expect(document.source!.source, LyricSourceType.local);
      expect(document.original!.toJson()['format'], krc ? 'krc' : 'qrc');
      expect(jsonEncode(store.forAudio(source)!.toJson()), unchanged);
      final reopened = LyricDocumentStore(storageDirectory: directory);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.forAudio(saved)!.render()!.lines.single.start,
          Duration.zero);
    });
  }

  test(
      'edited LRC, headers, original, offsets and undo versions all follow '
      'the shortened timeline', () async {
    final original =
        Lrc.fromLrcText('[00:01.00]Old\n[00:03.00]Later', LrcSource.local)!;
    await store.select(source, original);
    await store.edit(
        source,
        '[ti:Title]\n[ar:Artist]\n[offset:200]\n[length:02:00]\n'
        '[00:01.00]Early\n[00:02.00]Edited┃翻译\n[00:04.00]End',
        originalText: '[ti:Title]\n[00:01.00]Old\n[00:03.00]Later');
    await store.setOffset(source, 200);
    await trim(1.5, 3.5);
    final document = store.forAudio(saved)!;
    expect(document.edited, isNotNull);
    expect(document.locked, isTrue);
    expect(document.offsetMs, 0);
    expect(document.editedText, contains('[ti:Title]'));
    expect(document.editedText, contains('[ar:Artist]'));
    expect(document.editedText, isNot(contains('[offset:')));
    expect(document.editedText, isNot(contains('[length:')));
    expect(document.editedText, isNot(contains('End')));
    final editable = Lrc.fromLrcText(document.editedText!, LrcSource.local)!;
    expect(editable.lines.map((line) => line.start), [_ms(0), _ms(500)]);
    expect((editable.lines.last as UnsyncLyricLine).content, 'Edited┃翻译');
    expect(document.originalText, contains('[00:01.700000]Later'));
    expect(document.history, isNotEmpty);
    for (final version in document.history) {
      expect(version['trackId'], saved.stableTrackId);
      expect(version['path'], saved.path);
      expect(version['offsetMs'], 0);
    }
    await store.restoreVersion(saved, document.history.length - 1);
    expect(store.forAudio(saved)!.render()!.lines.last.start, _ms(1500));
    expect(store.forAudio(source)!.offsetMs, 200);
    expect(store.forAudio(source)!.editedText, contains('[offset:200]'));
  });

  test(
      'overwrite replaces same identity and notifies only the committed '
      'destination revision', () async {
    await store.select(source,
        Lrc.fromLrcText('[00:01.00]First\n[00:03.00]Second', LrcSource.local)!);
    final previous = store.forAudio(source)!.revision;
    var notifications = 0;
    store.addListener(() => notifications++);
    await trim(2, 4, overwrite: true);
    expect(store.documents, hasLength(1));
    expect(store.forAudio(source)!.revision, previous + 1);
    expect(store.forAudio(source)!.render()!.lines.first.start, Duration.zero);
    expect(store.forAudio(source)!.render()!.lines.last.start, _ms(1000));
    expect(store.changes.value, {source.stableTrackId});
    expect(notifications, 1);
  });

  test(
      'repeated chorus with parser and application offsets survives snapshot '
      'and trims the second occurrence', () async {
    const text = '[ti:Repeated chorus]\n[offset:250]\n'
        '[00:01.001][00:10.001]Chorus\n'
        '[00:01.001][00:10.001]副歌译文\n'
        '[00:03.001]Verse\n[00:12.001]After';
    final parsed = Lrc.fromLrcText(text, LrcSource.local, separator: '┃')!;
    final restored = LyricSnapshot.fromJson(
            jsonDecode(jsonEncode(LyricSnapshot.capture(parsed).toJson())))!
        .toLyric();
    expect(restored.lines.map((line) => line.start.inMilliseconds),
        [751, 2751, 9751, 11751]);
    await store.select(source, restored);
    await store.edit(source, text, originalText: text);
    await store.setOffset(source, 125);
    final unchanged = jsonEncode(store.forAudio(source)!.toJson());

    // The selected interval contains the end of the verse and the second
    // chorus. The first occurrence must not be shifted into the clip.
    await trim(9.5, 11.5);
    final document = store.forAudio(saved)!;
    final lines = document.render()!.lines.cast<LrcLine>().toList();
    expect(lines.map((line) => line.content), ['Verse', 'Chorus┃副歌译文']);
    expect(lines.map((line) => line.start.inMilliseconds), [0, 376]);
    expect(lines.map((line) => line.length.inMilliseconds), [376, 1624]);
    expect(document.offsetMs, 0);
    expect(document.editedText, contains('[00:00.376000]Chorus┃副歌译文'));
    final editable = Lrc.fromLrcText(document.editedText!, LrcSource.local)!;
    expect(editable.lines.last.start.inMilliseconds, 376);
    expect(jsonEncode(store.forAudio(source)!.toJson()), unchanged);

    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    final savedLine = reopened.forAudio(saved)!.render()!.lines.last as LrcLine;
    expect(savedLine.start.inMilliseconds, 376);
    expect(savedLine.content, 'Chorus┃副歌译文');
  });

  test(
      'turning off preservation removes the destination override including '
      'offset, manual lock and history but leaves the source copy untouched',
      () async {
    await store.edit(source, '[00:01.00]Source');
    await store.edit(saved, '[00:02.00]Destination');
    await store.setOffset(saved, 1000);
    await trim(1, 2, preserve: false);
    expect(store.forAudio(saved), isNull);
    expect(store.forAudio(source)!.editedText, '[00:01.00]Source');
    expect(store.changes.value, {saved.stableTrackId});
    await trim(1, 2, preserve: false, overwrite: true);
    expect(store.documents, isEmpty);
  });

  test('source without a cached document clears stale destination data',
      () async {
    await store.edit(saved, '[00:01.00]Stale');
    await trim(1, 2);
    expect(store.forAudio(saved), isNull);
    expect(store.documents, isEmpty);
  });

  test(
      'offset-only records use trimmed local lyrics and retain unapplied '
      'calibration instead of fetching the full remote song', () async {
    LYRIC_SOURCES[source.path] =
        LyricSource(LyricSourceType.qq, qqSongMid: 'whole-song');
    await store.setOffset(source, 350);
    await trim(10, 20);
    final document = store.forAudio(saved)!;
    expect(document.effective, isNull);
    expect(document.source!.source, LyricSourceType.local);
    expect(document.offsetMs, 350);
    expect(store.forAudio(source)!.source!.source, LyricSourceType.qq);
  });

  test(
      'untimed text stays untimed, and the explicit no-lyrics preference stays',
      () async {
    await store.select(source, PlainLyric('One\nTwo'), locked: true);
    await store.setOffset(source, 2000);
    await trim(60, 70);
    final document = store.forAudio(saved)!;
    expect(document.render(), isA<PlainLyric>());
    expect((document.render() as PlainLyric).text, 'One\nTwo');
    expect(document.offsetMs, 0);
    await store.setNoLyrics(source, true);
    await trim(60, 70);
    expect(store.forAudio(saved)!.noLyrics, isTrue);
    expect(store.forAudio(saved)!.render(), isNull);
  });

  test(
      'negative calibration, duplicate translations and open-ended last '
      'lines retain only the active interval', () async {
    await store.select(
        source,
        Lrc([
          LrcLine(_ms(1000), 'One', isBlank: false),
          LrcLine(_ms(1000), 'Translation', isBlank: false),
          LrcLine(_ms(4000), 'Two', isBlank: false),
        ], LrcSource.local));
    await store.setOffset(source, -500);
    await trim(1, 4);
    final lines = store.forAudio(saved)!.render()!.lines.cast<LrcLine>();
    expect(lines.map((line) => line.content), ['One', 'Translation', 'Two']);
    expect(lines.map((line) => line.start), [_ms(0), _ms(0), _ms(2500)]);
    expect(lines.map((line) => line.length), [_ms(2500), _ms(2500), _ms(500)]);
  });

  test(
      'no intersecting lines stays an authoritative empty snapshot, and '
      'end-boundary words are excluded', () async {
    await store.select(
        source,
        Qrc([
          QrcLine(
              _ms(4000), _ms(1000), [QrcWord(_ms(4000), _ms(1000), 'After')])
        ]),
        locked: true);
    await trim(2, 4);
    expect(store.forAudio(saved)!.effective, isNotNull);
    expect(store.forAudio(saved)!.render()!.lines, isEmpty);
    expect(store.forAudio(saved)!.locked, isTrue);
  });

  test('invalid intervals never mutate or publish the cached document',
      () async {
    await store.edit(source, '[00:01.00]Unchanged');
    final original = jsonEncode(store.forAudio(source)!.toJson());
    for (final interval in [
      (-1.0, 2.0),
      (2.0, 2.0),
      (3.0, 2.0),
      (double.nan, 2.0),
      (1.0, double.infinity),
      (0.0, .0000001)
    ]) {
      await expectLater(
          trim(interval.$1, interval.$2, overwrite: true), throwsArgumentError);
      expect(jsonEncode(store.forAudio(source)!.toJson()), original);
    }
  });

  test(
      'queued edits are observed and an identity persistence failure does '
      'not replace an existing destination', () async {
    final edit = store.edit(source, '[00:01.00]Newest');
    final clipped = trim(1, 2);
    await Future.wait([edit, clipped]);
    expect(
        (store.forAudio(saved)!.render()!.lines.single as UnsyncLyricLine)
            .content,
        'Newest');
    final before =
        await File('${directory.path}/lyric_documents.json').readAsString();
    final failing = LyricDocumentStore(
        storageDirectory: directory,
        persistIdentity: () async =>
            throw const FileSystemException('test failure'));
    addTearDown(failing.dispose);
    await failing.load();
    await expectLater(
        synchronizeTrimmedLyricDocument(source, saved, 1, 2,
            preserve: false, documents: failing),
        throwsA(isA<FileSystemException>()));
    expect(failing.forAudio(saved), isNotNull);
    expect(await File('${directory.path}/lyric_documents.json').readAsString(),
        before);
  });
  test(
      'trimming a draft-only document never activates it or doubles its offset',
      () async {
    await store.saveDraft(
        source, Lrc.fromLrcText('[00:02]Draft\n[00:04]Next', LrcSource.local)!);
    await store.setOffset(source, 500);
    await trim(1, 5);
    final doc = store.forAudio(saved)!;
    expect(doc.effective, isNull);
    expect(doc.draft, isNotNull);
    expect(doc.offsetMs, 500);
    await store.useDraft(saved);
    expect(store.forAudio(saved)!.render()!.lines.first.start,
        const Duration(milliseconds: 1500));
  });
}
