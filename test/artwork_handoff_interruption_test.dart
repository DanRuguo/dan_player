import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/cached_artwork_blur.dart';
import 'package:dan_player/component/detail_header_backdrop.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frame extends ImageProvider<_Frame> {
  final ready = Completer<ImageInfo>();
  int loads = 0;

  @override
  Future<_Frame> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Frame key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(
        ready.future.then((frame) => frame.clone()));
  }

  void complete(ui.Image image) {
    final frame = ImageInfo(image: image.clone());
    addTearDown(frame.dispose);
    ready.complete(frame);
  }
}

class _RasterHandles {
  _RasterHandles({VoidCallback? onFirstRaster}) {
    ui.Image.onCreate = (image) {
      _previousCreate?.call(image);
      // Fixture sources are 32px. Observe the real handoff raster handles,
      // including clones, rather than an internal capture counter.
      if (image.width > 32 || image.height > 32) {
        live.add(image);
        if (created++ == 0) onFirstRaster?.call();
      }
      final unique = <ui.Image>[];
      for (final handle in live) {
        if (!unique.any(handle.isCloneOf)) unique.add(handle);
      }
      peakImages = peakImages < unique.length ? unique.length : peakImages;
    };
    ui.Image.onDispose = (image) {
      live.remove(image);
      _previousDispose?.call(image);
    };
  }
  final _previousCreate = ui.Image.onCreate;
  final _previousDispose = ui.Image.onDispose;
  final live = <ui.Image>{};
  int peakImages = 0;
  int created = 0;
  void restore() {
    ui.Image.onCreate = _previousCreate;
    ui.Image.onDispose = _previousDispose;
  }
}

Future<ui.Image> _image(WidgetTester tester, Color color) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(color, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      picture.dispose();
      return image;
    }))!;

Future<ui.Image> _texture(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var x = 0; x < 32; x += 4) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), 0, 4, 32),
            Paint()..color = x % 8 == 0 ? Colors.red : Colors.blue);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      picture.dispose();
      return image;
    }))!;

