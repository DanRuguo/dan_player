import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edited timestamps are sorted before animation lengths are computed',
      () {
    final lrc = Lrc.fromLrcText(
        '[00:08.00]Third\n[00:01.00]First\n[00:01.00]Translation\n[00:04.00]Second',
        LrcSource.local,
        separator: '┃')!;
    final lines = lrc.lines.cast<LrcLine>();
    expect(lines.map((line) => line.content),
        ['First┃Translation', 'Second', 'Third']);
    expect(lines.map((line) => line.length.inSeconds), [3, 4, 0]);
  });

  test('malformed or non-finite timestamps are skipped safely', () {
    expect(LrcLine.fromLine('[00:NaN]bad'), isNull);
    expect(LrcLine.fromLine('] [00:01]bad'), isNull);
    expect(LrcLine.fromLine('[-1:02]bad'), isNull);
  });

  test('a valid edited UTF-16 sidecar is preferred before native embedded tags',
      () async {
    final parent = await Directory(
            path.join(Directory.current.path, 'build', 'lyric-tests'))
        .create(recursive: true);
    final scratch = await parent.createTemp('sidecar-');
    try {
      final audio = Audio('Sidecar', 'Artist', 'Album', 0, 60, null, null,
          path.join(scratch.path, 'sidecar.mp3'), 0, 0, null);
      const text = '[00:01.00]本地编辑歌词';
      final bytes = <int>[0xff, 0xfe];
      for (final unit in text.codeUnits) {
        bytes.addAll([unit & 0xff, unit >> 8]);
      }
      await File(path.setExtension(audio.path, '.lrc')).writeAsBytes(bytes);
      // There is intentionally no audio file or Rust initialization. A valid
      // local override must return before attempting to read embedded tags.
      final lrc = await Lrc.fromAudioPath(audio);
      expect((lrc!.lines.single as LrcLine).content, '本地编辑歌词');
      expect(lrc.source, LrcSource.local);

      await File(path.setExtension(audio.path, '.lrc'))
          .writeAsBytes(utf8.encode('[00:02.00]第二次编辑'));
      expect(
          ((await Lrc.fromAudioPath(audio))!.lines.single as LrcLine).content,
          '第二次编辑');
    } finally {
      if (path.isWithin(parent.path, scratch.path)) {
        await scratch.delete(recursive: true);
      }
    }
  });
}
