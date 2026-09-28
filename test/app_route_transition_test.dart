import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/music_category_fixtures.dart';

class _InMemoryCovers extends CategoryCoverStore {
  _InMemoryCovers()
      : super(dataDirectory: () async => throw StateError('No fixture I/O'));

  @override
  Future<ImageProvider?> imageFor(MusicCategoryGroup group) async => null;
}

void main() {
  testWidgets('page groups preserve the baseline staggered fade and rise',
      (tester) async {
    final animation = AnimationController(
        vsync: tester, value: .1, duration: AppRouteTransition.enterDuration);
    addTearDown(animation.dispose);
    const key = ValueKey('baseline-page-group');
    await tester.pumpWidget(MaterialApp(
        home: AppRouteTransition(
            animation: animation,
            child: const AppEntranceScope(
                child:
                    AppEntrance(order: 6, child: Text('Music', key: key))))));
    final first = tester.getTopLeft(find.byKey(key));
    final entrance = find.byType(AppEntrance);
    expect(
        tester
            .widget<Opacity>(find
                .descendant(of: entrance, matching: find.byType(Opacity))
                .first)
            .opacity,
        0);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 180));
    final opacity = tester
        .widget<Opacity>(
            find.descendant(of: entrance, matching: find.byType(Opacity)).first)
        .opacity;
    expect(opacity, allOf(greaterThan(0), lessThan(1)));
    final middle = tester.getTopLeft(find.byKey(key));
    expect(middle.dx, first.dx);
    expect(middle.dy,
        allOf(lessThan(first.dy), greaterThan(first.dy - AppEntrance.distance)));
    animation.value = 1;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(key)),
        first.translate(0, -AppEntrance.distance));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category tiles preserve the baseline fade and scaling',
      (tester) async {
    final covers = _InMemoryCovers();
    addTearDown(covers.dispose);
    final groups = MusicCategories([CategoryTestAudio('Track')])
        .groups(MusicCategoryKind.artist);
    await tester.pumpWidget(MaterialApp(
        home: AppRouteTransition(
            animation: const AlwaysStoppedAnimation(1),
            child: PageScaffold(
                title: 'Categories',
                actions: const [],
                body: CustomScrollView(slivers: [
                  CategoryTileGrid(
                      groups: groups,
                      presentation: const CategoryPresentation(),
                      onChanged: (_) {},
                      onOpen: (_) {},
                      covers: covers,
                      changing: const {},
                      onChangeCover: (_) {},
                      onRemoveCover: (_) {},
                      icon: Icons.album,
                      persistLayout: false)
                ])))));
    final category = find.byWidgetPredicate((widget) =>
        widget is AppEntrance &&
        widget.identity == ('category-tile', groups.single.persistenceKey));
    expect(category, findsOneWidget);
    Transform scale() => tester
        .widgetList<Transform>(
            find.descendant(of: category, matching: find.byType(Transform)))
        .firstWhere((widget) => widget.alignment == Alignment.center);
    double opacity() => tester
        .widget<Opacity>(
            find.descendant(of: category, matching: find.byType(Opacity)).first)
        .opacity;
    expect(scale().transform.storage[0], closeTo(.9, .001));
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(scale().transform.storage[0], allOf(greaterThan(.9), lessThan(1)));
    expect(opacity(), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(scale().transform.storage[0], 1);
    expect(opacity(), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming page preserves the baseline whole-surface crossfade',
      (tester) async {
    final boundary = GlobalKey();
    final animation = AnimationController(
        vsync: tester, value: .2, duration: AppRouteTransition.enterDuration);
    addTearDown(animation.dispose);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal)
        .copyWith(surface: Colors.white);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: RepaintBoundary(
            key: boundary,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(
                  color: Color(0xFFFF0000),
                  child: Center(child: Text('OLD PAGE'))),
              AppRouteTransition(
                  animation: animation,
                  child: const ColoredBox(color: Colors.white)),
            ]))));
    final data = (await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    final alpha = AppMotion.emphasizedCurve.transform(animation.value);
    expect(data[0], 255);
    expect(data[1], closeTo(255 * alpha, 1));
    expect(data[2], closeTo(255 * alpha, 1));
    expect(data[3], 255,
        reason: 'The route surface follows the original opacity path');
    animation.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'page pop preserves base state and ${reduced ? 'skips' : 'finishes'} exit animation',
        (tester) async {
      var entered = 0;
      final input = TextEditingController(text: 'preserved search');
      addTearDown(input.dispose);
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            pageBuilder: (_, state) => SlideTransitionPage(
                  key: state.pageKey,
                  child: Scaffold(
                      body: Column(children: [
                    TextField(controller: input),
                    Builder(
                        builder: (context) => TextButton(
                            onPressed: () => context.push('/detail'),
                            child: const Text('Open'))),
                  ])),
                )),
        GoRoute(
            path: '/detail',
            pageBuilder: (_, state) => SlideTransitionPage(
                  key: state.pageKey,
                  child: Scaffold(
                      key: const ValueKey('detail-surface'),
                      backgroundColor: Colors.blue,
                      body: AppEntrance(
                          identity: 'detail-group',
                          child: Builder(builder: (context) {
                            entered++;
                            return TextButton(
                                onPressed: () => context.pop(),
                                child: const Text('Back'));
                          }))),
                )),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final beforeExit = entered;
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('detail-surface')), findsOneWidget,
          reason:
              'The outgoing page lives until reverseTransitionDuration ends');
      final transition = find
          .ancestor(
              of: find.byKey(const ValueKey('detail-surface')),
              matching: find.byType(AppRouteTransition))
          .first;
      final opacity = tester
          .widget<Opacity>(find
              .descendant(of: transition, matching: find.byType(Opacity))
              .first)
          .opacity;
      if (reduced) {
        expect(opacity, 0);
      } else {
        expect(opacity, greaterThan(0));
        expect(opacity, lessThan(1));
      }
      expect(entered, beforeExit,
          reason: 'The route child is not rebuilt each animation frame');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('detail-surface')), findsNothing,
          reason: 'Returning completes within 260ms instead of the old 420ms');
      await tester.pumpAndSettle();
      expect(input.text, 'preserved search');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test('route durations include a finite return transition', () {
    final page = SlideTransitionPage(child: const SizedBox());
    expect(page.transitionDuration, AppRouteTransition.enterDuration);
    expect(page.reverseTransitionDuration, AppRouteTransition.exitDuration);
    expect(page.transitionDuration, const Duration(milliseconds: 240));
    expect(page.reverseTransitionDuration, page.transitionDuration);
  });

  for (final start in [.1, .5, 1.0]) {
    testWidgets(
        'return from partial forward $start has no first-frame opacity jump',
        (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: AppRouteTransition.enterDuration,
        reverseDuration: AppRouteTransition.exitDuration,
        value: start,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: AppRouteTransition(
        animation: controller,
        child: const ColoredBox(color: Colors.blue),
      )));
      double opacity() =>
          tester.widget<Opacity>(find.byType(Opacity).first).opacity;
      final expected = AppMotion.emphasizedCurve.transform(start);
      expect(opacity(), closeTo(expected, .000001));
      controller.reverse();
      await tester.pump();
      expect(opacity(), closeTo(expected, .000001));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 16));
      expect(opacity(), 0, reason: 'Dismissed must not flash visible again');
      controller.forward();
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('forward and reverse use the same visual path at the same value',
      (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: AppRouteTransition.enterDuration,
      reverseDuration: AppRouteTransition.exitDuration,
      value: .6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppRouteTransition(
        animation: controller,
        child: const ColoredBox(color: Colors.blue),
      ),
    ));
    double opacity() =>
        tester.widget<Opacity>(find.byType(Opacity).first).opacity;

    final forward = opacity();
    controller.reverse();
    await tester.pump();
    expect(controller.value, closeTo(.6, .000001));
    expect(opacity(), closeTo(forward, .000001));
    controller.forward();
    await tester.pump();
    expect(controller.value, closeTo(.6, .000001));
    expect(opacity(), closeTo(forward, .000001));
    controller.stop();
  });
}
