import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'category_pointer_glow_test.dart' as capture;

void main() {
  testWidgets(
      'scroll cancels the first circle hover before its scheduled frame',
      (tester) async {
    final cover = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: 160,
        height: 230,
        child: CoverPointerScope(
            child: ListView(
          controller: scroll,
          children: [
            RepaintBoundary(
                key: cover,
                child: const SizedBox(
                  height: 200,
                  child: CategoryPointerGlow(
                      circle: true,
                      child: ColoredBox(color: Color(0xff080c10))),
                )),
            const SizedBox(height: 500),
          ],
        )),
      ))),
    ));
    await tester.pumpAndSettle();
    final baseline = await capture.pixels(tester, cover);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    final origin = tester.getTopLeft(find.byKey(cover));
    await pointer.moveTo(origin + const Offset(80, 30));
    // Both local and shared samples are queued, but neither notifier has
    // published a value yet. Clearing null must still cancel the local sample.
    scroll.jumpTo(16);
    await tester.pump();
    expect(await capture.pixels(tester, cover), orderedEquals(baseline));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await pointer.removePointer();
  });

  testWidgets('scroll clears local circle glow before switching to rectangle',
      (tester) async {
    final cover = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var circle = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
        width: 160,
        height: 230,
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return CoverPointerScope(
              child: ListView(
            controller: scroll,
            children: [
              RepaintBoundary(
                  key: cover,
                  child: SizedBox(
                      height: 200,
                      child: CategoryPointerGlow(
                          circle: circle,
                          child: const ColoredBox(color: Color(0xff080c10))))),
              const SizedBox(height: 500),
            ],
          ));
        }),
      ),
    ))));
    await tester.pumpAndSettle();
    final baseline = await capture.pixels(tester, cover);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    final origin = tester.getTopLeft(find.byKey(cover));
    await pointer.moveTo(origin + const Offset(80, 30));
    await tester.pump();
    expect(await capture.pixels(tester, cover), isNot(orderedEquals(baseline)));
    // The mouse still intersects the circle; only scrolling changes its local
    // coordinate. Hover events are not emitted for a stationary mouse.
    scroll.jumpTo(16);
    await tester.pump();
    update(() => circle = false);
    await tester.pump();
    expect(await capture.pixels(tester, cover), orderedEquals(baseline),
        reason: 'The old local hover sample must not reappear in another shape '
            'after the shared scope cleared its pointer on scroll');
    await pointer.removePointer();
  });
}
