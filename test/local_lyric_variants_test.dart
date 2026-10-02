import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/local_lyric_parser.dart';
import 'package:dan_player/lyric/local_lyric_reader.dart';
import 'package:dan_player/lyric/local_lyric_variants.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Audio audio;
  setUp(() async {
    final root = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (root == null ||
        !p.isWithin(
            p.join(Directory.current.parent.path, 'tool', 'qa-local'), root)) {
      throw StateError('Use independent workspace QA data');
    }
    fixture = await Directory(root).createTemp('local-variants-');
    audio = Audio('Song', 'Artist', 'Album', 0, 60, null, null,
        p.join(fixture.path, 'Song.flac'), 0, 0, null);
    await File(audio.localFilePath).writeAsBytes([0]);
    clearLocalLyricMemoryCache();
  });
  tearDown(() async {
    clearLocalLyricMemoryCache();
    await fixture.delete(recursive: true);
  });
  Future<File> write(String name, String text) async =>
      File(p.join(fixture.path, name)).writeAsString(text);
  LocalLyricVariant variant(String name) =>
      LocalLyricVariant.fromPath(audio, p.join(fixture.path, name))!;
  Future<Lyric?> read(String name) => readLocalLyric(audio,
      variant: variant(name), lineOrder: LocalLyricLineOrder.automatic);

  test('enumerates only exact song-stem language files and sorts formats',
      () async {
    for (final name in [
      'Song.zh-CN.lrc',
      'Song.ja.lrc',
      'Song.ja.yrc',
      'Song.ko.ttml',
      'Song.en-US.elrc',
      'Song.fr.krc',
      'Song.de.qrc',
      'Song.lrc',
      'Song.qrc.translation.lrc',
      'Song.translation.lrc',
      'Song.romanization.lrc',
      'Song.live.lrc',
      'Song2.ja.lrc',
      'Song.ja.txt',
      'Song.zh_CN.lrc',
      'Song.ja.lrc.romanization.lrc'
    ]) {
      await write(name, '[00:01.00]text');
    }
    await Directory(p.join(fixture.path, 'Song.es.lrc')).create();
    final result = await findLocalLyricVariants(audio);
    expect(result.truncated, isFalse);
    expect(result.candidates.map((item) => item.filename), [
      'Song.de.qrc',
      'Song.en-US.elrc',
      'Song.fr.krc',
      'Song.ja.yrc',
      'Song.ja.lrc',
      'Song.ko.ttml',
      'Song.zh-CN.lrc'
    ]);
    expect(
        LocalLyricVariant.fromPath(
            audio, p.join(fixture.parent.path, 'Song.ja.lrc')),
        isNull);
    expect(
        LocalLyricVariant.fromPath(
                audio, p.join(fixture.path, 'Song.zh-Hans-CN.lrc'))
            ?.languageTag,
        'zh-Hans-CN');
  });

  test('enumeration retains at most 32 candidates and reports truncation',
      () async {
    for (var i = 0; i < 35; i++) {
      await write('Song.en-${100 + i}.lrc', '[00:01.00]$i');
    }
    final result = await findLocalLyricVariants(audio);
    expect(result.candidates.length, 32);
    expect(result.truncated, isTrue);
  });

  test(
      'directory scan stops after 4096 entries without reading unrelated files',
      () async {
    for (var i = 0; i < 4097; i++) {
      await write('Unrelated$i.txt', '');
    }
    final result = await findLocalLyricVariants(audio);
    expect(result.candidates, isEmpty);
    expect(result.truncated, isTrue);
  });

  test('explicit language is independent of default priority and never merged',
      () async {
    await write('Song.yrc', '[1000,1000](1000,1000,0)Default');
    await write('Song.ja.lrc', '[00:01.00]日本語');
    await write('Song.zh-CN.lrc', '[00:01.00]中文');
    final selected = await read('Song.ja.lrc');
    expect(lyricLineText(selected!.lines.single), '日本語');
    expect(localLyricOrigin(selected), endsWith('Song.ja.lrc'));
    expect(
        lyricLineText((await readLocalLyric(audio,
                lineOrder: LocalLyricLineOrder.automatic))!
            .lines
            .single),
        'Default');
    expect(lyricLineText((await read('Song.zh-CN.lrc'))!.lines.single), '中文');
  });

  test(
      'word variant uses only its own declared companions and validates revisions',
      () async {
    await write('Song.ja.yrc', '[1000,1000](1000,500,0)日(1500,500,0)本');
    await write('Song.lrc', '[00:01.00]Unrelated default translation');
    await write('Song.zh-CN.lrc', '[00:01.00]Unchosen language');
    var selected = await read('Song.ja.yrc');
    expect((selected!.lines.single as SyncLyricLine).translation, isNull);
    await write(
        'Song.ja.yrc.translation.lrc', '[00:01.00]Declared translation');
    await write('Song.ja.yrc.romanization.lrc', '[00:01.00]ni hon');
    selected = await read('Song.ja.yrc');
    var line = selected!.lines.single as SyncLyricLine;
    expect(line.translation, 'Declared translation');
    expect(line.romanization, 'ni hon');
    expect(line.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
    line.words.first.content = 'Mutated';
    line.translation = 'Mutated';
    final copied = (await read('Song.ja.yrc'))!.lines.single as SyncLyricLine;
    expect(copied.content, '日本');
    expect(copied.translation, 'Declared translation');
    await write('Song.ja.yrc.translation.lrc', '[00:01.00]Revised translation');
    expect(
        ((await read('Song.ja.yrc'))!.lines.single as SyncLyricLine)
            .translation,
        'Revised translation');
    await write('Song.ja.yrc', '[1000,1000](1000,1000,0)Changed main');
    expect(lyricLineText((await read('Song.ja.yrc'))!.lines.single),
        'Changed main');
  });

  test('same language parallel formats remain independent main lyrics',
      () async {
    await write('Song.ja.yrc', '[1000,1000](1000,1000,0)Original');
    await read('Song.ja.yrc');
    await write('Song.ja.lrc', '[00:01.00]Another main version');
    expect(
        ((await read('Song.ja.yrc'))!.lines.single as SyncLyricLine)
            .translation,
        isNull);
    expect(lyricLineText((await read('Song.ja.lrc'))!.lines.single),
        'Another main version');
    await File(p.join(fixture.path, 'Song.ja.lrc')).delete();
    expect(
        ((await read('Song.ja.yrc'))!.lines.single as SyncLyricLine)
            .translation,
        isNull);
  });

  test('TTML language version preserves words and declared translation roles',
      () async {
    await write(
        'Song.ja.ttml',
        '<tt xmlns="http://www.w3.org/ns/ttml" '
            'xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>'
            '<p begin="1s" end="2s"><span begin="0s" end=".5s">日</span>'
            '<span begin=".5s" end="1s">本</span>'
            '<span ttm:role="x-translation">Japan</span></p></div></body></tt>');
    final line = (await read('Song.ja.ttml'))!.lines.single as SyncLyricLine;
    expect(line.content, '日本');
    expect(line.translation, 'Japan');
    expect(line.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
  });

  test('missing or oversized explicit file never falls back to another source',
      () async {
    await write('Song.lrc', '[00:01.00]Default');
    expect(await read('Song.ja.lrc'), isNull);
    await write('Song.ja.lrc', 'A' * (LyricEditDraft.maxBytes + 1));
    final warnings = <String>[];
    expect(
        await readLocalLyric(audio,
            variant: variant('Song.ja.lrc'),
            lineOrder: LocalLyricLineOrder.automatic,
            onWarning: warnings.add),
        isNull);
    expect(warnings, isNotEmpty);
    expect(localLyricMemoryCacheSize, 0);
  });

  test('foreign-song variant and cancelled scans/readers cannot publish',
      () async {
    await write('Song.ja.lrc', '[00:01.00]Japanese');
    final other = Audio('Other', '', '', 0, 60, null, null,
        p.join(fixture.path, 'Other.flac'), 0, 0, null);
    expect(
        await readLocalLyric(other,
            variant: variant('Song.ja.lrc'),
            lineOrder: LocalLyricLineOrder.automatic),
        isNull);
    expect(
        (await findLocalLyricVariants(audio, stillCurrent: () => false))
            .candidates,
        isEmpty);
    var checks = 0;
    expect(
        await readLocalLyric(audio,
            variant: variant('Song.ja.lrc'),
            lineOrder: LocalLyricLineOrder.automatic,
            stillCurrent: () => ++checks < 3),
        isNull);
    expect(localLyricMemoryCacheSize, 0);
  });

  test(
      'selected snapshot survives reopen without language preferences or file access',
      () async {
    await write('Song.ko.lrc', '[offset:200]\n[00:01.00]한국어');
    final selected = (await read('Song.ko.lrc'))!;
    final store = LyricDocumentStore(storageDirectory: fixture);
    addTearDown(store.dispose);
    await store.select(audio, selected);
    await File(p.join(fixture.path, 'Song.ko.lrc')).delete();
    final reopened = LyricDocumentStore(storageDirectory: fixture);
    addTearDown(reopened.dispose);
    await reopened.load();
    final restored = reopened.forAudio(audio)!.effective!.toLyric();
    expect(lyricLineText(restored.lines.single), '한국어');
    expect(restored.lines.single.start, selected.lines.single.start);
  });
}
