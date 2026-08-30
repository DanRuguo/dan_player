import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
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
}
