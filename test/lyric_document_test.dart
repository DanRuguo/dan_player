import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/compact_lyric_frame.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path, {CueTrackReference? cue}) => Audio('Sample',
    'Synthetic artist', 'Synthetic album', 1, 120, null, null, path, 0, 0, null,
    cueTrack: cue);

Lrc _line(String content) => Lrc.fromLrcText(
    '[offset:200]\n[00:01.00]$content\n[00:02.00]Second', LrcSource.web)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LyricDocumentStore store;
  late Audio audio;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-lyric-document-');
    await TrackIdentityRegistry.instance.initialize(directory: directory);
    audio = _audio('${directory.path}\\fixture.wav');
    store = LyricDocumentStore(
        storageDirectory: directory,
        persistIdentity: () => TrackIdentityRegistry.instance.flush());
    await store.load();
    LYRIC_SOURCES.clear();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
    LYRIC_SOURCES.clear();
  });

  test('lock captures immutable words, translations and original timestamps',
      () async {
    final raw = Qrc([
      QrcLine(
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          [
            QrcWord(const Duration(milliseconds: 1100),
                const Duration(milliseconds: 400), 'One')
          ],
          '译文'),
    ]);
    await store.setLocked(audio, true, current: raw);
    raw.lines.first.start = Duration.zero;
    (raw.lines.first as SyncLyricLine).words.first.content = 'Changed';
    final saved = store.forAudio(audio)!;
    final line = saved.render()!.lines.single as SyncLyricLine;
    expect(line.start, const Duration(seconds: 1));
    expect(line.words.single.content, 'One');
    expect(line.translation, '译文');
    expect(saved.locked, isTrue);
  });

  test(
      'format offset plus application offset applies once across reread and seeks',
      () async {
    final raw = _line('Original');
    await store.select(audio, raw);
    await store.setOffset(audio, 500);
    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    for (var count = 0; count < 3; count++) {
      final display = reopened.forAudio(audio)!.render()!;
      expect(display.lines.first.start, const Duration(milliseconds: 1300));
      final timeline = CompactLyricTimeline(display);
      expect(timeline.at(const Duration(milliseconds: 1200)).status,
          CompactLyricStatus.upcoming);
      expect(
          timeline.at(const Duration(milliseconds: 1400)).primary, 'Original');
      expect(timeline.at(Duration.zero).status, CompactLyricStatus.upcoming);
    }
    expect(raw.lines.first.start, const Duration(milliseconds: 800));
    expect(reopened.forAudio(audio)!.original!.toLyric().lines.first.start,
        const Duration(milliseconds: 800));
  });

  test(
      'word timestamps share the same media-time offset without changing spans',
      () async {
    final raw = Qrc([
      QrcLine(const Duration(seconds: 2), const Duration(seconds: 1), [
        QrcWord(const Duration(milliseconds: 2200),
            const Duration(milliseconds: 400), 'Word')
      ])
    ]);
    await store.select(audio, raw);
    await store.setOffset(audio, -500);
    final line = store.forAudio(audio)!.render()!.lines.single as SyncLyricLine;
    expect(line.start.inMilliseconds, 1500);
    expect(line.words.single.start.inMilliseconds, 1700);
    expect(line.words.single.length.inMilliseconds, 400);
  });

  test('plain text stays untimed after confirmation and offset', () async {
    await store.select(audio, PlainLyric('One\nTwo'), locked: true);
    await store.setOffset(audio, 500);
    final lyric = store.forAudio(audio)!.render();
    expect(lyric, isA<PlainLyric>());
    expect((lyric as PlainLyric).text, 'One\nTwo');
    expect(lyric.lines.single.start, Duration.zero);
  });

  test(
      'edit preserves original and explicit source switches preserve recoverable revision',
      () async {
    await store.select(audio, _line('Original'),
        source: LyricSource(LyricSourceType.netease, neteaseSongId: '100'));
    await store.edit(audio, '[00:01.00]Human revision');
    expect(store.forAudio(audio)!.locked, isTrue);
    expect(store.forAudio(audio)!.original!.toLyric().lines.first,
        isA<UnsyncLyricLine>());
    await store.select(audio, _line('Other source'),
        source: LyricSource(LyricSourceType.qq, qqSongMid: 'synthetic'));
    final revisedVersion = store.forAudio(audio)!.history.lastIndexWhere(
        (version) => version['editedText'] == '[00:01.00]Human revision');
    expect(revisedVersion, greaterThanOrEqualTo(0));
    await store.restoreVersion(audio, revisedVersion);
    expect(store.forAudio(audio)!.editedText, '[00:01.00]Human revision');
    await store.restoreOriginal(audio);
    expect(store.forAudio(audio)!.edited, isNull);
    expect(
        (store.forAudio(audio)!.render()!.lines.first as UnsyncLyricLine)
            .content,
        'Original');
  });

  test('late same-track candidate cannot replace edited or locked revision',
      () async {
    final revisionBeforeFetch = store.revisionFor(audio);
    await store.edit(audio, '[00:01.00]Confirmed');
    await expectLater(
        store.select(audio, _line('Late network'),
            expectedRevision: revisionBeforeFetch),
        throwsA(isA<StaleLyricRevision>()));
    expect(store.forAudio(audio)!.editedText, '[00:01.00]Confirmed');
  });

  test('creating a lyric from scratch does not invent an original version',
      () async {
    await store.edit(audio, '[00:01.00]Written by user');
    await store.edit(audio, '[00:01.00]Revised by user',
        original: store.forAudio(audio)!.effective!.toLyric());
    await store.setLocked(audio, true,
        current: store.forAudio(audio)!.effective!.toLyric());
    expect(store.forAudio(audio)!.original, isNull);
    expect(store.forAudio(audio)!.history.first['editedText'],
        '[00:01.00]Written by user');
  });

  test('session cancelled while saving cannot commit the fetched candidate',
      () async {
    final identity = Completer<void>();
    final pendingStore = LyricDocumentStore(
        storageDirectory: directory, persistIdentity: () => identity.future);
    addTearDown(pendingStore.dispose);
    var current = true;
    final pending = pendingStore.select(audio, _line('Late candidate'),
        stillCurrent: () => current);
    final check = expectLater(pending, throwsA(isA<StaleLyricRevision>()));
    current = false;
    identity.complete();
    await check;
    expect(pendingStore.forAudio(audio), isNull);
  });

  test('no-lyric flag survives restart and retains manual work for recovery',
      () async {
    await store.edit(audio, '[00:00.00]Keep me');
    await store.setNoLyrics(audio, true);
    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.forAudio(audio)!.render(), isNull);
    await reopened.setNoLyrics(audio, false);
    expect(reopened.forAudio(audio)!.editedText, '[00:00.00]Keep me');
  });

  test('directory reassociation keeps stable ID and revised offset', () async {
    await store.edit(audio, '[00:00.00]Portable revision');
    await store.setOffset(audio, 500);
    final oldPath = audio.path;
    final nextPath = '${directory.path}\\moved\\fixture.wav';
    TrackIdentityRegistry.instance
        .remapPaths((value) => value == oldPath ? nextPath : value);
    await TrackIdentityRegistry.instance.flush();
    await store.relocatePath(oldPath, nextPath);
    final moved = _audio(nextPath);
    expect(moved.stableTrackId, audio.stableTrackId);
    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.forAudio(moved)!.offsetMs, 500);
    expect(reopened.forAudio(moved)!.editedText, '[00:00.00]Portable revision');
    expect(reopened.forAudio(moved)!.path, nextPath);
  });

  test('a changed CUE segment cannot inherit the old segment document',
      () async {
    final cue = CueTrackReference(
        cuePath: '${directory.path}\\album.cue',
        sourcePath: '${directory.path}\\album.flac',
        number: 1,
        startFrame: 0,
        endFrame: 750);
    final first = _audio(cue.identity, cue: cue);
    await store.edit(first, '[00:01.00]Segment revision');
    final changed = CueTrackReference(
        cuePath: cue.cuePath,
        sourcePath: cue.sourcePath,
        number: 1,
        startFrame: 150,
        endFrame: 750);
    final next = _audio(changed.identity, cue: changed);
    expect(next.stableTrackId, isNot(first.stableTrackId));
    expect(store.forAudio(next), isNull);
  });

  test('failed save keeps both in-memory and durable previous revision',
      () async {
    await store.edit(audio, '[00:01.00]Safe');
    final before = store.forAudio(audio)!;
    final primary = File('${directory.path}\\lyric_documents.json');
    final original = await primary.readAsString();
    final blocker = Directory('${primary.path}.$pid.tmp');
    await blocker.create();
    await expectLater(
        store.setOffset(audio, 500), throwsA(isA<FileSystemException>()));
    expect(store.forAudio(audio), same(before));
    expect(await primary.readAsString(), original);
  });

  test('bad primary restores backup and retains failed bytes on next save',
      () async {
    await store.edit(audio, '[00:01.00]Backup');
    await store.setOffset(audio, 500);
    final primary = File('${directory.path}\\lyric_documents.json');
    await primary.writeAsString('broken primary');
    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.forAudio(audio)!.offsetMs, 0);
    await reopened.setOffset(audio, 1000);
    expect((jsonDecode(await primary.readAsString()) as Map)['version'], 1);
    final corrupt = await directory
        .list()
        .where((file) => file.path.contains('.corrupt.'))
        .toList();
    expect(corrupt, hasLength(1));
    expect(await File(corrupt.single.path).readAsString(), 'broken primary');
  });

  test(
      'damaged primary and backup refuse writes instead of clearing manual lyrics',
      () async {
    final primary = File('${directory.path}\\lyric_documents.json');
    await primary.writeAsString('broken');
    await File('${primary.path}.bak').writeAsString('also broken');
    final reopened = LyricDocumentStore(storageDirectory: directory);
    addTearDown(reopened.dispose);
    await expectLater(reopened.load(), throwsFormatException);
    await expectLater(reopened.setNoLyrics(audio, true), throwsFormatException);
    expect(await primary.readAsString(), 'broken');
  });

  test('online source restriction remains effective for saved documents',
      () async {
    final online = Audio.online(
        provider: 'qq',
        id: 'synthetic',
        title: 'Online',
        artist: 'Synthetic',
        album: 'Fixture',
        duration: 120);
    await expectLater(
        store.select(online, _line('No local mapping'),
            source: LyricSource(LyricSourceType.local)),
        throwsFormatException);
    expect(() => store.edit(online, '[00:00.00]No write'), throwsStateError);
    expect(store.forAudio(online), isNull);
  });
}
