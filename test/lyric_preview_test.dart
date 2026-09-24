import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter_test/flutter_test.dart';

Audio audio({String path = 'song.mp3', CueTrackReference? cue}) =>
    Audio('Song', 'Artist', 'Album', 0, 8, null, null, path, 0, 0, null,
        cueTrack: cue);

class MainPlayback extends TrimMainPlayback {
  @override
  Object? track = Object();
  @override
  bool playing = true;
  @override
  double position = 12;
  int resumed = 0;
  @override
  void pause() {
    playing = false;
    notifyListeners();
  }

  @override
  void resume() {
    playing = true;
    resumed++;
    notifyListeners();
  }

  void move(double value) {
    position = value;
    notifyListeners();
  }
}

class ProcessFake implements TrimPreviewProcess {
  final done = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => done.future;
  @override
  void kill() {
    killed = true;
    if (!done.isCompleted) done.complete(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('line range uses word end or next distinct LRC line without overrun',
      () {
    final lrc = Lrc.fromLrcText(
        '[00:01]one\n[00:03]two\n[00:03]translated\n[00:05]last',
        LrcSource.local)!;
    expect(lyricPreviewRange(lrc, 0, 8), (start: 1.0, end: 3.0));
    expect(lyricPreviewRange(lrc, 1, 8), (start: 3.0, end: 5.0));
    expect(lyricPreviewRange(lrc, 3, 8), (start: 5.0, end: 8.0));
    final word = Qrc([
      QrcLine(const Duration(seconds: 2), const Duration(seconds: 1), [
        QrcWord(const Duration(seconds: 2), const Duration(seconds: 2), 'word')
      ])
    ]);
    expect(lyricPreviewRange(word, 0, 8), (start: 2.0, end: 4.0));
    expect(lyricPreviewRange(word, 0, 3), (start: 2.0, end: 3.0));
  });
  test('native clock parser handles split records and ignores diagnostics', () {
    final values = <double>[];
    final parser = LyricPreviewClockParser(values.add);
    parser.add('nan M-A: nan\rInput song\n   1.');
    parser.add('25 M-A: 0.0\r   1.28 M-A: 0.0\r');
    expect(values, [1.25, 1.28]);
  });
  test(
      'preview pause keeps main paused and close restores unchanged playback once',
      () async {
    final main = MainPlayback();
    final process = ProcessFake();
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => main,
        launch: (_, start, duration, clock) async {
          expect(start, 1);
          expect(duration, 2);
          clock(1.5);
          return process;
        });
    await preview.play(1, 3);
    expect(main.playing, isFalse);
    expect(preview.position, 1.5);
    await preview.pause();
    expect(process.killed, isTrue);
    expect(main.playing, isFalse);
    await preview.close();
    expect(main.resumed, 1);
    await preview.close();
    expect(main.resumed, 1);
    preview.dispose();
  });
  test('late decoder launch is reaped before main playback resumes', () async {
    final main = MainPlayback(), process = ProcessFake();
    final pending = Completer<TrimPreviewProcess>();
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => main, launch: (_, __, ___, ____) => pending.future);
    final play = preview.play(1, 3);
    await Future<void>.delayed(Duration.zero);
    final close = preview.close();
    expect(main.resumed, 0);
    pending.complete(process);
    await play;
    await close;
    expect(process.killed, isTrue);
    expect(main.resumed, 1);
    preview.dispose();
  });
  test('user seek during preview wins and is never undone', () async {
    final main = MainPlayback(), process = ProcessFake();
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => main, launch: (_, __, ___, ____) async => process);
    await preview.play(1, 3);
    main.move(40);
    await Future<void>.delayed(Duration.zero);
    await preview.close();
    expect(process.killed, isTrue);
    expect(main.resumed, 0);
    expect(main.position, 40);
    preview.dispose();
  });
  test('rapid seeking rejects stale clock updates', () async {
    final clocks = <void Function(double)>[];
    final processes = <ProcessFake>[];
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => null,
        launch: (_, __, ___, clock) async {
          clocks.add(clock);
          final p = ProcessFake();
          processes.add(p);
          return p;
        });
    await preview.play(0, 8);
    await preview.play(3, 5);
    clocks.first(1.8);
    expect(preview.position, 3);
    clocks.last(3.7);
    expect(preview.position, 3.7);
    clocks.last(3.68);
    expect(preview.position, 3.7);
    clocks.last(double.nan);
    expect(preview.position, 3.7);
    expect(processes.first.killed, isTrue);
    await preview.close();
    preview.dispose();
  });
  test(
      'repeated successful previews settle at the exact endpoint, not last stats',
      () async {
    final processes = <ProcessFake>[];
    final clocks = <void Function(double)>[];
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => null,
        launch: (_, __, ___, clock) async {
          clocks.add(clock);
          final process = ProcessFake();
          processes.add(process);
          return process;
        });
    final positions = <double>[];
    final subscription = preview.positionStream.listen(positions.add);
    for (final lastStat in [1.38, 1.39, 1.40]) {
      await preview.play(.85, 1.418);
      clocks.last(lastStat);
      processes.last.done.complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(preview.playing, isFalse);
      expect(preview.position, 1.418);
      expect(positions.last, 1.418);
      for (final clock in clocks) {
        clock(1.37); // Even stderr delivered after exit must not rewind it.
      }
      expect(preview.position, 1.418);
    }
    await subscription.cancel();
    await preview.close();
    preview.dispose();
  });
  test('pause, failed exit and replaced process never complete the new range',
      () async {
    final processes = <ProcessFake>[];
    final clocks = <void Function(double)>[];
    final preview = LyricAudioPreview(audio(),
        mainPlayback: () => null,
        launch: (_, __, ___, clock) async {
          clocks.add(clock);
          final process = ProcessFake();
          processes.add(process);
          return process;
        });
    await preview.play(1, 3);
    clocks.last(1.5);
    await preview.pause();
    expect(preview.position, 1.5);
    await preview.play(1, 3);
    clocks.last(1.7);
    processes.last.done.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(preview.position, 1.7);
    expect(preview.error, isNotNull);
    await preview.play(1, 3);
    clocks.last(1.8);
    await preview.play(4, 6);
    expect(preview.position, 4);
    clocks[2](2.9);
    expect(preview.position, 4);
    clocks.last(4.2);
    await preview.close();
    expect(preview.position, 4.2);
    preview.dispose();
  });
  test('CUE preview maps line time to file time and back', () async {
    const cue = CueTrackReference(
        cuePath: r'J:\library\album.cue',
        sourcePath: r'J:\library\album.flac',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    final preview = LyricAudioPreview(audio(cue: cue),
        mainPlayback: () => null,
        launch: (file, start, duration, clock) async {
          expect(file, cue.sourcePath);
          expect(start, 11);
          expect(duration, 2);
          clock(11.4);
          return ProcessFake();
        });
    await preview.play(1, 3);
    expect(preview.position, closeTo(1.4, .001));
    await preview.close();
    preview.dispose();
  });
  test(
      'draft save is inert until explicit selection, even after a selected draft is edited again',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-draft-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LyricDocumentStore(storageDirectory: dir);
    final song = audio(path: '${dir.path}/song.mp3');
    final original = Lrc.fromLrcText('[00:01]Original', LrcSource.local)!;
    await store.select(song, original);
    final state = store.forAudio(song)!.toJson();
    var draftNotice = false;
    store.addListener(() => draftNotice = store.savingDraftOnly);
    final sample = lyricEditingExample(LyricEditFormat.qrc).parse();
    await store.saveDraft(song, sample, expectedRevision: 1);
    expect(draftNotice, isTrue);
    final saved = store.forAudio(song)!;
    expect(saved.effective!.toJson(), state['original']);
    expect(saved.locked, state['locked']);
    expect(saved.source?.toMap(), state['source']);
    final restart = LyricDocumentStore(storageDirectory: dir);
    await restart.load();
    expect(restart.forAudio(song)!.draft, isNotNull);
    await restart.useDraft(song, expectedRevision: 2);
    final selected = restart.forAudio(song)!;
    expect(selected.locked, isTrue);
    expect(selected.edited!.toJson(), selected.draft!.toJson());
    await restart.saveDraft(
        song, Lrc.fromLrcText('[00:02]New draft', LrcSource.local)!,
        expectedRevision: 3);
    expect(restart.forAudio(song)!.effective!.toJson(),
        selected.effective!.toJson());
    expect(restart.forAudio(song)!.draft!.toJson(),
        isNot(selected.draft!.toJson()));
  });
  test('every selectable format has a valid editable example', () {
    for (final format in LyricEditFormat.values) {
      expect(lyricEditingExample(format).parse().lines, isNotEmpty,
          reason: format.name);
    }
  });
  test(
      'native ffplay reports media clock and terminates at the requested sentence',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-native-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/silent.wav');
    final bytes = ByteData(44 + 44100 * 2 * 3);
    void ascii(int at, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(at + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    ascii(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 44100, Endian.little);
    bytes.setUint32(28, 88200, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, bytes.lengthInBytes - 44, Endian.little);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final native =
        LyricAudioPreview(audio(path: file.path), mainPlayback: () => null);
    await native.prepare();
    expect(native.duration, closeTo(3, .001));
    await native.close();
    native.dispose();
    final times = <double>[];
    final process = await launchLyricPreview(file.path, 1, 1, times.add);
    final code = await process.exitCode.timeout(const Duration(seconds: 10),
        onTimeout: () {
      process.kill();
      return -1;
    });
    expect(code, 0);
    expect(times.length, greaterThan(5));
    expect(times.first, closeTo(1, .15));
    expect(times.last, lessThanOrEqualTo(2.1));
    // Reproduce the reported sub-second sentence with the real decoder.
    final replay =
        LyricAudioPreview(audio(path: file.path), mainPlayback: () => null);
    for (var i = 0; i < 3; i++) {
      final finished = Completer<void>();
      void changed() {
        if (!replay.playing && !replay.loading && replay.position == 1.418) {
          if (!finished.isCompleted) finished.complete();
        }
      }

      replay.addListener(changed);
      await replay.play(.85, 1.418);
      await finished.future.timeout(const Duration(seconds: 10));
      replay.removeListener(changed);
      expect(replay.error, isNull);
      expect(replay.position, 1.418);
    }
    await replay.close();
    replay.dispose();
  }, skip: Platform.environment['DAN_PLAYER_FFMPEG_DIR'] == null);
}
