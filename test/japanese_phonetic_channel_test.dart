import 'dart:async';

import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/japanese_phonetic');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  JapanesePhoneticChannel service() =>
      JapanesePhoneticChannel(channel: channel, supported: true);

  test('unsupported platform never invokes native channel', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) => throw StateError('unexpected channel'));
    final result =
        await JapanesePhoneticChannel(channel: channel, supported: false)
            .analyze(['漢']);
    expect(result.available, isFalse);
  });

  test('native request enforces finite chunk budget before dispatch', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    for (final chunks in [
      [''],
      ['漢' * 101],
      List.filled(17, '漢')
    ]) {
      await expectLater(service().analyze(chunks), throwsArgumentError);
    }
    expect(calls, 0);
  });

  test(
      'decoded native words keep full input and unavailable chunks independent',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'analyze');
      expect(call.arguments, {
        'chunks': ['漢字', '漢かな']
      });
      return {
        'available': true,
        'chunks': [
          [
            {'text': '漢字', 'reading': 'かんじ'}
          ],
          null,
        ],
      };
    });
    final result = await service().analyze(['漢字', '漢かな']);
    expect(result.available, isTrue);
    expect(result.words[0]!.single.text, '漢字');
    expect(result.words[0]!.single.reading, 'かんじ');
    expect(result.words[1], isNull);
  });

  test('malformed native response does not become a reading', () async {
    for (final response in [
      {'available': true, 'chunks': []},
      {
        'available': true,
        'chunks': [17]
      },
      {
        'available': true,
        'chunks': [
          [
            {'text': '', 'reading': 'x'}
          ]
        ]
      },
      {
        'available': true,
        'chunks': [
          [
            {'text': '漢', 'reading': 'a' * 2001}
          ]
        ]
      },
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect((await service().analyze(['漢'])).available, isFalse);
    }
  });

  test('native error cancels only its current request', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'analyze') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
    expect((await service().analyze(['漢'])).available, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['analyze', 'cancel']);
  });

  testWidgets('late old timeout cannot cancel a newer completed request',
      (tester) async {
    final pending = Completer<Object?>();
    var calls = 0, cancels = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'cancel') {
        cancels++;
        return Future.value(null);
      }
      calls++;
      if (calls == 1) return pending.future;
      return Future.value({
        'available': true,
        'chunks': [
          [
            {'text': '漢', 'reading': 'かん'}
          ]
        ]
      });
    });
    final bridge = service();
    final old = bridge.analyze(['漢']);
    await tester.pump();
    final current = await bridge.analyze(['漢']);
    expect(current.words.single!.single.reading, 'かん');
    await tester.pump(const Duration(seconds: 6));
    expect((await old).available, isFalse);
    expect(cancels, 0);
    pending.complete(null);
    await tester.pump();
  });
}
