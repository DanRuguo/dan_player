import 'dart:ui' as raster;

import 'package:dan_player/component/process_resource_chart.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _redPixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final data =
            await image.toByteData(format: raster.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        var red = 0;
        for (var index = 0; index < bytes.length; index += 4) {
          if (bytes[index] > 180 &&
              bytes[index + 1] < 100 &&
              bytes[index + 2] < 100 &&
              bytes[index + 3] > 100) {
            red++;
          }
        }
        return red;
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  Widget host(GlobalKey key,
          {required List<double?> history,
          double? value,
          ProcessResourceDisplay mode = ProcessResourceDisplay.line}) =>
      MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 64,
                      height: 12,
                      child: Align(
                          child: ProcessResourceChart(
                              history: history,
                              value: value,
                              maximum: 100,
                              mode: mode,
                              color: Colors.red,
                              track: Colors.grey,
                              height: mode == ProcessResourceDisplay.line
                                  ? 12
                                  : 4))))));

  testWidgets(
      'tiny line retains an isolated valid sample between unknown values',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(host(key, history: [null, 25, null]));
    await tester.pump();
    expect(tester.getSize(find.byType(CustomPaint).last).width, 64);
    expect(await _redPixels(tester, key), greaterThan(0));
    await tester.pumpWidget(host(key, history: [null, null, null]));
    await tester.pump();
    expect(await _redPixels(tester, key), 0);
  });

  testWidgets(
      'tiny bars fill loose alignment width and never fabricate missing values',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
        host(key, history: [], value: 50, mode: ProcessResourceDisplay.bar));
    await tester.pump();
    expect(tester.getSize(find.byType(CustomPaint).last), const Size(64, 4));
    expect(await _redPixels(tester, key), greaterThan(80));
    await tester
        .pumpWidget(host(key, history: [], mode: ProcessResourceDisplay.bar));
    await tester.pump();
    expect(await _redPixels(tester, key), 0);
  });
}
