import 'dart:async';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_presentation_timeline.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(int start, int duration, String text)
      : super(Duration(milliseconds: start), Duration(milliseconds: duration),
            text);
}

class _Line extends SyncLyricLine {
  _Line(int start, int duration, List<SyncLyricWord> words)
      : super(Duration(milliseconds: start), Duration(milliseconds: duration),
            words);
}

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

class _Fixture {
  _Fixture(this.lyric, this.position) {
    addTearDown(() async {
      await positions.close();
      settings.dispose();
    });
  }
  final Lyric lyric;
  double position;
  int reads = 0;
  bool playing = true;
  final positions = StreamController<double>.broadcast(sync: true);
  final settings = LyricViewController();
  Widget app() => MaterialApp(
          home: Scaffold(
              body: SizedBox(
        width: 420,
        height: 480,
        child: ChangeNotifierProvider.value(
          value: settings,
          child: VerticalLyricScrollView(
            lyric: lyric,
            positionStream: positions.stream,
            readPosition: () {
              reads++;
              return position;
            },
            onSeek: (_) {},
            playing: playing,
          ),
        ),
      )));
  Future<void> emit(WidgetTester tester, double value) async {
    position = value;
    positions.add(value);
    await tester.pump();
  }
}

_Lyrics _gapped() => _Lyrics([
      _Line(0, 10000, [
        _Word(0, 300, 'short'),
        _Word(2000, 500, 'short'),
        _Word(8000, 1000, 'held')
      ]),
      _Line(10000, 10000, [_Word(10000, 1000, 'next')]),
    ]);

void main() {
  for (final parts in [
    ['e', '\u0301'],
    ['👩‍', '👩‍👧‍👦'],
  ]) {
    test('split grapheme ${parts.join()} keeps its combined held-note interval',
        () {
      final timeline = LyricPresentationTimeline([
        _Line(
            0, 4000, [_Word(1000, 400, parts[0]), _Word(1400, 400, parts[1])]),
      ]);
      // The painter shapes one 800 ms final group, despite each provider item
      // being shorter than the 650 ms held-note threshold.
      expect(timeline.endFor(0), const Duration(milliseconds: 1960));
      expect(
          timeline.needsFrames(0, const Duration(milliseconds: 821)), isFalse);
      expect(
          timeline.needsFrames(0, const Duration(milliseconds: 822)), isTrue);
      expect(
          timeline.needsFrames(0, const Duration(milliseconds: 1959)), isTrue);
      expect(
          timeline.needsFrames(0, const Duration(milliseconds: 1960)), isFalse);
    });
  }

  test(
      'split final grapheme ignores trailing whitespace and empty timing items',
      () {
    final timeline = LyricPresentationTimeline([
      _Line(0, 10000, [
        _Word(1000, 400, 'e'),
        _Word(1400, 400, '\u0301'),
        _Word(9000, 1000, ' '),
        _Word(10000, 1000, '')
      ]),
    ]);
    expect(timeline.endFor(0), const Duration(milliseconds: 1960));
    expect(timeline.needsFrames(0, const Duration(milliseconds: 1900)), isTrue);
    expect(
        timeline.needsFrames(0, const Duration(milliseconds: 9000)), isFalse);
  });

  test('a merged grapheme below the held-note threshold has no synthetic tail',
      () {
    final timeline = LyricPresentationTimeline([
      _Line(0, 4000, [_Word(1000, 300, 'e'), _Word(1300, 300, '\u0301')]),
    ]);
    expect(timeline.endFor(0), const Duration(milliseconds: 1600));
    expect(
        timeline.needsFrames(0, const Duration(milliseconds: 1600)), isFalse);
  });

  test(
      'presentation intervals cover real words and only the final held-note margins',
      () {
    final timeline = LyricPresentationTimeline(_gapped().lines);
    bool needs(int ms) => timeline.needsFrames(0, Duration(milliseconds: ms));
    expect(needs(0), isTrue);
    expect(needs(300), isFalse);
    expect(needs(1965), isFalse);
    expect(needs(1966), isTrue);
    expect(needs(2000), isTrue);
    expect(needs(2500), isFalse);
    expect(needs(7785), isFalse);
    expect(needs(7786), isTrue);
    expect(needs(9199), isTrue);
    expect(needs(9200), isFalse);
    expect(timeline.endFor(0), const Duration(milliseconds: 9200));
  });

  test('merged overlap intervals and authored long interludes remain animated',
      () {
    final timeline = LyricPresentationTimeline([
      _Line(0, 4000, [
        _Word(200, 1000, 'first'),
        _Word(100, 400, 'second'),
        _Word(500, 400, 'last')
      ]),
      LrcLine(Duration.zero, '',
          isBlank: true, length: const Duration(seconds: 8)),
      _Line(0, 8000, []),
      LrcLine(Duration.zero, 'plain',
          isBlank: false, length: const Duration(seconds: 8)),
    ]);
    expect(timeline.needsFrames(0, const Duration(milliseconds: 1100)), isTrue);
    expect(
        timeline.needsFrames(0, const Duration(milliseconds: 1200)), isFalse);
    for (final index in [1, 2]) {
      expect(timeline.needsFrames(index, const Duration(seconds: 7)), isTrue);
      expect(timeline.needsFrames(index, const Duration(seconds: 8)), isFalse);
    }
    expect(timeline.needsFrames(3, const Duration(seconds: 3)), isFalse);
  });

  testWidgets(
      'word gaps and completed tails stop the display ticker until the next lead',
      (tester) async {
    final fixture = _Fixture(_gapped(), .9);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final reads = fixture.reads;
    await tester.pump(const Duration(milliseconds: 80));
    expect(fixture.reads, reads,
        reason: 'No word or interlude changes in this gap');
    expect(tester.binding.transientCallbackCount, 0);
    await fixture.emit(tester, 7.79);
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'Wake just before the held-note lead');
    await fixture.emit(tester, 9.05);
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'The release extends beyond the real word end');
    fixture.position = 9.21;
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.binding.transientCallbackCount, 0,
        reason:
            'A display sample can stop the ticker without rebuilding the line');
    await fixture.emit(tester, .1);
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'Reverse seeks into a word restart presentation');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a releasing overlap retains its tail while the anchor waits for its words',
      (tester) async {
    final fixture = _Fixture(
        _Lyrics([
          _Line(0, 5600, [_Word(0, 5600, 'held')]),
          _Line(5000, 5000, [_Word(7000, 1000, 'later')]),
        ]),
        5.5);
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    await fixture.emit(tester, 5.7);
    final before = fixture.reads;
    await tester.pump(const Duration(milliseconds: 20));
    expect(fixture.reads, greaterThan(before),
        reason: 'The old voice still has a 400 ms release');
    fixture.position = 6.01;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    final stoppedReads = fixture.reads;
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.reads, stoppedReads);
    await fixture.emit(tester, 6.8);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    fixture.playing = false;
    await tester.pumpWidget(fixture.app());
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(hours: 2));
    fixture.playing = true;
    await tester.pumpWidget(fixture.app());
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
