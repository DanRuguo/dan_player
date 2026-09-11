import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('progress does not repaint its static content or page',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    addTearDown(positions.close);
    var pagePaints = 0;
    var contentPaints = 0;
    await tester.pumpWidget(MaterialApp(
        home: CustomPaint(
      painter: _PaintCounter(() => pagePaints++),
      child: Center(
          child: RectangleProgressIndicator(
        size: const Size(300, 64),
        positionStream: positions.stream,
        lengthProvider: () => 180,
        onSeek: (_) {},
        child: CustomPaint(
            painter: _PaintCounter(() => contentPaints++),
            child: const SizedBox(width: 300, height: 64)),
      )),
    )));
    await tester.pumpAndSettle();
    final before = (pagePaints, contentPaints);
    for (var i = 1; i <= 30; i++) {
      positions.add(i / 30);
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect((pagePaints, contentPaints), before);
    expect(
        tester
            .widget<CustomPaint>(find.byWidgetPredicate((w) =>
                w is CustomPaint && w.painter is RectangleProgressPainter))
            .painter,
        isA<RectangleProgressPainter>());
  });
  for (final ratio in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('centered handle stays crisp at half-pixel origin ${ratio}x',
        (tester) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(400 * ratio + 1, 100 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final scheme = ColorScheme.fromSeed(seedColor: Colors.purple);
      final positions = StreamController<double>.broadcast(sync: true);
      addTearDown(positions.close);
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: RepaintBoundary(
              key: capture,
              child: ColoredBox(
                  color: scheme.surface,
                  child: Center(
                      child: SizedBox(
                          width: 400,
                          height: 80,
                          child: RectangleProgressIndicator(
                              size: const Size(400, 80),
                              positionStream: positions.stream,
                              lengthProvider: () => 100,
                              initialPosition: 41.3,
                              onSeek: (_) {},
                              child: const SizedBox.expand())))))));
      final bar = tester.getRect(find.byType(RectangleProgressIndicator));
      expect(bar.left * ratio, closeTo(.5, .001));
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: bar.topLeft + const Offset(165.2, 40));
      await mouse.moveTo(bar.topLeft + const Offset(165.3, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final render =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: ratio);
        try {
          final pixels =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final row = (bar.center.dy * ratio).round();
          var solidPixels = 0;
          for (var x = 0; x < image.width; x++) {
            final offset = (row * image.width + x) * 4;
            final rgb = pixels.getUint8(offset) << 16 |
                pixels.getUint8(offset + 1) << 8 |
                pixels.getUint8(offset + 2);
            if (rgb == (scheme.primary.toARGB32() & 0xffffff)) solidPixels++;
          }
          expect(solidPixels, (2 * ratio).round(),
              reason: 'global placement must not soften the solid core');
        } finally {
          image.dispose();
        }
      });
      await mouse.removePointer();
    });
  }

  for (final ratio in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('solid handle is pixel aligned at ${ratio}x', (tester) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.purple);
      final progress = ValueNotifier<double>(0);
      final hint = ValueNotifier<double>(1);
      addTearDown(progress.dispose);
      addTearDown(hint.dispose);
      final painter = RectangleProgressPainter(
          progress: progress,
          scheme: scheme,
          dragIndicatorColor: scheme.primary,
          highlightBoundary: hint,
          devicePixelRatio: ratio);
      for (final fraction in [0.0, .413, .5345, 1.0]) {
        progress.value = fraction;
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder)..scale(ratio), const Size(400, 80));
          final picture = recorder.endRecording();
          final image = await picture.toImage(
              (400 * ratio).round(), (80 * ratio).round());
          try {
            final pixels =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            final row = (40 * ratio).round();
            final core = <int>[];
            for (var x = 0; x < image.width; x++) {
              final offset = (row * image.width + x) * 4;
              final alpha = pixels.getUint8(offset + 3);
              if (alpha == 255) {
                core.add(x);
                final rgb = pixels.getUint8(offset) << 16 |
                    pixels.getUint8(offset + 1) << 8 |
                    pixels.getUint8(offset + 2);
                expect(rgb, scheme.primary.toARGB32() & 0xffffff);
              } else {
                expect(alpha, lessThan(140),
                    reason: 'no partly covered fuzzy edge beside the core');
              }
            }
            expect(core.length, (2 * ratio).round());
            expect(core.last - core.first + 1, core.length);
            if (fraction == 0) {
              expect(core.first, 0);
            } else if (fraction == 1) {
              expect(core.last, image.width - 1);
            } else {
              expect((core.first + core.last + 1) / 2,
                  closeTo(400 * ratio * fraction, .51));
            }
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
      }
      expect(
          painter.shouldRepaint(RectangleProgressPainter(
              progress: progress,
              scheme: scheme,
              dragIndicatorColor: scheme.primary,
              highlightBoundary: hint,
              devicePixelRatio: ratio + .25)),
          isTrue);
    });
  }

  testWidgets('drag handle follows a runtime theme colour change',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    addTearDown(positions.close);

    Widget host(Color seed) => MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
          home: RectangleProgressIndicator(
            size: const Size(200, 40),
            positionStream: positions.stream,
            lengthProvider: () => 100,
            initialPosition: 50,
            onSeek: (_) {},
            child: const SizedBox(width: 200, height: 40),
          ),
        );

    RectangleProgressPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RectangleProgressPainter>()
        .single;

    const firstSeed = Colors.teal;
    await tester.pumpWidget(host(firstSeed));
    final first = painter();
    expect(first.dragIndicatorColor,
        ColorScheme.fromSeed(seedColor: firstSeed).primary);

    const secondSeed = Colors.deepOrange;
    await tester.pumpWidget(host(secondSeed));
    final second = painter();
    expect(second.dragIndicatorColor,
        ColorScheme.fromSeed(seedColor: secondSeed).primary);
    expect(second.dragIndicatorColor, isNot(first.dragIndicatorColor));
    expect(second.shouldRepaint(first), isTrue,
        reason: 'an already visible handle must repaint with the new theme');
  });

  testWidgets('partly animated handle stays opaque theme primary',
      (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
    final progress = ValueNotifier<double>(.5);
    final hint = ValueNotifier<double>(.5);
    addTearDown(progress.dispose);
    addTearDown(hint.dispose);
    final painter = RectangleProgressPainter(
      progress: progress,
      scheme: scheme,
      dragIndicatorColor: scheme.primary,
      highlightBoundary: hint,
    );

    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(100, 40));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 40);
      try {
        final pixels =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final offset = (20 * image.width + 50) * 4;
        final rgb = pixels.getUint8(offset) << 16 |
            pixels.getUint8(offset + 1) << 8 |
            pixels.getUint8(offset + 2);
        expect(rgb, scheme.primary.toARGB32() & 0xffffff);
        expect(pixels.getUint8(offset + 3), 255,
            reason: 'animation must not blend the theme colour into black');
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
  });

  testWidgets('progress is finite, clamped and releases its subscription',
      (tester) async {
    var cancelled = false;
    final positions = StreamController<double>(
      sync: true,
      onCancel: () => cancelled = true,
    );
    addTearDown(positions.close);
    var length = 0.0;

    await tester.pumpWidget(MaterialApp(
      home: RectangleProgressIndicator(
        size: const Size(100, 4),
        positionStream: positions.stream,
        lengthProvider: () => length,
        child: const SizedBox(width: 100, height: 4),
      ),
    ));

    RectangleProgressPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RectangleProgressPainter>()
        .single;

    positions.add(10);
    expect(painter().progress.value, 0,
        reason: 'zero length must not publish NaN or infinity');

    length = 20;
    positions.add(30);
    expect(painter().progress.value, 1,
        reason: 'native position overshoot is bounded to the painted track');

    positions.add(-4);
    expect(painter().progress.value, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(cancelled, isTrue);
  });
}

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.count);
  final VoidCallback count;
  @override
  void paint(Canvas canvas, Size size) => count();
  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
