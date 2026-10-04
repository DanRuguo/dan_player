import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

class _RailScenario {
  const _RailScenario({
    required this.height,
    this.windowWidth = 1000,
    this.textScale = 1,
    this.language = UiLanguage.zh,
    this.padding = EdgeInsets.zero,
  });

  final double height, windowWidth, textScale;
  final UiLanguage language;
  final EdgeInsets padding;
}

class _RailFixture {
  _RailFixture(this.tester, _RailScenario initial)
      : scenario = ValueNotifier(initial) {
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value =
        const ProcessResourcePreferences(enabled: true, showInSidebar: true);
    router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
      GoRoute(
          path: paths.AUDIOS_PAGE,
          builder: (_, __) => Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder(
                      valueListenable: scenario,
                      child: SideNav(resourceCoordinator: coordinator),
                      builder: (context, value, child) => SizedBox(
                          key: hostKey,
                          width: value.windowWidth,
                          height: value.height,
                          // ResponsiveBuilder must see the medium window
                          // allocation. The actual rail chooses its own 80px.
                          child: Align(
                              alignment: Alignment.topLeft, child: child))))))
    ]);
    addTearDown(() {
      AppSettings.instance.processResources.value = saved;
      uiLanguage.value = UiLanguage.zh;
    });
  }

  final WidgetTester tester;
  final ValueNotifier<_RailScenario> scenario;
  final rig = ResourceTestRig();
  late final coordinator =
      ProcessResourceCoordinator.forTesting(service: rig.service);
  late final GoRouter router;
  final hostKey = GlobalKey();

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    scenario.dispose();
    coordinator.dispose();
    await rig.close();
  }

  Future<void> mount() async {
    await tester.pumpWidget(UiLanguageScope(
        child: ValueListenableBuilder(
            valueListenable: scenario,
            builder: (context, value, _) => MaterialApp.router(
                routerConfig: router,
                theme: ThemeData(
                    platform: TargetPlatform.windows,
                    useMaterial3: true,
                    fontFamily: danEmbeddedFontFamily,
                    fontFamilyFallback: danFontFamilyFallback,
                    colorScheme:
                        ColorScheme.fromSeed(seedColor: Colors.indigo)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        disableAnimations: true,
                        padding: value.padding,
                        textScaler: TextScaler.linear(value.textScale)),
                    child: child!)))));
  }

  Future<void> setScenario(_RailScenario value) async {
    uiLanguage.value = value.language;
    scenario.value = value;
    await assertStableAndReachable();
  }

  Future<void> assertStableAndReachable() async {
    final value = scenario.value;
    final description =
        '${value.height}px/${value.windowWidth}px/${value.language.name}/${value.textScale}x';
    final frames = await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(frames, lessThan(20),
        reason: 'full/reduced navigation must settle without a layout loop');
    expect(tester.takeException(), isNull);
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget,
        reason: 'the fixture must exercise the real legacy rail branch');
    expect(tester.getSize(rail).width, 80);
    final scrollable =
        find.descendant(of: rail, matching: find.byType(Scrollable));
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThanOrEqualTo(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));

    final viewport = tester.getRect(find.descendant(
        of: rail, matching: find.byType(SingleChildScrollView)));
    final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
    expect(monitor, findsOneWidget);
    final footer = tester.getRect(monitor);
    final host = tester.getRect(find.byKey(hostKey));
    expect(footer.top, greaterThanOrEqualTo(viewport.bottom - .01),
        reason: '$description: footer must stay outside reachable navigation');
    expect(footer.bottom, lessThanOrEqualTo(host.bottom + .01));
    final lastIcon = find.byIcon(destinations.last.icon);
    final last = tester.getRect(lastIcon);
    expect(last.top, greaterThanOrEqualTo(viewport.top - .01));
    expect(last.bottom, lessThanOrEqualTo(viewport.bottom + .01));
    expect(lastIcon.hitTestable(), findsOneWidget,
        reason: 'the last destination remains reachable above the footer');
    await coordinator.settled;
    expect(rig.service.active, isTrue);

    final before = (viewport, footer, last);
    final calls = rig.calls.length;
    await rig.sample(cpu: 18.5, gpu: 23.4);
    await tester.pumpAndSettle();
    expect((
      tester.getRect(find.descendant(
          of: rail, matching: find.byType(SingleChildScrollView))),
      tester.getRect(monitor),
      tester.getRect(lastIcon)
    ), before, reason: 'sampling must not relayout or remeasure navigation');
    // Reaching the last destination triggers the platform scrollbar's finite
    // delayed fade. Finish that interaction before checking actual idle work.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(rig.calls.length, calls,
        reason: 'idle layout must not restart the sampling session');
    expect(tester.takeException(), isNull);
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  testWidgets('short rail settles across full and reduced height boundaries',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 900);
    final fixture = _RailFixture(tester, const _RailScenario(height: 575));
    await fixture.mount();
    for (final height in [575.0, 600.0, 650.0, 700.0, 750.0, 650.0, 575.0]) {
      await fixture.setScenario(_RailScenario(height: height));
    }
    await fixture.close();
  });

  testWidgets(
      'short rail invalidates geometry for window text and language changes',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 900);
    final fixture = _RailFixture(tester, const _RailScenario(height: 650));
    await fixture.mount();
    for (final scenario in [
      const _RailScenario(height: 650),
      const _RailScenario(
          height: 650,
          windowWidth: 900,
          textScale: 1.5,
          language: UiLanguage.en),
      const _RailScenario(
          height: 600,
          windowWidth: 1050,
          textScale: 2,
          language: UiLanguage.ja),
      const _RailScenario(height: 575, textScale: 1.8, language: UiLanguage.ko),
      const _RailScenario(
          height: 750, padding: EdgeInsets.only(top: 24, bottom: 16)),
      const _RailScenario(height: 650),
    ]) {
      await fixture.setScenario(scenario);
    }
    await fixture.close();
  });
}
