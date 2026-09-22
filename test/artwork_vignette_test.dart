import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/artwork_dither.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/artwork_vignette.dart';
import 'package:dan_player/component/fluid_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemoryImage> _solid() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xffdcdcdc), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  picture.dispose();
  try {
    return MemoryImage((await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List());
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData())!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

Widget _app(GlobalKey key, Future<ImageProvider?> Function() load,
        {Object id = 'cover',
        bool fluid = true,
        bool playing = false,
        bool motion = false,
        ValueNotifier<bool>? hidden,
        Color surface = Colors.white,
        double opacity = 0,
        Widget child = const SizedBox.expand()}) =>
    MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)
              .copyWith(surface: surface)),
      home: Center(
          child: RepaintBoundary(
              key: key,
              child: SizedBox(
                  width: 320,
                  height: 180,
                  child: ArtworkBackdrop(
                    artworkKey: id,
                    loadArtwork: load,
                    fluid: fluid,
                    motion: motion,
                    isPlaying: playing,
                    hidden: hidden,
                    blur: 8,
                    opacity: opacity,
                    child: child,
                  )))),
    );

Future<void> _ready(WidgetTester tester, ImageProvider source) async {
  final context = tester.element(find.byType(ArtworkBackdrop));
  await tester.runAsync(() => precacheImage(
      ResizeImage(source,
          width: 512, height: 512, policy: ResizeImagePolicy.fit),
      context));
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
      'radial shade preserves center and normalized wide/portrait edges',
      (tester) async {
    for (final size in [const Size(320, 180), const Size(180, 320)]) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox.fromSize(
                      size: size,
                      child: const ColoredBox(
                          color: Colors.white,
                          child: Stack(
                              fit: StackFit.expand,
                              children: [ArtworkVignette()])))))));
      final bytes = await _pixels(tester, key);
      int red(int x, int y) => bytes[(y * size.width.toInt() + x) * 4];
      expect(red(size.width ~/ 2, size.height ~/ 2), 255);
      expect(red(size.width ~/ 2, 1), closeTo(220, 2));
      expect(red(1, 1), closeTo(164, 3));
      expect(red(1, 1),
          closeTo(red(size.width.toInt() - 2, size.height.toInt() - 2), 1));
      final before = bytes;
      await tester.pump(const Duration(seconds: 3));
      expect(await _pixels(tester, key), orderedEquals(before));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('missing and failed cover placeholders never receive edge shade',
      (tester) async {
    final key = GlobalKey();
    final pending = Completer<ImageProvider?>();
    await tester.pumpWidget(_app(key, () => pending.future));
    expect(find.byType(ArtworkVignette), findsNothing);
    expect(find.byType(ArtworkDither), findsNothing);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkVignette), findsNothing);
    expect(find.byType(ArtworkDither), findsNothing);
    final empty = await _pixels(tester, key);
    expect(empty[0], 255);
    expect(empty[(90 * 320 + 160) * 4], 255);
    await tester.pumpWidget(_app(
        key, () => Future<ImageProvider?>.error(StateError('missing')),
        id: 'failed'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkVignette), findsNothing);
    expect(await _pixels(tester, key), orderedEquals(empty));
    expect(tester.takeException(), isNull);
  });

  testWidgets('only fluid covers are shaded beneath theme veil and foreground',
      (tester) async {
    final source = (await tester.runAsync(_solid))!;
    final key = GlobalKey();
    await tester.pumpWidget(_app(key, () async => source, fluid: false));
    await _ready(tester, source);
    expect(find.byType(ArtworkVignette), findsNothing);
    final original = await _pixels(tester, key);
    expect(original[(90 * 320 + 160) * 4], 220);
    await tester.pumpWidget(_app(key, () async => source));
    await _ready(tester, source);
    final shaded = await _pixels(tester, key);
    expect(find.byType(ArtworkVignette), findsOneWidget);
    expect(shaded[(90 * 320 + 160) * 4], closeTo(220, 1));
    expect(shaded[(1 * 320 + 1) * 4], closeTo(141, 3));
    var taps = 0;
    for (final surface in [Colors.white, Colors.black]) {
      await tester.pumpWidget(_app(key, () async => source,
          surface: surface,
          opacity: .5,
          child: Center(
              child: GestureDetector(
                  onTap: () => taps++,
                  child: const ColoredBox(
                      color: Color(0xff44aaff),
                      child: SizedBox(width: 32, height: 24))))));
      await tester.pumpAndSettle();
      final veiled = await _pixels(tester, key);
      const edge = (1 * 320 + 1) * 4;
      final expected = (shaded[edge] + (surface == Colors.white ? 255 : 0)) / 2;
      expect(veiled[edge], closeTo(expected, 2));
      expect(veiled[(90 * 320 + 160) * 4], 0x44);
      await tester.tapAt(tester.getCenter(find.byType(GestureDetector).last));
    }
    expect(taps, 2);
  });

  testWidgets('vignette adds no refresh when flow pauses or window hides',
      (tester) async {
    final source = (await tester.runAsync(_solid))!;
    final key = GlobalKey();
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_app(key, () async => source,
        motion: true, playing: true, hidden: hidden));
    await _ready(tester, source);
    final flow =
        tester.widget<Flow>(find.byType(Flow)).delegate as ArtworkFlowDelegate;
    hidden.value = true;
    await tester.pump();
    final phase = flow.phase.value;
    final frozen = await _pixels(tester, key);
    await tester.pump(const Duration(seconds: 2));
    expect(flow.phase.value, phase);
    expect(await _pixels(tester, key), orderedEquals(frozen));
    expect(tester.binding.hasScheduledFrame, isFalse);
    hidden.value = false;
    await tester.pumpWidget(_app(key, () async => source,
        motion: true, playing: false, hidden: hidden));
    await tester.pump();
    final paused = await _pixels(tester, key);
    await tester.pump(const Duration(seconds: 2));
    expect(await _pixels(tester, key), orderedEquals(paused));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real cover before/after renders keep text and center unchanged',
      (tester) async {
    final sourcePath = Platform.environment['DAN_VIGNETTE_RENDER_SOURCE'];
    final output = Platform.environment['DAN_VIGNETTE_RENDER_DIR'];
    if (sourcePath == null || output == null) return;
    await tester.runAsync(() => (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load());
    final source = MemoryImage(
        (await tester.runAsync(() => File(sourcePath).readAsBytes()))!);
    await tester.runAsync(() => Directory(output).create(recursive: true));
    for (final dark in [false, true]) {
      for (final shade in [false, true]) {
        final key = GlobalKey();
        final surface =
            dark ? const Color(0xff19171c) : const Color(0xfffcf6fc);
        final foreground =
            dark ? const Color(0xfff4eafa) : const Color(0xff322636);
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                        width: 640,
                        height: 360,
                        child: Stack(fit: StackFit.expand, children: [
                          ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 26,
                                  sigmaY: 26,
                                  tileMode: ui.TileMode.clamp),
                              child: Image(image: source, fit: BoxFit.cover)),
                          if (shade) ...[
                            const ArtworkDither(),
                            const ArtworkVignette(),
                          ],
                          ColoredBox(color: surface.withValues(alpha: .42)),
                          Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text('‹',
                                      style: TextStyle(
                                          fontFamily: danEmbeddedFontFamily,
                                          color: foreground,
                                          fontSize: 28,
                                          decoration: TextDecoration.none)))),
                          Center(
                              child: Text('WASTED LOVE\nLyrics in focus',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: danEmbeddedFontFamily,
                                      color: foreground,
                                      fontSize: 28,
                                      decoration: TextDecoration.none))),
                        ]))))));
        await tester.runAsync(
            () => precacheImage(source, tester.element(find.byType(Image))));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    '$output/${dark ? 'dark' : 'light'}-${shade ? 'after' : 'before'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    }
  });
}
