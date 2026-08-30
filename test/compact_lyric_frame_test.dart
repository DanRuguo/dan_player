import 'package:dan_player/lyric/compact_lyric_frame.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Line extends UnsyncLyricLine {
  _Line(int seconds, String text) : super(Duration(seconds: seconds), text);
}

class _Word extends SyncLyricWord {
  _Word(int seconds, String text)
      : super(Duration(seconds: seconds), const Duration(seconds: 1), text);
}

class _SyncLine extends SyncLyricLine {
  _SyncLine(int seconds, List<SyncLyricWord> words, [String? translation])
      : super(Duration(seconds: seconds), const Duration(seconds: 5), words,
            translation);
}

class _UnknownLine extends LyricLine {
  _UnknownLine() : super(Duration.zero);
}

void main() {
  test('plain lyric uses a bounded untimed summary in compact views', () {
    final timeline = CompactLyricTimeline(
      PlainLyric('First untimed line\nSecond line\nThird line'),
    );
    final frame = timeline.at(const Duration(hours: 1));

    expect(frame.primary, 'First untimed line');
    expect(frame.secondary, contains('无时间轴歌词'));
    expect(frame.fullText, isNot(contains('Second line')));
    expect(frame.identity, timeline.at(Duration.zero).identity);
  });

  test('empty and unknown lyrics are unavailable, never presumed instrumental',
      () {
    for (final lines in <List<LyricLine>>[
      [],
      [_Line(0, '  '), _Line(10, '')],
      [_UnknownLine()],
    ]) {
      final frame = CompactLyricTimeline(_Lyric(lines)).at(Duration.zero);
      expect(frame.status, CompactLyricStatus.unavailable);
      expect(frame.primary, '暂无歌词');
    }
  });

  test('the first lyric is previewed without falsely marking it active', () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(10, 'First line'),
      _Line(20, 'Second line'),
    ]));
    final frame = timeline.at(const Duration(milliseconds: 9999));
    expect(frame.status, CompactLyricStatus.upcoming);
    expect(frame.primary, '歌词即将开始');
    expect(frame.secondary, 'First line');
    expect(frame.secondaryKind, CompactLyricSecondary.firstLine);
    expect(frame.lineIndex, -1);
    expect(timeline.at(const Duration(seconds: 10)).primary, 'First line');
  });

  test('leading blank timestamp rows still produce a clear upcoming state', () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, ''),
      _Line(2, '  '),
      _Line(10, 'First sung line'),
    ]));
    expect(timeline.at(const Duration(seconds: 4)).status,
        CompactLyricStatus.upcoming);
    expect(
        timeline.at(const Duration(seconds: 4)).secondary, 'First sung line');
  });

  test(
      'exact timestamps, forward seek and backward seek use the shared timeline',
      () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'One'),
      _Line(10, 'Two'),
      _Line(20, 'Three'),
    ]));
    for (final (milliseconds, index, content) in [
      (0, 0, 'One'),
      (9999, 0, 'One'),
      (10000, 1, 'Two'),
      (75000, 2, 'Three'),
      (1000, 0, 'One'),
      (20000, 2, 'Three'),
    ]) {
      final frame = timeline.at(Duration(milliseconds: milliseconds));
      expect(frame.lineIndex, index);
      expect(frame.primary, content);
      expect(frame.status, CompactLyricStatus.active);
    }
  });

  test('equal timestamps retain the shared last-equal-line tie breaking', () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'Before'),
      _Line(10, 'Original'),
      _Line(10, 'Last same timestamp'),
      _Line(20, 'After'),
    ]));
    final frame = timeline.at(const Duration(seconds: 10));
    expect(frame.lineIndex, 2);
    expect(frame.primary, 'Last same timestamp');
  });

  test('parser-applied positive and negative offsets are not applied twice',
      () {
    for (final (offset, firstMilliseconds) in [(2500, 2500), (-2500, 7500)]) {
      final lyric = Lrc.fromLrcText(
        '[offset:$offset]\n[00:05.00]First\n[00:10.00]Second',
        LrcSource.local,
        separator: '┃',
      )!;
      final timeline = CompactLyricTimeline(lyric);
      expect(lyric.lines.first.start.inMilliseconds, firstMilliseconds);
      expect(
        timeline.at(Duration(milliseconds: firstMilliseconds - 1)).status,
        CompactLyricStatus.upcoming,
      );
      expect(timeline.at(Duration(milliseconds: firstMilliseconds)).primary,
          'First');
      expect(
          timeline.at(Duration(milliseconds: firstMilliseconds + 5000)).primary,
          'Second');
    }
  });

  test('LRC original and translated lines stay in one current-line frame', () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'Hello┃你好┃こんにちは'),
      _Line(10, 'Next'),
    ]));
    final frame = timeline.at(Duration.zero);
    expect(frame.primary, 'Hello');
    expect(frame.secondary, '你好 · こんにちは');
    expect(frame.secondaryKind, CompactLyricSecondary.translation);
    expect(frame.fullText, 'Hello\n译文：你好 · こんにちは');
    expect(frame.displaySecondary, '你好 · こんにちは');
  });

  test('timed words supply the same original text and prefer real translation',
      () {
    final timeline = CompactLyricTimeline(_Lyric([
      _SyncLine(0, [_Word(0, 'Hello '), _Word(1, 'world')], '  你好世界  '),
      _Line(10, 'Next'),
    ]));
    final frame = timeline.at(const Duration(seconds: 1));
    expect(frame.primary, 'Hello world');
    expect(frame.secondary, '你好世界');
    expect(frame.secondaryKind, CompactLyricSecondary.translation);
    expect(frame.identity, timeline.at(const Duration(seconds: 3)).identity);
  });

  test('without translation the next nonblank line becomes the preview', () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'Current'),
      _Line(5, ''),
      _Line(8, '  '),
      _Line(10, 'Next┃下一句译文'),
    ]));
    final current = timeline.at(Duration.zero);
    expect(current.secondaryKind, CompactLyricSecondary.nextLine);
    expect(current.secondary, 'Next');
    expect(current.displaySecondary, '下一句 · Next');
    expect(current.fullText, 'Current\n下一句：Next');
    final gap = timeline.at(const Duration(seconds: 7));
    expect(gap.status, CompactLyricStatus.interlude);
    expect(gap.secondary, 'Next');
    expect(gap.lineIndex, 1);
  });

  test('the final sung line and a trailing interlude do not invent a next line',
      () {
    final sung = CompactLyricTimeline(_Lyric([_Line(0, 'Last')]));
    final frame = sung.at(const Duration(days: 1));
    expect(frame.primary, 'Last');
    expect(frame.secondary, isEmpty);
    expect(frame.secondaryKind, CompactLyricSecondary.none);
    final gap = CompactLyricTimeline(_Lyric([
      _Line(0, 'Last'),
      _Line(10, ''),
    ])).at(const Duration(seconds: 20));
    expect(gap.status, CompactLyricStatus.interlude);
    expect(gap.secondary, isEmpty);
  });

  for (final marker in [
    '纯音乐，请欣赏',
    '纯音乐，请您欣赏。',
    '[Instrumental]',
    'Instrumental version',
  ]) {
    test('an explicit $marker-only lyric is labelled instrumental', () {
      final timeline = CompactLyricTimeline(_Lyric([
        _Line(0, ''),
        _Line(10, marker),
      ]));
      for (final seconds in [0, 10, 100]) {
        final frame = timeline.at(Duration(seconds: seconds));
        expect(frame.status, CompactLyricStatus.instrumental);
        expect(frame.primary, '纯音乐，请欣赏');
      }
    });
  }

  test('an instrumental break is not a claim that the whole song has no vocals',
      () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'Verse'),
      _Line(10, '[Instrumental]'),
      _Line(20, 'Chorus'),
    ]));
    final frame = timeline.at(const Duration(seconds: 12));
    expect(frame.status, CompactLyricStatus.interlude);
    expect(frame.secondary, 'Chorus');
    expect(timeline.at(const Duration(seconds: 20)).primary, 'Chorus');
  });

  test('ordinary lyrics that mention instrumental music are not reclassified',
      () {
    final frame = CompactLyricTimeline(_Lyric([
      _Line(0, 'We dance to instrumental music'),
    ])).at(Duration.zero);
    expect(frame.status, CompactLyricStatus.active);
    expect(frame.primary, 'We dance to instrumental music');
  });

  test(
      'line identity ignores ticks but distinguishes repeated text occurrences',
      () {
    final timeline = CompactLyricTimeline(_Lyric([
      _Line(0, 'Repeat'),
      _Line(10, 'Repeat'),
      _Line(20, 'Repeat'),
    ]));
    expect(timeline.at(Duration.zero).identity,
        timeline.at(const Duration(seconds: 9)).identity);
    expect(timeline.at(Duration.zero).identity,
        isNot(timeline.at(const Duration(seconds: 10)).identity));
  });

  test('reading frames never rewrites the shared lyric or its word timing', () {
    final line = _SyncLine(10, [_Word(10, 'Original')], 'Translation');
    final lines = <LyricLine>[line, _Line(20, 'Next')];
    final lyric = _Lyric(lines);
    final timeline = CompactLyricTimeline(lyric);
    timeline.at(const Duration(seconds: 12));
    timeline.at(const Duration(seconds: 1));
    expect(identical(lyric.lines, lines), isTrue);
    expect(identical(lyric.lines.first, line), isTrue);
    expect(line.start, const Duration(seconds: 10));
    expect(line.words.single.start, const Duration(seconds: 10));
    expect(line.content, 'Original');
    expect(line.translation, 'Translation');
  });
}
