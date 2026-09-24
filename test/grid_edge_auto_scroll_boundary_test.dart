import 'package:dan_player/component/adaptive_grid_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edge scroll stops on grid exit, hide and controller switch',
      (tester) async {
    final scroll = ScrollController();
    final replacement = ScrollController();
    ScrollController activeScroll = scroll;
    final dragKey = UniqueKey();
    var visible = true;
    late StateSetter update;
    addTearDown(scroll.dispose);
    addTearDown(replacement.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(builder: (context, setState) {
            update = setState;
            return TickerMode(
                enabled: visible,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: GridEdgeAutoScrollRegion(
                    controller: activeScroll,
                    child: Stack(children: [
                      ListView.builder(
                        controller: activeScroll,
                        itemCount: 40,
                        itemExtent: 40,
                        itemBuilder: (_, index) => Text('Row $index'),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 200,
                        height: 40,
                        child: AdaptiveGridDragSource<String>(
                          dragKey: dragKey,
                          data: 'row',
                          feedback: const SizedBox(width: 40, height: 40),
                          child: const ColoredBox(color: Colors.blue),
                        ),
                      ),
                    ]),
                  ),
                ));
          }),
        ),
      ),
    ));

    final rect = tester.getRect(find.byType(GridEdgeAutoScrollRegion));
    final drag = await tester.startGesture(rect.topCenter + const Offset(0, 20),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    await drag.moveTo(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump(const Duration(milliseconds: 120));
    expect(scroll.offset, greaterThan(0));

    await drag.moveTo(Offset(rect.right + 80, rect.bottom - 2));
    await tester.pump(const Duration(milliseconds: 16));
    final atExit = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, atExit);

    await drag.moveTo(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, greaterThan(atExit));
    update(() => visible = false);
    await tester.pump();
    final atHide = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, atHide);

    update(() {
      visible = true;
      activeScroll = replacement;
    });
    await tester.pump();
    await drag.moveTo(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(replacement.offset, greaterThan(0));
    update(() => activeScroll = scroll);
    await tester.pump();
    final afterRebind = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, afterRebind);
    await drag.up();
    await tester.pump();
  });
}
