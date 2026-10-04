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

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  for (final layout in [
    (name: 'expanded', window: 1200.0, nav: 300.0, continuous: true),
    (name: 'compact', window: 1200.0, nav: 76.0, continuous: true),
    (name: 'legacy rail', window: 1000.0, nav: 80.0, continuous: false),
    (name: 'drawer', window: 1200.0, nav: 304.0, continuous: false),
  ]) {
    testWidgets(
        '${layout.name} preserves all navigation coordinates when monitoring changes',
        (tester) async {
      sizePlaylistFeature(tester, width: layout.window, height: 1000);
      final saved = AppSettings.instance.processResources.value;
      addTearDown(() {
        AppSettings.instance.processResources.value = saved;
        uiLanguage.value = UiLanguage.zh;
      });
      final rig = ResourceTestRig();
      final coordinator =
          ProcessResourceCoordinator.forTesting(service: rig.service);
      AppSettings.instance.processResources.value =
          const ProcessResourcePreferences();
      final boundary = GlobalKey();
      final router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
        GoRoute(
            path: paths.AUDIOS_PAGE,
            builder: (_, __) => Scaffold(
                    body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: layout.name == 'legacy rail'
                          ? layout.window
                          : layout.nav,
                      height: 1000,
                      child: SideNav(
                          desktopWidth: layout.continuous ? layout.nav : null,
                          resourceCoordinator: coordinator)),
                ))),
      ]);
      for (final language in UiLanguage.values) {
        uiLanguage.value = language;
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
              useMaterial3: true,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
          builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(
                          language == UiLanguage.ko ? 1.8 : 1)),
                  child: child!)),
        )));
        await tester.pumpAndSettle();
        if (layout.name == 'legacy rail') {
          expect(find.byType(NavigationRail), findsOneWidget);
        }
        final icons = [for (final d in destinations) find.byIcon(d.icon)];
        expect(icons.every((f) => f.evaluate().length == 1), isTrue);
        final before = [for (final f in icons) tester.getRect(f)];
        AppSettings.instance.processResources.value =
            const ProcessResourcePreferences(
                enabled: true, showInSidebar: true);
        await tester.pumpAndSettle();
        expect([for (final f in icons) tester.getRect(f)], before,
            reason:
                'empty space below navigation must not move any destination');
        final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
        expect(tester.getTopLeft(monitor).dy, greaterThan(before.last.bottom));
        expect(tester.getBottomLeft(monitor).dy, lessThanOrEqualTo(1000));
        await rig.sample(cpu: 18.5, gpu: 22);
        await tester.pump();
        expect([for (final f in icons) tester.getRect(f)], before,
            reason: 'resource samples must not change navigation layout');
        if (language == UiLanguage.zh && layout.name == 'expanded') {
          await capturePlaylistFeature(
              tester, boundary, 'sidebar-resources-stable');
        }
        AppSettings.instance.processResources.value =
            const ProcessResourcePreferences();
        await tester.pumpAndSettle();
        expect([for (final f in icons) tester.getRect(f)], before);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await rig.close();
    });
  }
}
