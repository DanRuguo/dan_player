import 'dart:async';

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Word extends SyncLyricWord {
  _Word(int start, int length, String text)
      : super(Duration(milliseconds: start), Duration(milliseconds: length),
            text);
}

class _Line extends SyncLyricLine {
  _Line(List<SyncLyricWord> words)
      : super(Duration.zero, const Duration(seconds: 3), words, 'translation');
}

class _Source extends TaskbarLyricSource {
  @override
  Future<Lyric?> lyric = Future.value(null);
  @override
  int generation = 1;
  @override
  int session = 1;
  @override
  bool hasTrack = true;
  @override
  double position = 0;
  @override
  bool playing = true;
  @override
  double playbackRate = 1;
  @override
  Object? intent;
  @override
  double duration = 10;
  void changed() => notifyListeners();
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Source source;
  late List<Map<String, Object>> writes;
  late List<Object> errors;
  late Duration elapsed;
  late TaskbarLyricAppearance appearance;
  late TaskbarLyricsPublisher publisher;

  setUp(() {
    source = _Source();
    writes = [];
    errors = [];
    elapsed = Duration.zero;
    appearance = const TaskbarLyricAppearance(
        accent: 42, fontFamily: 'fixture', fontPath: 'fixture.ttf');
  });

  void start({Future<void> Function(Map<String, Object>)? send}) {
    publisher = TaskbarLyricsPublisher(
      source: source,
      appearance: () => appearance,
      elapsed: () => elapsed,
      send: send ?? (payload) async => writes.add(payload),
      onError: (error, _) => errors.add(error),
    );
    addTearDown(() async {
      await publisher.close();
      source.dispose();
    });
  }

  test('primary newlines emoji and combining marks retain every character',
      () async {
    source.lyric = Future.value(_Lyric([
      LrcLine(Duration.zero, '  😀e\u0301\r\n第二段\n第三段┃译文', isBlank: false),
      LrcLine(const Duration(seconds: 2), 'next┃translation', isBlank: false),
    ]));
    start();
    await _flush();
    expect(writes.last['text'], '😀e\u0301 第二段 第三段');
    expect(writes.last['nextText'], 'next');
    expect(writes.last['words'], isEmpty);
    expect(writes.last['lineStartMilliseconds'], 0);
    expect(writes.last['lineEndMilliseconds'], 2000);
  });

  test('authored words retain UTF16 slots and zero duration without guesses',
      () async {
    final line = _Line([_Word(0, 0, '😀'), _Word(0, 1200, 'e\u0301你')]);
    source.lyric = Future.value(_Lyric([line]));
    start();
    await _flush();
    final words = writes.last['words'] as List<Map<String, Object>>;
    expect(words.map((word) => word['content']).join(), writes.last['text']);
    expect((words.first['content'] as String).length, 2);
    expect(words.first['lengthMilliseconds'], 0);
    expect(words.last['startMilliseconds'], 0);
    expect(writes.last['lineEndMilliseconds'], 3000);
    expect(writes.last['nextText'], '');
  });

  test('negative authored timing keeps the display offset exactly once',
      () async {
    final authored = _Lyric([
      _Line([_Word(0, 0, '😀'), _Word(500, 1200, '第二词')]),
    ]);
    final snapshot = LyricSnapshot.capture(authored);
    source.lyric = Future.value(snapshot.toLyric(offsetMs: -750));
    start();
    await _flush();
    final words = writes.last['words'] as List<Map<String, Object>>;
    expect(words.first['startMilliseconds'], -750);
    expect(words.last['startMilliseconds'], -250);
    expect(words.first['lengthMilliseconds'], 0);
    expect(words.last['lengthMilliseconds'], 1200);
    expect(writes.last['lineStartMilliseconds'], -750);
    expect(writes.last['lineEndMilliseconds'], 2250);
    expect(writes.last['text'], '😀第二词');
    expect((authored.lines.single as SyncLyricLine).words.first.start,
        Duration.zero);
  });

  test('normalization mismatch never invents timed UTF16 ranges', () async {
    source.lyric = Future.value(_Lyric([
      _Line([_Word(0, 200, ' first\nsecond ')])
    ]));
    start();
    await _flush();
    expect(writes.last['text'], 'first second');
    expect(writes.last['words'], isEmpty);
  });

  test(
      'long legal text is retained and excess word slots degrade to whole line',
      () async {
    source.lyric = Future.value(_Lyric([
      _Line([for (var index = 0; index < 6000; index++) _Word(index, 1, '字')]),
    ]));
    start();
    await _flush();
    expect((writes.last['text'] as String).length, 6000);
    expect(writes.last['words'], isEmpty);
  });

  test('LRC and plain text use real end boundary but never word timings',
      () async {
    source.lyric = Future.value(PlainLyric('one\ntwo 😀'));
    start();
    await _flush();
    expect(writes.last['text'], 'one two 😀');
    expect(writes.last['lineEndMilliseconds'], 10000);
    expect(writes.last['words'], isEmpty);
  });

  test('late previous future and same-future new generation cannot publish old',
      () async {
    final old = Completer<Lyric?>();
    final next = Completer<Lyric?>();
    source.lyric = old.future;
    start();
    await _flush();
    source.lyric = next.future;
    source.generation++;
    source.session++;
    source.changed();
    await _flush();
    old.complete(PlainLyric('old'));
    await _flush();
    expect(writes.any((write) => write['text'] == 'old'), false);
    next.complete(PlainLyric('current'));
    await _flush();
    final previousIdentity = writes.last['sourceIdentity'];
    source.generation++;
    source.changed();
    await _flush();
    expect(writes.last['text'], 'current');
    expect(writes.last['sourceIdentity'], isNot(previousIdentity));
  });

