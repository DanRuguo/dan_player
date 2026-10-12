import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authored romaji survives independent generated reading and Han spans',
      () async {
    final source = Lrc([
      LrcLine(Duration.zero, '😀明日カタカナと会える', isBlank: false)
        ..romanization = 'ashita katakana to aeru'
    ], LrcSource.local);
    final projector = JapaneseReadingProjector(
        analyze: (_) async => const JapanesePhoneticBatch([
              [
                JapanesePhoneticWord('😀', 'changed'),
                JapanesePhoneticWord('明日', 'あした'),
                JapanesePhoneticWord('カタカナと', 'かたかなと'),
                JapanesePhoneticWord('会える', 'あえる'),
              ]
            ]));
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    final line = result.lyric.lines.single;
    expect(line.romanization, 'ashita katakana to aeru');
    expect(line.japaneseReading, '😀あしたカタカナとあえる');
    expect(
        line.japaneseReadingSpans
            .map((span) => [span.start, span.end, span.text]),
        [
          [2, 4, 'あした'],
          [9, 10, 'あ']
        ]);
    expect(source.lines.single.japaneseReading, isNull);
    expect(source.lines.single.japaneseReadingSpans, isEmpty);
    final saved = LyricSnapshot.capture(result.lyric).toJson();
    expect(saved.toString(), isNot(contains('japaneseReading')));
    expect(LyricSnapshot.fromJson(saved)!.toLyric().lines.single.romanization,
        line.romanization);
  });

  test('matching authored kana suppresses duplicate generated annotation',
      () async {
    final source = Lrc([
      LrcLine(Duration.zero, '日本語かな', isBlank: false)..romanization = 'ニホンゴカナ'
    ], LrcSource.local);
    final projector = JapaneseReadingProjector(
        analyze: (_) async => const JapanesePhoneticBatch([
              [
                JapanesePhoneticWord('日本語', 'にほんご'),
                JapanesePhoneticWord('かな', 'かな'),
              ]
            ]));
    final result = await projector.project(source,
        enabled: true, stillCurrent: () => true);
    expect(result.result, JapaneseReadingResult.unchanged);
    expect(result.lyric, same(source));
    expect(source.lines.single.romanization, 'ニホンゴカナ');
  });

  test(
      'ruby kana anchors align complete Han groups and reject ambiguous splits',
      () {
    final spans = japaneseReadingWordSpans('お食べ物', 'おたべもの', offset: 3);
    expect(spans.map((span) => [span.start, span.end, span.text]), [
      [4, 5, 'た'],
      [6, 7, 'もの']
    ]);
    expect(japaneseReadingWordSpans('漢か字', 'あかかい'), isEmpty);
    expect(japaneseReadingWordSpans('カナ', 'かな'), isEmpty);
    expect(japaneseReadingWordSpans('𱍐', '𱍐'), isEmpty);
    expect(japaneseReadingWordSpans('一\ufe0f', 'いち').single.end, 2);
    expect(japaneseReadingWordSpans('𠀀', 'いい').single.end, 2);
  });

  test('missing offline component remains a distinct retriable result',
      () async {
    final source =
        Lrc([LrcLine(Duration.zero, '漢かな', isBlank: false)], LrcSource.local);
    final projector = JapaneseReadingProjector(
        analyze: (_) async =>
            const JapanesePhoneticBatch([null], dictionaryMissing: true));
    expect(
        (await projector.project(source,
                enabled: true, stillCurrent: () => true))
            .result,
        JapaneseReadingResult.dictionaryMissing);
    expect(projector.cachedEntries, 0);
  });
}
