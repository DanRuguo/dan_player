import 'package:dan_player/component/touch_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edge swipe triggers only on a completed horizontal touch',
      (tester) async {
    var swipes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TouchEdgeSwipe(
          onSwipeRight: () => swipes++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final cancelled = await tester.createGesture(kind: PointerDeviceKind.touch);
    await cancelled.down(const Offset(5, 200));
    await cancelled.moveTo(const Offset(130, 202));
    await cancelled.cancel();
    expect(swipes, 0);

    final vertical = await tester.createGesture(kind: PointerDeviceKind.touch);
    await vertical.down(const Offset(5, 200));
    await vertical.moveTo(const Offset(30, 330));
    await vertical.up();
    expect(swipes, 0);

    final horizontal =
        await tester.createGesture(kind: PointerDeviceKind.touch);
    await horizontal.down(const Offset(5, 200));
    await horizontal.moveTo(const Offset(110, 202));
    await horizontal.up();
    expect(swipes, 1);
  });

  testWidgets('cover swipe uses distance and keeps vertical motion inert',
      (tester) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TouchTrackSwipe(
          onPrevious: () => previous++,
          onNext: () => next++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final vertical = await tester.createGesture(kind: PointerDeviceKind.touch);
    await vertical.down(const Offset(300, 200));
    await vertical.moveTo(const Offset(305, 340));
    await vertical.up();
    expect((previous, next), (0, 0));

    final left = await tester.createGesture(kind: PointerDeviceKind.touch);
    await left.down(const Offset(300, 200));
    await left.moveTo(const Offset(200, 202));
    await left.up();
    expect((previous, next), (0, 1));

    final right = await tester.createGesture(kind: PointerDeviceKind.touch);
    await right.down(const Offset(200, 200));
    await right.moveTo(const Offset(300, 202));
    await right.up();
    expect((previous, next), (1, 1));
  });
}
