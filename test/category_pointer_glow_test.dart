import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> pixels(WidgetTester tester, GlobalKey key,
    {String? name}) async {
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      const output = String.fromEnvironment('DAN_GLOW_RENDER');
      if (output.isNotEmpty && name != null) {
        await Directory(output).create(recursive: true);
        await File('$output/$name.png').writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List());
      }
      return Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

double difference(Uint8List before, Uint8List after, Rect area) {
  var sum = 0.0;
  var count = 0;
  for (var y = area.top.toInt(); y < area.bottom; y++) {
    for (var x = area.left.toInt(); x < area.right; x++) {
      for (var channel = 0; channel < 3; channel++) {
        final index = (y * 160 + x) * 4 + channel;
        sum += (before[index] - after[index]).abs();
        count++;
      }
    }
  }
  return sum / count;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('shared gutter reveal reaches neighbors only: dark=$dark',
        (tester) async {
      final keys = List.generate(3, (_) => GlobalKey());
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: Center(
                  child: CoverPointerScope(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              RepaintBoundary(
                  key: keys[i],
                  child: SizedBox(
                      width: 160,
                      height: 160,
                      child: CategoryPointerGlow(
                          child: ColoredBox(
                              color: dark
                                  ? const Color(0xff080c10)
                                  : const Color(0xfffaf7ee)))))
            ]
          ]))))));
      await tester.pumpAndSettle();
      final before = <Uint8List>[];
      for (final key in keys) {
        before.add(await pixels(tester, key));
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final origin = tester.getTopLeft(find.byKey(keys.first));
      for (final x in [159.0, 162.0]) {
        await mouse.moveTo(origin + Offset(x, 80));
        await tester.pump();
        final neighbor = await pixels(tester, keys[1],
            name: 'neighbor-${dark ? 'dark' : 'light'}-$x');
        expect(
            difference(before[1], neighbor, const Rect.fromLTRB(1, 75, 3, 85)),
            greaterThan(20));
        expect(await pixels(tester, keys[2]), orderedEquals(before[2]));
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(await pixels(tester, keys[1]), orderedEquals(before[1]));
      await mouse.removePointer();
    });
    for (final circle in [false, true]) {
      testWidgets(
          'edge reveal contrast, exit and idle: dark=$dark circle=$circle',
          (tester) async {
        final key = GlobalKey();
        tester.view.physicalSize = const Size(400, 300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: dark ? Brightness.dark : Brightness.light,
          )),
          home: Scaffold(
              body: Center(
                  child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 160,
              height: 200,
              child: CategoryPointerGlow(
                  circle: circle,
                  child: ColoredBox(
                      color: dark
                          ? const Color(0xff080c10)
                          : const Color(0xfffaf7ee))),
            ),
          ))),
        ));
        await tester.pumpAndSettle();
        final before = await pixels(tester, key);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(10, 10));
        final top = tester.getTopLeft(find.byKey(key));
        await mouse.moveTo(top + const Offset(80, 4));
        await tester.pump();
        final edge = await pixels(tester, key,
            name:
                'edge-${dark ? 'dark' : 'light'}-${circle ? 'circle' : 'tile'}');
        // The top stroke is visibly different on near-white and near-black art.
        expect(difference(before, edge, const Rect.fromLTRB(75, 1, 85, 3)),
            greaterThan(25));
        expect(difference(before, edge, const Rect.fromLTRB(75, 156, 85, 159)),
            lessThan(1));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(seconds: 5));
        expect(await pixels(tester, key), orderedEquals(edge));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await mouse.moveTo(const Offset(10, 10));
        await tester.pump();
        expect(await pixels(tester, key), orderedEquals(before));
        if (circle) {
          await mouse.moveTo(top + const Offset(80, 185));
          await tester.pump();
          expect(await pixels(tester, key), orderedEquals(before),
              reason: 'Caption hover must not light the circle');
        }
        await mouse.removePointer();
      });
    }
  }
}
