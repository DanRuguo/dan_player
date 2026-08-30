import 'dart:convert';

import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/l10n/catalog_tray.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('tray radius is additive, finite, bounded and does not change opacity',
      () {
    expect(PlayerExperiencePreferences.fromMap(null).trayMenuBlurRadius, 0);
    for (final (raw, expected) in <(Object?, double)>[
      (null, 0),
      ('12', 0),
      (true, 0),
      (double.nan, 0),
      (double.infinity, 0),
      (double.negativeInfinity, 0),
      (-1, 0),
      (999, 24),
      (12.5, 12.5),
      (24, 24),
    ]) {
      final value = PlayerExperiencePreferences.fromMap({
        'trayMenuBlurRadius': raw,
        'playbackRate': 1.5,
        'taskbarControls': false,
      });
      expect(value.trayMenuBlurRadius, expected, reason: '$raw');
      expect(value.playbackRate, 1.5);
      expect(value.taskbarControls, false);
      expect(
          PlayerExperiencePreferences.fromMap(
              jsonDecode(jsonEncode(value.toMap()))),
          value);
    }
    const configured = PlayerExperiencePreferences(trayMenuBlurRadius: 12);
    expect(configured.copyWith(trayMenuBlurRadius: double.nan), configured);
    expect(configured.copyWith(), configured);
    expect(configured, isNot(const PlayerExperiencePreferences()));
    expect(configured.hashCode, configured.copyWith().hashCode);
    expect(
        PlayerExperiencePreferences.safeTrayMenuBlurRadius(null,
            fallback: double.nan),
        0);
    expect(
        const PlayerExperiencePreferences(trayMenuBlurRadius: double.nan)
            .copyWith()
            .trayMenuBlurRadius,
        0);
    expect(configured.copyWith(closeToTray: true).toMap(),
        {...configured.toMap(), 'closeToTray': true});
    expect(
        configured
            .toMap()
            .keys
            .any((key) => key.toLowerCase().contains('opacity')),
        false);
  });

  test(
      'radius initializes, coalesces separately from theme and stops on disposal',
      () async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value =
        rig.preferences.value.copyWith(trayMenuBlurRadius: 6);
    await rig.initialize();
    await flushDesktopEvents();
    expect(
        rig.native.calls
            .where((e) => e.$1 == 'configure')
            .single
            .$2!['trayMenuBlurRadius'],
        6);
    rig.preferences.value =
        rig.preferences.value.copyWith(trayMenuBlurRadius: 12);
    rig.preferences.value =
        rig.preferences.value.copyWith(trayMenuBlurRadius: 24);
    await flushDesktopEvents();
    final updates = rig.native.calls.where((e) => e.$1 == 'configure').toList();
    expect(updates, hasLength(2));
    expect(updates.last.$2!['trayMenuBlurRadius'], 24);
    expect(updates.last.$2!.containsKey('accent'), false);
    rig.preferences.value = rig.preferences.value.copyWith(closeToTray: true);
    await flushDesktopEvents();
    expect(rig.native.calls.where((e) => e.$1 == 'configure'), hasLength(2));
    await rig.integration.dispose();
    final count = rig.native.calls.length;
    rig.preferences.value =
        rig.preferences.value.copyWith(trayMenuBlurRadius: 0);
    await flushDesktopEvents();
    expect(rig.native.calls, hasLength(count));
  });

  Future<void> mount(WidgetTester tester, DesktopTestRig rig,
      {Future<void> Function()? persist,
      double width = 507,
      double scale = 1,
      Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = Size(width, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UiLanguageScope(
        child: ValueListenableBuilder<UiLanguage>(
            valueListenable: uiLanguage,
            builder: (context, language, _) => MaterialApp(
                locale: language.locale,
                supportedLocales:
                    UiLanguage.values.map((value) => value.locale),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.deepOrange, brightness: brightness)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: DesktopIntegrationSettings(
                            preferences: rig.preferences,
                            integration: rig.integration,
                            persist: persist ?? () async {})))))));
  }

  testWidgets(
      'drag saves only the committed value and preserves concurrent preferences',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    var saves = 0;
    await mount(tester, rig, persist: () async {
      saves++;
    });
    final finder = find.byKey(const ValueKey('tray-menu-blur-radius-setting'));
    var slider = tester.widget<Slider>(finder);
    for (var value = 1.0; value <= 24; value++) {
      slider.onChanged!(value);
    }
    await tester.pump();
    expect(saves, 0);
    expect(rig.preferences.value.trayMenuBlurRadius, 0);
    expect(tester.widget<Slider>(finder).value, 24);
    rig.preferences.value =
        rig.preferences.value.copyWith(taskbarSongPreview: false);
    slider = tester.widget<Slider>(finder);
    slider.onChangeEnd!(24);
    await tester.pump();
    expect(saves, 1);
    expect(rig.preferences.value.trayMenuBlurRadius, 24);
    expect(rig.preferences.value.taskbarSongPreview, false);
    expect(rig.playback.starts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed radius persistence is visible and does not undo the selection',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await mount(tester, rig,
        persist: () async => throw StateError('synthetic disk failure'));
    tester
        .widget<Slider>(
            find.byKey(const ValueKey('tray-menu-blur-radius-setting')))
        .onChangeEnd!(12);
    await tester.pump();
    expect(rig.preferences.value.trayMenuBlurRadius, 12);
    expect(find.textContaining('保存桌面设置失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'tray blur $language/$brightness at 320px and 200% stays themed and scrollable',
          (tester) async {
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        uiLanguage.value = language;
        await mount(tester, rig, width: 320, scale: 2, brightness: brightness);
        final slider =
            find.byKey(const ValueKey('tray-menu-blur-radius-setting'));
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        final context = tester.element(slider);
        final scheme = Theme.of(context).colorScheme;
        final sliderTheme = SliderTheme.of(context);
        expect(sliderTheme.thumbColor, scheme.primary);
        expect(sliderTheme.activeTrackColor, scheme.primary);
        expect(sliderTheme.valueIndicatorColor, scheme.primary);
        expect(sliderTheme.valueIndicatorTextStyle!.color, scheme.onPrimary);
        expect(
            sliderTheme.valueIndicatorTextStyle,
            Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onPrimary));
        expect(tester.getSize(slider).height, greaterThanOrEqualTo(44));
        final expected = language == UiLanguage.zh
            ? '托盘菜单高斯模糊'
            : uiCatalogTray['托盘菜单高斯模糊']![language.index - 1];
        expect(find.text(expected), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Exercise a real pointer gesture, not just the callback contract.
        await tester.tapAt(tester.getCenter(slider));
        await tester.pumpAndSettle();
        expect(rig.preferences.value.trayMenuBlurRadius, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
