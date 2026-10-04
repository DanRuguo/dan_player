import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  testWidgets(
      'hidden settings release sample listener while sidebar stays live',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 1100);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final prefs = ValueNotifier(
        const ProcessResourcePreferences(enabled: true, showInSidebar: true));
    final hidden = ValueNotifier(false);
    final visible = ValueNotifier(true);
    await tester.pumpWidget(listeningStatusHost(Column(children: [
      SizedBox(
          width: 260,
          child: CompactProcessResourceMonitor(
              surface: ProcessResourceSurface.sidebar,
              preferences: prefs,
              coordinator: coordinator,
              isHidden: hidden)),
      Expanded(
          child: SingleChildScrollView(
              child: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  child: ProcessResourceMonitor(
                      preferences: prefs,
                      coordinator: coordinator,
                      isHidden: hidden),
                  builder: (context, value, child) =>
                      TickerMode(enabled: value, child: child!)))),
    ])));
    await tester.pumpAndSettle();
    await rig.sample(cpu: 12.5);
    await tester.pump();
    final metric = find.byKey(const ValueKey('resource-value-CPU'));
    expect(tester.widget<Text>(metric).data, '12.5%');
    visible.value = false;
    await tester.pumpAndSettle();
    final oldText = tester.widget<Text>(metric);
    await rig.sample(cpu: 39);
    await tester.pump();
    expect(tester.widget<Text>(metric), same(oldText));
    expect(find.text('39.0%'), findsOneWidget);
    expect(rig.calls.map((call) => call.method), ['start']);
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(metric).data, '39.0%');
    expect(rig.calls.map((call) => call.method), ['start']);
    await tester.pumpWidget(const SizedBox());
    await coordinator.settled;
    coordinator.dispose();
    await rig.close();
    prefs.dispose();
    hidden.dispose();
    visible.dispose();
  });
  testWidgets('settings mounted after lifecycle pause stays idle until resumed',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 900);
    final rig = ResourceTestRig();
    final prefs =
        ValueNotifier(const ProcessResourcePreferences(enabled: true));
    final hidden = ValueNotifier(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        child: ProcessResourceMonitor(
            preferences: prefs, controller: rig.service, isHidden: hidden))));
    await tester.pumpAndSettle();
    expect(rig.calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(rig.calls.single.method, 'start');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
  });
  for (final language in UiLanguage.values) {
    testWidgets(
        'independent location controls, large text and search ${language.name}',
        (tester) async {
      sizePlaylistFeature(tester, width: 400, height: 1000);
      uiLanguage.value = language;
      final boundary = GlobalKey();
      final rig = ResourceTestRig();
      final prefs = ValueNotifier(const ProcessResourcePreferences());
      final hidden = ValueNotifier(false);
      await tester.pumpWidget(listeningStatusHost(
          SingleChildScrollView(
              child: ProcessResourceMonitor(
                  preferences: prefs,
                  controller: rig.service,
                  isHidden: hidden,
                  onPreferencesChanged: (value) async => prefs.value = value)),
          scale: 1.5,
          brightness: Brightness.dark,
          boundary: boundary));
      await tester.pumpAndSettle();
      expect(rig.calls, isEmpty);
      expect(find.byKey(const ValueKey('resource-sidebar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('resource-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resource-sidebar')));
      await tester.pumpAndSettle();
      expect(prefs.value.showInSidebar, isTrue);
      expect(prefs.value.showInLyrics, isFalse);
      await tester.tap(find.byKey(const ValueKey('resource-lyrics')));
      await tester.pumpAndSettle();
      expect(prefs.value.showInLyrics, isTrue);
      for (final label in ['在侧栏下方显示', '在歌词页左上角显示']) {
        final translated = translateUi(label, language);
        expect(
            searchSettings(translated)
                .any((entry) => entry.id == 'process-resources'),
            isTrue);
      }
      expect(tester.takeException(), isNull);
      await captureListeningStatus(
          tester, boundary, 'location-settings-${language.name}-400-large');
      await tester.tap(find.byKey(const ValueKey('resource-enabled')));
      await tester.pumpAndSettle();
      expect(prefs.value.enabled, isFalse);
      expect(prefs.value.showInSidebar && prefs.value.showInLyrics, isTrue);
      expect(rig.calls.last.method, 'stop');
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      await rig.close();
      prefs.dispose();
      hidden.dispose();
    });
  }
}
