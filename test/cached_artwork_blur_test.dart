import 'dart:ui' as ui;

import 'package:dan_player/component/cached_artwork_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemoryImage> source(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return MemoryImage(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('blur cache follows source, blur and size without ongoing frames',
      (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = (await tester.runAsync(() => source(Colors.red)))!;
    final second = (await tester.runAsync(() => source(Colors.blue)))!;
    Widget app(ImageProvider image, double blur, double width) => MaterialApp(
        home: Center(
            child: SizedBox(
                width: width,
                height: 500,
                child: CachedArtworkBlur(image: image, blur: blur))));
    Future<void> ready(ImageProvider image) async {
      await tester.runAsync(() =>
          precacheImage(image, tester.element(find.byType(CachedArtworkBlur))));
      await tester.pump();
      await tester.pump();
    }

    await tester.pumpWidget(app(first, 32, 1600));
    await ready(first);
    final snapshot = tester.widget<SnapshotWidget>(find.byType(SnapshotWidget));
    expect(snapshot.controller.allowSnapshotting, isTrue);
    expect(
        MediaQuery.devicePixelRatioOf(
            tester.element(find.byType(SnapshotWidget))),
        closeTo(768 / 1600, .001));
    await tester.pumpWidget(app(second, 48, 1000));
    await ready(second);
    expect(tester.widget<Image>(find.byType(Image)).image, second);
    expect(
        tester.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller,
        same(snapshot.controller));
    expect(snapshot.controller.allowSnapshotting, isTrue);
    expect(
        MediaQuery.devicePixelRatioOf(
            tester.element(find.byType(SnapshotWidget))),
        closeTo(.768, .001));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
