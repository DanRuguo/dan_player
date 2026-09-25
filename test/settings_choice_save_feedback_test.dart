import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: UiLanguageScope(
        child: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [child]),
        ),
      ),
    );

Future<void> _retry(WidgetTester tester, String key) async {
  final feedback = find.byKey(ValueKey(key));
  expect(feedback, findsOneWidget);
  expect(
      find.descendant(of: feedback, matching: find.text('设置保存失败，本次会话仍保留当前选择')),
      findsOneWidget);
  await tester.tap(find.descendant(
      of: feedback, matching: find.widgetWithText(TextButton, '重试保存')));
  await tester.pump();
  expect(feedback, findsNothing);
}

void main() {
  test('new settings guidance has English, Japanese and Korean copy', () {
    for (final original in [
      '单项开关只控制对应动画；全部开关还会同步调整频谱、背景动效与低频律动、歌词回弹。播放、点击、拖动和实时进度不受影响。',
      '仅决定下次加载时本地与在线歌词的优先顺序；当前歌曲不会立即换词，可手动指定默认歌词。',
      '设置保存失败；请检查当前设置并重试。',
      '设置仍在变化，请稍后重试。',
    ]) {
      for (final language
          in UiLanguage.values.where((l) => l != UiLanguage.zh)) {
        expect(translateUi(original, language), isNot(original),
            reason: '${language.code}: $original');
      }
    }
  });

  testWidgets('automatic online search keeps a failed choice and retries it',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.automaticOnlineLyrics.value;
    addTearDown(() => settings.automaticOnlineLyrics.value = previous);
    settings.automaticOnlineLyrics.value = false;
    var attempts = 0;
    await tester
        .pumpWidget(_host(AutomaticOnlineLyricsSwitch(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(settings.automaticOnlineLyrics.value, isTrue);
    await _retry(tester, 'automatic-online-save-failure');
    expect(attempts, 2);
  });

  testWidgets(
      'an older failed choice cannot report an error after a newer save',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.automaticOnlineLyrics.value;
    addTearDown(() => settings.automaticOnlineLyrics.value = previous);
    settings.automaticOnlineLyrics.value = false;
    final first = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(_host(AutomaticOnlineLyricsSwitch(persist: () {
      return ++attempts == 1 ? first.future : Future<void>.value();
    })));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    first.completeError(StateError('older write failed'));
    await tester.pump();
    expect(settings.automaticOnlineLyrics.value, isFalse);
    expect(find.byKey(const ValueKey('automatic-online-save-failure')),
        findsNothing);
    expect(attempts, 2);
  });

  testWidgets('session restore choice shows a retry without rolling back',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.restoreLastSession;
    addTearDown(() => settings.restoreLastSession = previous);
    settings.restoreLastSession = false;
    var attempts = 0;
    await tester.pumpWidget(_host(RestoreSessionSwitch(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(settings.restoreLastSession, isTrue);
    await _retry(tester, 'restore-session-save-failure');
    expect(attempts, 2);
  });

  testWidgets('lyric priority explains deferred effect and retries save',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.localLyricFirst;
    addTearDown(() => settings.localLyricFirst = previous);
    settings.localLyricFirst = true;
    var attempts = 0;
    await tester.pumpWidget(_host(DefaultLyricSourceControl(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    expect(find.textContaining('当前歌曲不会立即换词'), findsOneWidget);
    tester
        .widget<AppSegmentedControl<bool>>(
            find.byType(AppSegmentedControl<bool>))
        .onChanged!(false);
    await tester.pump();
    expect(settings.localLyricFirst, isFalse);
    await _retry(tester, 'lyric-source-save-failure');
    expect(attempts, 2);
  });

  testWidgets('dynamic color reports a failed save and permits retry',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.dynamicTheme;
    addTearDown(() {
      settings.dynamicTheme = previous;
      ThemeProvider.instance.syncDynamicThemeSetting();
    });
    settings.dynamicTheme = false;
    var attempts = 0;
    await tester.pumpWidget(_host(DynamicThemeSwitch(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(settings.dynamicTheme, isTrue);
    await _retry(tester, 'dynamic-theme-save-failure');
    expect(attempts, 2);
  });

  testWidgets('lyric API never reports success before a durable save',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.lyricApiUrl;
    addTearDown(() => settings.lyricApiUrl = previous);
    settings.lyricApiUrl = null;
    var attempts = 0;
    await tester.pumpWidget(_host(LyricApiEditor(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    await tester.tap(find.text('设置接口'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '接口地址'), 'https://example.com/api');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(settings.lyricApiUrl, 'https://example.com/api');
    expect(find.text('歌词API已更新'), findsNothing);
    await _retry(tester, 'lyric-api-save-failure');
    expect(attempts, 2);
  });

  testWidgets('theme color keeps session choice when save fails',
      (tester) async {
    final settings = AppSettings.instance;
    final previous = settings.defaultTheme;
    addTearDown(() {
      settings.defaultTheme = previous;
      ThemeProvider.instance.applyTheme(seedColor: Color(previous));
    });
    var attempts = 0;
    await tester.pumpWidget(_host(ThemeSelector(persist: () async {
      if (++attempts == 1) throw StateError('disk full');
    })));
    await tester.tap(find.text('主题选择器'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('theme-hex-input')), '#123456');
    await tester.tap(find.byKey(const ValueKey('theme-confirm')));
    await tester.pumpAndSettle();
    expect(settings.defaultTheme, const Color(0xff123456).toARGB32());
    await _retry(tester, 'theme-color-save-failure');
    expect(attempts, 2);
  });

  testWidgets('save failure message is a live region in narrow layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(SettingsSaveFeedback(onRetry: () {})));
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widgetList<Semantics>(find.descendant(
                of: find.byType(SettingsSaveFeedback),
                matching: find.byType(Semantics)))
            .any((semantics) => semantics.properties.liveRegion == true),
        isTrue);
  });
}
