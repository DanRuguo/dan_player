import 'package:dan_player/component/adaptive_grid_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Scene {
  final scroll = ScrollController();

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 240,
                    height: 240,
                    child: GridEdgeAutoScrollRegion(
                        controller: scroll,
                        child: Stack(children: [
                          ListView.builder(
                              controller: scroll,
                              itemCount: 100,
                              itemExtent: 40,
                              itemBuilder: (_, index) => Text('Row $index')),
                          Positioned(
                              left: 0,
                              top: 0,
                              width: 240,
                              height: 40,
                              child: AdaptiveGridDragSource<_Scene>(
                                  dragKey: const ValueKey('source'),
                                  data: this,
                                  feedback:
                                      const SizedBox(width: 40, height: 40),
                                  child: const ColoredBox(color: Colors.blue)))
                        ])))))));
  }

  Future<TestGesture> begin(WidgetTester tester, PointerDeviceKind kind) async {
    final rect = tester.getRect(find.byType(GridEdgeAutoScrollRegion));
    final primary = await tester.startGesture(
        rect.topCenter + const Offset(0, 20),
        kind: kind,
        pointer: 101);
    if (kind == PointerDeviceKind.touch) {
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    }
    await primary.moveBy(const Offset(20, 0));
    await tester.pump();
    await primary.moveTo(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump(const Duration(milliseconds: 120));
    expect(scroll.offset, greaterThan(0));
    return primary;
  }

  Future<TestGesture> drag(WidgetTester tester, PointerDeviceKind kind) async {
    await mount(tester);
    return begin(tester, kind);
  }

  Future<TestGesture> secondary(WidgetTester tester) => tester.startGesture(
      tester.getCenter(find.byType(GridEdgeAutoScrollRegion)) +
          const Offset(-80, 0),
      pointer: 102);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  }
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
        '${kind.name} edge ownership ignores a coincident older contact',
        (tester) async {
      final scene = _Scene();
      try {
        await scene.mount(tester);
        final rect = tester.getRect(find.byType(GridEdgeAutoScrollRegion));
        final secondary = await tester.startGesture(
            Offset(rect.center.dx, rect.bottom - 2),
            pointer: 102);
        final primary = await scene.begin(tester, kind);
        await secondary.up();
        final before = scene.scroll.offset;
        await tester.pump(const Duration(milliseconds: 160));
        expect(scene.scroll.offset, greaterThan(before + 40),
            reason: 'equal pointer positions do not transfer drag ownership '
                'to an older unrelated contact');
        await primary.cancel();
        final stopped = scene.scroll.offset;
        await tester.pump(const Duration(milliseconds: 300));
        expect(scene.scroll.offset, stopped);
        expect(tester.takeException(), isNull);
      } finally {
        await scene.close(tester);
      }
    });

    for (final cancelSecondary in [false, true]) {
      testWidgets(
          '${kind.name} edge drag survives unrelated pointer ${cancelSecondary ? 'cancel' : 'up'}',
          (tester) async {
        final scene = _Scene();
        try {
          final primary = await scene.drag(tester, kind);
          final secondary = await scene.secondary(tester);
          if (cancelSecondary) {
            await secondary.cancel();
          } else {
            await secondary.up();
          }
          final before = scene.scroll.offset;
          await tester.pump(const Duration(milliseconds: 160));
          expect(scene.scroll.offset, greaterThan(before + 40),
              reason: 'a contact that never owns the card drag cannot release '
                  'its stationary edge-scroll timer');
          await primary.cancel();
          final stopped = scene.scroll.offset;
          await tester.pump(const Duration(milliseconds: 300));
          expect(scene.scroll.offset, stopped);
          expect(tester.takeException(), isNull);
        } finally {
          await scene.close(tester);
        }
      });
    }

    testWidgets('${kind.name} owner release stops with another contact held',
        (tester) async {
      final scene = _Scene();
      try {
        final primary = await scene.drag(tester, kind);
        final secondary = await scene.secondary(tester);
        await primary.up();
        final stopped = scene.scroll.offset;
        await tester.pump(const Duration(milliseconds: 300));
        expect(scene.scroll.offset, stopped,
            reason: 'a held unrelated contact does not prolong the drag');
        await secondary.cancel();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await scene.close(tester);
      }
    });
  }
}
