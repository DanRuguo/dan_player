import 'dart:convert';

import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lyric = '[00:01.00]歌词 🎵';

  test('reads UTF-8 with and without a BOM', () {
    expect(decodeLyricText(utf8.encode(lyric)), lyric);
    expect(decodeLyricText([0xef, 0xbb, 0xbf, ...utf8.encode(lyric)]), lyric);
  });

  test('reads UTF-16 little and big endian lyrics', () {
    final littleEndian = <int>[0xff, 0xfe];
    final bigEndian = <int>[0xfe, 0xff];
    for (final unit in lyric.codeUnits) {
      littleEndian.addAll([unit & 0xff, unit >> 8]);
      bigEndian.addAll([unit >> 8, unit & 0xff]);
    }
    expect(decodeLyricText(littleEndian), lyric);
    expect(decodeLyricText(bigEndian), lyric);
  });

  test('invalid encoding is rejected instead of silently corrupting edits', () {
    expect(() => decodeLyricText([0xff, 0xfe, 0x01]), throwsFormatException);
    expect(() => decodeLyricText([0x81, 0x81]), throwsFormatException);
  });
}
