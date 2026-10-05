import 'dart:ui' as raster;

import 'package:dan_player/component/process_resource_chart.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<(int, int)>> _coloredPixels(
        WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        final pixels = <(int, int)>[];
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final index = (y * image.width + x) * 4;
            if (bytes[index] > 180 &&
                bytes[index + 1] < 100 &&
                bytes[index + 2] < 100 &&
                bytes[index + 3] > 100) {
              pixels.add((x, y));
            }
          }
        }
        return pixels;
      } finally {
        image.dispose();
      }
    }))!;

Future<(int, int)> _coloredExtent(WidgetTester tester, GlobalKey key) async {
  var top = 1 << 30, bottom = -1;
  for (final pixel in await _coloredPixels(tester, key)) {
    if (pixel.$2 < top) top = pixel.$2;
    if (pixel.$2 > bottom) bottom = pixel.$2;
  }
  return (top, bottom);
}

void main() {
  test('low utilization and high plateaus use bounded rounded divisions', () {
    for (final samples in [
      [.2, .5],
      [98.2, 98.6],
      [0.0],
      [100.0]
    ]) {
      final scale =
          ProcessResourceChartScale.fromHistory(samples, maximum: 100);
      expect(scale.minimum, greaterThanOrEqualTo(0));
      expect(scale.maximum, lessThanOrEqualTo(100));
      expect(scale.maximum - scale.minimum, greaterThanOrEqualTo(1));
      expect(scale.maximum - scale.minimum, lessThan(2));
      expect(scale.division, .5);
      for (final sample in samples) {
        expect(sample, inInclusiveRange(scale.minimum, scale.maximum));
      }
    }
    final broad =
        ProcessResourceChartScale.fromHistory(const [0, 25, 100], maximum: 100);
    expect(broad.minimum, 0);
    expect(broad.maximum, 100);
    expect(broad.division, 50);
    final outlier = ProcessResourceChartScale.fromHistory(
        const [.1, .2, .1, 90],
        maximum: 100);
    expect(outlier.minimum, 0);
    expect(outlier.maximum, 100);
    expect(outlier.fraction(90), .9,
        reason: 'The real peak must be retained instead of cropped for zoom.');
    final plateau = ProcessResourceChartScale.fromHistory(
        const [64, 64, null, 64],
        maximum: 100);
    expect(plateau.fraction(64), .5);
  });

  test('unknown samples do not affect the range or invent utilization', () {
    final scale = ProcessResourceChartScale.fromHistory(
        const [null, double.nan, double.infinity, -1, 101, .2, .5],
        maximum: 100);
    expect(scale,
        ProcessResourceChartScale.fromHistory(const [.2, .5], maximum: 100));
    final empty =
        ProcessResourceChartScale.fromHistory(const [null], maximum: 100);
    expect(empty.minimum, 0);
    expect(empty.maximum, 100);
    for (final invalid in [0.0, -1.0, double.infinity, double.nan]) {
      final fallback =
          ProcessResourceChartScale.fromHistory(const [null], maximum: invalid);
      expect(fallback.fraction(.5), .5);
    }
  });

  test('RAM and memory ranges retain units and readable fractional divisions',
      () {
    final ram = ProcessResourceChartScale.fromHistory(const [.42, .46],
        maximum: 100, minimumSpan: .1);
    expect(ram.maximum - ram.minimum, lessThan(.2));
    expect(ram.format(ram.division), '0.05%');
    const mib = 1024.0 * 1024;
    final bytes = ProcessResourceChartScale.fromHistory(
        const [64 * mib, 64.3 * mib],
        maximum: 64.3 * mib, minimumSpan: mib);
    expect(bytes.minimum, lessThan(64 * mib));
    expect(bytes.maximum, 64.3 * mib);
    expect(bytes.maximum - bytes.minimum, greaterThanOrEqualTo(mib));
    expect(bytes.maximum - bytes.minimum, lessThan(2 * mib));
  });

  test(
      'small boundary fluctuations keep the range until expansion or meaningful contraction',
      () {
    final tracker = ProcessResourceChartScaleTracker();
    final initial = tracker.resolve([10.2, 10.3], maximum: 100);
    final quantized = ProcessResourceChartScale.fromHistory(const [10.3, 10.81],
        maximum: 100);
    expect(quantized, isNot(initial),
        reason: 'The new range crosses a rounding boundary.');
    expect(tracker.resolve([10.3, 10.81], maximum: 100), same(initial));
    final expanded = tracker.resolve([10.3, 25], maximum: 100);
    expect(expanded.maximum, greaterThanOrEqualTo(25));
    expect(expanded, isNot(initial));
    final contracted = tracker.resolve([25, 25.1], maximum: 100);
    expect(contracted.maximum - contracted.minimum,
        lessThan((expanded.maximum - expanded.minimum) / 2));
    final cleared = tracker.resolve([null], maximum: 100);
    expect(cleared.minimum, 0);
    expect(cleared.maximum, 100);
    final fresh = tracker.resolve([.2, .5], maximum: 100);
    expect(fresh.maximum, lessThan(2));
  });

  testWidgets('small sample fluctuations remain visible in a compact sparkline',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
      key: key,
      child: const SizedBox(
          width: 64,
          child: ProcessResourceChart(
            history: [.2, .5, .2],
            value: .2,
            maximum: 100,
            mode: ProcessResourceDisplay.line,
            color: Colors.red,
            track: Colors.grey,
            height: 12,
          )),
    ))));
    await tester.pump();
    final extent = await _coloredExtent(tester, key);
    expect(extent.$2 - extent.$1, greaterThanOrEqualTo(2),
        reason:
            'A fixed 0–100% axis reduces this fluctuation below one pixel.');
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'out of range values break the line and retain isolated valid dots',
      (tester) async {
    final key = GlobalKey();
    Widget host(List<double?> values) => MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: SizedBox(
                    width: 64,
                    child: ProcessResourceChart(
                        history: values,
                        value: null,
                        maximum: 100,
                        mode: ProcessResourceDisplay.line,
                        color: Colors.red,
                        track: Colors.grey,
                        height: 12)))));
    for (final invalid in [-1.0, 101.0, double.nan, double.infinity]) {
      for (final values in [
        [invalid, 40.0, invalid],
        [40.0, invalid, 40.0]
      ]) {
        await tester.pumpWidget(host(values
            .map((value) => value == invalid || !value.isFinite ? null : value)
            .toList()));
        await tester.pump();
        final reference = await _coloredPixels(tester, key);
        expect(reference, isNotEmpty);
        await tester.pumpWidget(host(values));
        await tester.pump();
        expect(await _coloredPixels(tester, key), orderedEquals(reference),
            reason: 'Invalid samples must behave exactly like unknowns.');
      }
    }
    await tester.pumpWidget(host([-1, 101, double.nan, double.infinity]));
    await tester.pump();
    expect((await _coloredExtent(tester, key)).$2, -1);
  });
}
