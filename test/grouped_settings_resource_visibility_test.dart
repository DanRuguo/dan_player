import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  testWidgets(
      'resource monitor stops on category exit even when hidden visuals stay active',
      (tester) async {
    uiLanguage.value = UiLanguage.zh;
    sizePlaylistFeature(tester, width: 1000, height: 1000);
    final rig = ResourceTestRig();
    final preferences =
        ValueNotifier(const ProcessResourcePreferences(enabled: true));
    final rendering =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    final hidden = ValueNotifier(false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      final closing = rig.close();
      await tester.pump();
      await closing;
      preferences.dispose();
      rendering.dispose();
      hidden.dispose();
    });

    const monitorKey = ValueKey('section-resource-monitor');
    final monitor = ProcessResourceMonitor(
        key: monitorKey,
        controller: rig.service,
        preferences: preferences,
        isHidden: hidden,
        onPreferencesChanged: (value) async => preferences.value = value);
    await tester.pumpWidget(listeningStatusHost(RenderingPreferencesScope(
        preferences: rendering,
        child: GroupedSettings(initialSection: 'backup', sections: [
          SettingsSection(
              id: 'backup',
              title: '备份与恢复',
              icon: Icons.backup_outlined,
              children: [monitor]),
          const SettingsSection(
              id: 'appearance',
              title: '外观',
              icon: Icons.palette_outlined,
              children: [Text('Other settings')]),
        ]))));
    await tester.pumpAndSettle();
    expect(rig.service.active, isTrue);
    expect(rig.calls.single.method, 'start');
    final oldSession = rig.session;
    await rig.sample();
    await tester.pump();
    final historyCount = rig.service.history.length;
    expect(historyCount, 1);

    await tester
        .tap(find.byKey(const ValueKey('settings-category-appearance')));
    await tester.pump();
    final monitorContext =
        tester.element(find.byKey(monitorKey, skipOffstage: false));
    expect(TickerMode.valuesOf(monitorContext).enabled, isTrue,
        reason: 'The visual preference deliberately keeps this ticker gate on');
    expect(SettingsSectionVisibility.isVisibleOf(monitorContext), isFalse);
    expect(rig.service.active, isFalse);
    expect(rig.calls.last.method, 'stop');
    final stoppedCalls = rig.calls.length;
    await rig.sample(session: oldSession, cpu: 95);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.service.history, hasLength(historyCount));
    expect(rig.calls, hasLength(stoppedCalls));

    await tester.tap(find.byKey(const ValueKey('settings-category-backup')));
    await tester.pumpAndSettle();
    expect(rig.service.active, isTrue);
    expect(rig.calls.last.method, 'start');
    expect(rig.session, isNot(oldSession));

    await tester.tap(find.byKey(const ValueKey('resource-enabled')));
    await tester.pumpAndSettle();
    expect(preferences.value.enabled, isFalse);
    expect(rig.service.active, isFalse);
    final disabledCalls = rig.calls.length;
    for (final id in ['appearance', 'backup']) {
      await tester.tap(find.byKey(ValueKey('settings-category-$id')));
      await tester.pumpAndSettle();
    }
    expect(rig.calls, hasLength(disabledCalls));
    expect(rig.service.active, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
