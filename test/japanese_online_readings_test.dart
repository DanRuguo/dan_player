import 'dart:async';
import 'dart:convert';

import 'package:dan_player/lyric/japanese_online_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reply(Map<String, dynamic> body, List words) => {
      'jsonrpc': '2.0',
      'id': body['id'],
      'result': {'word': words},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online protocol packs lines and preserves subword source alignment',
      () async {
    var calls = 0;
    final adapter =
        JapaneseOnlineReadingAnalyzer(request: (body, key, active) async {
      calls++;
      expect(key, 'local-client');
      expect(active(), isTrue);
      expect(body['method'], 'jlp.furiganaservice.furigana');
      expect(body['params'], {'q': '歌う夜空\nかなカナ🙂', 'grade': 1});
      return reply(body, [
        {
          'surface': '歌う',
          'furigana': 'うたう',
          'subword': [
            {'surface': '歌', 'furigana': 'うた'},
            {'surface': 'う', 'furigana': 'う'}
          ]
        },
        {'surface': '夜空', 'furigana': 'よぞら'},
        {'surface': 'かなカナ🙂'},
      ]);
    });
    final got = await adapter.analyze(['歌う夜空', 'かなカナ🙂'],
        clientId: 'local-client', stillCurrent: () => true);
    expect(got.available, isTrue);
    expect(calls, 1);
    expect(got.words[0]!.map((w) => '${w.text}:${w.reading}'),
        ['歌:うた', 'う:う', '夜空:よぞら']);
    expect(got.words[1]!.single.text, 'かなカナ🙂');
    expect(got.cacheNamespace, startsWith('online/'));
    expect(got.cacheNamespace, isNot(contains('local-client')));
  });

  test('online bodies stay under the documented 4 KiB byte limit', () async {
    var calls = 0;
    final adapter =
        JapaneseOnlineReadingAnalyzer(request: (body, _, active) async {
      calls++;
      expect(utf8.encode(jsonEncode(body)).length, lessThanOrEqualTo(4096));
      final q = (body['params'] as Map)['q'] as String;
      return reply(body, [
        for (final text in q.split('\n')) {'surface': text}
      ]);
    });
    final chunks = List.generate(16, (i) => '${'漢' * 99}$i'.substring(0, 100));
    final result = await adapter.analyze(chunks,
        clientId: 'key', stillCurrent: () => true);
    expect(result.available, isTrue);
    expect(result.words.map((row) => row!.map((w) => w.text).join()), chunks);
    expect(calls, 2);
  });

  test('omitted whitespace remains literal and never changes offsets',
      () async {
    final adapter = JapaneseOnlineReadingAnalyzer(
        request: (body, _, active) async => reply(body, [
              {'surface': '夜', 'furigana': 'よる'},
              {'surface': '空', 'furigana': 'そら'}
            ]));
    final result = await adapter
        .analyze([' 夜 ', ' 空 '], clientId: 'key', stillCurrent: () => true);
    expect(result.available, isTrue);
    expect(result.words.map((row) => row!.map((w) => w.text).join()),
        [' 夜 ', ' 空 ']);
    expect(result.words.first![1].reading, 'よる');
  });

  for (final defect in ['source', 'id', 'error', 'reading', 'subword']) {
    test('online rejects $defect mismatch rather than inventing ruby',
        () async {
      final adapter =
          JapaneseOnlineReadingAnalyzer(request: (body, _, active) async {
        final response = reply(body, [
          {'surface': '夜空', 'furigana': 'よぞら'}
        ]);
        switch (defect) {
          case 'source':
            response['result'] = {
              'word': [
                {'surface': '別', 'furigana': 'べつ'}
              ]
            };
          case 'id':
            response['id'] = 'obsolete';
          case 'error':
            response['error'] = {'code': -1};
          case 'reading':
            response['result'] = {
              'word': [
                {'surface': '夜空', 'furigana': '<bad>'}
              ]
            };
          case 'subword':
            response['result'] = {
              'word': [
                {
                  'surface': '夜空',
                  'subword': [
                    {'surface': '空'}
                  ]
                }
              ]
            };
        }
        return response;
      });
      expect(
          (await adapter
                  .analyze(['夜空'], clientId: 'key', stillCurrent: () => true))
              .available,
          isFalse);
    });
  }

  test('cancelled and revoked requests cannot publish or start further groups',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    Map<String, dynamic>? body;
    var allowed = true, calls = 0;
    final adapter = JapaneseOnlineReadingAnalyzer(request: (next, _, active) {
      body = next;
      calls++;
      return pending.future;
    });
    final future =
        adapter.analyze(['夜空'], clientId: 'key', stillCurrent: () => allowed);
    allowed = false;
    adapter.cancel();
    pending.complete(reply(body!, [
      {'surface': '夜空', 'furigana': 'よぞら'}
    ]));
    expect((await future).available, isFalse);
    expect(calls, 1);
  });

  test('one total deadline bounds an unresponsive reading service', () async {
    final adapter = JapaneseOnlineReadingAnalyzer(
        timeout: const Duration(milliseconds: 20),
        request: (_, __, ___) => Completer<Map<String, dynamic>>().future);
    expect(
        (await adapter
                .analyze(['夜空'], clientId: 'key', stillCurrent: () => true))
            .available,
        isFalse);
  });

  test('local settings roundtrip and discard invalid legacy header identifiers',
      () {
    const prefs = JapaneseReadingPreferences(
        enabled: true, yahooClientId: 'local-client', lastManualMode: 'online');
    expect(JapaneseReadingPreferences.fromJson(prefs.toJson()), prefs);
    for (final bad in ['two words', 'bad\r\nheader', '日本', 'k' * 2049]) {
      expect(
          JapaneseReadingPreferences.fromJson(
              {'yahooClientId': bad, 'lastManualMode': 'bogus'}).yahooClientId,
          '');
    }
    expect(
        JapaneseReadingPreferences.fromJson(const {'lastManualMode': 'bogus'})
            .lastManualMode,
        'offline');
    expect(prefs.copyWith(yahooClientId: '').enabled, isTrue);
  });

  test(
      'global gate blocks automatic work but permits each explicit manual method',
      () async {
    var onlineCalls = 0, offlineCalls = 0, inspections = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => false,
        clientId: () => 'key',
        offline: (chunks) async {
          offlineCalls++;
          return const JapanesePhoneticBatch([
            [JapanesePhoneticWord('夜空', 'よぞら')]
          ]);
        },
        cancelOffline: () {},
        hasDictionary: () async {
          inspections++;
          return true;
        },
        online: JapaneseOnlineReadingAnalyzer(request: (body, _, active) async {
          onlineCalls++;
          return reply(body, [
            {'surface': '夜空', 'furigana': 'よぞら'}
          ]);
        }));
    expect((await policy.analyze(['夜空'])).available, isFalse);
    expect([onlineCalls, offlineCalls, inspections], [0, 0, 0]);
    expect(
        (await policy
                .analyzeWithMode(['夜空'], JapaneseReadingRequestMode.online))
            .available,
        isTrue);
    expect(
        (await policy
                .analyzeWithMode(['夜空'], JapaneseReadingRequestMode.offline))
            .available,
        isTrue);
    expect([onlineCalls, offlineCalls, inspections], [1, 1, 1]);
    policy.dispose();
  });

  test('online failure falls back offline or identifies missing component',
      () async {
    var dictionary = true, offlineCalls = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => true,
        clientId: () => 'key',
        offline: (_) async {
          offlineCalls++;
          return const JapanesePhoneticBatch([]);
        },
        cancelOffline: () {},
        hasDictionary: () async => dictionary,
        online: JapaneseOnlineReadingAnalyzer(
            request: (_, __, ___) async => throw StateError('fixture')));
    expect((await policy.analyze(['夜空'])).available, isTrue);
    dictionary = false;
    expect((await policy.analyze(['夜空'])).dictionaryMissing, isTrue);
    expect(offlineCalls, 1);
    policy.dispose();
  });

  test(
      'closing the global gate mid response never starts offline automatic work',
      () async {
    var permitted = true, inspections = 0, offlineCalls = 0;
    final pending = Completer<Map<String, dynamic>>();
    Map<String, dynamic>? body;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => permitted,
        clientId: () => 'key',
        offline: (_) async {
          offlineCalls++;
          return const JapanesePhoneticBatch([]);
        },
        cancelOffline: () {},
        hasDictionary: () async {
          inspections++;
          return true;
        },
        online: JapaneseOnlineReadingAnalyzer(request: (next, _, active) {
          body = next;
          return pending.future;
        }));
    final future = policy.analyze(['夜空']);
    permitted = false;
    pending.complete(reply(body!, [
      {'surface': '夜空', 'furigana': 'よぞら'}
    ]));
    expect((await future).available, isFalse);
    expect([inspections, offlineCalls], [0, 0]);
    policy.dispose();
  });

  test(
      'explicit online requires configured ID and cannot reinterpret remembered mode',
      () async {
    var calls = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => false,
        clientId: () => '',
        offline: (_) async {
          calls++;
          return const JapanesePhoneticBatch([]);
        },
        cancelOffline: () {},
        hasDictionary: () async => true);
    expect(
        (await policy
                .analyzeWithMode(['夜空'], JapaneseReadingRequestMode.online))
            .available,
        isFalse);
    expect((await policy.analyze(['夜空'])).available, isFalse);
    expect(calls, 0);
    policy.dispose();
  });
}
