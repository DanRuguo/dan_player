import 'dart:isolate';

import 'package:dan_player/src/bass/bass_player.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native configuration failure retains its type across the URL isolate',
      () async {
    await expectLater(
      Isolate.run<void>(() => throw const BassNetworkConfigurationException(
            BassNetworkConfigurationFailure.proxy,
            42,
          )),
      throwsA(isA<BassNetworkConfigurationException>()
          .having((error) => error.failure, 'failure',
              BassNetworkConfigurationFailure.proxy)
          .having((error) => error.errorCode, 'errorCode', 42)),
    );
  });

  test('proxy and timeout notices retain the BASS code in all UI languages',
      () {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    const expected = <UiLanguage, (String, String)>{
      UiLanguage.zh: ('无法设置联网音频代理（BASS 错误码 42）。', '无法设置联网音频超时（BASS 错误码 43）。'),
      UiLanguage.en: (
        'Could not configure the online audio proxy (BASS error 42).',
        'Could not configure the online audio timeout (BASS error 43).'
      ),
      UiLanguage.ja: (
        'オンライン音声のプロキシを設定できませんでした（BASS エラー 42）。',
        'オンライン音声のタイムアウトを設定できませんでした（BASS エラー 43）。'
      ),
      UiLanguage.ko: (
        '온라인 오디오 프록시를 설정할 수 없습니다(BASS 오류 42).',
        '온라인 오디오 제한 시간을 설정할 수 없습니다(BASS 오류 43).'
      ),
    };

    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      expect(
          bassNetworkConfigurationNotice(
              const BassNetworkConfigurationException(
                  BassNetworkConfigurationFailure.proxy, 42)),
          expected[language]!.$1);
      expect(
          bassNetworkConfigurationNotice(
              const BassNetworkConfigurationException(
                  BassNetworkConfigurationFailure.timeout, 43)),
          expected[language]!.$2);
    }
  });

  test('output mode failures show the translated cause in both notice paths',
      () {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    const cause = BassNetworkConfigurationException(
        BassNetworkConfigurationFailure.proxy, 42);
    const translatedCause = <UiLanguage, String>{
      UiLanguage.zh: '无法设置联网音频代理（BASS 错误码 42）。',
      UiLanguage.en:
          'Could not configure the online audio proxy (BASS error 42).',
      UiLanguage.ja: 'オンライン音声のプロキシを設定できませんでした（BASS エラー 42）。',
      UiLanguage.ko: '온라인 오디오 프록시를 설정할 수 없습니다(BASS 오류 42).',
    };

    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final restored in [true, false]) {
        final notice = bassOutputModeFailureNotice(cause, restored: restored);
        expect(notice, contains(translatedCause[language]));
        expect(notice, isNot(contains('BassNetworkConfigurationException')));
      }
    }
  });
}
