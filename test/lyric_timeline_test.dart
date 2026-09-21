import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = [
    LrcLine(const Duration(seconds: 2), 'first', isBlank: false),
    LrcLine(const Duration(seconds: 5), 'second', isBlank: false),
    LrcLine(const Duration(seconds: 9), 'third', isBlank: false),
  ];

  test('current lyric line uses the latest timestamp at or before position',
      () {
    expect(findCurrentLyricLineIndex(lines, Duration.zero), 0);
    expect(findCurrentLyricLineIndex(lines, const Duration(seconds: 2)), 0);
    expect(
      findCurrentLyricLineIndex(lines, const Duration(milliseconds: 8999)),
      1,
    );
    expect(findCurrentLyricLineIndex(lines, const Duration(seconds: 9)), 2);
    expect(findCurrentLyricLineIndex(lines, const Duration(minutes: 1)), 2);
  });

  test('empty lyric has no active line', () {
    expect(findCurrentLyricLineIndex([], Duration.zero), -1);
  });

  test('authored word overlap keeps voices active, tiny overlap does not', () {
    final lyric = Qrc.fromQrcText(
        '[0,4000]前声(0,4000)\n[2000,2100]后声(2000,2100)\n[4000,3000]下一句(4000,3000)');
    final timeline = LyricOverlapTimeline(lyric.lines);
    expect(
        timeline.activeIndices(const Duration(milliseconds: 2500), 1), {0, 1});
    expect(timeline.activeIndices(const Duration(milliseconds: 4050), 2), {2});
    expect(timeline.activeIndices(const Duration(milliseconds: 1000), 0), {0});
  });
}
