import 'dart:async';

import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/japanese_online_reading_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/japanese_reading_ui_fixture.dart';

const _open = ValueKey('japanese-online-configure');
const _dialog = ValueKey('japanese-online-dialog');
const _field = ValueKey('japanese-online-client-id');
const _save = ValueKey('japanese-online-save');
const _cancel = ValueKey('japanese-online-cancel');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UiLanguage previousLanguage;
  late ValueNotifier<JapaneseReadingPreferences> preferences;
  var saves = 0;
  late List<String> urls;
  setUpAll(setUpJapaneseUiFixture);
  tearDownAll(tearDownJapaneseUiFixture);
  setUp(() {
    previousLanguage = uiLanguage.value;
    preferences = ValueNotifier(const JapaneseReadingPreferences());
    saves = 0;
    urls = [];
  });
  tearDown(() {
    preferences.dispose();
    uiLanguage.value = previousLanguage;
  });

  Widget settings({Future<void> Function()? persist}) =>
      JapaneseOnlineReadingSettings(
          preferences: preferences,
          persist: persist ??
              () async {
                saves++;
              },
          openUrl: (url) async {
            urls.add(url);
          });

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_open));
    await tester.tap(find.byKey(_open));
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsOneWidget);
  }

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'Japanese online ${language.code} ${size.$1} ${size.$2} keeps complete local configuration',
          (tester) async {
        final boundary = GlobalKey();
        await mountJapaneseUi(tester, settings(),
            language: language,
            width: size.$1,
            scale: size.$2,
            boundary: boundary);
        await open(tester);
        await captureJapaneseUi(tester, boundary,
            'online-${language.code}-${size.$1.toInt()}-${size.$2.toInt()}');
        await expectJapaneseUiText(tester, find.byKey(_dialog));
        expect(
            tester.widget<TextField>(find.byKey(_field)).obscureText, isTrue);
        expect(find.text('Web Services by Yahoo! JAPAN'), findsOneWidget);
        expect(saves, 0);
        expect(urls, isEmpty);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.ensureVisible(find.byKey(_cancel));
        await tester.tap(find.byKey(_cancel));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'Japanese online cancel and clear remain drafts until explicit save',
      (tester) async {
    preferences.value = const JapaneseReadingPreferences(
        enabled: true,
        yahooClientId: 'original-fixture',
        lastManualMode: 'online');
    await mountJapaneseUi(tester, settings());
    await open(tester);
    expect(tester.widget<TextField>(find.byKey(_field)).controller!.text,
        'original-fixture');
    await tester.tap(find.byKey(const ValueKey('japanese-online-visibility')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(_field)).obscureText, isFalse);
    await tester.enterText(find.byKey(_field), 'cancelled-fixture');
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    expect(preferences.value.yahooClientId, 'original-fixture');
    expect(saves, 0);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('japanese-online-clear')));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byKey(_field)).controller!.text, isEmpty);
    expect(preferences.value.yahooClientId, 'original-fixture');
    await tester.tap(find.byKey(_save));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(preferences.value.yahooClientId, isEmpty);
    expect(preferences.value.enabled, isTrue);
    expect(preferences.value.lastManualMode, 'online');
    expect(find.byKey(_dialog), findsNothing);
  });

  testWidgets(
      'Japanese online invalid input and failed save preserve a retryable draft',
      (tester) async {
    await mountJapaneseUi(tester, settings(persist: () async {
      saves++;
      if (saves == 1) throw StateError('fixture save failure');
    }));
    await open(tester);
    await tester.enterText(find.byKey(_field), '日本語');
    await tester.tap(find.byKey(_save));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(preferences.value.yahooClientId, isEmpty);
    expect(find.byKey(const ValueKey('japanese-online-error')), findsOneWidget);
    await tester.enterText(find.byKey(_field), 'valid-fixture');
    await tester.tap(find.byKey(_save));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byKey(_dialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_field)).controller!.text,
        'valid-fixture');
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNotNull);
    await tester.tap(find.byKey(_save));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(preferences.value.yahooClientId, 'valid-fixture');
    expect(urls, isEmpty);
    expect(find.byKey(_dialog), findsNothing);
  });

  testWidgets(
      'Japanese online saving is single flight and late completion leaves new route',
      (tester) async {
    final completion = Completer<void>();
    final navigator = GlobalKey<NavigatorState>();
    await mountJapaneseUi(tester, settings(persist: () {
      saves++;
      return completion.future;
    }), navigator: navigator, reduced: false);
    await open(tester);
    await tester.enterText(find.byKey(_field), 'pending-fixture');
    final save = tester.widget<FilledButton>(find.byKey(_save)).onPressed!;
    save();
    save();
    expect(saves, 1);
    navigator.currentState!.pop();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Text('New credential page fixture'))));
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('New credential page fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese online links use official registration and exact attribution',
      (tester) async {
    await mountJapaneseUi(tester, settings());
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('japanese-online-register')));
    await tester.tap(find.byKey(const ValueKey('japanese-online-attribution')));
    expect(urls, [
      'https://e.developer.yahoo.co.jp/register',
      'https://developer.yahoo.co.jp/sitemap/'
    ]);
    expect(saves, 0);
    expect(preferences.value.yahooClientId, isEmpty);
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
  });
}
