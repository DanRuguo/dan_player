import 'dart:ui' as drawing;

import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _TransformCounter extends SingleChildRenderObjectWidget {
  const _TransformCounter({required this.count, required super.child});
  final VoidCallback count;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CountTransform(count);
}

class _CountTransform extends RenderProxyBox {
  _CountTransform(this.count);
  final VoidCallback count;
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    count();
    super.applyPaintTransform(child, transform);
  }
}

class _Artwork extends CustomPainter {
  _Artwork(this.count);
  final VoidCallback count;
  @override
  void paint(Canvas canvas, Size size) {
    count();
    canvas.drawColor(Colors.black, BlendMode.src);
  }

  @override
  bool shouldRepaint(_Artwork oldDelegate) => false;
}

Future<int> _pixel(WidgetTester tester, GlobalKey key, int x) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData(
                format: drawing.ImageByteFormat.rawRgba))!
            .getUint8((80 * image.width + x) * 4);
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final shared in [false, true]) {
    testWidgets('held samples transform once per frame shared=$shared',
        (tester) async {
      var transforms = 0, paints = 0;
      Widget body = CategoryPointerGlow(
          child: CustomPaint(painter: _Artwork(() => paints++)));
      if (shared) body = CoverPointerScope(child: body);
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: _TransformCounter(
        count: () => transforms++,
        child: SizedBox(width: 420, height: 160, child: body),
      ))));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(CategoryPointerGlow));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(origin + const Offset(80, 80));
      await tester.pump();
      await mouse.down(origin + const Offset(80, 80));
      final before = transforms;
      final artwork = paints;
      for (var sample = 0; sample < 100; sample++) {
        await mouse.moveTo(origin + Offset(200 + sample.toDouble(), 80));
      }
      expect(transforms, before,
          reason: 'hardware events must not traverse cover geometry');
      await tester.pump(const Duration(milliseconds: 16));
      expect(transforms - before, inInclusiveRange(1, shared ? 4 : 1));
      expect(paints, artwork, reason: 'pointer input only repaints the light');
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'held pointer projects current layout after ancestor movement shared=$shared',
        (tester) async {
      final boundary = GlobalKey();
      late StateSetter change;
      var left = 100.0, width = 420.0;
      await tester
          .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
        change = setState;
        Widget body =
            const CategoryPointerGlow(child: ColoredBox(color: Colors.black));
        if (shared) body = CoverPointerScope(child: body);
        return Stack(children: [
          Positioned(
              left: left,
              top: 100,
              width: width,
              height: 160,
              child: RepaintBoundary(key: boundary, child: body))
        ]);
      })));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(180, 180));
      await tester.pump();
      await mouse.down(const Offset(180, 180));
      // The hardware event is pending before either the new ancestor
      // translation or width is laid out. Projection must use that frame's
      // geometry, not the down-time or preceding-frame transform.
      await mouse.moveTo(const Offset(640, 180));
      change(() {
        left = 300;
        width = 360;
      });
      await tester.pump();
      expect(await _pixel(tester, boundary, 340), greaterThan(20),
          reason:
              'the down-time hit-test transform no longer belongs to this layout');
      expect(await _pixel(tester, boundary, 80), 0);
      // The reverse relayout places this pending global sample outside the
      // current scope/card, even though it was inside before layout.
      await mouse.moveTo(const Offset(641, 180));
      change(() {
        left = 100;
        width = 420;
      });
      await tester.pump();
      expect(await _pixel(tester, boundary, 340), 0);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('held shared samples retain near-only paint invalidation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var transforms = 0;
    final artworkPaints = List<int>.filled(8, 0);
    final notifications = List<int>.filled(8, 0);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: _TransformCounter(
                count: () => transforms++,
                child: SizedBox(
                    width: 898,
                    height: 100,
                    child: CoverPointerScope(
                        child: Row(children: [
                      for (var card = 0; card < 8; card++) ...[
                        if (card > 0) const SizedBox(width: 14),
                        SizedBox(
                            width: 100,
                            height: 100,
                            child: CategoryPointerGlow(
                                key: ValueKey(card),
                                child: CustomPaint(
                                    painter:
                                        _Artwork(() => artworkPaints[card]++))))
                      ]
                    ])))))));
    await tester.pumpAndSettle();
    final painters = <CustomPainter>[];
    final listeners = <VoidCallback>[];
    for (var card = 0; card < 8; card++) {
      final painter = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byKey(ValueKey(card)),
              matching: find.byType(CustomPaint)))
          .map((widget) => widget.foregroundPainter)
          .firstWhere((painter) => painter != null)!;
      void listener() => notifications[card]++;
      painters.add(painter);
      listeners.add(listener);
      painter.addListener(listener);
    }
    final origin = tester.getTopLeft(find.byKey(const ValueKey(0)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(origin + const Offset(50, 50));
    await tester.pump();
    await mouse.down(origin + const Offset(50, 50));
    notifications.fillRange(0, notifications.length, 0);
    final beforeTransforms = transforms;
    final beforeArtwork = List<int>.of(artworkPaints);
    for (var sample = 0; sample < 100; sample++) {
      await mouse.moveTo(origin + Offset(60 + sample * .3, 50));
    }
    expect(transforms, beforeTransforms,
        reason: 'hardware samples only replace the pending global point');
    expect(notifications, everyElement(0));
    await tester.pump(const Duration(milliseconds: 16));
    // Keep the existing per-frame mounted-card near check. Only these first
    // two cards are within its expanded radius; distant foregrounds must not
    // receive notifications or repaint their unchanged decoded artwork.
    expect(notifications.take(2), everyElement(1));
    expect(notifications.skip(2), everyElement(0));
    expect(artworkPaints, beforeArtwork);
    debugPrint('8-card held samples: hardware transforms=0, '
        'publish/paint transforms=${transforms - beforeTransforms}, '
        'near notifications=$notifications');
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var card = 0; card < 8; card++) {
      painters[card].removeListener(listeners[card]);
    }
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
