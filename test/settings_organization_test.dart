import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/page/settings_page/rendering_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/l10n/catalog_settings_organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new setting labels have all four language variants', () {
    for (final key in catalogSettingsOrganization.keys) {
      for (final language in UiLanguage.values) {
        final result = translateUi(key, language);
        expect(result, isNotEmpty);
        if (language != UiLanguage.zh) expect(result, isNot(key));
      }
    }
  });

  testWidgets('split sections keep common controls first and all theme actions',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    final groups = tester.widget<GroupedSettings>(find.byType(GroupedSettings));
    expect(groups.sections.map((section) => section.id), [
      'library',
      'lyrics',
      'appearance',
      'effects',
      'desktop',
      'backup',
      'about'
    ]);
    final appearance =
        groups.sections.singleWhere((section) => section.id == 'appearance');
    expect(appearance.children.first, isA<InterfaceSettings>());
    expect((appearance.children.first as InterfaceSettings).group,
        InterfaceSettingsGroup.language);
    await tester
        .tap(find.byKey(const ValueKey('settings-category-appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeModeControl), findsOneWidget);
    expect(find.byType(ThemeSelector), findsOneWidget);
    expect(find.byType(DynamicThemeSwitch), findsOneWidget);
    expect(find.byType(RenderingSettings), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-category-effects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('surface-blur')), findsOneWidget);
    final lyric = find.byKey(const ValueKey('lyric-spectrum'));
    final compact = find.byKey(const ValueKey('compact-spectrum'));
    expect(
        tester.element(
            find.ancestor(of: lyric, matching: find.byType(SettingsSurface))),
        same(tester.element(find.ancestor(
            of: compact, matching: find.byType(SettingsSurface)))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('visual controls update independently and retry a failed save',
      (tester) async {
    final previous = AppSettings.instance.rendering.value;
    AppSettings.instance.rendering.value = const RenderingPreferences();
    addTearDown(() => AppSettings.instance.rendering.value = previous);
    var fail = true;
    var writes = 0;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: VisualEffectsSettings(persist: () async {
        writes++;
        if (fail) throw StateError('fixture failure');
      }),
    ))));
    await tester.pumpAndSettle();
    final lyric = tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('lyric-spectrum')));
    lyric.onChanged!(false);
    await tester.pumpAndSettle();
    final preferences = AppSettings.instance.rendering.value;
    expect(preferences.lyricSpectrum, isFalse);
    expect(preferences.compactSpectrum, isTrue);
    expect(preferences.surfaceBlur, isTrue);
    final density = tester.widget<AppSegmentedControl<SpectrumDensity>>(
        find.byKey(const ValueKey('spectrum-density')));
    expect(density.onChanged, isNull);
    expect(find.text('保存界面设置失败；本次会话仍然有效。'), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(find.text('保存界面设置失败；本次会话仍然有效。'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
