import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Document extends Lyric {
  _Document(super.lines);
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
  double duration = 12;
  void changed() => notifyListeners();
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('natural next row and clock corrections preserve transition ownership',
      () async {
    final source = _Source()
      ..lyric = Future.value(_Document([
        LrcLine(Duration.zero, 'first', isBlank: false),
        LrcLine(const Duration(seconds: 2), 'second', isBlank: false),
        LrcLine(const Duration(seconds: 4), 'third', isBlank: false),
      ]))
      ..intent = (command: 1, source: 1, seek: 0, closed: false);
    final writes = <Map<String, Object>>[];
    var elapsed = Duration.zero;
    final publisher = TaskbarLyricsPublisher(
      source: source,
      elapsed: () => elapsed,
      appearance: () => const TaskbarLyricAppearance(
          accent: 0xff123456, fontFamily: 'fixture', fontPath: ''),
      send: (value) async => writes.add(value),
      onError: (error, trace) => fail('$error\n$trace'),
    );
    addTearDown(() async {
      await publisher.close();
      source.dispose();
    });
    await _flush();
    final initial = writes.last;
    expect(initial['text'], 'first');
    expect(initial['nextText'], 'second');

    source.position = 2;
    elapsed = const Duration(seconds: 2);
    source.changed();
    await _flush();
    final handoff = writes.last;
    expect(handoff['text'], initial['nextText']);
    expect(handoff['nextText'], 'third');
    expect(handoff['sourceIdentity'], initial['sourceIdentity']);
    expect(handoff['timelineRevision'], initial['timelineRevision']);
    expect(handoff['lineIdentity'], isNot(initial['lineIdentity']));
    expect(handoff['playing'], true);
    expect(handoff['animate'], true);

    // Corrections during the native 560 ms handoff keep the same ownership.
    source.position = 2.4;
    elapsed = const Duration(milliseconds: 2400);
    source.changed();
    await _flush();
    expect(writes.last['positionMilliseconds'], 2400);
    expect(writes.last['lineIdentity'], handoff['lineIdentity']);
    expect(writes.last['timelineRevision'], handoff['timelineRevision']);
    expect(writes.last['sourceIdentity'], handoff['sourceIdentity']);

    source.playbackRate = 1.5;
    source.changed();
    await _flush();
    expect(writes.last['playbackRate'], 1.5);
    expect(writes.last['timelineRevision'], handoff['timelineRevision']);

    source.position = 4;
    source.intent = (command: 1, source: 1, seek: 1, closed: false);
    source.changed();
    await _flush();
    expect(writes.last['text'], 'third');
    expect(writes.last['sourceIdentity'], handoff['sourceIdentity']);
    expect(writes.last['timelineRevision'],
        (handoff['timelineRevision'] as int) + 1);
  });
}
