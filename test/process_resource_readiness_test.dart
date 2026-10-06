import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized()
      .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  for (final surface in ['settings', 'sidebar', 'lyrics']) {
    for (final reduced in [false, true]) {
      testWidgets(
          '$surface readiness gates sampling independently of reduced motion $reduced',
          (tester) async {
        sizePlaylistFeature(tester, width: 800, height: 1000);
        final rig = ResourceTestRig();
        final coordinator =
            ProcessResourceCoordinator.forTesting(service: rig.service);
        final preferences = ValueNotifier(const ProcessResourcePreferences(
            enabled: true, showInSidebar: true, showInLyrics: true));
        final hidden = ValueNotifier(false);
        final readiness = ValueNotifier((outer: false, inner: true));
        final monitor = surface == 'settings'
            ? ProcessResourceMonitor(
                coordinator: coordinator,
                preferences: preferences,
                isHidden: hidden,
                onPreferencesChanged: (value) async =>
                    preferences.value = value)
            : CompactProcessResourceMonitor(
                surface: surface == 'sidebar'
                    ? ProcessResourceSurface.sidebar
                    : ProcessResourceSurface.lyrics,
                coordinator: coordinator,
                preferences: preferences,
                isHidden: hidden);
        try {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback),
              home: Scaffold(
                  body: Builder(
                      builder: (context) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(disableAnimations: reduced),
                          child: ValueListenableBuilder(
                              valueListenable: readiness,
                              builder: (context, value, _) => AppEntranceScope(
                                  ready: value.outer,
                                  child: AppEntranceScope(
                                      ready: value.inner,
                                      child: Align(
                                          alignment: Alignment.topLeft,
                                          child: SizedBox(
                                              width: surface == 'settings'
                                                  ? 700
                                                  : 260,
                                              child: AppEntrance(
                                                  identity: 'monitor',
                                                  child: monitor)))))))))));
          await tester.pumpAndSettle();
          await coordinator.settled;
          expect(rig.calls, isEmpty,
              reason: 'preloading behind the opaque startup overlay must not '
                  'lease the native worker, even when entrances are disabled');
          expect(coordinator.service.active, isFalse);
          expect(tester.binding.transientCallbackCount, 0);

          // The nearest scope cannot override an unready ancestor.
          readiness.value = (outer: true, inner: false);
          await tester.pumpAndSettle();
          await coordinator.settled;
          expect(rig.calls, isEmpty);

          readiness.value = (outer: true, inner: true);
          await tester.pumpAndSettle();
          await coordinator.settled;
          expect(rig.calls.map((call) => call.method), ['start']);
          await rig.sample(cpu: 37);
          await tester.pump();
          expect(coordinator.service.latest!.cpuPercent, 37);

          readiness.value = (outer: false, inner: true);
          await tester.pumpAndSettle();
          await coordinator.settled;
          expect(rig.calls.map((call) => call.method), ['start', 'stop']);
          final before = rig.calls.length;
          await tester.pump(const Duration(seconds: 30));
          expect(rig.calls, hasLength(before));
          expect(tester.binding.transientCallbackCount, 0);

          readiness.value = (outer: true, inner: true);
          await tester.pumpAndSettle();
          await coordinator.settled;
          expect(
              rig.calls.map((call) => call.method), ['start', 'stop', 'start']);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          coordinator.dispose();
          await rig.close();
          preferences.dispose();
          hidden.dispose();
          readiness.dispose();
        }
      });
    }
  }
}
