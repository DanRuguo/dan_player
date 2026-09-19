import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountPaint extends CustomPainter {
  _CountPaint(this.count);
  final void Function() count;
  @override
  void paint(Canvas canvas, Size size) {
    count();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blueGrey);
  }

  @override
  bool shouldRepaint(_CountPaint oldDelegate) => false;
}

void main() {
  testWidgets('burst samples coalesce without repainting cover contents',
      (tester) async {
    var artworkPaints = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: CoverPointerScope(
          child: SizedBox(
        width: 160,
        height: 160,
        child: CategoryPointerGlow(
            child: CustomPaint(
          painter: _CountPaint(() => artworkPaints++),
        )),
      )),
    ))));
    await tester.pumpAndSettle();
    final initialPaints = artworkPaints;
    final glow = tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byType(CategoryPointerGlow),
            matching: find.byType(CustomPaint)))
        .singleWhere((paint) => paint.foregroundPainter != null)
        .foregroundPainter!;
    var notifications = 0;
    glow.addListener(() => notifications++);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final origin = tester.getTopLeft(find.byType(CategoryPointerGlow));
    for (var frame = 0; frame < 20; frame++) {
      final before = notifications;
      for (var sample = 0; sample < 100; sample++) {
        await mouse.moveTo(
            origin + Offset(1 + sample.toDouble(), 20 + frame.toDouble()));
      }
      // A 1 kHz device must not walk every cover on every hardware sample.
      expect(notifications, before);
      await tester.pump(const Duration(milliseconds: 16));
      expect(notifications, before + 1);
      expect(artworkPaints, initialPaints);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    // Exit cancels a pending sample; it must never relight a stale cover.
    await mouse.moveTo(origin + const Offset(10, 10));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    final exitCount = notifications;
    await tester.pump(const Duration(seconds: 5));
    expect(notifications, exitCount);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(artworkPaints, initialPaints);
    await mouse.removePointer();
  });

  testWidgets('scroll cancels pending hover and fresh input uses new geometry',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          width: 160,
          height: 160,
          child: CoverPointerScope(
            child: ListView.builder(
              controller: scroll,
              itemCount: 30,
              itemExtent: 160,
              itemBuilder: (_, i) => CategoryPointerGlow(
                  key: ValueKey(i),
                  child: const ColoredBox(color: Colors.grey)),
            ),
          )),
    ))));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getTopLeft(find.byKey(const ValueKey(0))) +
        const Offset(80, 80));
    scroll.jumpTo(320);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mouse.moveTo(tester.getTopLeft(find.byKey(const ValueKey(2))) +
        const Offset(80, 40));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
