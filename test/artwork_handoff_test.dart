import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final frame = Completer<ImageInfo>();
  int loads = 0;
  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _ControlledImage key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(
        frame.future.then((info) => info.clone()));
  }

  void complete(ui.Image image) {
    final info = ImageInfo(image: image.clone());
    addTearDown(info.dispose);
    frame.complete(info);
  }
}

Audio _song(String id) => Audio.online(
    provider: 'fixture',
    id: id,
    title: id,
    artist: 'artist',
    album: 'album',
    duration: 30);

Widget _app(Widget child) => MaterialApp(
    home: Scaffold(
        body: Center(child: SizedBox.square(dimension: 200, child: child))));

Future<ui.Image> _picture(WidgetTester tester, Color color) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(color, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      picture.dispose();
      return image;
    }))!;

void _shows(WidgetTester tester, ui.Image expected) {
  final image = tester.widget<RawImage>(find.byType(RawImage).last).image;
  expect(image, isNotNull);
  expect(image!.isCloneOf(expected), isTrue);
  expect(find.text('loading'), findsNothing);
  expect(find.text('missing'), findsNothing);
}

Future<Color> _pixel(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      const directory = String.fromEnvironment('DAN_ARTWORK_RENDER');
      if (directory.isNotEmpty) {
        await Directory(directory).create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('$directory/$name.png')
            .writeAsBytes(png.buffer.asUint8List());
      }
      final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      return Color.fromARGB(bytes.getUint8(offset + 3), bytes.getUint8(offset),
          bytes.getUint8(offset + 1), bytes.getUint8(offset + 2));
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  testWidgets(
      'production foreground and backdrop preserve waiting frames then fade',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final firstPixels = await _picture(tester, const Color(0xFF168F88));
    final nextPixels = await _picture(tester, const Color(0xFFA64468));
    addTearDown(firstPixels.dispose);
    addTearDown(nextPixels.dispose);
    final first = _ControlledImage()..complete(firstPixels);
    final next = _ControlledImage();
    final boundary = GlobalKey();
    Widget page(String id, ImageProvider source) => MaterialApp(
          theme: ThemeData(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF7ACDC4),
                  brightness: Brightness.dark)),
          home: RepaintBoundary(
              key: boundary,
              child: ArtworkBackdrop(
                artworkKey: id,
                loadArtwork: () async => source,
                blur: 24,
                opacity: .45,
                child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Track $id',
                                style: const TextStyle(fontSize: 24)),
                            const Text('Album artwork · playback'),
                            const SizedBox(height: 22),
                            Expanded(
                                child: Row(children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: AudioArtwork(
                                      audio: _song(id),
                                      size: 280,
                                      retainWhileLoading: true,
                                      loadArtwork: (_, __) async => source,
                                      placeholder: const Center(
                                          child:
                                              Icon(Icons.music_note, size: 72)),
                                      loading: const Center(
                                          child: CircularProgressIndicator()))),
                              const SizedBox(width: 36),
                              const Expanded(
                                  child: Center(
                                      child: Text(
                                          'Lyrics and controls remain visible',
                                          style: TextStyle(fontSize: 22)))),
                            ])),
                            const SizedBox(height: 22),
                            const LinearProgressIndicator(value: .45),
                            const SizedBox(height: 16),
                            const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.skip_previous),
                                  SizedBox(width: 28),
                                  Icon(Icons.pause),
                                  SizedBox(width: 28),
                                  Icon(Icons.skip_next),
                                ]),
                          ]),
                    )),
              )),
        );
    await tester.pumpWidget(page('A', first));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNWidgets(2));
    await _pixel(tester, boundary, 'production-old');
    await tester.pumpWidget(page('B', next));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _pixel(tester, boundary, 'production-waiting');
    next.complete(nextPixels);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await _pixel(tester, boundary, 'production-ready-000ms');
    for (final time in [60, 120, 180]) {
      await tester.pump(const Duration(milliseconds: 60));
      await _pixel(tester, boundary, 'production-ready-${time}ms');
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ready images fade over an opaque old frame and obey reduced motion',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    final blue = await _picture(tester, const Color(0xFF0000FF));
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final first = _ControlledImage()..complete(red);
    final second = _ControlledImage();
    final boundary = GlobalKey();
    Widget page(String id, ImageProvider provider) => _app(RepaintBoundary(
          key: boundary,
          child: ArtworkHandoff(
              artworkKey: id,
              loadArtwork: () async => provider,
              placeholder: const ColoredBox(color: Colors.black),
              imageBuilder: (image) =>
                  Image(image: image, gaplessPlayback: true)),
        ));
    await tester.pumpWidget(page('a', first));
    await tester.pump();
    final before = await _pixel(tester, boundary, 'before');
    await tester.pumpWidget(page('b', second));
    await tester.pump(const Duration(milliseconds: 300));
    expect(await _pixel(tester, boundary, 'waiting-for-decode'), before);
    second.complete(blue);
    await tester.pump();
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2));
    await tester.pump(AppMotion.standard ~/ 2);
    final mid = await _pixel(tester, boundary, 'ready-fade-midpoint');
    // An opaque red frame plus the new blue fade keeps full alpha and does
    // not expose the black fallback between the two colors.
    expect(mid.a, 1);
    expect(mid.r, greaterThan(0));
    expect(mid.b, greaterThan(0));
    expect(mid.r + mid.b, closeTo(before.r + before.b, .02));
    await tester.pump(AppMotion.standard);
    expect(find.byType(RawImage), findsOneWidget);
    await _pixel(tester, boundary, 'ready');
    await tester.pumpWidget(page('a-again', first));
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    _shows(tester, red);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same song revision retains art but a recycled row does not',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    addTearDown(red.dispose);
    final first = _ControlledImage()..complete(red);
    final pending = Completer<ImageProvider?>();
    Widget page(int revision, Future<ImageProvider?> future) =>
        _app(AudioArtwork(
            audio: _song('a'),
            revision: revision,
            loadArtwork: (_, __) => future,
            placeholder: const Text('missing'),
            loading: const Text('loading')));
    await tester.pumpWidget(page(1, Future.value(first)));
    await tester.pump();
    await tester.pumpWidget(page(2, pending.future));
    _shows(tester, red);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('missing'), findsOneWidget);
    final lateCodec = _ControlledImage();
    await tester.pumpWidget(page(3, Future.value(lateCodec)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    lateCodec.complete(red);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback cover stays painted through provider and codec loading',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    final blue = await _picture(tester, const Color(0xFF0000FF));
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final first = _ControlledImage()..complete(red);
    final second = _ControlledImage();
    final request = Completer<ImageProvider?>();
    Widget page(String id, Future<ImageProvider?> future) => _app(AudioArtwork(
        audio: _song(id),
        retainWhileLoading: true,
        size: 200,
        loadArtwork: (_, __) => future,
        loading: const Text('loading'),
        placeholder: const Text('missing')));
    await tester.pumpWidget(page('a', Future.value(first)));
    await tester.pump();
    _shows(tester, red);
    final state = tester.state(find.byType(AudioArtwork));
    await tester.pumpWidget(page('b', request.future));
    await tester.pump(const Duration(milliseconds: 300));
    _shows(tester, red);
    request.complete(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _shows(tester, red);
    second.complete(blue);
    await tester.pump();
    await tester.pump();
    _shows(tester, blue);
    expect(tester.state(find.byType(AudioArtwork)), same(state));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'background ignores superseded decoded frames and keeps current art',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    final blue = await _picture(tester, const Color(0xFF0000FF));
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final first = _ControlledImage()..complete(red);
    final abandoned = _ControlledImage();
    final latest = _ControlledImage();
    Widget page(String id, ImageProvider provider) => _app(ArtworkBackdrop(
        artworkKey: id,
        loadArtwork: () async => provider,
        blur: 0,
        opacity: 0,
        child: const SizedBox.expand()));
    await tester.pumpWidget(page('a', first));
    await tester.pump();
    _shows(tester, red);
    await tester.pumpWidget(page('b', abandoned));
    await tester.pump();
    await tester.pumpWidget(page('c', latest));
    await tester.pump();
    abandoned.complete(blue);
    await tester.pump();
    _shows(tester, red);
    latest.complete(blue);
    await tester.pump();
    await tester.pump();
    _shows(tester, blue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cache hits switch without an empty frame and do not decode twice',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    final blue = await _picture(tester, const Color(0xFF0000FF));
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final first = _ControlledImage()..complete(red);
    final second = _ControlledImage()..complete(blue);
    Widget page(String id, ImageProvider provider) => _app(ArtworkHandoff(
        artworkKey: id,
        loadArtwork: () async => provider,
        placeholder: const Text('missing'),
        loading: const Text('loading'),
        imageBuilder: (image) => Image(image: image, gaplessPlayback: true)));
    await tester.pumpWidget(page('a', first));
    await tester.pump();
    _shows(tester, red);
    await precacheImage(second, tester.element(find.byType(ArtworkHandoff)));
    await tester.pumpWidget(page('b', second));
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pump();
    _shows(tester, blue);
    expect(first.loads, 1);
    expect(second.loads, 1);
  });

  testWidgets('missing failed or stalled artwork clears the retained frame',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    addTearDown(red.dispose);
    var key = 0;
    Widget page(Future<ImageProvider?> Function() load) => _app(ArtworkHandoff(
        artworkKey: key++,
        loadArtwork: load,
        placeholder: const Text('missing'),
        loading: const Text('loading'),
        imageBuilder: (image) => Image(image: image, gaplessPlayback: true)));
    Future<void> ready() async {
      final image = _ControlledImage()..complete(red);
      await tester.pumpWidget(page(() async => image));
      await tester.pump();
      _shows(tester, red);
    }

    for (final load in <Future<ImageProvider?> Function()>[
      () async => null,
      () => throw StateError('provider missing'),
    ]) {
      await ready();
      await tester.pumpWidget(page(load));
      await tester.pump();
      expect(find.text('missing'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    }
    await ready();
    final broken = _ControlledImage();
    await tester.pumpWidget(page(() async => broken));
    await tester.pump();
    broken.frame.completeError(StateError('decode'));
    await tester.pumpAndSettle();
    expect(find.text('missing'), findsOneWidget);
    await ready();
    final stalled = _ControlledImage();
    await tester.pumpWidget(page(() async => stalled));
    await tester.pump();
    _shows(tester, red);
    await tester.pump(ArtworkHandoff.loadTimeout);
    expect(find.text('missing'), findsOneWidget);
    stalled.complete(red);
    await tester.pump();
    expect(find.text('missing'), findsOneWidget);
    final late = Completer<ImageProvider?>();
    await tester.pumpWidget(page(() => late.future));
    await tester.pumpWidget(const SizedBox());
    late.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('library row reuse never shows the previous songs cover',
      (tester) async {
    final red = await _picture(tester, const Color(0xFFFF0000));
    addTearDown(red.dispose);
    final first = _ControlledImage()..complete(red);
    final pending = Completer<ImageProvider?>();
    Widget page(String id, Future<ImageProvider?> future) => _app(AudioArtwork(
        audio: _song(id),
        loadArtwork: (_, __) => future,
        loading: const Text('loading'),
        placeholder: const Text('missing')));
    await tester.pumpWidget(page('a', Future.value(first)));
    await tester.pump();
    _shows(tester, red);
    await tester.pumpWidget(page('b', pending.future));
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('loading'), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('missing'), findsOneWidget);
  });
}
