import 'package:dan_player/component/background_image_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  bool playing = true,
  bool visible = true,
  bool enabled = true,
  bool ticker = true,
  bool reduced = false,
  bool contrast = false,
  ValueListenable<bool>? hidden,
  Widget child = const SizedBox.expand(),
}) =>
    MaterialApp(
      home: MediaQuery(
        data:
            MediaQueryData(disableAnimations: reduced, highContrast: contrast),
        child: TickerMode(
          enabled: ticker,
          child: BackgroundImageMotion(
            enabled: enabled,
            isPlaying: playing,
            isVisible: visible,
            hidden: hidden,
            child: child,
          ),
        ),
      ),
    );

double _phase(WidgetTester tester) => tester
    .widget<ValueListenableBuilder<double>>(find.descendant(
      of: find.byType(BackgroundImageMotion),
      matching: find.byType(ValueListenableBuilder<double>),
    ))
    .valueListenable
    .value;

class _CountingChild extends StatelessWidget {
  const _CountingChild(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const ColoredBox(color: Colors.teal);
  }
}

class _Hidden extends ValueNotifier<bool> {
  _Hidden(super.value);
  bool get observed => hasListeners;
}

void main() {
  testWidgets(
      'a low-frequency clock updates only the transform, not its texture',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(_app(child: _CountingChild(() => builds++)));
    expect(_phase(tester), 0);
    await tester.pump(const Duration(milliseconds: 49));
    expect(_phase(tester), 0);
    await tester.pump(const Duration(milliseconds: 1));
    final oneFrame = _phase(tester);
    expect(oneFrame, closeTo(1 / 720, 1e-10));
    for (var index = 0; index < 19; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_phase(tester), closeTo(1 / 36, 1e-10));
    expect(builds, 1);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing,
        reason: 'motion itself does not create a costly per-frame blur');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('paused playback freezes and resume continues without resetting',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    final before = _phase(tester);
    await tester.pumpWidget(_app(playing: false));
    await tester.pump(const Duration(seconds: 2));
    expect(_phase(tester), before);
    await tester.pumpWidget(_app());
    expect(_phase(tester), before);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_phase(tester), greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['invisible', 'ticker', 'reduced', 'highContrast']) {
    testWidgets('$mode never starts a decorative timer', (tester) async {
      await tester.pumpWidget(_app(
        visible: mode != 'invisible',
        ticker: mode != 'ticker',
        reduced: mode == 'reduced',
        contrast: mode == 'highContrast',
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(_phase(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final mode in ['reduceMotion', 'disableAnimations', 'highContrast']) {
    testWidgets('platform $mode disables the clock independently of MediaQuery',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        reduceMotion: mode == 'reduceMotion',
        disableAnimations: mode == 'disableAnimations',
        highContrast: mode == 'highContrast',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 2));
      expect(_phase(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('native hidden signal stops immediately without a rebuild',
      (tester) async {
    final hidden = _Hidden(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_app(hidden: hidden));
    expect(hidden.observed, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    final value = _phase(tester);
    hidden.value = true;
    await tester.pump(const Duration(seconds: 2));
    expect(_phase(tester), value);
    hidden.value = false;
    await tester.pump(const Duration(milliseconds: 50));
    expect(_phase(tester), greaterThan(value));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(hidden.observed, isFalse);
    hidden.value = true;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing hidden source detaches the old listener',
      (tester) async {
    final first = _Hidden(false);
    final next = _Hidden(true);
    addTearDown(first.dispose);
    addTearDown(next.dispose);
    await tester.pumpWidget(_app(hidden: first));
    await tester.pumpWidget(_app(hidden: next));
    expect(first.observed, isFalse);
    expect(next.observed, isTrue);
    first.value = true;
    await tester.pump(const Duration(seconds: 1));
    expect(_phase(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(next.observed, isFalse);
  });

  testWidgets('application pause cancels immediately and foreground resumes',
      (tester) async {
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));
    final value = _phase(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(_phase(tester), value);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_phase(tester), greaterThan(value));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covered route freezes its background until returning',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const BackgroundImageMotion(
          enabled: true, isPlaying: true, child: SizedBox.expand()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    final phase = tester
        .widget<ValueListenableBuilder<double>>(
            find.byType(ValueListenableBuilder<double>))
        .valueListenable;
    navigator.currentState!.push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const SizedBox.expand(),
    ));
    await tester.pump();
    final stopped = phase.value;
    await tester.pump(const Duration(seconds: 2));
    expect(phase.value, stopped);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(phase.value, greaterThan(stopped));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'disabled motion preserves the exact child and never schedules frames',
      (tester) async {
    await tester
        .pumpWidget(_app(enabled: false, child: const Text('unchanged')));
    expect(
        find.byKey(const ValueKey('background-motion-offset')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('unchanged'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
