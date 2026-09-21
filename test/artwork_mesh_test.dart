import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/artwork_mesh_painter.dart';
import 'package:dan_player/component/cached_artwork_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Phase extends ValueNotifier<double> {
  _Phase() : super(0);
  bool get observed => hasListeners;
}

void main() {
  test('mesh preserves borders, positive cells and seamless loop', () {
    for (var frame = 0; frame <= 120; frame++) {
      final phase = frame / 120;
      for (var y = 0; y <= 20; y++) {
        for (var x = 0; x <= 20; x++) {
          final p = ArtworkMeshPainter.texturePoint(x / 20, y / 20, phase);
          expect(p.dx, inInclusiveRange(0, 1));
          expect(p.dy, inInclusiveRange(0, 1));
          if (x == 0 || x == 20 || y == 0 || y == 20) {
            expect((p - Offset(x / 20, y / 20)).distance, lessThan(1e-9));
          }
          if (x < 20 && y < 20) {
            final right =
                ArtworkMeshPainter.texturePoint((x + 1) / 20, y / 20, phase) -
                    p;
            final down =
                ArtworkMeshPainter.texturePoint(x / 20, (y + 1) / 20, phase) -
                    p;
            expect(right.dx * down.dy - right.dy * down.dx, greaterThan(0));
          }
          if (frame == 120) {
            expect(
                (p - ArtworkMeshPainter.texturePoint(x / 20, y / 20, 0))
                    .distance,
                lessThan(1e-9));
          }
        }
      }
    }
  });

  testWidgets(
      'real cached texture moves without rebuilding image or idle frames',
      (tester) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 240),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(320, 240),
              [Colors.deepOrange, Colors.purple, Colors.cyan], [0, .45, 1]));
    canvas.drawCircle(
        const Offset(120, 100), 60, Paint()..color = Colors.amber);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(320, 240));
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final provider = MemoryImage(data!.buffer.asUint8List());
    image!.dispose();
    picture.dispose();
    final phase = _Phase();
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                    width: 320,
                    height: 240,
                    child: CachedArtworkBlur(
                        image: provider, blur: 18, phase: phase))))));
    await tester.runAsync(() => precacheImage(
        provider, tester.element(find.byType(CachedArtworkBlur))));
    await tester.pumpAndSettle();
    final painter = tester
        .widget<SnapshotWidget>(find.byType(SnapshotWidget))
        .painter as ArtworkMeshPainter;
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !painter.shaderReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(painter.shaderReady, isTrue);
    await tester.pump();
    final child = tester.element(find.byType(Image));
    Future<List<int>> pixels(String name) async {
      final snap = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final raw = (await snap.toByteData())!.buffer.asUint8List();
      const output = String.fromEnvironment('DAN_MESH_RENDER');
      if (output.isNotEmpty) {
        final file = File('$output/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
            (await snap.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List());
      }
      snap.dispose();
      return raw;
    }

    final before = (await tester.runAsync(() => pixels('mesh-start')))!;
    phase.value = .21;
    await tester.pump();
    final moved = (await tester.runAsync(() => pixels('mesh-flow')))!;
    expect(moved, isNot(orderedEquals(before)));
    expect(tester.element(find.byType(Image)), same(child));
    for (var i = 3; i < moved.length; i += 4) {
      expect(moved[i], 255);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect((await tester.runAsync(() => pixels('mesh-paused')))!,
        orderedEquals(moved));
    phase.value = 1;
    await tester.pump();
    expect((await tester.runAsync(() => pixels('mesh-loop')))!,
        orderedEquals(before));
    await tester.pumpWidget(const SizedBox());
    expect(phase.observed, isFalse);
    phase.dispose();
  });
}
