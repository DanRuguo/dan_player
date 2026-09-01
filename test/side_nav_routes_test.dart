import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
      'unifying playlists preserves existing saved startup destination indexes',
      () {
    expect(app_paths.START_PAGES.take(4), [
      app_paths.AUDIOS_PAGE,
      app_paths.ARTISTS_PAGE,
      app_paths.COLLECTIONS_PAGE,
      app_paths.FOLDERS_PAGE,
    ]);
    expect(app_paths.START_PAGES.last, app_paths.PLAYLISTS_PAGE);
    expect(destinations.map((item) => item.desPath).toSet().length,
        destinations.length);
    expect(destinations.where((item) => item.label == '歌单'), hasLength(1));
    expect(destinations.where((item) => item.label == '合集'), isEmpty);
  });

  for (final width in [900.0, 1280.0]) {
    for (final textScale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'playlist and settings remain reachable at $width/507 '
            'with $textScale text in $brightness', (tester) async {
          tester.view.devicePixelRatio = 1.25;
          tester.view.physicalSize = Size(width * 1.25, 507 * 1.25);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final previousStartPage = AppPreference.instance.startPage;
          addTearDown(
              () => AppPreference.instance.startPage = previousStartPage);
          final router = GoRouter(
            initialLocation: app_paths.AUDIOS_PAGE,
            routes: [
              for (final destination in destinations)
                GoRoute(
                  path: destination.desPath,
                  builder: (_, __) => const Scaffold(
                    body: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [SideNav(), Expanded(child: SizedBox())],
                    ),
                  ),
                ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(MaterialApp.router(
            theme: ThemeData(
              platform: TargetPlatform.windows,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.teal, brightness: brightness),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            routerConfig: router,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('合集'), findsNothing);
          await tester.ensureVisible(find.text('歌单'));
          await tester.tap(find.text('歌单'));
          await tester.pumpAndSettle();
          expect(
              GoRouterState.of(tester.element(find.byType(SideNav))).uri.path,
              app_paths.PLAYLISTS_PAGE);
          expect(app_paths.START_PAGES[AppPreference.instance.startPage],
              app_paths.PLAYLISTS_PAGE);
          final selected = destinations
              .indexWhere((item) => item.desPath == app_paths.PLAYLISTS_PAGE);
          if (width < 1100) {
            final rail =
                tester.widget<NavigationRail>(find.byType(NavigationRail));
            expect(rail.selectedIndex, selected);
            expect(rail.scrollable, isTrue);
          } else {
            expect(
                tester
                    .widget<NavigationDrawer>(find.byType(NavigationDrawer))
                    .selectedIndex,
                selected);
          }
          await tester.ensureVisible(find.text('设置'));
          await tester.tap(find.text('设置'));
          await tester.pumpAndSettle();
          expect(
              GoRouterState.of(tester.element(find.byType(SideNav))).uri.path,
              app_paths.SETTINGS_PAGE);
          expect(tester.takeException(), isNull);
          expect(PlayService.isInitialized, isFalse);
        });
      }
    }
  }

  testWidgets('an unlisted route does not give the rail a negative index',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Row(children: [SideNav(), Expanded(child: SizedBox())]),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('top-level sidebar switches replace instead of growing history',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: app_paths.AUDIOS_PAGE,
      routes: [
        for (final destination in destinations)
          GoRoute(
            path: destination.desPath,
            builder: (_, __) => const Scaffold(
              body: Row(children: [SideNav(), Expanded(child: SizedBox())]),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (final label in ['分类', '歌单', '设置', '音乐']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse, reason: '主导航不应把退出的页面及监听器保留在历史栈中');
    }

    expect(tester.takeException(), isNull);
  });
}
