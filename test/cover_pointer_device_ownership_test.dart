import 'dart:ui' as drawing;

import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _pixel(
    WidgetTester tester, GlobalKey boundary, Offset point) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes =
          await image.toByteData(format: drawing.ImageByteFormat.rawRgba);
      final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      return bytes!.getUint8(offset);
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final shared in [false, true]) {
    for (final pending in [false, true]) {
      for (final samePoint in [false, true]) {
        testWidgets(
            'older hover device exit keeps the newer glow shared=$shared pending=$pending same=$samePoint',
            (tester) async {
          final boundary = GlobalKey();
          Widget cover() => const CategoryPointerGlow(
              child: SizedBox.expand(child: ColoredBox(color: Colors.black)));
          Widget body = SizedBox(
              width: 420,
              height: 160,
              child: shared
                  ? Stack(children: [
                      Positioned(
                          left: 0,
                          top: 0,
                          width: 160,
                          height: 160,
                          child: cover()),
                      Positioned(
                          left: 260,
                          top: 0,
                          width: 160,
                          height: 160,
                          child: cover()),
                    ])
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(dimension: 160, child: cover())));
          if (shared) body = CoverPointerScope(child: body);
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: Center(
                      child: RepaintBoundary(key: boundary, child: body)))));
          await tester.pumpAndSettle();
          final origin = tester.getTopLeft(find.byKey(boundary));
          final oldPoint = origin + const Offset(40, 80);
          final latestPoint =
              samePoint ? oldPoint : origin + Offset(shared ? 340 : 110, 80);
          for (final device in [11, 22]) {
            await tester.sendEventToBinding(PointerAddedEvent(
                device: device,
                kind: PointerDeviceKind.mouse,
                position: Offset.zero));
          }
          addTearDown(() async {
            for (final device in [11, 22]) {
              await tester.sendEventToBinding(PointerRemovedEvent(
                  device: device, kind: PointerDeviceKind.mouse));
            }
          });
          await tester.sendEventToBinding(PointerHoverEvent(
              device: 11, kind: PointerDeviceKind.mouse, position: oldPoint));
          await tester.pump();
          await tester.sendEventToBinding(PointerHoverEvent(
              device: 22,
              kind: PointerDeviceKind.mouse,
              position: latestPoint));
          if (!pending) {
            await tester.pump();
            expect(await _pixel(tester, boundary, latestPoint - origin),
                greaterThan(20));
          }
          // Device 22 remains over the cover. The older mouse moves out of both
          // the tile and scope; its exit must not revoke the latest live sample.
          await tester.sendEventToBinding(const PointerHoverEvent(
              device: 11,
              kind: PointerDeviceKind.mouse,
              position: Offset.zero));
          await tester.pump();
          expect(await _pixel(tester, boundary, latestPoint - origin),
              greaterThan(20));
          await tester.sendEventToBinding(const PointerHoverEvent(
              device: 22,
              kind: PointerDeviceKind.mouse,
              position: Offset.zero));
          await tester.pump();
          expect(await _pixel(tester, boundary, latestPoint - origin), 0);
          expect(tester.binding.hasScheduledFrame, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
