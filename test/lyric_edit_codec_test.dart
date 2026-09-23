import 'dart:convert';
import 'dart:io';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter_test/flutter_test.dart';

Qrc rich() => Qrc([
      QrcLine(
          const Duration(milliseconds: 1001),
          const Duration(milliseconds: 1499),
          [
            QrcWord(const Duration(milliseconds: 1001),
                const Duration(milliseconds: 499), '光🌙 '),
            QrcWord(const Duration(milliseconds: 1500),
                const Duration(milliseconds: 1000), '안녕 (hello)'),
          ],
          '翻译・Translation')
        ..romanization = 'hikari · annyeong'
    ]);
SyncLyricLine contentLine(Lyric lyric) => lyric.lines
    .whereType<SyncLyricLine>()
    .firstWhere((line) => line.words.isNotEmpty);

void main() {
  for (final format in [
    LyricEditFormat.enhanced,
    LyricEditFormat.qrc,
    LyricEditFormat.krc,
    LyricEditFormat.yrc,
    LyricEditFormat.lossless
  ]) {
    test(
        '${format.name} preserves word times, unicode, translation and pronunciation',
        () {
      final source = rich();
      final draft = LyricEditDraft.fromLyric(source, format);
      final restored = contentLine(draft.parse());
      final original = contentLine(source);
      expect(restored.start, original.start);
      expect(restored.length, original.length);
      expect(restored.words.map((w) => [w.start, w.length, w.content]),
          original.words.map((w) => [w.start, w.length, w.content]));
      expect(restored.translation, original.translation);
      expect(restored.romanization, original.romanization);
    });
  }
  test('LRC auxiliary tracks merge with exact millisecond precision', () {
    final lyric = const LyricEditDraft(
            LyricEditFormat.lrc, '[00:01.001]Hello\n[00:04.567]世界',
            translation: '[00:01.001]你好', romanization: '[00:04.567]sekai')
        .parse();
    expect((lyric.lines.first as LrcLine).content, 'Hello┃你好');
    expect(lyric.lines.last.romanization, 'sekai');
    final round = LyricEditDraft.fromLyric(lyric, LyricEditFormat.lrc).parse();
    expect(LyricSnapshot.capture(round).toJson(),
        LyricSnapshot.capture(lyric).toJson());
  });
  test('plain text and native copy preserve all lines', () {
    const content = 'First\n你好🌙\n안녕\n終わり';
    for (final format in [LyricEditFormat.plain, LyricEditFormat.lossless]) {
      final lyric = LyricEditDraft.fromLyric(PlainLyric(content), format)
          .parse() as PlainLyric;
      expect(lyric.text, content);
    }
  });
  test('line timing does not invent per-character word times', () {
    final source = Lrc.fromLrcText(
        '[00:01.001]Hello world\n[00:03.001]Goodbye', LrcSource.local)!;
    final result =
        LyricEditDraft.fromLyric(source, LyricEditFormat.qrc).parse();
    expect(contentLine(result).words.length, 1);
    expect(contentLine(result).words.single.content, 'Hello world');
  });
  test('native snapshot preserves microseconds and intentional trailing span',
      () {
    final line = contentLine(rich());
    line.start += const Duration(microseconds: 123);
    for (final word in line.words) {
      word.start += const Duration(microseconds: 123);
    }
    line.length += const Duration(milliseconds: 200);
    final original = Qrc([line]);
    final copy =
        LyricEditDraft.fromLyric(original, LyricEditFormat.lossless).parse();
    expect(LyricSnapshot.capture(copy).toJson(),
        LyricSnapshot.capture(original).toJson());
  });
  test('malformed and out-of-range words fail before playback normalization',
      () {
    for (final draft in [
      const LyricEditDraft(LyricEditFormat.qrc, '[1000,100]oops(900,100)'),
      const LyricEditDraft(LyricEditFormat.qrc, '[1000,100]oops(1000,500)'),
      const LyricEditDraft(LyricEditFormat.krc, '[1000,100]<0,500,0>oops'),
      const LyricEditDraft(LyricEditFormat.yrc, '[1000,100](1000,500,0)oops'),
      const LyricEditDraft(
          LyricEditFormat.enhanced, '[00:01.000]<00:02.000>oops<00:01.000>'),
      const LyricEditDraft(LyricEditFormat.enhanced,
          '[00:01.000]missing<00:01.000>word<00:02.000>'),
      const LyricEditDraft(
          LyricEditFormat.enhanced, '[00:01.000]<00:01.000>missing end'),
      const LyricEditDraft(LyricEditFormat.qrc, '[1000,100]no word timings'),
      const LyricEditDraft(LyricEditFormat.lrc, 'missing line header'),
    ]) {
      expect(draft.parse, throwsFormatException, reason: draft.original);
    }
  });
  test('unmatched auxiliary times cannot be silently discarded', () {
    expect(
        const LyricEditDraft(LyricEditFormat.lrc, '[00:01.000]Hello',
                translation: '[00:02.000]你好')
            .parse,
        throwsFormatException);
    expect(
        const LyricEditDraft(LyricEditFormat.plain, 'Hello',
                romanization: '[00:00]hello')
            .parse,
        throwsFormatException);
  });
  test('oversized draft is rejected', () {
    expect(
        LyricEditDraft(
                LyricEditFormat.plain, 'x' * (LyricEditDraft.maxBytes + 1))
            .parse,
        throwsFormatException);
  });
  test('all file exports import with companion tracks', () {
    for (final format in LyricEditFormat.values) {
      final draft = LyricEditDraft.fromLyric(rich(), format);
      final name = 'song.${format.extension}';
      final files = draft.exportFiles(name);
      final imported = LyricEditDraft.importBytes(files[name]!, name);
      final result = LyricEditDraft(imported.format, imported.original,
              translation: utf8.decode(files['$name.translation.lrc'] ?? []),
              romanization: utf8.decode(files['$name.romanization.lrc'] ?? []))
          .parse();
      expect(hasLyricContent(result), isTrue, reason: format.name);
      if (format.timedWords) {
        expect(contentLine(result).translation, '翻译・Translation');
      }
    }
  });
  test('cleared auxiliary tracks replace old companions and keep backups',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-export-');
    addTearDown(() => dir.delete(recursive: true));
    final file = '${dir.path}/song.lrc';
    await writeLyricExport(const LyricEditDraft(
            LyricEditFormat.lrc, '[00:01]Hello',
            translation: '[00:01]你好')
        .exportFiles(file));
    await writeLyricExport(
        const LyricEditDraft(LyricEditFormat.lrc, '[00:01]Hello')
            .exportFiles(file));
    expect(await File('$file.translation.lrc').readAsString(), isEmpty);
    expect((await dir.list().toList()).where((f) => f.path.endsWith('.bak')),
        isNotEmpty);
  });
  test('export group rolls back the main file if a companion cannot be written',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-rollback-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/song.lrc');
    await file.writeAsString('old');
    await expectLater(
        writeLyricExport({
          file.path: utf8.encode('new'),
          '${dir.path}/absent/aux.lrc': [1]
        }),
        throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'old');
    expect((await dir.list().toList()).where((f) => f.path.endsWith('.tmp')),
        isEmpty);
  });
  test(
      'rich revisions survive restart and restoration with conflict protection',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-rich-document-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LyricDocumentStore(storageDirectory: dir);
    final audio = Audio('Song', 'Artist', 'Album', 0, 180, null, null,
        '${dir.path}/song.mp3', 0, 0, null);
    final original = rich();
    final edited = const LyricEditDraft(
            LyricEditFormat.qrc, '[1001,499]New(1001,499)',
            translation: '[00:01.001]新', romanization: '[00:01.001]xin')
        .parse();
    await store.editLyric(audio, edited,
        original: original, expectedRevision: 0);
    final reloaded = LyricDocumentStore(storageDirectory: dir);
    await reloaded.load();
    final doc = reloaded.forAudio(audio)!;
    expect(doc.locked, isTrue);
    expect(contentLine(doc.effective!.toLyric()).romanization, 'xin');
    expect(LyricSnapshot.capture(doc.original!.toLyric()).toJson(),
        LyricSnapshot.capture(original).toJson());
    await expectLater(reloaded.editLyric(audio, original, expectedRevision: 0),
        throwsA(isA<StaleLyricRevision>()));
  });
  test('conversion checks timing, auxiliary content and microsecond loss', () {
    expect(lyricConversionPreservesData(rich(), LyricEditFormat.lrc), isFalse);
    expect(
        lyricConversionPreservesData(rich(), LyricEditFormat.plain), isFalse);
    expect(lyricConversionPreservesData(rich(), LyricEditFormat.krc), isTrue);
    final source = rich();
    contentLine(source).length += const Duration(milliseconds: 500);
    expect(lyricConversionPreservesData(source, LyricEditFormat.enhanced),
        isFalse);
    expect(
        lyricConversionPreservesData(source, LyricEditFormat.lossless), isTrue);
  });
  for (final format in LyricEditFormat.values.where((f) => f.timedWords)) {
    test('${format.name} retimes whole row and creates correct word markers',
        () {
      final source = LyricEditDraft.fromLyric(rich(), format);
      final moved = retimeLyricEditorRow(source.original, format, 3001, 4500);
      final line = contentLine(LyricEditDraft(format, moved).parse());
      expect(line.start, const Duration(milliseconds: 3001));
      expect(line.words.first.start, const Duration(milliseconds: 3001));
      expect(line.words.last.start, const Duration(milliseconds: 3500));
      final word = timedLyricWord('你好', format, 3500, 4000, lineStartMs: 3000);
      final header =
          format == LyricEditFormat.enhanced ? '[00:03.000]' : '[3000,1000]';
      final marked = contentLine(LyricEditDraft(format, '$header$word').parse())
          .words
          .single;
      expect(marked.start, const Duration(milliseconds: 3500));
      expect(marked.length, const Duration(milliseconds: 500));
      expect(marked.content, '你好');
    });
  }
  test('line timestamp replaces the existing header without corrupting text',
      () {
    expect(
        retimeLyricEditorRow(
            '[00:01.000]Hello', LyricEditFormat.lrc, 2345, 2345),
        '[00:02.345]Hello');
    expect(
        () => timedLyricWord('word(1000,500)', LyricEditFormat.qrc, 1000, 1500,
            lineStartMs: 1000),
        throwsFormatException);
  });
  test('file import preserves cleared and populated companion tracks',
      () async {
    final dir = await Directory.systemTemp.createTemp('lyric-import-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/song.krc');
    await writeLyricExport(LyricEditDraft.fromLyric(rich(), LyricEditFormat.krc)
        .exportFiles(file.path));
    expect((await file.readAsBytes()).take(4), [107, 114, 99, 49]);
    final restored = contentLine((await readLyricEditFile(file)).parse());
    expect(restored.translation, '翻译・Translation');
    expect(restored.romanization, 'hikari · annyeong');
  });
  test(
      'retiming an existing selected word replaces its marker, never doubles it',
      () {
    for (final format in LyricEditFormat.values.where((f) => f.timedWords)) {
      final row = lyricEditingExample(format).original.split('\n').first;
      final from = row.indexOf('Hello '), to = from + 'Hello '.length;
      final result = replaceTimedLyricWord(row, format, from, to, 1100, 1500,
          lineStartMs: 1000);
      final line = contentLine(LyricEditDraft(format, result).parse());
      expect(line.words.length, 2, reason: format.name);
      expect(line.words.first.start, const Duration(milliseconds: 1100));
      expect(line.words.first.length, const Duration(milliseconds: 400));
      expect(line.content, 'Hello world');
    }
  });
  test(
      'preserving online lyrics prefers an editable word format before native JSON',
      () {
    expect(preferredLyricEditingFormat(rich()), LyricEditFormat.qrc);
    expect(preferredLyricEditingFormat(PlainLyric('hello')),
        LyricEditFormat.plain);
    final micro = rich();
    contentLine(micro).start += const Duration(microseconds: 1);
    for (final word in contentLine(micro).words) {
      word.start += const Duration(microseconds: 1);
    }
    expect(preferredLyricEditingFormat(micro), LyricEditFormat.lossless);
  });
  test(
      'line retiming carries auxiliary tracks and applies their offsets exactly once',
      () {
    final moved = retimeLyricAuxiliaryRows(
        '[offset:100]\n[00:01.100]译文\n[00:02.100]下一句', 1000, 1500);
    expect(moved, '[00:01.500]译文\n[00:02.000]下一句');
    final lyric = LyricEditDraft(
            LyricEditFormat.lrc, '[00:01.500]One\n[00:02.000]Two',
            translation: moved)
        .parse();
    expect((lyric.lines.first as LrcLine).content, 'One┃译文');
  });

  test('KRC language frame keeps both translation and pronunciation', () {
    final frame = base64Encode(utf8.encode(jsonEncode({
      'content': [
        {
          'type': 1,
          'lyricContent': [
            ['译文']
          ]
        },
        {
          'type': 0,
          'lyricContent': [
            ['hello', 'world']
          ]
        }
      ]
    })));
    final lyric = LyricEditDraft.importBytes(
            utf8.encode(
                '[language:$frame]\n[1000,1000]<0,500,0>Hello <500,500,0>world'),
            'song.krc')
        .parse();
    expect(contentLine(lyric).translation, '译文');
    expect(contentLine(lyric).romanization, 'hello world');
  });
}