  test('same text at different line indices changes identity and next line',
      () async {
    source.lyric = Future.value(_Lyric([
      LrcLine(Duration.zero, 'chorus', isBlank: false),
      LrcLine(const Duration(seconds: 2), 'chorus', isBlank: false),
      LrcLine(const Duration(seconds: 4), 'end', isBlank: false),
    ]));
    start();
    await _flush();
    final identity = writes.last['lineIdentity'];
    source.position = 2;
    source.changed();
    await _flush();
    expect(writes.last['text'], 'chorus');
    expect(writes.last['nextText'], 'end');
    expect(writes.last['lineIdentity'], isNot(identity));
  });

  test(
      'same-session reload preserves text until explicit null or error resolves',
      () async {
    source.lyric = Future.value(PlainLyric('existing'));
    start();
    await _flush();
    writes.clear();
    source.lyric = Future.value(PlainLyric('replacement'));
    source.generation++;
    source.changed();
    await _flush();
    expect(writes.every((write) => write['text'] != ''), true);
    expect(writes.last['text'], 'replacement');
    final pending = Completer<Lyric?>();
    final identity = writes.last['sourceIdentity'];
    final lineIdentity = writes.last['lineIdentity'];
    final words = writes.last['words'];
    final count = writes.length;
    source.lyric = pending.future;
    source.generation++;
    source.changed();
    await _flush();
    expect(writes.last['text'], 'replacement');
    expect(writes.length, count);
    expect(writes.last['sourceIdentity'], identity);
    expect(writes.last['lineIdentity'], lineIdentity);
    expect(identical(writes.last['words'], words), true);
    pending.complete(null);
    await _flush();
    expect(writes.last['text'], '');
    source.lyric = Future.value(PlainLyric('restored'));
    source.generation++;
    source.changed();
    await _flush();
    final failed = Completer<Lyric?>();
    source.lyric = failed.future;
    source.generation++;
    source.changed();
    await _flush();
    expect(writes.last['text'], 'restored');
    failed.completeError(StateError('fixture'));
    await _flush();
    expect(writes.last['text'], '');
    expect(errors, isEmpty);
  });

  test('40fps position samples correct only every 400ms and reuse word maps',
      () async {
    source.lyric = Future.value(_Lyric([
      _Line([_Word(0, 3000, 'words')])
    ]));
    start();
    await _flush();
    final baseline = writes.length;
    final words = writes.last['words'];
    for (var millis = 25; millis <= 1000; millis += 25) {
      elapsed = Duration(milliseconds: millis);
      source.position = millis / 1000;
      source.changed();
      await _flush();
    }
    expect(writes.length - baseline, 2);
    expect(writes.last['positionMilliseconds'], 800);
    expect(identical(writes.last['words'], words), true);
  });

  test('same-position seek backward pause and rate reanchor immediately',
      () async {
    source.lyric = Future.value(PlainLyric('current'));
    source.position = 1;
    start();
    await _flush();
    final revision = writes.last['timelineRevision'] as int;
    source.intent =
        1; // Explicit command identity, even with unchanged position.
    source.changed();
    await _flush();
    expect(writes.last['timelineRevision'], revision + 1);
    source.position = .1;
    source.intent = 2;
    source.playing = false;
    source.changed();
    await _flush();
    expect(writes.last['playing'], false);
    expect(writes.last['positionMilliseconds'], 100);
    source.playbackRate = 1.5;
    source.changed();
    await _flush();
    expect(writes.last['playbackRate'], 1.5);
  });

  test('empty lyric does not send position corrections or fake loading status',
      () async {
    start();
    await _flush();
    final baseline = writes.length;
    for (var second = 1; second <= 5; second++) {
      source.position = second.toDouble();
      source.intent = second;
      elapsed = Duration(seconds: second);
      source.changed();
      await _flush();
    }
    expect(writes.length, baseline);
    expect(writes.last['text'], '');
    expect(writes.last['nextText'], '');
  });

  test('blocked native update coalesces latest and close follows in-flight ack',
      () async {
    final gate = Completer<void>();
    var blocked = false;
    source.lyric = Future.value(_Lyric([
      LrcLine(Duration.zero, 'a', isBlank: false),
      LrcLine(const Duration(seconds: 1), 'b', isBlank: false),
      LrcLine(const Duration(seconds: 2), 'c', isBlank: false),
    ]));
    start(send: (payload) async {
      writes.add(payload);
      if (payload['text'] == 'a' && !blocked) {
        blocked = true;
        await gate.future;
      }
    });
    await _flush();
    source.position = 1;
    source.changed();
    await _flush();
    source.position = 2;
    source.changed();
    await _flush();
    gate.complete();
    await _flush();
    expect(writes.where((write) => write['text'] == 'b'), isEmpty);
    expect(writes.last['text'], 'c');
    await publisher.close();
    expect(writes.last['enabled'], false);
    source.changed();
    await _flush();
    expect(writes.last['enabled'], false);
  });

  test('closing pending lyric never publishes its late completion', () async {
    final gate = Completer<Lyric?>();
    source.lyric = gate.future;
    start();
    await _flush();
    await publisher.close();
    final count = writes.length;
    gate.complete(PlainLyric('late'));
    await _flush();
    expect(writes.length, count);
    expect(writes.last['enabled'], false);
  });
}
