import 'dart:async';

import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';

Lrc _lrc(List<String> lines) => Lrc([
      for (var i = 0; i < lines.length; i++)
        LrcLine(Duration(seconds: i), lines[i], isBlank: false),
    ], LrcSource.local);

JapanesePhoneticBatch _read(List<String> chunks) => JapanesePhoneticBatch([
      for (final text in chunks)
        [JapanesePhoneticWord(text, text.replaceAll('漢', 'かん'))],
    ]);

void main() {
  test('Japanese readings default off and invalid values remain off', () {
    for (final value in [
      null,
      true,
      'enabled',
      {'enabled': 1},
      {'enabled': 'true'}
    ]) {
      expect(JapaneseReadingPreferences.fromJson(value).enabled, isFalse);
    }
    const enabled = JapaneseReadingPreferences(enabled: true);
    expect(JapaneseReadingPreferences.fromJson(enabled.toJson()), enabled);
    expect(
        enabled.copyWith(enabled: false), const JapaneseReadingPreferences());
  });

  test('disabled and pure Chinese automatic lyrics never invoke analyzer',
      () async {
    var calls = 0;
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls++;
      return _read(texts);
    });
    final source = _lrc(['漢字']);
    for (final enabled in [false, true]) {
      final result = await projector.project(source,
          enabled: enabled, stillCurrent: () => true);
      expect(result.lyric, same(source));
      expect(result.result, JapaneseReadingResult.unchanged);
    }
    expect(calls, 0);
  });

  test('Japanese BCP47 script and region metadata accept Han only lyrics',
      () async {
    for (final language in [
      'ja-Jpan-JP',
      'ja-Hira',
      'JA_Kana_JP',
      'en; ja-Latn-JP',
      'ja-u-nu-latn',
      'ja-JP-x-player'
    ]) {
      final projector =
          JapaneseReadingProjector(analyze: (text) async => _read(text));
      final result = await projector.project(_lrc(['漢字']),
          language: language, enabled: true, stillCurrent: () => true);
      expect(result.result, JapaneseReadingResult.applied, reason: language);
    }
    for (final language in [
      'zh-Hans-CN',
      'japanese-other',
      'javascript',
      'ja-',
      'ja!!'
    ]) {
      expect(isJapaneseReadingLanguage(language), isFalse, reason: language);
    }
  });

  test('explicit Japanese metadata permits Han only lines with author priority',
      () async {
    final calls = <List<String>>[];
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls.add(texts);
      return _read(texts);
    });
    final source = _lrc(['漢字', '漢文'])..lines[1].romanization = 'Author romaji';
    final result = await projector.project(source,
        language: 'en; ja_JP', enabled: true, stillCurrent: () => true);
    expect(result.result, JapaneseReadingResult.applied);
    expect(result.lyric.lines[0].japaneseReading, 'かん字');
    expect(result.lyric.lines[1].romanization, 'Author romaji');
    expect(result.lyric.lines[1].japaneseReading, 'かん文');
    expect(source.lines[0].japaneseReading, isNull);
    expect(calls, [
      ['漢字', '漢文']
    ]);
  });

  test('kana context permits other Japanese Han lines but Latin is untouched',
      () async {
    final calls = <List<String>>[];
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls.add(texts);
      return _read(texts);
    });
    final source = _lrc(['かな', '漢字', 'English']);
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(result.lyric.lines[1].japaneseReading, 'かん字');
    expect(result.lyric.lines[0].japaneseReading, isNull);
    expect(result.lyric.lines[2].japaneseReading, isNull);
    expect(calls.single, ['漢字']);
  });

  test('manual force parses Han without enabling automatic preference',
      () async {
    final projector =
        JapaneseReadingProjector(analyze: (texts) async => _read(texts));
    final source = _lrc(['漢']);
    final result = await projector.project(source,
        enabled: false, force: true, stillCurrent: () => true);
    expect(result.lyric.lines.single.japaneseReading, 'かん');
    expect(source.lines.single.japaneseReading, isNull);
  });

  test('100 UTF16 chunks never divide combining emoji flags or trailing text',
      () {
    final text = '${'漢' * 99}か\u3099👩‍👩‍👧‍👦🇯🇵${'漢' * 190}終';
    final chunks = japaneseReadingChunks(text);
    expect(chunks.map((chunk) => chunk.text).join(), text);
    expect(chunks.every((chunk) => chunk.text.length <= 100), isTrue);
    expect(chunks.expand((chunk) => chunk.text.characters), text.characters);
    expect(chunks.last.text.endsWith('終'), isTrue);
  });

  test('word spans retain whole Han runs and exact UTF16 anchored ranges', () {
    final long = '${'漢' * 100}かな';
    final longSpans = japaneseReadingWordSpans(long, 'かんかな', offset: 7);
    expect(longSpans, hasLength(1));
    expect(longSpans.single.start, 7);
    expect(longSpans.single.end, 107);
    expect(longSpans.single.text, 'かん');

    final spans =
        japaneseReadingWordSpans('𠀀\uFE0Fか\u3099夜', 'カンカ\u3099ヨル', offset: 7);
    expect(spans.map((span) => (span.start, span.end, span.text)), [
      (7, 10, 'カン'),
      (12, 13, 'ヨル'),
    ]);
    expect(japaneseReadingWordSpans('夜かな空かな', 'ヨルカナソラカナ'), isEmpty,
        reason: 'Repeated kana anchors must not invent per-Han readings');
  });

  test('oversized single grapheme is retained verbatim between parsed chunks',
      () async {
    final giant = 'a${'\u0301' * 105}';
    final text = '漢$giant漢';
    final chunks = japaneseReadingChunks(text);
    expect(chunks[1].analyzable, isFalse);
    final calls = <String>[];
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls.addAll(texts);
      return _read(texts);
    });
    final result = await projector.project(PlainLyric(text),
        enabled: false, force: true, stillCurrent: () => true);
    expect(result.lyric.lines.single.japaneseReading, 'かん$giantかん');
    expect(calls, ['漢']);
  });

  test(
      'long plain lyrics process every batch without dropping whitespace or tail',
      () async {
    final lines = [for (var i = 0; i < 24; i++) '漢$i ${'字' * 94}\r\n'];
    final source = PlainLyric('${lines.join()}漢tail');
    final sizes = <int>[];
    final projector = JapaneseReadingProjector(
        analyze: (texts) async {
          sizes.add(texts.length);
          return _read(texts);
        },
        maximumEntries: 2,
        maximumCacheBytes: 500);
    final result = await projector.project(source,
        enabled: false, force: true, stillCurrent: () => true);
    expect(result.lyric, isA<PlainLyric>());
    expect(result.lyric.lines.single.start, Duration.zero);
    expect(result.lyric.lines.single.japaneseReading,
        source.text.replaceAll('漢', 'かん'));
    expect(sizes.length, greaterThan(1));
    expect(sizes.every((size) => size <= 16), isTrue);
    expect(projector.cachedEntries, lessThanOrEqualTo(2));
    expect(projector.cachedBytes, lessThanOrEqualTo(500));
  });

  test('failed or incomplete native chunks retain all original text', () async {
    final source = _lrc(['漢か', '漢き', '漢く']);
    final projector = JapaneseReadingProjector(
        analyze: (_) async => const JapanesePhoneticBatch([
              null,
              [JapanesePhoneticWord('漢', 'かん')],
              [JapanesePhoneticWord('漢く', 'かんく')],
            ]));
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(result.lyric.lines.map((line) => line.japaneseReading),
        [null, null, 'かんく']);
  });

  test('word timestamps translations and author offsets are preserved exactly',
      () async {
    final source = Qrc([
      QrcLine(
          const Duration(microseconds: 1234567),
          const Duration(microseconds: 7654321),
          [
            QrcWord(const Duration(microseconds: 1234567),
                const Duration(microseconds: 789123), '漢'),
            QrcWord(const Duration(microseconds: 2222222),
                const Duration(microseconds: 333333), 'かな'),
          ],
          'Chinese translation'),
    ]);
    final projector =
        JapaneseReadingProjector(analyze: (texts) async => _read(texts));
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    final display = result.lyric.lines.single as SyncLyricLine;
    final original = source.lines.single as SyncLyricLine;
    expect(display.start, original.start);
    expect(display.length, original.length);
    expect(display.translation, original.translation);
    expect(display.words.map((word) => [word.start, word.length, word.content]),
        original.words.map((word) => [word.start, word.length, word.content]));
    expect(display.japaneseReading, 'かんかな');
    expect(original.japaneseReading, isNull);
  });

  test(
      'empty Windows words report unavailable and retry without negative cache',
      () async {
    var calls = 0;
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls++;
      return calls == 1 ? const JapanesePhoneticBatch([[]]) : _read(texts);
    });
    final source = _lrc(['漢かな']);
    final first = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(first.result, JapaneseReadingResult.unavailable);
    expect(projector.cachedEntries, 0);
    final retry = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(retry.result, JapaneseReadingResult.applied);
    expect(retry.lyric.lines.single.japaneseReading, 'かんかな');
  });

  test('KRC source type and supplied romanization are preserved', () async {
    final source = Krc([
      KrcLine(Duration.zero, const Duration(seconds: 1),
          [QrcWord(Duration.zero, const Duration(seconds: 1), '漢かな')])
        ..romanization = 'author'
    ]);
    final projector =
        JapaneseReadingProjector(analyze: (text) async => _read(text));
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(result.lyric, isA<Krc>());
    expect(result.lyric.lines.single.romanization, 'author');
    expect(result.lyric.lines.single.japaneseReading, 'かんかな');
    expect(source.lines.single.japaneseReading, isNull);
  });

  test('repeated line requests reuse a finite content cache', () async {
    var calls = 0;
    final projector = JapaneseReadingProjector(analyze: (texts) async {
      calls++;
      return _read(texts);
    });
    final source = _lrc(['漢か', '漢か']);
    for (var i = 0; i < 2; i++) {
      final result = await projector.project(source,
          enabled: true, stillCurrent: () => true);
      expect(result.lyric.lines.map((line) => line.japaneseReading),
          ['かんか', 'かんか']);
    }
    expect(calls, 1);
    expect(projector.cachedEntries, 1);
  });

  test('cancelled batch neither caches late data nor starts remaining batch',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    var calls = 0;
    var cancellations = 0;
    final projector = JapaneseReadingProjector(
        analyze: (texts) {
          calls++;
          return pending.future;
        },
        cancel: () => cancellations++);
    final source = _lrc([for (var i = 0; i < 18; i++) '漢かな$i']);
    final result =
        projector.project(source, enabled: true, stillCurrent: () => true);
    expect(calls, 1);
    projector.cancel();
    pending.complete(_read([for (var i = 0; i < 16; i++) '漢かな$i']));
    expect((await result).result, JapaneseReadingResult.stale);
    expect(calls, 1);
    expect(cancellations, 1);
    expect(projector.cachedEntries, 0);
  });

  test('new source owns results when old analyzer finishes after retarget',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    final projector = JapaneseReadingProjector(
        analyze: (texts) =>
            texts.single == '漢か' ? pending.future : Future.value(_read(texts)));
    final old = projector.project(_lrc(['漢か']),
        enabled: true, stillCurrent: () => true);
    final current = await projector.project(_lrc(['漢き']),
        enabled: true, stillCurrent: () => true);
    pending.complete(_read(['漢か']));
    expect((await old).result, JapaneseReadingResult.stale);
    expect(current.lyric.lines.single.japaneseReading, 'かんき');
    expect(projector.cachedEntries, 1);
  });

  test('unavailable analyzer and whole-source budget never publish a prefix',
      () async {
    var calls = 0;
    final projector = JapaneseReadingProjector(
        analyze: (_) async {
          calls++;
          return const JapanesePhoneticBatch([], available: false);
        },
        maximumInputUnits: 20);
    final source = _lrc(['漢かな']);
    final unavailable = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(unavailable.result, JapaneseReadingResult.unavailable);
    expect(unavailable.lyric, same(source));
    final huge = _lrc(['漢かな', 'x' * 30]);
    final rejected =
        await projector.project(huge, enabled: true, stillCurrent: () => true);
    expect(rejected.result, JapaneseReadingResult.tooLarge);
    expect(rejected.lyric, same(huge));
    expect(calls, 1);
  });
}
