import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
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
    const page = SlideTransitionPage(child: SizedBox());
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
