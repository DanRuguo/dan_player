import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemoryImage> _cover(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return MemoryImage(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

ResizeImage _bounded(ImageProvider provider) => ResizeImage(
      provider,
      width: 512,
      height: 512,
      policy: ResizeImagePolicy.fit,
    );

Widget _app({
  Object artworkKey = 'song-a',
  required Future<ImageProvider?> Function() loadArtwork,
  Widget child = const SizedBox.expand(),
}) =>
    MaterialApp(
      home: ArtworkBackdrop(
        artworkKey: artworkKey,
        loadArtwork: loadArtwork,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );

Future<void> _resolveImage(WidgetTester tester, ImageProvider provider) async {
  final context = tester.element(find.byType(ArtworkBackdrop));
  await tester.runAsync(() => precacheImage(
        _bounded(provider),
        context,
        onError: (_, __) {},
      ));
  await tester.pumpAndSettle();
}

Future<List<Color>> _sample(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      return points.map((point) {
        final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets(
      'rebuilds reuse artwork; identity or revision changes reload once',
      (tester) async {
    var reads = 0;
    var taps = 0;
    Widget page(Object key) => _app(
          artworkKey: key,
          // A new callback instance on every parent build is not a new request.
          loadArtwork: () async {
            reads++;
            return null;
          },
          child: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Open details'),
            ),
          ),
        );

    await tester.pumpWidget(page(('song-a', 0)));
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await tester.pumpWidget(page(('song-a', 0)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(reads, 1);
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(reads, 1);

    await tester.pumpWidget(page(('song-a', 1)));
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.pumpWidget(page(('song-b', 1)));
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late old cover cannot replace the new track', (tester) async {
    final covers = (await tester.runAsync(() async => [
          await _cover(Colors.red),
          await _cover(Colors.blue),
        ]))!;
    final oldRequest = Completer<ImageProvider?>();
    final newRequest = Completer<ImageProvider?>();
    await tester.pumpWidget(_app(loadArtwork: () => oldRequest.future));
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(_app(
      artworkKey: 'song-b',
      loadArtwork: () => newRequest.future,
    ));
    newRequest.complete(covers[1]);
    await tester.pump();
    await _resolveImage(tester, covers[1]);
    oldRequest.complete(covers[0]);
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.imageProvider, covers[1]);
    expect(resized.width, 512);
    expect(resized.height, 512);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.allowUpscaling, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending track changes retain the rendered art and ignore late errors',
      (tester) async {
    final cover = (await tester.runAsync(() => _cover(Colors.teal)))!;
    final pending = Completer<ImageProvider?>();
    await tester.pumpWidget(_app(loadArtwork: () async => cover));
    await tester.pump();
    await _resolveImage(tester, cover);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(_app(
      artworkKey: 'waiting-track',
      loadArtwork: () => pending.future,
    ));
    expect(find.byType(Image), findsOneWidget,
        reason: 'Keep the rendered frame until the new artwork is ready.');
    await tester.pumpWidget(_app(
      artworkKey: 'final-track',
      loadArtwork: () async => null,
    ));
    pending.completeError(StateError('superseded artwork failed'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing and failed requests leave an opaque local fallback',
      (tester) async {
    final loads = <Future<ImageProvider?> Function()>[
      () async => null,
      () => throw StateError('synchronous artwork failure'),
      () => Future<ImageProvider?>.error(StateError('asynchronous failure')),
    ];
    for (var index = 0; index < loads.length; index++) {
      await tester.pumpWidget(_app(
        artworkKey: index,
        loadArtwork: loads[index],
        child: const Center(child: Text('Readable details')),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Readable details'), findsOneWidget);
      final background = tester.widget<ColoredBox>(find.descendant(
        of: find.byType(ArtworkBackdrop),
        matching: find.byType(ColoredBox),
      ));
      final scheme =
          Theme.of(tester.element(find.byType(ArtworkBackdrop))).colorScheme;
      expect(background.color, scheme.surface);
      expect(background.color.a, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a corrupt image is handled without losing foreground controls',
      (tester) async {
    final badCover = MemoryImage(Uint8List.fromList([1, 2, 3, 4]));
    var taps = 0;
    await tester.pumpWidget(_app(
      loadArtwork: () async => badCover,
      child: Center(
        child: TextButton(
          onPressed: () => taps++,
          child: const Text('Still available'),
        ),
      ),
    ));
    await tester.pump();
    await _resolveImage(tester, badCover);
    await tester.tap(find.text('Still available'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an in-flight request can finish after the page is disposed',
      (tester) async {
    final pending = Completer<ImageProvider?>();
    await tester.pumpWidget(_app(loadArtwork: () => pending.future));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('failed after disposal'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1000.0]) {
      testWidgets('$brightness $width artwork stays inside the readable page',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        final covers = (await tester.runAsync(() async => [
              await _cover(Colors.red),
              await _cover(Colors.blue),
              await _cover(
                  brightness == Brightness.dark ? Colors.white : Colors.black),
            ]))!;
        final boundaryKey = GlobalKey();
        const outside = Color(0xFF244559);
        const title = Text('Song details');

        Future<List<Color>> render(MemoryImage cover) async {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: outside,
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: ArtworkBackdrop(
                        artworkKey: cover,
                        loadArtwork: () async => cover,
                        child: const Material(
                          type: MaterialType.transparency,
                          child: Center(child: title),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
          await tester.pump();
          await _resolveImage(tester, cover);
          expect(tester.getRect(find.byType(ArtworkBackdrop)),
              Rect.fromLTWH(48, 0, width - 48, 700));
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(ImageFiltered), findsOneWidget);
          expect(
              find.ancestor(
                of: find.byWidget(title),
                matching: find.byType(ImageFiltered),
              ),
              findsNothing,
              reason: 'Only artwork, never the foreground text, is filtered.');
          return _sample(tester, boundaryKey, [
            const Offset(24, 32),
            const Offset(47, 32),
            const Offset(49, 32),
            Offset(width - 24, 32),
          ]);
        }

        final red = await render(covers[0]);
        final blue = await render(covers[1]);
        for (final pixels in [red, blue]) {
          expect(pixels[0], outside);
          expect(pixels[1], outside,
              reason: 'Blur and opaque fallback must not leak into a sibling.');
          expect(pixels[2].a, 1);
          expect(pixels[3].a, 1);
        }
        expect(red[2].r, greaterThan(blue[2].r + 0.08));
        expect(blue[2].b, greaterThan(red[2].b + 0.08));
        final worstBackground = (await render(covers[2]))[3];
        final textLuminance = scheme.onSurface.computeLuminance();
        final backgroundLuminance = worstBackground.computeLuminance();
        final contrast = (math.max(textLuminance, backgroundLuminance) + 0.05) /
            (math.min(textLuminance, backgroundLuminance) + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5),
            reason: 'Normal page text stays readable over extreme artwork.');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