Future<List<int>> _pixel(WidgetTester tester, GlobalKey key) async {
  // The capture commits after paint. Paint its next-frame target at the same
  // animation time before reading pixels; readback must not advance a fade.
  await tester.pump();
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      return [
        for (var channel = 0; channel < 4; channel++)
          bytes.getUint8(offset + channel)
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void _continuous(List<int> before, List<int> after) {
  expect(after[3], before[3],
      reason: 'A handoff must not expose the fallback.');
  for (var channel = 0; channel < 3; channel++) {
    expect((after[channel] - before[channel]).abs(), lessThanOrEqualTo(2),
        reason:
            'The new fade starts from the presented mixture, channel $channel.');
  }
}

void main({String? onlyCase}) {
  for (final backdrop in [false, true]) {
    final name = backdrop
        ? 'rapid backdrop replacements retain the presented mixture'
        : 'rapid foreground replacements retain the presented mixture';
    if (onlyCase != null && onlyCase != name) continue;
    testWidgets(name, (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 240);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final pixels = <ui.Image>[];
      for (final color in [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.orange
      ]) {
        pixels.add(await _image(tester, color));
      }
      for (final image in pixels) {
        addTearDown(image.dispose);
      }
      final sources = [
        for (var index = 0; index < pixels.length; index++) _Frame()
      ];
      sources[0].complete(pixels[0]);
      final boundary = GlobalKey();
      Widget page(int index) => MaterialApp(
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          home: Center(
              child: SizedBox.square(
                  dimension: 160,
                  child: RepaintBoundary(
                      key: boundary,
                      child: backdrop
                          ? ArtworkBackdrop(
                              artworkKey: index,
                              loadArtwork: () async => sources[index],
                              blur: 0,
                              opacity: 0,
                              child: const SizedBox.expand())
                          : ArtworkHandoff(
                              artworkKey: index,
                              loadArtwork: () async => sources[index],
                              placeholder:
                                  const ColoredBox(color: Colors.black),
                              imageBuilder: (provider) => Image(
                                  image: provider, fit: BoxFit.cover))))));
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(1));
      sources[1].complete(pixels[1]);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      var previous = await _pixel(tester, boundary);
      expect(previous[0], greaterThan(0));
      expect(previous[2], greaterThan(0),
          reason: 'The fixture must interrupt a real red/blue blend.');

      for (var index = 2; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(pixels[index]);
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump();
          _continuous(previous, await _pixel(tester, boundary));
        }
        expect(find.byType(RawImage).evaluate().length, lessThanOrEqualTo(2),
            reason:
                'Rapid switches must not stack a growing set of old cover widgets.');
        await tester.pump(AppMotion.standard ~/ 3);
        final moved = await _pixel(tester, boundary);
        expect(moved, isNot(previous),
            reason: 'The newly selected image must begin fading in.');
        previous = moved;
      }
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(sources.map((source) => source.loads), everyElement(1));
      expect(tester.takeException(), isNull);
    });
  }

  const zeroName =
      'same-frame ready replacements retain the fully outgoing image';
  if (onlyCase == null || onlyCase == zeroName) {
    testWidgets(zeroName, (tester) async {
      final red = await _image(tester, Colors.red);
      final blue = await _image(tester, Colors.blue);
      final green = await _image(tester, Colors.green);
      for (final image in [red, blue, green]) {
        addTearDown(image.dispose);
      }
      final sources = [for (var index = 0; index < 3; index++) _Frame()];
      final boundary = GlobalKey();
      Widget page(int index) => MaterialApp(
              home: Center(
                  child: SizedBox.square(
            dimension: 160,
            child: RepaintBoundary(
                key: boundary,
                child: ArtworkHandoff(
                  artworkKey: index,
                  loadArtwork: () async => sources[index],
                  placeholder: const SizedBox.expand(),
                  imageBuilder: (provider) =>
                      Image(image: provider, fit: BoxFit.cover),
                )),
          )));
      sources[0].complete(red);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      final outgoing = await _pixel(tester, boundary);
      await tester.pumpWidget(page(1));
      sources[1].complete(blue);
      await tester.pump();
      await tester.pump();
      _continuous(outgoing, await _pixel(tester, boundary));
      await tester.pumpWidget(page(2));
      sources[2].complete(green);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        _continuous(outgoing, await _pixel(tester, boundary));
      }
      await tester.pumpAndSettle();
      expect((await _pixel(tester, boundary))[1], greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  const firstName =
      'replacing a first-frame reveal preserves its partial image and releases its entrance slot';
  if (onlyCase == null || onlyCase == firstName) {
    testWidgets(firstName, (tester) async {
      final red = await _image(tester, Colors.red);
      final blue = await _image(tester, Colors.blue);
      addTearDown(red.dispose);
      addTearDown(blue.dispose);
      final first = _Frame();
      final next = _Frame();
      final boundary = GlobalKey();
      Widget page(String key, _Frame source) => MaterialApp(
          home: AppEntranceScope(
              maxConcurrentAnimations: 1,
              child: Center(
                  child: SizedBox.square(
                      dimension: 160,
                      child: RepaintBoundary(
                          key: boundary,
                          child: ArtworkHandoff(
                              artworkKey: key,
                              animateFirstFrame: true,
                              loadArtwork: () async => source,
                              placeholder: const SizedBox.expand(),
                              imageBuilder: (provider) => Image(
                                  image: provider, fit: BoxFit.cover)))))));
      await tester.pumpWidget(page('first', first));
      first.complete(red);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      final before = await _pixel(tester, boundary);
      expect(before[3], inInclusiveRange(1, 254),
          reason: 'The original first frame must still be revealing.');
      await tester.pumpWidget(page('next', next));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        _continuous(before, await _pixel(tester, boundary));
      }
      final context = tester.element(find.byType(ArtworkHandoff));
      final release = AppEntranceScope.reserveAnimationOf(context);
      expect(release, isNotNull,
          reason:
              'Replacing the entrance releases its shared budget immediately.');
      release?.call();
      expect(tester.binding.transientCallbackCount, 0,
          reason:
              'Waiting for the next cover must not retain the cancelled entrance clock.');
      next.complete(blue);
      await tester.pumpAndSettle();
      expect((await _pixel(tester, boundary))[3], 255);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  const uncachedName =
      'interrupted targets retain one codec with image caching disabled';
  if (onlyCase == null || onlyCase == uncachedName) {
    testWidgets(uncachedName, (tester) async {
      final cache = PaintingBinding.instance.imageCache;
      final originalSize = cache.maximumSize;
      final originalBytes = cache.maximumSizeBytes;
      cache.maximumSize = 0;
      cache.maximumSizeBytes = 0;
      addTearDown(() {
        cache.maximumSize = originalSize;
        cache.maximumSizeBytes = originalBytes;
      });
      final image = await _image(tester, Colors.red);
      addTearDown(image.dispose);
      final sources = [for (var index = 0; index < 5; index++) _Frame()];
      Widget page(int index) => MaterialApp(
              home: Center(
                  child: SizedBox.square(
            dimension: 160,
            child: ArtworkHandoff(
              artworkKey: index,
              loadArtwork: () async => sources[index],
              placeholder: const SizedBox.expand(),
              imageBuilder: (source) => Image(image: source, fit: BoxFit.cover),
            ),
          )));
      sources[0].complete(image);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      for (var index = 1; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(image);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump();
        }
        expect(sources[index].loads, 1,
            reason: 'The codec must survive the capture/next-frame mount gap.');
        await tester.pump(AppMotion.standard ~/ 3);
      }
      await tester.pumpAndSettle();
      expect(sources.map((source) => source.loads), everyElement(1));
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  const fluidName =
      'interrupted fluid backdrops retire old blur and motion subtrees';
  if (onlyCase == null || onlyCase == fluidName) {
    testWidgets(fluidName, (tester) async {
      final image = await _image(tester, Colors.red);
      addTearDown(image.dispose);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final sources = [for (var index = 0; index < 4; index++) _Frame()];
      Widget page(int index) => MaterialApp(
              home: Center(
                  child: SizedBox.square(
            dimension: 160,
            child: ArtworkBackdrop(
              artworkKey: index,
              loadArtwork: () async => sources[index],
              blur: 16,
              opacity: .25,
              motion: true,
              fluid: true,
              isPlaying: true,
              hidden: hidden,
              child: const SizedBox.expand(),
            ),
          )));
      sources[0].complete(image);
      await tester.pumpWidget(page(0));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      await tester.pumpWidget(page(1));
      sources[1].complete(image);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      expect(find.byType(BackgroundImageMotion), findsNWidgets(2),
          reason: 'An ordinary A/B fade retains both existing live motions.');
      expect(find.byType(CachedArtworkBlur), findsNWidgets(4),
          reason: 'FluidArtwork preserves two real layers per live source.');
      for (var index = 2; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(image);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump();
        }
        expect(find.byType(BackgroundImageMotion), findsOneWidget);
        expect(find.byType(CachedArtworkBlur), findsNWidgets(2),
            reason: 'The presented composite retires every old blur cache.');
        expect(find.byType(RawImage), findsNWidgets(2));
        await tester.pump(AppMotion.standard ~/ 3);
      }
      hidden.value = true;
      // Handoff's setState schedules one LayoutBuilder frame callback. Paint
      // that required update before counting ongoing presentation callbacks.
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'The hidden surface retains no continuing animation clock.');
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byType(BackgroundImageMotion), findsOneWidget);
      expect(find.byType(CachedArtworkBlur), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final policy in [
    'hidden',
    'ticker disabled',
    'reduced',
    'invisible',
    'late hide'
  ]) {
    final name = '$policy releases interrupted raster and animation resources';
    if (onlyCase != null && onlyCase != name) continue;
    testWidgets(name, (tester) async {
      final image = await _image(tester, Colors.red);
      addTearDown(image.dispose);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final rasters = _RasterHandles(
          onFirstRaster: policy == 'late hide'
              ? () => tester.binding
                  .addPostFrameCallback((_) => hidden.value = true)
              : null);
      addTearDown(rasters.restore);
      final sources = [for (var index = 0; index < 4; index++) _Frame()];
      Widget page(int index, {bool stop = false}) => MaterialApp(
            themeAnimationDuration: Duration.zero,
            home: TickerMode(
              enabled: !(stop && policy == 'ticker disabled'),
              child: Center(
                  child: SizedBox.square(
                dimension: 160,
                child: ArtworkHandoff(
                  artworkKey: index,
                  hidden: hidden,
                  isVisible: !(stop && policy == 'invisible'),
                  loadArtwork: () async => sources[index],
                  placeholder: const SizedBox.expand(),
                  imageBuilder: (source) =>
                      Image(image: source, fit: BoxFit.cover),
                ),
              )),
            ),
          );
      sources[0].complete(image);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(1));
      sources[1].complete(image);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      await tester.pumpWidget(page(2));
      sources[2].complete(image);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      if (policy != 'late hide') {
        expect(rasters.live, hasLength(1),
            reason: 'Only the retained native composite handle remains.');
        if (policy == 'hidden') {
          hidden.value = true;
        } else if (policy == 'reduced') {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
          addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        } else {
          await tester.pumpWidget(page(2, stop: true));
        }
      } else {
        expect(rasters.created, greaterThan(0),
            reason:
                'Hide must interrupt an actual paint capture before commit.');
      }
      // The platform's ImageState accessibility observer also schedules one
      // layout update. A zero-time paint consumes it without completing a fade.
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(rasters.live, isEmpty,
          reason: 'A hidden/reduced surface does not retain a frozen raster.');
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.binding.transientCallbackCount, 0);
      expect(rasters.live, isEmpty);
      sources[3].complete(image);
      await tester.pumpWidget(page(3, stop: true));
      await tester.pumpAndSettle();
      expect(rasters.live, isEmpty,
          reason: 'Disabled motion commits the new image without capturing.');
      expect(find.byType(RawImage), findsOneWidget);
      expect(rasters.peakImages, lessThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
      expect(rasters.live, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  const styleName =
      'live backdrop setting changes preserve an ordinary fade phase';
  if (onlyCase == null || onlyCase == styleName) {
    testWidgets(styleName, (tester) async {
      final red = await _image(tester, Colors.red);
      final blue = await _image(tester, Colors.blue);
      addTearDown(red.dispose);
      addTearDown(blue.dispose);
      final sources = [_Frame()..complete(red), _Frame()];
      Widget page(int index, {bool changed = false}) => MaterialApp(
              home: Center(
                  child: SizedBox.square(
            dimension: 160,
            child: ArtworkBackdrop(
              artworkKey: index,
              blur: changed ? 24 : 16,
              opacity: changed ? .5 : .25,
              loadArtwork: () async => sources[index],
              child: const SizedBox.expand(),
            ),
          )));
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(1));
      sources[1].complete(blue);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      double phase() => tester
          .widget<FadeTransition>(find
              .descendant(
                of: find.byType(ArtworkHandoff),
                matching: find.byType(FadeTransition),
              )
              .last)
          .opacity
          .value;
      final before = phase();
      expect(before, inExclusiveRange(0, 1));
      await tester.pumpWidget(page(1, changed: true));
      expect(phase(), before,
          reason:
              'Only a stale raster needs invalidation; live layers update in place.');
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(tester.binding.transientCallbackCount, 1);
      await tester.pump(AppMotion.standard ~/ 3);
      expect(phase(), greaterThan(before));
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  const blurName =
      'header blur settings invalidate a textured interrupted composite';
  if (onlyCase == null || onlyCase == blurName) {
    testWidgets(blurName, (tester) async {
      final texture = await _texture(tester);
      addTearDown(texture.dispose);
      final preferences = ValueNotifier(const RenderingPreferences());
      addTearDown(preferences.dispose);
      final sources = [for (var index = 0; index < 3; index++) _Frame()];
      final futures = [
        for (final source in sources) Future<ImageProvider?>.value(source)
      ];
      final selected = GlobalKey();
      final reference = GlobalKey();
      Widget page(int index) => MaterialApp(
              home: Center(
                  child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RenderingPreferencesScope(
                preferences: preferences,
                child: SizedBox.square(
                    dimension: 160,
                    child: RepaintBoundary(
                      key: selected,
                      child: DetailHeaderBackdrop(artwork: futures[index]),
                    )),
              ),
              RenderingPreferencesScope(
                preferences: const AlwaysStoppedAnimation(
                    RenderingPreferences(surfaceBlur: false)),
                child: SizedBox.square(
                    dimension: 160,
                    child: RepaintBoundary(
                      key: reference,
                      child: DetailHeaderBackdrop(artwork: futures[2]),
                    )),
              ),
            ],
          )));
      sources[0].complete(texture);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      for (var index = 1; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(texture);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump();
        }
        await tester.pump(AppMotion.standard ~/ 3);
      }
      expect(await _pixel(tester, selected),
          isNot(await _pixel(tester, reference)),
          reason:
              'The striped fixture distinguishes blurred art from its target.');
      preferences.value = preferences.value.copyWith(surfaceBlur: false);
      await tester.pump();
      _continuous(
          await _pixel(tester, reference), await _pixel(tester, selected));
      expect(tester.binding.transientCallbackCount, 0);
      expect(sources.map((source) => source.loads), everyElement(1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in ['resize', 'DPR', 'theme and font', 'presentation']) {
    final samePicture = change == 'theme and font';
    final name = samePicture
        ? 'theme and font changes without picture appearance preserve the fade'
        : '$change invalidates a retained composite without reallocating';
    if (onlyCase != null && onlyCase != name) continue;
    testWidgets(name, (tester) async {
      final image = await _image(tester, Colors.red);
      addTearDown(image.dispose);
      final rasters = _RasterHandles();
      addTearDown(rasters.restore);
      final sources = [for (var index = 0; index < 3; index++) _Frame()];
      Widget page(int index, {bool changed = false}) => MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(
                fontFamily:
                    changed && change == 'theme and font' ? 'serif' : null),
            home: MediaQuery(
              data: MediaQueryData(
                  devicePixelRatio: changed && change == 'DPR' ? 1.5 : 1),
              child: Center(
                  child: SizedBox.square(
                dimension: changed && change == 'resize' ? 180 : 160,
                child: ArtworkHandoff(
                  artworkKey: index,
                  presentationKey: changed && change == 'presentation',
                  loadArtwork: () async => sources[index],
                  placeholder: const SizedBox.expand(),
                  imageBuilder: (source) =>
                      Image(image: source, fit: BoxFit.cover),
                ),
              )),
            ),
          );
      sources[0].complete(image);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      for (var index = 1; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(image);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump();
        }
        await tester.pump(AppMotion.standard ~/ 3);
      }
      expect(rasters.live, hasLength(1));
      double phase() => tester
          .widget<FadeTransition>(find
              .descendant(
                  of: find.byType(ArtworkHandoff),
                  matching: find.byType(FadeTransition))
              .last)
          .opacity
          .value;
      final before = phase();
      await tester.pumpWidget(page(2, changed: true));
      await tester.pump();
      if (samePicture) {
        expect(rasters.live, hasLength(1),
            reason:
                'The decoded picture has no font or theme-color dependency.');
        expect(phase(), before);
        expect(tester.binding.transientCallbackCount, 1);
        await tester.pump(AppMotion.standard ~/ 3);
        expect(phase(), greaterThan(before));
        await tester.pumpAndSettle();
      }
      expect(rasters.live, isEmpty);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(sources.map((source) => source.loads), everyElement(1));
      expect(tester.takeException(), isNull);
    });
  }

  const capName =
      'oversized physical viewports preserve the existing two-image handoff';
  if (onlyCase == null || onlyCase == capName) {
    testWidgets(capName, (tester) async {
      final image = await _image(tester, Colors.red);
      addTearDown(image.dispose);
      final rasters = _RasterHandles();
      addTearDown(rasters.restore);
      final sources = [for (var index = 0; index < 3; index++) _Frame()];
      Widget page(int index) => MaterialApp(
              home: MediaQuery(
            // 160 * 30 in both dimensions exceeds the cap, without allocating
            // a giant test window or calling the handoff's policy helper.
            data: const MediaQueryData(devicePixelRatio: 30),
            child: Center(
                child: SizedBox.square(
              dimension: 160,
              child: ArtworkHandoff(
                artworkKey: index,
                loadArtwork: () async => sources[index],
                placeholder: const SizedBox.expand(),
                imageBuilder: (source) =>
                    Image(image: source, fit: BoxFit.cover),
              ),
            )),
          ));
      sources[0].complete(image);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      for (var index = 1; index < sources.length; index++) {
        await tester.pumpWidget(page(index));
        sources[index].complete(image);
        await tester.pump();
        await tester.pump();
        await tester.pump(AppMotion.standard ~/ 3);
        expect(find.byType(RawImage), findsNWidgets(2));
        expect(rasters.live, isEmpty);
      }
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final backdrop in [false, true]) {
    final name = backdrop
        ? 'animated album palette preserves an interrupted backdrop fade'
        : 'animated album palette preserves an interrupted foreground fade';
    if (onlyCase != null && onlyCase != name) continue;
    testWidgets(name, (tester) async {
      final colors = [Colors.red, Colors.blue, Colors.green];
      final pixels = [for (final color in colors) await _image(tester, color)];
      for (final image in pixels) {
        addTearDown(image.dispose);
      }
      final sources = [for (var index = 0; index < 3; index++) _Frame()];
      final selected = GlobalKey();
      final reference = GlobalKey();
      final fixedTheme =
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: colors[0]));
      Widget cover(int index) => backdrop
          ? ArtworkBackdrop(
              artworkKey: index,
              blur: 0,
              opacity: 0,
              loadArtwork: () async => sources[index],
              child: const SizedBox.expand(),
            )
          : ArtworkHandoff(
              artworkKey: index,
              loadArtwork: () async => sources[index],
              placeholder: const SizedBox.expand(),
              imageBuilder: (provider) =>
                  Image(image: provider, fit: BoxFit.cover),
            );
      Widget page(int index) => MaterialApp(
            theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: colors[index])),
            themeAnimationDuration: AppMotion.standard,
            themeAnimationCurve: AppMotion.standardCurve,
            home: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox.square(
                  dimension: 160,
                  child: RepaintBoundary(
                    key: selected,
                    child: cover(index),
                  )),
              Theme(
                  data: fixedTheme,
                  child: SizedBox.square(
                    dimension: 160,
                    child: RepaintBoundary(key: reference, child: cover(index)),
                  )),
            ])),
          );
      sources[0].complete(pixels[0]);
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(1));
      sources[1].complete(pixels[1]);
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      final mixture = await _pixel(tester, selected);
      expect(mixture[0], greaterThan(0));
      expect(mixture[2], greaterThan(0));
      _continuous(await _pixel(tester, reference), mixture);
      await tester.pumpWidget(page(2));
      sources[2].complete(pixels[2]);
      _continuous(mixture, await _pixel(tester, selected));
      // A real AnimatedTheme palette tick must not fill the selected cover.
      // The unchanged-theme peer has the identical artwork and fade clock.
      for (final elapsed in [
        const Duration(milliseconds: 1),
        AppMotion.standard ~/ 3
      ]) {
        await tester.pump(elapsed);
        _continuous(
            await _pixel(tester, reference), await _pixel(tester, selected));
      }
      await tester.pumpAndSettle();
      _continuous(
          await _pixel(tester, reference), await _pixel(tester, selected));
      expect(sources.map((source) => source.loads), everyElement(1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
