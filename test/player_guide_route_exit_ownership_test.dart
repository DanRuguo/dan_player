import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_feature_fixture.dart';

class _RoutePops extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

class _GuideScene {
  final pops = _RoutePops();
  late final router = GoRouter(
    initialLocation: '/details',
    observers: [pops],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('guide-root-page'))),
        routes: [
          GoRoute(
            path: 'details',
            builder: (context, _) => Scaffold(
              key: const ValueKey('guide-underlying-page'),
              body: Center(
                child: FilledButton(
                  key: const ValueKey('guide-route-open'),
                  onPressed: () => showPlayerFeatureGuide(context),
                  child: const Text('Open guide'),
                ),
              ),
            ),
          ),
        ],
      ),
      for (final path in ['/audios', '/categories'])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(
              key: ValueKey('guide-destination-$path'),
              body: Center(child: Text(path))),
        ),
    ],
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-underlying-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-route-open')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerFeatureGuideDialog), findsOneWidget);
    expect(pops.routes, isEmpty);
  }

  VoidCallback button(WidgetTester tester, String key) =>
      tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed!;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  testWidgets('queued guide close only pops its own dialog once',
      (tester) async {
    final scene = _GuideScene();
    await scene.open(tester);
    final guideRoute =
        ModalRoute.of(tester.element(find.byType(PlayerFeatureGuideDialog)))!;
    final close = scene.button(tester, 'close-player-feature-guide');
    // Two queued activations can run before reverse installs IgnorePointer.
    // Use the actual button callback against two real Navigator page routes.
    close();
    close();
    await tester.pumpAndSettle();
    expect(scene.pops.routes, [guideRoute]);
    expect(find.byKey(const ValueKey('guide-underlying-page')), findsOneWidget);
    expect(scene.router.routeInformationProvider.value.uri.path, '/details');
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed guide tool callback cannot navigate another page',
      (tester) async {
    final scene = _GuideScene();
    await scene.open(tester);
    final guideRoute =
        ModalRoute.of(tester.element(find.byType(PlayerFeatureGuideDialog)))!;
    final music = scene.button(tester, 'guide-basic-music-page');
    scene.button(tester, 'close-player-feature-guide')();
    music();
    await tester.pumpAndSettle();
    expect(scene.pops.routes, [guideRoute]);
    expect(find.byKey(const ValueKey('guide-underlying-page')), findsOneWidget);
    expect(scene.router.routeInformationProvider.value.uri.path, '/details');
    expect(tester.takeException(), isNull);
  });

  testWidgets('first guide tool wins over a queued second destination',
      (tester) async {
    final scene = _GuideScene();
    await scene.open(tester);
    final music = scene.button(tester, 'guide-basic-music-page');
    final categories = scene.button(tester, 'guide-basic-category-page');
    music();
    categories();
    await tester.pumpAndSettle();
    expect(scene.router.routeInformationProvider.value.uri.path, '/audios');
    expect(find.byKey(const ValueKey('guide-destination-/audios')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
