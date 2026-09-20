import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/fluid_artwork.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Uses the real ResizeImage decoder callback, not predecoded mock frames.
class _Image extends ImageProvider<_Image> {
  _Image(this.bytes);
  Future<Uint8List> bytes;
  int loads = 0;
  Size? decodedSize;
  ImageStreamCompleter? latestStream;

  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) {
    loads++;
    final pendingBytes = bytes;
    return latestStream = OneFrameImageStreamCompleter(() async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(await pendingBytes);
      final codec = await decode(buffer);
      try {
        final frame = await codec.getNextFrame();
        decodedSize =
            Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        return ImageInfo(image: frame.image);
      } finally {
        codec.dispose();
      }
    }());
  }
}

const _palette = [
  Color(0xffcc2200),
  Color(0xff00bb44),
  Color(0xff2244cc),
  Color(0xffbb9900)
];

Future<Uint8List> _png(List<Color> colors,
    {int width = 256, int height = 128}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < 4; i++) {
    canvas.drawRect(
        Rect.fromLTWH(
            (i % 2) * width / 2, (i ~/ 2) * height / 2, width / 2, height / 2),
        Paint()..color = colors[i]);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

Future<_Image> _ready(WidgetTester tester, List<Color> colors) async =>
    (await tester.runAsync(() async {
      final image = _Image(Future.value(await _png(colors)));
      expect(await FluidArtworkPalette.resolve(image), colors);
      return image;
    }))!;

Future<void> _drain(WidgetTester tester) async {
  // Image decoding/readback futures belong to the real engine zone.
  await tester.runAsync(() async {});
  await tester.pump();
}

Widget _app(
  ImageProvider image, {
  ValueListenable<bool>? hidden,
  bool playing = true,
  bool enabled = true,
  bool reduced = false,
  bool themeMotion = true,
  GlobalKey? boundary,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: MotionPreferencesScope(
          preferences: MotionPreferences(
              disabled: themeMotion ? const {} : const {MotionKind.theme}),
          child: Center(
              child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 240,
                    height: 160,
                    child: BackgroundImageMotion(
                      enabled: enabled,
                      isPlaying: playing,
                      hidden: hidden,
                      phaseBuilder: (phase, active, child) => FluidArtwork(
                          image: image,
                          phase: phase,
                          active: active,
                          fallback: child),
                      child: const ColoredBox(
                          key: ValueKey('fallback'), color: Colors.black),
                    ),
                  ))),
        ),
      ),
    );

FluidArtworkPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byType(FluidArtwork),
        matching: find.byWidgetPredicate((widget) =>
            widget is CustomPaint && widget.painter is FluidArtworkPainter)))
    .painter! as FluidArtworkPainter;

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

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('samples at 32px and shares one decode across size wrappers',
      (tester) async {
    await tester.runAsync(() async {
      final source = _Image(Future.value(await _png(_palette)));
      final first = FluidArtworkPalette.resolve(source);
      final wrapper = ArtworkImageProvider(
          ResizeImage(source, width: 512), const ArtworkSize(128, 128));
      expect(FluidArtworkPalette.resolve(wrapper), same(first));
      expect(await first, _palette);
      expect(source.decodedSize, const Size(32, 16));
      expect(source.loads, 1);
      expect(source.latestStream!.hasListeners, isFalse);
    });
  });

  testWidgets('transparent samples do not poison a recovered same-source image',
      (tester) async {
    await tester.runAsync(() async {
      final source =
          _Image(Future.value(await _png(List.filled(4, Colors.transparent))));
      expect(await FluidArtworkPalette.resolve(source), isNull);
      expect(source.latestStream!.hasListeners, isFalse);
      source.bytes = Future.value(await _png(_palette));
      expect(await FluidArtworkPalette.resolve(source), _palette);
      expect(source.loads, 2);
    });
  });

  testWidgets('bounded palette cache retains recent futures and evicts oldest',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(_palette);
      final sources = List.generate(17, (_) => _Image(Future.value(bytes)));
      final first = FluidArtworkPalette.resolve(sources.first);
      await first;
      for (final image in sources.skip(1)) {
        await FluidArtworkPalette.resolve(image);
      }
      final recent = FluidArtworkPalette.resolve(sources.last);
      expect(FluidArtworkPalette.resolve(sources.last), same(recent));
      expect(FluidArtworkPalette.resolve(sources.first), isNot(same(first)));
      await FluidArtworkPalette.resolve(sources.first);
    });
  });

  testWidgets('late previous artwork cannot replace the current colour field',
      (tester) async {
    final pending =
        (await tester.runAsync(() async => Completer<Uint8List>()))!;
    final old = _Image(pending.future);
    await tester.runAsync(() async {
      unawaited(FluidArtworkPalette.resolve(old));
    });
    final current = await _ready(tester, _palette);
    await tester.pumpWidget(_app(old));
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    await tester.pumpWidget(_app(current));
    await _drain(tester);
    expect(_painter(tester).colors, _palette);
    await tester.runAsync(() async {
      pending.complete(await _png(List.filled(4, Colors.white)));
      await FluidArtworkPalette.resolve(old);
    });
    await _drain(tester);
    expect(_painter(tester).colors, _palette);
    expect(old.latestStream!.hasListeners, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shared phase repaints opaque pixels without rebuilding the painter or decoding',
      (tester) async {
    final source = await _ready(tester, _palette);
    final key = GlobalKey();
    await tester.pumpWidget(_app(source, boundary: key));
    await _drain(tester);
    final painter = _painter(tester);
    final initial = await _pixels(tester, key);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final after = await _pixels(tester, key);
    expect(identical(_painter(tester), painter), isTrue);
    expect(painter.phase.value, closeTo(1 / 36, 1e-10));
    expect(listEquals(initial, after), isFalse);
    expect([for (var i = 3; i < after.length; i += 4) after[i]],
        everyElement(255));
    expect(source.loads, 1);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'native hide immediately stops both shared phase and pending colour transition',
      (tester) async {
    final first = await _ready(tester, _palette);
    final second = await _ready(tester, List.filled(4, Colors.white));
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_app(first, hidden: hidden));
    await _drain(tester);
    await tester.pumpWidget(_app(second, hidden: hidden));
    await _drain(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final phase = _painter(tester).phase;
    final frozen = phase.value;
    hidden.value = true;
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(phase.value, frozen);
    expect(_painter(tester).colors, List.filled(4, Colors.white));
    expect(tester.binding.hasScheduledFrame, isFalse);
    hidden.value = false;
    await tester.pump(const Duration(milliseconds: 50));
    expect(phase.value, greaterThan(frozen));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('palette arriving while hidden never starts a finite animation',
      (tester) async {
    final first = await _ready(tester, _palette);
    final pending =
        (await tester.runAsync(() async => Completer<Uint8List>()))!;
    final second = _Image(pending.future);
    await tester.runAsync(() async {
      unawaited(FluidArtworkPalette.resolve(second));
    });
    final hidden = ValueNotifier(true);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_app(first, hidden: hidden));
    await _drain(tester);
    await tester.pumpWidget(_app(second, hidden: hidden));
    await tester.runAsync(() async {
      pending.complete(await _png(List.filled(4, Colors.white)));
      await FluidArtworkPalette.resolve(second);
    });
    await _drain(tester);
    expect(_painter(tester).colors, List.filled(4, Colors.white));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(_painter(tester).phase.value, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final gate in ['pause', 'reduced', 'theme', 'disabled']) {
    testWidgets(
        '$gate cancels an in-flight colour transition without a build-phase exception',
        (tester) async {
      final first = await _ready(tester, _palette);
      final second = await _ready(tester, List.filled(4, Colors.white));
      await tester.pumpWidget(_app(first));
      await _drain(tester);
      await tester.pumpWidget(_app(second));
      await _drain(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(_app(second,
          playing: gate != 'pause',
          reduced: gate == 'reduced',
          enabled: gate != 'disabled',
          themeMotion: gate != 'theme'));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      if (gate == 'disabled') {
        expect(find.byType(FluidArtwork), findsNothing);
        expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
      } else {
        expect(_painter(tester).colors, List.filled(4, Colors.white));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
