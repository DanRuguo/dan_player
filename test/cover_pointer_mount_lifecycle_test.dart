import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return Uint8List.fromList(
            (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final circle in [false, true]) {
    for (final action in ['exit', 'hide', 'shape then exit']) {
      testWidgets(
          'new cover under stationary pointer clears on $action circle=$circle',
          (tester) async {
        final boundary = GlobalKey();
        var mounted = false, visible = true;
        var currentCircle = circle;
        late StateSetter update;
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
          child: StatefulBuilder(builder: (context, setState) {
            update = setState;
            return TickerMode(
                enabled: visible,
                child: CoverPointerScope(
                    child: SizedBox(
                  width: 330,
                  height: 200,
                  child: Row(children: [
                    const SizedBox(
                        width: 160,
                        height: 200,
                        child: CategoryPointerGlow(
                            child: ColoredBox(color: Colors.black))),
                    const SizedBox(width: 10),
                    RepaintBoundary(
                        key: boundary,
                        child: SizedBox(
                            width: 160,
                            height: 200,
                            child: mounted
                                ? CategoryPointerGlow(
                                    circle: currentCircle,
                                    child:
                                        const ColoredBox(color: Colors.black))
                                : const ColoredBox(color: Colors.black)))
                  ]),
                )));
          }),
        ))));
        await tester.pumpAndSettle();
        final baseline = await _pixels(tester, boundary);
        final pointer =
            await tester.createGesture(kind: PointerDeviceKind.mouse);
        await pointer.addPointer(location: const Offset(10, 10));
        await pointer.moveTo(
            tester.getTopLeft(find.byKey(boundary)) + const Offset(80, 4));
        await tester.pump();
        update(() => mounted = true);
        await tester.pump();
        final lit = await _pixels(tester, boundary);
        expect(lit, isNot(orderedEquals(baseline)),
            reason:
                'A cover mounted beneath a stationary pointer must show the shared light');
        if (action == 'hide') {
          update(() => visible = false);
          await tester.pump();
          update(() => visible = true);
        } else {
          if (action == 'shape then exit') {
            update(() => currentCircle = !currentCircle);
            await tester.pump();
            expect(await _pixels(tester, boundary),
                isNot(orderedEquals(baseline)));
          }
          await pointer.moveTo(const Offset(10, 10));
        }
        await tester.pumpAndSettle();
        expect(await _pixels(tester, boundary), orderedEquals(baseline),
            reason:
                'The newly mounted cover must retire its first cached glow when the scope clears');
        expect(tester.binding.transientCallbackCount, 0);
        await pointer.removePointer();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
