import 'dart:typed_data';

import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:dan_player/component/category_tile_motion.dart';
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
            (await image.toByteData())!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

class _PaintCount extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_PaintCount oldDelegate) => false;
}

void main() {
  for (final circle in [false, true]) {
    testWidgets(
        'stationary pointer stays anchored during tile motion ($circle)',
        (tester) async {
      final key = GlobalKey();
      final artwork = _PaintCount();
      var rect = const Rect.fromLTWH(100, 100, 160, 160);
      late StateSetter update;
      await tester.pumpWidget(
          MaterialApp(home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return CoverPointerScope(
            child: Stack(children: [
          Positioned.fromRect(
              rect: rect,
              child: CategoryTileMotion(
                  rect: rect,
                  linear: true,
                  child: RepaintBoundary(
                      key: key,
                      child: CategoryPointerGlow(
                          circle: circle,
                          child: CustomPaint(painter: artwork)))))
        ]));
      })));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      const pointer = Offset(185, 180);
      await mouse.moveTo(pointer);
      await tester.pump();
      final initial = await _pixels(tester, key);
      final paints = artwork.paints;
      update(() => rect = const Rect.fromLTWH(160, 100, 160, 160));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final stationary = await _pixels(tester, key);
      expect(stationary, isNot(orderedEquals(initial)),
          reason:
              'The light must remain at the screen pointer as the tile moves');
      await mouse.moveTo(pointer);
      await tester.pump();
      expect(await _pixels(tester, key), orderedEquals(stationary),
          reason:
              'A fresh hover sample must not correct a stale local position');
      expect(artwork.paints, paints,
          reason: 'Geometry and pointer feedback must reuse the artwork layer');
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.moveTo(const Offset(600, 180));
      await tester.pump();
      final unlit = await _pixels(tester, key);
      update(() => rect = const Rect.fromLTWH(550, 100, 160, 160));
      await tester.pumpAndSettle();
      expect(await _pixels(tester, key), isNot(orderedEquals(unlit)),
          reason: 'A distant tile can enter the stationary pointer light');
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(await _pixels(tester, key), orderedEquals(unlit),
          reason: 'Leaving must also clear a tile lit only by layout motion');
      await mouse.removePointer();
    });
  }

  testWidgets('rectangle glow reaches the full gradient radius without popping',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: CoverPointerScope(
            child: Stack(children: [
      Positioned(
          left: 200,
          top: 100,
          width: 160,
          height: 160,
          child: RepaintBoundary(
              key: key,
              child: const CategoryPointerGlow(
                  child: ColoredBox(color: Colors.black))))
    ]))));
    await tester.pumpAndSettle();
    final before = await _pixels(tester, key);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(110, 180));
    await tester.pump();
    expect(await _pixels(tester, key), isNot(orderedEquals(before)),
        reason: 'A 140 px gradient must not be discarded at 72 px');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mouse.removePointer();
  });

  testWidgets('hidden pointer scopes drop queued samples and schedule no work',
      (tester) async {
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return TickerMode(
          enabled: enabled,
          child: const CoverPointerScope(
              child:
                  CategoryPointerGlow(child: ColoredBox(color: Colors.black))));
    })));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(100, 100));
    update(() => enabled = false);
    await tester.pump();
    await tester.pump();
    await mouse.moveTo(const Offset(120, 120));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mouse.removePointer();
  });
}
