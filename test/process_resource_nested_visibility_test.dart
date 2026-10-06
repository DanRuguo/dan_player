import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized()
      .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets('retained monitor follows a replaced outer scroll position',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 1000);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final preferences = ValueNotifier(
        const ProcessResourcePreferences(enabled: true, showInLyrics: true));
    final hidden = ValueNotifier(false);
    final first = ScrollController(initialScrollOffset: 260);
    final replacement = TrackingScrollController(initialScrollOffset: 260);
    final binding = ValueNotifier<ScrollController>(first);
    final inner = ScrollController();
    final monitorKey = GlobalKey();
    final retained = SizedBox(
        height: 300,
        child: SingleChildScrollView(
            controller: inner,
            child: SizedBox(
                width: 260,
                child: CompactProcessResourceMonitor(
                    key: monitorKey,
                    surface: ProcessResourceSurface.lyrics,
                    coordinator: coordinator,
                    preferences: preferences,
                    isHidden: hidden))));
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 700,
                      height: 180,
                      child: ValueListenableBuilder<ScrollController>(
                          valueListenable: binding,
                          builder: (context, controller, _) => ListView(
                                  controller: controller,
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.pixels(1000),
                                  children: [
                                    const SizedBox(height: 260),
                                    retained,
                                    const SizedBox(height: 700)
                                  ])))))));
      await tester.pumpAndSettle();
      await coordinator.settled;
      expect(rig.calls.map((call) => call.method), ['start']);
      final mountedMonitor = find.byKey(monitorKey, skipOffstage: false);
      final element = mountedMonitor.evaluate().single;
      final originalPosition = first.position;
      binding.value = replacement;
      await tester.pumpAndSettle();
      await coordinator.settled;
      expect(replacement.position, isNot(same(originalPosition)));
      expect(mountedMonitor.evaluate().single, same(element));
      replacement.jumpTo(0);
      await tester.pumpAndSettle();
      await coordinator.settled;
      expect(mountedMonitor.evaluate().single, same(element));
      expect(coordinator.service.active, isFalse,
          reason: 'a retained inner viewport must not leave a lease attached '
              'to the outer position replaced by its owner');
      replacement.jumpTo(260);
      await tester.pumpAndSettle();
      await coordinator.settled;
      expect(rig.calls.map((call) => call.method), ['start', 'stop', 'start']);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      await rig.close();
      preferences.dispose();
      hidden.dispose();
      binding.dispose();
      first.dispose();
      replacement.dispose();
      inner.dispose();
    }
  });

  for (final surface in ['settings', 'sidebar', 'lyrics']) {
    testWidgets('$surface sampling follows every ancestor viewport',
        (tester) async {
      sizePlaylistFeature(tester, width: 800, height: 1000);
      final rig = ResourceTestRig();
      final coordinator =
          ProcessResourceCoordinator.forTesting(service: rig.service);
      final preferences = ValueNotifier(const ProcessResourcePreferences(
          enabled: true, showInSidebar: true, showInLyrics: true));
      final hidden = ValueNotifier(false);
      final outer = ScrollController();
      final inner = ScrollController();
      final monitorKey = GlobalKey();
      final monitor = surface == 'settings'
          ? ProcessResourceMonitor(
              key: monitorKey,
              coordinator: coordinator,
              preferences: preferences,
              isHidden: hidden,
              onPreferencesChanged: (value) async => preferences.value = value)
          : CompactProcessResourceMonitor(
              key: monitorKey,
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
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 700,
                        height: 180,
                        child: SingleChildScrollView(
                            controller: outer,
                            child: Column(children: [
                              const SizedBox(height: 260),
                              SizedBox(
                                  height: 300,
                                  child: SingleChildScrollView(
                                      controller: inner,
                                      child: Column(children: [
                                        SizedBox(
                                            width: surface == 'settings'
                                                ? 680
                                                : 260,
                                            child: monitor),
                                        const SizedBox(height: 700)
                                      ]))),
                              const SizedBox(height: 700)
                            ])))))));
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(tester.getRect(find.byKey(monitorKey)).top, 260);
        expect(rig.calls, isEmpty,
            reason: 'the monitor overlaps the screen and its nearest viewport '
                'but is completely clipped by the outer viewport');

        outer.jumpTo(260);
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(rig.calls.map((call) => call.method), ['start']);
        await rig.sample(cpu: 37);
        await tester.pump();

        outer.jumpTo(0);
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(rig.calls.map((call) => call.method), ['start', 'stop'],
            reason: 'the outer scroll position must invalidate visibility '
                'even though the inner position never changes');
        final before = rig.calls.length;
        await tester.pump(const Duration(seconds: 30));
        expect(rig.calls, hasLength(before));
        expect(tester.binding.transientCallbackCount, 0);

        outer.jumpTo(260);
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(
            rig.calls.map((call) => call.method), ['start', 'stop', 'start']);
        // A partial intersection still owns a lease; fully scrolling the
        // monitor out of the inner viewport releases it.
        inner.jumpTo(10);
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(coordinator.service.active, isTrue);
        inner.jumpTo(inner.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(rig.calls.map((call) => call.method),
            ['start', 'stop', 'start', 'stop']);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        await rig.close();
        preferences.dispose();
        hidden.dispose();
        outer.dispose();
        inner.dispose();
      }
    });
  }
}
