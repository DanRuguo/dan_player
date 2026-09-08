import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:dan_player/page/settings_page/rendering_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/l10n/catalog_rendering.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old and malformed preferences default on; only a bool opts out', () {
    for (final raw in [
      null,
      false,
      0,
      [],
      {},
      {'pauseWhenHidden': 'false'},
      {'pauseWhenHidden': 0},
      {'pauseWhenHidden': null}
    ]) {
      expect(RenderingPreferences.fromMap(raw), const RenderingPreferences());
    }
    for (final pause in [true, false]) {
      final value = RenderingPreferences(pauseWhenHidden: pause);
      expect(RenderingPreferences.fromMap(value.toMap()), value);
      expect(value.copyWith(), value);
      expect(value.copyWith(pauseWhenHidden: !pause).pauseWhenHidden, !pause);
      expect(
          value.hashCode, RenderingPreferences.fromMap(value.toMap()).hashCode);
    }
  });

  testWidgets('lyrics spectrum can be disabled without creating audio',
      (tester) async {
    final prefs =
        ValueNotifier(const RenderingPreferences(lyricSpectrum: false));
    addTearDown(prefs.dispose);
    expect(
        RenderingPreferences.fromMap(prefs.value.toMap()).lyricSpectrum, false);
    expect(
        RenderingPreferences.fromMap({'lyricSpectrum': 'false'}).lyricSpectrum,
        true);
    await tester.pumpWidget(RenderingPreferencesScope(
        preferences: prefs,
        child: const MaterialApp(
            home: SpectrumProgressSection(
                spectrum: LyricPageSpectrum(height: 42),
                progress: Text('progress')))));
    expect(find.byType(FullWidthSpectrum), findsNothing);
    expect(find.text('progress'), findsOneWidget);
    expect(PlayService.isInitialized, false);
  });

  test('opt-out bypasses visibility but never paused or detached lifecycle',
      () {
    for (final pause in [true, false]) {
      final prefs = RenderingPreferences(pauseWhenHidden: pause);
      for (final lifecycle in [null, ...AppLifecycleState.values]) {
        final hardStop = lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.detached;
        final foreground =
            lifecycle == null || lifecycle == AppLifecycleState.resumed;
        expect(prefs.allowsVisualUpdates(lifecycle: lifecycle),
            !hardStop && (!pause || foreground));
        expect(
            prefs.allowsVisualUpdates(
                lifecycle: lifecycle, treeVisible: false, nativeHidden: true),
            !hardStop && !pause);
      }
    }
  });

  test('new setting has complete independent four-language messages', () {
    for (final entry in catalogRendering.entries) {
      expect(entry.value, hasLength(3));
      for (final language in UiLanguage.values) {
        final translated = translateUi(entry.key, language);
        expect(translated, isNotEmpty);
        if (language != UiLanguage.zh) expect(translated, isNot(entry.key));
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets('${language.code} rendering switch fits 320px at 200% text',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var value = const RenderingPreferences();
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
                body: SingleChildScrollView(
              child: StatefulBuilder(
                  builder: (context, setState) => RenderingSettings(
                        value: value,
                        onChanged: (next) => setState(() => value = next),
                      )),
            ))),
      )));
      expect(find.text(translateUi('不可见时暂停视觉更新', language)), findsOneWidget);
      final toggle = find.descendant(
          of: find.byKey(const ValueKey('pause-hidden-visuals')),
          matching: find.byType(Switch));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(value.pauseWhenHidden, isFalse);
      expect(tester.takeException(), isNull);
      expect(PlayService.isInitialized, isFalse);
    });
  }

  testWidgets(
      'interface persists rendering immediately and reports save failure',
      (tester) async {
    final original = AppSettings.instance.rendering.value;
    addTearDown(() => AppSettings.instance.rendering.value = original);
    AppSettings.instance.rendering.value = const RenderingPreferences();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: InterfaceSettings(persist: () async {
        calls++;
        if (calls == 1) throw StateError('Synthetic save failure');
      })),
    )));
    final toggle = find.descendant(
        of: find.byKey(const ValueKey('pause-hidden-visuals')),
        matching: find.byType(Switch));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.rendering.value.pauseWhenHidden, isFalse);
    expect(calls, 1);
    expect(find.text('保存界面设置失败；本次会话仍然有效。'), findsOneWidget);
    final retry = find.text('重试');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('保存界面设置失败；本次会话仍然有效。'), findsNothing);
    expect(AppSettings.instance.rendering.value.pauseWhenHidden, isFalse);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });
}
