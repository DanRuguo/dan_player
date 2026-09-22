import 'dart:typed_data';

import 'package:dan_player/component/artwork_dither.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pixels(
        WidgetTester tester, GlobalKey key, double dpr) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: dpr);
      try {
        return (await image.toByteData())!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

Future<Uint8List> _render(WidgetTester tester, GlobalKey key,
    {required bool grain,
    double dpr = 1,
    Size size = const Size(256, 128),
    Color? color}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: dpr),
          child: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox.fromSize(
                      size: size,
                      child: Stack(fit: StackFit.expand, children: [
                        DecoratedBox(
                            decoration: color == null
                                ? const BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                    Color(0xff707070),
                                    Color(0xff909090)
                                  ]))
                                : BoxDecoration(color: color)),
                        if (grain) const ArtworkDither(),
                      ])))))));
  await tester.runAsync(() async {});
  await tester.pumpAndSettle();
  return _pixels(tester, key, dpr);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ArtworkDither.prepare);

  testWidgets('sub-LSB grain lowers flat run lengths with near-zero mean bias',
      (tester) async {
    for (final dpr in [1.0, 1.25]) {
      final key = GlobalKey();
      const size = Size(512, 128);
      final plain =
          await _render(tester, key, grain: false, dpr: dpr, size: size);
      final grain =
          await _render(tester, key, grain: true, dpr: dpr, size: size);
      final width = (size.width * dpr).toInt();
      int longest(Uint8List bytes) {
        var maxRun = 1, run = 1;
        for (var i = 4; i < bytes.length; i += 4) {
          run =
              ((i ~/ 4) % width != 0 && bytes[i] == bytes[i - 4]) ? run + 1 : 1;
          if (run > maxRun) maxRun = run;
        }
        return maxRun;
      }

      var sum = 0, changed = 0;
      for (var i = 0; i < grain.length; i += 4) {
        final delta = grain[i] - plain[i];
        sum += delta;
        if (delta != 0) changed++;
        expect(delta.abs(), lessThanOrEqualTo(1));
        expect(grain[i + 3], 255);
      }
      expect((sum / (grain.length / 4)).abs(), lessThan(.06));
      expect(changed / (grain.length / 4), inInclusiveRange(.3, .7));
      expect(longest(grain), lessThan(longest(plain)));
    }
  });

  testWidgets('all colour ranges stay bounded within one output LSB',
      (tester) async {
    final key = GlobalKey();
    for (final color in [
      Colors.black,
      const Color(0xff202020),
      const Color(0xff808080),
      const Color(0xffe0e0e0),
      Colors.white,
      const Color(0xffdd3377),
      const Color(0xff125aaa)
    ]) {
      final plain = await _render(tester, key, grain: false, color: color);
      final grain = await _render(tester, key, grain: true, color: color);
      for (var channel = 0; channel < 3; channel++) {
        var sum = 0;
        for (var i = channel; i < grain.length; i += 4) {
          final delta = grain[i] - plain[i];
          sum += delta;
          expect(delta.abs(), lessThanOrEqualTo(1));
        }
        expect((sum / (grain.length / 4)).abs(), lessThanOrEqualTo(.51));
      }
    }
  });

  testWidgets('grain is deterministic across frames widths and physical DPR',
      (tester) async {
    final key = GlobalKey();
    for (final dpr in [1.0, 1.25]) {
      final wide = await _render(tester, key,
          grain: true,
          dpr: dpr,
          color: const Color(0xff808080),
          size: const Size(256, 128));
      await tester.pump(const Duration(seconds: 3));
      expect(await _pixels(tester, key, dpr), orderedEquals(wide));
      expect(tester.binding.hasScheduledFrame, isFalse);
      final tall = await _render(tester, key,
          grain: true,
          dpr: dpr,
          color: const Color(0xff808080),
          size: const Size(128, 256));
      final wideWidth = (256 * dpr).toInt(), tallWidth = (128 * dpr).toInt();
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          expect(tall[(y * tallWidth + x) * 4], wide[(y * wideWidth + x) * 4]);
        }
      }
      await tester.pumpWidget(const SizedBox());
      final again = await _render(tester, key,
          grain: true,
          dpr: dpr,
          color: const Color(0xff808080),
          size: const Size(256, 128));
      expect(again, orderedEquals(wide));
      expect(tester.binding.transientCallbackCount, 0);
    }
  });
}
