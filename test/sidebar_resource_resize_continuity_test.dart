import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/side_nav_layout.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  for (final scenario in [
    (language: UiLanguage.zh, height: 1000.0, scale: 1.0, reduce: false),
    (language: UiLanguage.en, height: 1000.0, scale: 1.8, reduce: true),
    (language: UiLanguage.ja, height: 575.0, scale: 1.8, reduce: false),
    (language: UiLanguage.ko, height: 360.0, scale: 2.0, reduce: true),
  ]) {
    testWidgets(
        '${scenario.language.name} real sidebar resize keeps monitor painted and one sampling session',
        (tester) async {
      sizePlaylistFeature(tester, width: 1200, height: scenario.height);
      final saved = AppSettings.instance.processResources.value;
      addTearDown(() {
        AppSettings.instance.processResources.value = saved;
        uiLanguage.value = UiLanguage.zh;
      });
      AppSettings.instance.processResources.value = ProcessResourcePreferences(
          enabled: true,
          showInSidebar: true,
          display: switch (scenario.language) {
            UiLanguage.en => ProcessResourceDisplay.bar,
            UiLanguage.ja => ProcessResourceDisplay.line,
            _ => ProcessResourceDisplay.numbers,
          });
      uiLanguage.value = scenario.language;
      final preferences = ValueNotifier(const PlayerExperiencePreferences());
      final rig = ResourceTestRig();
      final coordinator =
          ProcessResourceCoordinator.forTesting(service: rig.service);
      final channel = rig.channel;
      final calls = rig.calls;
      var saves = 0;
      final boundary = GlobalKey();
      final router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
        GoRoute(
            path: paths.AUDIOS_PAGE,
            builder: (_, __) => Scaffold(
                    body: Row(children: [
                  ResizableSideNav(
                      preferences: preferences,
                      resourceCoordinator: coordinator,
                      persist: () async {
                        saves++;
                      }),
                  const Expanded(child: SizedBox.shrink()),
                ]))),
      ]);
      try {
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp.router(
                routerConfig: router,
                theme: ThemeData(
                    platform: TargetPlatform.windows,
                    useMaterial3: true,
                    fontFamily: danEmbeddedFontFamily,
                    fontFamilyFallback: danFontFamilyFallback,
                    colorScheme:
                        ColorScheme.fromSeed(seedColor: Colors.indigo)),
                builder: (context, child) => RepaintBoundary(
                    key: boundary,
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            disableAnimations: scenario.reduce,
                            textScaler: TextScaler.linear(scenario.scale)),
                        child: child!)))));
        await tester.pumpAndSettle();
        await coordinator.settled;
        expect(calls.map((c) => c.method), ['start']);
        final session = (calls.single.arguments as Map)['session'];
        final sampleDelivered = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
                channel.name,
                const StandardMethodCodec()
                    .encodeMethodCall(MethodCall('sample', {
                  'session': session,
                  'cpuPercent': 12.5,
                  'gpuPercent': 8.5,
                  'workingSetBytes': 64 * 1024 * 1024,
                  'totalPhysicalMemoryBytes': 8 * 1024 * 1024 * 1024,
                })),
                (_) => sampleDelivered.complete());
        await sampleDelivered.future;
        await tester.pumpAndSettle();
        final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
        final originalMonitor = monitor.evaluate().single;
        final nav = find.byKey(const ValueKey('resizable-side-nav'));
        final viewport =
            find.descendant(of: nav, matching: find.byType(ListView));
        final navigationBefore = scenario.height >= 1000
            ? [
                for (final d in destinations)
                  tester.getRect(
                      find.byKey(ValueKey('continuous-nav-${d.desPath}')))
              ]
            : null;
        final gesture = await tester.startGesture(
            tester.getCenter(
                find.byKey(const ValueKey('side-nav-resize-handle'))),
            kind: scenario.height >= 1000
                ? PointerDeviceKind.mouse
                : PointerDeviceKind.touch);
        final start = tester
            .getCenter(find.byKey(const ValueKey('side-nav-resize-handle')));
        final threshold = sideNavCompactThreshold(
            tester.element(nav), destinations.map((d) => d.label));
        final widths = [
          284.0,
          267.0,
          threshold + 1,
          threshold - 1,
          120.0,
          90.0,
          76.0,
          90.0,
          threshold - 1,
          threshold + 1,
          240.0,
          310.0,
          380.0,
          310.0,
        ].map((width) => width.clamp(76.0, 380.0).toDouble()).toList();
        for (var step = 0; step < widths.length; step++) {
          await gesture.moveTo(start + Offset(widths[step] - 300, 0));
          if (step == 4 || step == 9) {
            await rig.sample(cpu: 23.4, gpu: 11.2);
          }
          // Inspect the first rendered frame, including rapid reversals; settling
          // after every move conceals the original one-frame offscreen footer.
          for (var frame = 0; frame < 2; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final host = tester.getRect(nav), footer = tester.getRect(monitor);
            expect(footer.top, greaterThanOrEqualTo(host.top));
            expect(footer.bottom, lessThanOrEqualTo(host.bottom),
                reason: '${scenario.language.name} step $step/frame $frame: '
                    'resizing must not park the monitor outside the viewport');
            expect(
                identical(monitor.evaluate().single, originalMonitor), isTrue);
            for (final metric in ['CPU', 'GPU', 'RAM']) {
              final rect = tester.getRect(
                  find.byKey(ValueKey('compact-resource-sidebar-$metric')));
              expect(host.contains(rect.center), isTrue,
                  reason: '$metric must remain visible on every resize frame');
            }
            if (navigationBefore != null) {
              for (var index = 0; index < destinations.length; index++) {
                final rect = tester.getRect(find.byKey(
                    ValueKey('continuous-nav-${destinations[index].desPath}')));
                expect(rect.center.dy, navigationBefore[index].center.dy,
                    reason: 'the existing compact shape animation may resize '
                        'a destination, but must not move its vertical center');
              }
            } else {
              expect(footer.top,
                  greaterThanOrEqualTo(tester.getRect(viewport).bottom));
            }
            await coordinator.settled;
            expect(coordinator.service.active, isTrue);
            expect(calls.map((c) => c.method), ['start'],
                reason: 'width changes must not stop/start the native sampler');
            expect(tester.takeException(), isNull);
          }
          if (step == 0 || widths[step] == 76 || widths[step] == 380) {
            await capturePlaylistFeature(tester, boundary,
                'resize-${scenario.language.name}-${widths[step].toInt()}');
          }
        }
        expect(saves, 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(saves, 1);
        if (navigationBefore == null) {
          final scrollable =
              find.descendant(of: viewport, matching: find.byType(Scrollable));
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(find.byIcon(destinations.last.icon).hitTestable(),
              findsOneWidget);
          expect(tester.getRect(find.byIcon(destinations.last.icon)).bottom,
              lessThanOrEqualTo(tester.getRect(monitor).top));
        }
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        expect(calls.map((c) => c.method), ['start']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await coordinator.settled;
        router.dispose();
        preferences.dispose();
        coordinator.dispose();
        await rig.close();
      }
      expect(calls.map((c) => c.method), ['start', 'stop']);
    });
  }
}
