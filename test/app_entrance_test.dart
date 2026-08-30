import 'package:dan_player/component/app_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _entrance = ValueKey('entrance');

Widget _app({
  Widget? child,
  Object identity = 'item',
  int order = 0,
  bool reduced = false,
  bool tickerEnabled = true,
  bool ready = true,
  int memory = 2048,
  int concurrency = 24,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: tickerEnabled,
          child: AppEntranceScope(
            ready: ready,
            maxRememberedIdentities: memory,
            maxConcurrentAnimations: concurrency,
            child: Center(
              child: child ??
                  AppEntrance(
                    key: _entrance,
                    identity: identity,
                    order: order,
                    child: const SizedBox(width: 100, height: 40),
                  ),
            ),
          ),
        ),
      ),
    );

double _opacity(WidgetTester tester, [Key key = _entrance]) => tester
    .widget<Opacity>(find
        .descendant(of: find.byKey(key), matching: find.byType(Opacity))
        .first)
    .opacity;

class _CountBuilds extends StatelessWidget {
  const _CountBuilds(this.onBuild);
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox(width: 100, height: 40, child: Text('Content'));
  }
}

void main() {
  testWidgets(
      'first appearance rises eight pixels without rebuilding its child',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(_app(
      child: AppEntrance(
        key: _entrance,
        child: _CountBuilds(() => builds++),
      ),
    ));
    expect(_opacity(tester), 0);
    final initialTransform = tester.widget<Transform>(find
        .descendant(of: find.byKey(_entrance), matching: find.byType(Transform))
        .first);
    expect(initialTransform.transform.getTranslation().y, 8);
    expect(tester.getSize(find.byKey(_entrance)), const Size(100, 40));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(builds, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal rebuilds and changed order never restart an entrance',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 80));
    final during = _opacity(tester);
    await tester.pumpWidget(_app(order: 999));
    expect(_opacity(tester), greaterThanOrEqualTo(during));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(_app(order: i));
      await tester.pump(const Duration(seconds: 5));
      expect(_opacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('stagger is finite and capped at 144ms even for huge indices',
      (tester) async {
    await tester.pumpWidget(_app(order: 100000));
    await tester.pump(const Duration(milliseconds: 143));
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 32));
    expect(_opacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 220));
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('negative indices do not add a delay', (tester) async {
    await tester.pumpWidget(_app(order: -10));
    await tester.pump(const Duration(milliseconds: 32));
    expect(_opacity(tester), greaterThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('MediaQuery reduced motion is immediately visible',
      (tester) async {
    await tester.pumpWidget(_app(reduced: true, order: 6));
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app());
    expect(_opacity(tester), 1);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('platform $feature is respected even with a custom MediaQuery',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(_app());
      expect(_opacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('enabling reduced motion finishes rather than pausing a ticker',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(_app(reduced: true));
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app());
    expect(_opacity(tester), 1);
  });

  testWidgets('a platform reduce-motion change immediately finishes motion',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 40));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    expect(_opacity(tester), 1);
  });

  testWidgets('disabled TickerMode starts at the final state and never replays',
      (tester) async {
    await tester.pumpWidget(_app(tickerEnabled: false));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_app());
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disabling TickerMode mid-flight stops and finishes the ticker',
      (tester) async {
    await tester.pumpWidget(_app(order: 6));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpWidget(_app(tickerEnabled: false));
    expect(_opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app());
    expect(_opacity(tester), 1);
  });

  testWidgets('stable identities survive disposal and scroll-style remounts',
      (tester) async {
    Widget row(String id) => AppEntrance(
          key: ValueKey(id),
          identity: ('row', id),
          child: const SizedBox(width: 40, height: 40),
        );
    await tester.pumpWidget(_app(child: row('a')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(child: const SizedBox.shrink()));
    await tester.pumpWidget(_app(child: row('a')));
    expect(_opacity(tester, const ValueKey('a')), 1);
    await tester.pumpWidget(_app(child: row('b')));
    expect(_opacity(tester, const ValueKey('b')), 0);
    await tester.pumpWidget(_app(child: row('a')));
    expect(_opacity(tester, const ValueKey('a')), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'reused unkeyed state remembers changed content without replaying',
      (tester) async {
    await tester.pumpWidget(_app(identity: 'a'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(identity: 'b'));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_app(child: const SizedBox.shrink()));
    await tester.pumpWidget(_app(identity: 'b'));
    expect(_opacity(tester), 1);
  });

  testWidgets(
      'bounded appearance memory saturates instead of evicting old rows',
      (tester) async {
    Widget row(String id) => AppEntrance(
          key: ValueKey(id),
          identity: id,
          child: const SizedBox(width: 10, height: 10),
        );
    await tester.pumpWidget(_app(
      memory: 3,
      child: Row(children: [row('a'), row('b'), row('c')]),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(memory: 3, child: row('d')));
    expect(_opacity(tester, const ValueKey('d')), 1);
    await tester.pumpWidget(_app(memory: 3, child: row('a')));
    expect(_opacity(tester, const ValueKey('a')), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('concurrency is bounded and completed controllers release slots',
      (tester) async {
    Widget row(String id) => AppEntrance(
          key: ValueKey(id),
          identity: id,
          child: const SizedBox(width: 10, height: 10),
        );
    await tester.pumpWidget(_app(
      concurrency: 2,
      child: Row(children: [row('a'), row('b'), row('c'), row('d')]),
    ));
    expect(_opacity(tester, const ValueKey('a')), 0);
    expect(_opacity(tester, const ValueKey('b')), 0);
    expect(_opacity(tester, const ValueKey('c')), 1);
    expect(_opacity(tester, const ValueKey('d')), 1);
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(concurrency: 2, child: row('e')));
    expect(_opacity(tester, const ValueKey('e')), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('nested entrances apply only one fade and one translation',
      (tester) async {
    const innerKey = ValueKey('inner');
    await tester.pumpWidget(_app(
      child: const AppEntrance(
        key: _entrance,
        child: AppEntrance(
          key: innerKey,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    ));
    expect(_opacity(tester), 0);
    expect(_opacity(tester, innerKey), 1);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets(
      'startup readiness preloads children without consuming their entry',
      (tester) async {
    var builds = 0;
    final content = AppEntranceScope(
      child: AppEntrance(
        key: _entrance,
        identity: 'preloaded',
        child: _CountBuilds(() => builds++),
      ),
    );
    await tester.pumpWidget(_app(ready: false, child: content));
    expect(builds, 1);
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(seconds: 5));
    expect(_opacity(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app(child: content));
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(builds, 1);
    await tester.pumpWidget(_app(ready: false, child: content));
    expect(_opacity(tester), 1, reason: 'Readiness is not a replay trigger.');
  });

  testWidgets('semantics, taps and long press remain available during entry',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    var holds = 0;
    const buttonKey = ValueKey('button');
    await tester.pumpWidget(_app(
      child: AppEntrance(
        key: _entrance,
        child: Semantics(
          label: 'Music action',
          button: true,
          child: GestureDetector(
            key: buttonKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            onLongPress: () => holds++,
            child: const SizedBox(width: 100, height: 48),
          ),
        ),
      ),
    ));
    expect(find.bySemanticsLabel('Music action'), findsOneWidget);
    await tester.tap(find.byKey(buttonKey));
    expect(taps, 1);
    await tester.longPress(find.byKey(buttonKey));
    expect(holds, 1);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposing during stagger or readiness leaves no timers or tickers',
      (tester) async {
    await tester.pumpWidget(_app(order: 6));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app(ready: false));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
