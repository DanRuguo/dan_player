import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/play_service/lyric_line_practice.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter_test/flutter_test.dart';

class _Playback extends Fake implements PlaybackService {
  @override
  final segmentLoop = SegmentLoopController();
  @override
  int playbackSessionToken = 7;
  @override
  double length = 100;
  @override
  bool canUseSegmentLoop = true;
  int enables = 0, starts = 0;
  @override
  bool setSegmentLoopEnabled(bool enabled) {
    enables++;
    segmentLoop.setEnabled(enabled);
    return segmentLoop.enabled;
  }

  @override
  void start({bool recordIntent = true}) => starts++;
}

LrcLine _line(int start, int length, [String text = '歌词']) =>
    LrcLine(Duration(milliseconds: start), text,
        isBlank: text.trim().isEmpty, length: Duration(milliseconds: length));
Lrc _lyric(List<LyricLine> lines) => Lrc(lines, LrcSource.local);

void main() {
  test('short displayed phrases form a continuous range across an empty row',
      () {
    final first = _line(8500, 400), blank = _line(8900, 800, '');
    final last = _line(9700, 400);
    final lyric = _lyric([first, blank, last]);
    expect(lyricLinePracticeRange(lyric, first, 100), isNull);
    expect(lyricSegmentPracticeRange(lyric, first, last, 100),
        (start: 8.5, end: 10.1));
    expect(first.start.inMilliseconds, 8500);
    expect(last.start.inMilliseconds, 9700);
    expect(first.length.inMilliseconds, 400);
    expect(lyric.lines, orderedEquals([first, blank, last]));
  });

  test('reverse endpoints normalize document indices without reordering rows',
      () {
    final first = _line(10000, 2000), last = _line(13000, 3000);
    final lyric = _lyric([first, last]);
    expect(lyricSegmentPracticeRange(lyric, last, first, 100),
        (start: 10.0, end: 16.0));
    expect(lyric.lines.first, same(first));
  });

  test('equal-time open LRC rows use the next distinct global timestamp', () {
    final a = _line(10000, 0, '原文'), b = _line(10000, 0, '同拍另一句');
    final lyric = _lyric([a, b, _line(13000, 0, ''), _line(18000, 2000)]);
    expect(
        lyricSegmentPracticeRange(lyric, a, b, 100), (start: 10.0, end: 13.0));
  });

  test('selected LRC tail uses track EOF while earlier rows infer their end',
      () {
    final a = _line(10000, 0), b = _line(15000, 0);
    expect(lyricSegmentPracticeRange(_lyric([a, b]), a, b, 20),
        (start: 10.0, end: 20.0));
  });

  test('overlapping selected voice covers its final word past the last row',
      () {
    final a = QrcLine(const Duration(seconds: 10), const Duration(seconds: 2), [
      QrcWord(const Duration(seconds: 10), const Duration(seconds: 6), '合唱')
    ]);
    final b = QrcLine(const Duration(seconds: 12), const Duration(seconds: 1), [
      QrcWord(const Duration(seconds: 12), const Duration(seconds: 1), '下一句')
    ]);
    final outside = QrcLine(
        const Duration(seconds: 18), const Duration(seconds: 20), [
      QrcWord(const Duration(seconds: 18), const Duration(seconds: 20), '未选')
    ]);
    final lyric = Qrc([a, b, outside]);
    expect(
        lyricSegmentPracticeRange(lyric, a, b, 100), (start: 10.0, end: 16.0));
    expect(a.length, const Duration(seconds: 2));
    expect(a.words.single.length, const Duration(seconds: 6));
  });

  test('negative displayed offset and EOF clip the combined range only once',
      () {
    final a = _line(-2000, 1000), b = _line(500, 1500);
    expect(lyricSegmentPracticeRange(_lyric([a, b]), a, b, 100),
        (start: 0.0, end: 2.0));
    final tailA = _line(98500, 1000), tailB = _line(99900, 1000);
    expect(lyricSegmentPracticeRange(_lyric([tailA, tailB]), tailA, tailB, 100),
        (start: 98.5, end: 100.0));
    expect(tailB.start.inMilliseconds, 99900);
  });

  test('clipped subsecond and authored short single selections never stretch',
      () {
    final a = _line(99500, 300), b = _line(99900, 100);
    final lyric = _lyric([a, b]);
    expect(lyricSegmentPracticeRange(lyric, a, b, 100), isNull);
    expect(lyricSegmentPracticeRange(lyric, a, a, 100), isNull);
  });

  test('millisecond one-second combined span keeps the existing AB threshold',
      () {
    final a = _line(1002, 300), b = _line(1502, 500);
    final range = lyricSegmentPracticeRange(_lyric([a, b]), a, b, 2.002)!;
    expect(range.end, 2.002);
    expect(range.start, closeTo(1.002, 1e-12));
    expect(range.end - range.start, greaterThanOrEqualTo(1));
  });

  test(
      'empty endpoints plain lyrics foreign identity and bad length are rejected',
      () {
    final a = _line(10000, 2000), b = _line(13000, 2000);
    final empty = _line(15000, 0, ''), lyric = _lyric([a, b, empty]);
    expect(lyricSegmentPracticeRange(lyric, a, empty, 100), isNull);
    expect(
        lyricSegmentPracticeRange(lyric, _line(10000, 2000), b, 100), isNull);
    expect(lyricSegmentPracticeRange(PlainLyric('无时间'), a, b, 100), isNull);
    for (final length in [double.nan, double.infinity, -1.0, .5]) {
      expect(lyricSegmentPracticeRange(lyric, a, b, length), isNull);
    }
  });

  test('long tracks and large documents preserve every selected original row',
      () {
    final rows = List<LyricLine>.generate(
        20000, (i) => _line(1080000000 + i * 2000, 0, '第 $i 句'));
    final lyric = _lyric(rows);
    expect(lyricSegmentPracticeRange(lyric, rows[5], rows[19999], 1200000),
        (start: 1080010.0, end: 1200000.0));
    expect(lyric.lines.length, 20000);
    expect(lyric.lines[5], same(rows[5]));
  });

  LyricPracticeResult apply(
          _Playback playback, Lyric lyric, LyricLine first, LyricLine last,
          {int session = 7, bool Function()? current}) =>
      practiceLyricSegment(
          playback: playback,
          lyric: lyric,
          first: first,
          last: last,
          playbackSession: session,
          isCurrentLyric: current ?? () => true);

  test(
      'multi-line apply preserves AB rounds and interval without starting playback',
      () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.configurePractice(rounds: 5, interval: 2);
    final a = _line(10000, 300), b = _line(12000, 300);
    expect(apply(playback, _lyric([a, b]), a, b), LyricPracticeResult.applied);
    expect(playback.segmentLoop.start, 10);
    expect(playback.segmentLoop.end, 12.3);
    expect(playback.segmentLoop.totalRounds, 5);
    expect(playback.segmentLoop.intervalSeconds, 2);
    expect(playback.segmentLoop.enabled, isTrue);
    expect(playback.enables, 1);
    expect(playback.starts, 0);
  });

  test(
      'stale session lyric ownership and invalid range keep the old AB untouched',
      () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.setStart(1, 100);
    playback.segmentLoop.setEnd(3, 100);
    final a = _line(10000, 300), b = _line(10200, 300);
    final lyric = _lyric([a, b]);
    expect(apply(playback, lyric, a, b, session: 6), LyricPracticeResult.stale);
    expect(apply(playback, lyric, a, b, current: () => false),
        LyricPracticeResult.stale);
    expect(apply(playback, lyric, a, b), LyricPracticeResult.invalidRange);
    playback.canUseSegmentLoop = false;
    expect(apply(playback, lyric, a, b), LyricPracticeResult.unavailable);
    expect(playback.segmentLoop.start, 1);
    expect(playback.segmentLoop.end, 3);
    expect(playback.enables, 0);
  });

  test('reentrant source replacement after A or B prevents old loop enabling',
      () {
    for (final changeAfter in [1, 2]) {
      final playback = _Playback();
      addTearDown(playback.segmentLoop.dispose);
      var notifications = 0;
      playback.segmentLoop.addListener(() {
        if (++notifications == changeAfter) playback.playbackSessionToken++;
      });
      final a = _line(10000, 2000), b = _line(13000, 2000);
      expect(apply(playback, _lyric([a, b]), a, b), LyricPracticeResult.stale);
      expect(playback.enables, 0);
      expect(playback.segmentLoop.enabled, isFalse);
    }
  });
}
