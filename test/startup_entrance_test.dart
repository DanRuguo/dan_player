import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/startup_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentKey = ValueKey('preloaded-content');

double _contentOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .descendant(of: find.byKey(_contentKey), matching: find.byType(Opacity))
        .first)
    .opacity;

class _PreloadProbe extends StatefulWidget {
  const _PreloadProbe({required this.onInit, required this.onDispose});
  final VoidCallback onInit;
  final VoidCallback onDispose;

  @override
  State<_PreloadProbe> createState() => _PreloadProbeState();
}

class _PreloadProbeState extends State<_PreloadProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Ready content');
}

void main() {
  testWidgets('splash preloads once and reveals only after its overlay leaves',
      (tester) async {
    var initializations = 0;
    var disposals = 0;
    await tester.pumpWidget(MaterialApp(
      home: StartupSplash(
        minimumVisibleDuration: const Duration(milliseconds: 100),
        fadeDuration: const Duration(milliseconds: 100),
        child: AppEntranceScope(
          child: AppEntrance(
            key: _contentKey,
            identity: 'startup-content',
            child: _PreloadProbe(
              onInit: () => initializations++,
              onDispose: () => disposals++,
            ),
          ),
        ),
      ),
    ));
    expect(initializations, 1);
    expect(_contentOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_contentOpacity(tester), 0);
    // Observe the actual overlay rather than coupling this lifecycle test to
    // the particular opacity widget used by the brand sequence.
    for (var frame = 0;
        frame < 40 &&
            find.byKey(StartupSplash.overlayKey).evaluate().isNotEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(StartupSplash.overlayKey).evaluate().isNotEmpty) {
        expect(_contentOpacity(tester), 0);
      }
    }
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
    expect(_contentOpacity(tester), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(_contentOpacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(_contentOpacity(tester), 1);
    expect(initializations, 1);
    expect(disposals, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposals, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion splash content is already at its final state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: StartupSplash(
          minimumVisibleDuration: Duration(milliseconds: 100),
          fadeDuration: Duration(milliseconds: 100),
          child: AppEntrance(
            key: _contentKey,
            child: Text('Reduced motion'),
          ),
        ),
      ),
    ));
    expect(_contentOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(_contentOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disposing before splash readiness cancels both timer and entry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: StartupSplash(
        child: AppEntrance(key: _contentKey, child: Text('Loading')),
      ),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
