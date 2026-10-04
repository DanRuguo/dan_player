import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/side_nav_layout.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

final _navIcon = find.descendant(
    of: find.byKey(const ValueKey('continuous-nav-${paths.AUDIOS_PAGE}')),
    matching: find.byType(Icon));
Finder _metric(String name) =>
    find.byKey(ValueKey('compact-resource-sidebar-$name'));
Finder _metricIcon(String name) =>
    find.descendant(of: _metric(name), matching: find.byType(Icon));
Finder _metricOpacity(String name) =>
    find.byKey(ValueKey('sidebar-resource-opacity-$name'));

class _Fixture {
  final preferences = ValueNotifier(const PlayerExperiencePreferences());
  final flags = ValueNotifier((visible: true, disabled: false, reduced: false));
  final rig = ResourceTestRig();
  late final coordinator =
      ProcessResourceCoordinator.forTesting(service: rig.service);
  late final GoRouter router;
  final boundary = GlobalKey();
  double threshold = 0;
  int saves = 0;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coordinator.settled;
    coordinator.dispose();
    await rig.close();
    router.dispose();
    preferences.dispose();
    flags.dispose();
  }
}

Future<_Fixture> _mount(WidgetTester tester,
    {UiLanguage language = UiLanguage.zh,
    double scale = 1,
    double height = 1000,
    bool rtl = false,
    bool isolateLayout = false,
    ProcessResourceDisplay display = ProcessResourceDisplay.numbers}) async {
  sizePlaylistFeature(tester, width: 1200, height: height);
  final fixture = _Fixture();
  final saved = AppSettings.instance.processResources.value;
  uiLanguage.value = language;
  AppSettings.instance.processResources.value = ProcessResourcePreferences(
      enabled: true, showInSidebar: true, display: display);
  fixture.router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
    GoRoute(
        path: paths.AUDIOS_PAGE,
        builder: (_, __) => Scaffold(
                body: Row(children: [
              ResizableSideNav(
                  preferences: fixture.preferences,
                  resourceCoordinator: fixture.coordinator,
                  persist: () async => fixture.saves++),
              const Expanded(child: SizedBox.shrink())
            ])))
  ]);
  addTearDown(() {
    AppSettings.instance.processResources.value = saved;
    uiLanguage.value = UiLanguage.zh;
  });
  await tester.pumpWidget(UiLanguageScope(
      child: MaterialApp.router(
          theme: ThemeData(
              platform: TargetPlatform.windows,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
          routerConfig: fixture.router,
          builder: (context, child) => AppEntranceScope(
              child: ValueListenableBuilder(
                  valueListenable: fixture.flags,
                  builder: (context, flags, _) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: flags.reduced),
                      child: Directionality(
                          textDirection:
                              rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: MotionPreferencesScope(
                              preferences: MotionPreferences(disabled: {
                                if (flags.disabled) MotionKind.layout,
                                if (isolateLayout) MotionKind.feedback,
                              }),
                              child: TickerMode(
                                  enabled: flags.visible,
                                  child: RepaintBoundary(
                                      key: fixture.boundary,
                                      child: Builder(builder: (context) {
                                        fixture.threshold =
                                            sideNavCompactThreshold(
                                                context,
                                                destinations
                                                    .map((d) => d.label));
                                        return child!;
                                      })))))))))));
  await tester.pumpAndSettle();
  await fixture.coordinator.settled;
  await fixture.rig.sample(cpu: 12.5, gpu: 8.5, gpuStatus: 'ready');
  await tester.pumpAndSettle();
  return fixture;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  for (final scenario in [
    (language: UiLanguage.zh, scale: 1.0, height: 1000.0, rtl: false),
    (language: UiLanguage.en, scale: 1.8, height: 1000.0, rtl: false),
    (language: UiLanguage.ja, scale: 1.8, height: 575.0, rtl: true),
    (language: UiLanguage.ko, scale: 2.0, height: 360.0, rtl: false),
  ]) {
    testWidgets(
        '${scenario.language.name} drag shares icon motion and label recovery',
        (tester) async {
      final fixture = await _mount(tester,
          language: scenario.language,
          scale: scenario.scale,
          height: scenario.height,
          rtl: scenario.rtl,
          display: scenario.language == UiLanguage.en
              ? ProcessResourceDisplay.bar
              : scenario.language == UiLanguage.ja
                  ? ProcessResourceDisplay.line
                  : ProcessResourceDisplay.numbers);
      try {
        final icons = {
          for (final name in ['CPU', 'GPU', 'RAM'])
            name: _metricIcon(name).evaluate().single
        };
        final nav = find.byKey(const ValueKey('resizable-side-nav'));
        final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
        final handle = tester
            .getCenter(find.byKey(const ValueKey('side-nav-resize-handle')));
        final gesture = await tester.startGesture(handle,
            kind: scenario.height < 600
                ? PointerDeviceKind.touch
                : PointerDeviceKind.mouse);
        Future<void> move(double width, {int frames = 5}) async {
          await gesture.moveTo(handle + Offset(width - 300, 0));
          for (var frame = 0; frame < frames; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            for (final name in icons.keys) {
              expect(tester.getCenter(_metricIcon(name)).dx,
                  closeTo(tester.getCenter(_navIcon).dx, .01),
                  reason:
                      '$name must share every intermediate navigation frame');
              expect(
                  identical(_metricIcon(name).evaluate().single, icons[name]),
                  isTrue,
                  reason:
                      'crossing compact mode must preserve the icon subtree');
            }
            final footer = tester.getRect(monitor), host = tester.getRect(nav);
            expect(footer.top, greaterThanOrEqualTo(host.top));
            expect(footer.bottom, lessThanOrEqualTo(host.bottom));
            if (scenario.height < 600) {
              final viewport =
                  find.descendant(of: nav, matching: find.byType(ListView));
              expect(footer.top,
                  greaterThanOrEqualTo(tester.getRect(viewport).bottom));
            }
            await fixture.coordinator.settled;
            expect(fixture.rig.calls.map((c) => c.method), ['start']);
            expect(tester.takeException(), isNull);
          }
        }

        await move(fixture.threshold + 12);
        final navOpacity = find
            .byKey(const ValueKey('nav-label-opacity-${paths.AUDIOS_PAGE}'));
        expect(tester.widget<Opacity>(navOpacity).opacity, closeTo(.25, .001));
        await move(fixture.threshold - 4, frames: 4);
        await capturePlaylistFeature(tester, fixture.boundary,
            'shared-${scenario.language.name}-inward');
        await fixture.rig.sample(cpu: 44, gpu: 22, gpuStatus: 'ready');
        await move(fixture.threshold + 12, frames: 4);
        for (final name in icons.keys) {
          expect(tester.widget<Opacity>(_metricOpacity(name)).opacity,
              tester.widget<Opacity>(navOpacity).opacity);
        }
        await gesture.up();
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          for (final name in icons.keys) {
            expect(tester.getCenter(_metricIcon(name)).dx,
                closeTo(tester.getCenter(_navIcon).dx, .01));
            expect(tester.widget<Opacity>(_metricOpacity(name)).opacity,
                tester.widget<Opacity>(navOpacity).opacity);
          }
        }
        expect(fixture.saves, 1);
        expect(tester.widget<Opacity>(navOpacity).opacity, 1);
        await capturePlaylistFeature(tester, fixture.boundary,
            'shared-${scenario.language.name}-recovered');
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(fixture.rig.calls.map((c) => c.method), ['start']);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    });
  }

  for (final policy in ['disabled', 'reduced', 'native', 'hidden']) {
    testWidgets('$policy ends shared active motion without extra clocks',
        (tester) async {
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      // The resize grip has an independent feedback animation. Keep normal
      // entrance scopes, but isolate layout clocks for this clock-count check.
      final fixture = await _mount(tester, isolateLayout: true);
      try {
        final handle = tester
            .getCenter(find.byKey(const ValueKey('side-nav-resize-handle')));
        final gesture =
            await tester.startGesture(handle, kind: PointerDeviceKind.mouse);
        await gesture.moveTo(handle + Offset(fixture.threshold - 304, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.binding.transientCallbackCount, 1,
            reason: 'all ten icons share the one active mode clock');
        if (policy == 'native') {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        } else {
          fixture.flags.value = (
            visible: policy != 'hidden',
            disabled: policy == 'disabled',
            reduced: policy == 'reduced'
          );
        }
        await tester.pump();
        for (final name in ['CPU', 'GPU', 'RAM']) {
          expect(tester.getCenter(_metricIcon(name)).dx,
              closeTo(tester.getCenter(_navIcon).dx, .01));
        }
        expect(tester.binding.transientCallbackCount, 0);
        await gesture.up();
        await tester.pumpAndSettle();
        await fixture.coordinator.settled;
        expect(fixture.rig.calls.map((c) => c.method),
            policy == 'hidden' ? ['start', 'stop'] : ['start']);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    });
  }
}
