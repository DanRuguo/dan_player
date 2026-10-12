import 'dart:async';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Object response(String text) => {
      'available': true,
      'chunks': [
        [
          {'text': text, 'reading': 'かん'}
        ]
      ]
    };
Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('test/japanese/ownership');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  test('playback interrupts and resumes valid background reading ownership',
      () async {
    final calls = <String>[];
    Completer<Object?>? active;
    messenger.setMockMethodCallHandler(method, (call) {
      if (call.method == 'cancel') {
        calls.add('cancel');
        active!.complete({'available': false});
        return Future.value(null);
      }
      final text = ((call.arguments as Map)['chunks'] as List).single as String;
      calls.add(text);
      active = Completer<Object?>();
      return active!.future;
    });
    final foreground =
        JapanesePhoneticChannel(channel: method, supported: true);
    final background = JapanesePhoneticChannel(foreground: foreground);
    final bulk = background.analyze(['漢bulk']);
    await drain();
    final playback = foreground.analyze(['漢play']);
    await drain();
    expect(calls, ['漢bulk', 'cancel', '漢play']);
    active!.complete(response('漢play'));
    expect((await playback).words.single!.single.text, '漢play');
    await drain();
    expect(calls.last, '漢bulk');
    active!.complete(response('漢bulk'));
    expect((await bulk).words.single!.single.text, '漢bulk');
    expect(calls.where((value) => value == 'cancel').length, 1);
  });

  test('cancelling pending bulk never cancels active playback', () async {
    final pending = Completer<Object?>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(method, (call) {
      calls.add(call.method);
      return call.method == 'analyze' ? pending.future : Future.value(null);
    });
    final foreground =
        JapanesePhoneticChannel(channel: method, supported: true);
    final background = JapanesePhoneticChannel(foreground: foreground);
    final playing = foreground.analyze(['漢']);
    await drain();
    final bulk = background.analyze(['漢bulk']);
    background.cancel();
    expect((await bulk).available, isFalse);
    pending.complete(response('漢'));
    expect((await playing).available, isTrue);
    expect(calls, ['analyze']);
  });

  test('rapid playback retarget keeps only latest pending native invocation',
      () async {
    final pending = Completer<Object?>();
    final texts = <String>[];
    messenger.setMockMethodCallHandler(method, (call) {
      expect(call.method, 'analyze');
      final text = ((call.arguments as Map)['chunks'] as List).single as String;
      texts.add(text);
      return text == '漢old' ? pending.future : Future.value(response(text));
    });
    final foreground =
        JapanesePhoneticChannel(channel: method, supported: true);
    final old = foreground.analyze(['漢old']);
    await drain();
    final middle = foreground.analyze(['漢middle']);
    final latest = foreground.analyze(['漢latest']);
    expect((await old).available, isFalse);
    expect((await middle).available, isFalse);
    expect((await latest).words.single!.single.text, '漢latest');
    expect(texts, ['漢old', '漢latest']);
    pending.complete(response('漢old'));
    await drain();
  });

  test(
      'dictionary path is injected and missing component status survives decode',
      () async {
    messenger.setMockMethodCallHandler(method, (call) async {
      expect(call.arguments, {
        'chunks': ['漢'],
        'dictionaryPath': 'J:/qa/dictionary.bin.gz'
      });
      return {
        'available': true,
        'dictionaryMissing': true,
        'chunks': [null]
      };
    });
    final channel = JapanesePhoneticChannel(
        channel: method,
        supported: true,
        dictionaryPath: () async => 'J:/qa/dictionary.bin.gz');
    final result = await channel.analyze(['漢']);
    expect(result.dictionaryMissing, isTrue);
    expect(result.words.single, isNull);
  });
}
