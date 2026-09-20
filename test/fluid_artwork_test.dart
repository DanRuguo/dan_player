import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/fluid_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemoryImage> _source() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var x = 0; x < 8; x++) {
    canvas.drawRect(
        Rect.fromLTWH(x * 40, 0, 40, 240),
        Paint()
          ..color =
              x.isEven ? const Color(0xffdd2244) : const Color(0xff113388));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 240);
  picture.dispose();
  try {
    return MemoryImage((await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List());
  } finally {
    image.dispose();
  }
}

Widget _app(ImageProvider image,
        {ValueNotifier<bool>? hidden,
        bool playing = true,
        bool enabled = true,
        bool layered = true,
        GlobalKey? boundary,
        Future<ImageProvider?> Function()? load,
        Object? id}) =>
    MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                    width: 320,
                    height: 240,
                    child: ArtworkBackdrop(
                        artworkKey: id ?? image,
                        loadArtwork: load ?? () async => image,
                        blur: 8,
                        opacity: 0,
                        motion: enabled,
                        fluid: layered,
                        isPlaying: playing,
                        hidden: hidden,
                        child: const SizedBox.expand())))));

Future<void> _ready(WidgetTester tester, ImageProvider image) async {
  final context = tester.element(find.byType(ArtworkBackdrop));
  await tester.runAsync(() => precacheImage(
      ResizeImage(image,
          width: 512, height: 512, policy: ResizeImagePolicy.fit),
      context));
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() async {});
    await tester.pump();
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

void main() {
  testWidgets(
      'layered motion retains blurred spatial detail and pauses immediately',
      (tester) async {
    final source = (await tester.runAsync(_source))!;
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(_app(source, hidden: hidden, boundary: key));
    await _ready(tester, source);
    expect(find.byType(FluidArtwork), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNWidgets(2));
    final first = await _pixels(tester, key);
    final reds = [for (var x = 32; x < 288; x += 8) first[(120 * 320 + x) * 4]];
    expect(
        reds.reduce((a, b) => a > b ? a : b) -
            reds.reduce((a, b) => a < b ? a : b),
        greaterThan(40),
        reason:
            'Repeated fine bands with the same quadrant averages must survive.');
    final flow =
        tester.widget<Flow>(find.byType(Flow)).delegate as ArtworkFlowDelegate;
    await tester.pump(const Duration(seconds: 2));
    expect(flow.phase.value, greaterThan(0));
    hidden.value = true;
    final frozen = flow.phase.value;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(flow.phase.value, frozen);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'pending artwork keeps the same outgoing flow and never inserts palette fields',
      (tester) async {
    final source = (await tester.runAsync(_source))!;
    await tester.pumpWidget(_app(source));
    await _ready(tester, source);
    final old = tester.element(find.byType(FluidArtwork));
    final pending = Completer<ImageProvider?>();
    await tester
        .pumpWidget(_app(source, id: 'next', load: () => pending.future));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.element(find.byType(FluidArtwork)), same(old));
    final next = (await tester.runAsync(_source))!;
    pending.complete(next);
    await _ready(tester, next);
    expect(find.byType(FluidArtwork), findsNWidgets(2));
    expect(tester.elementList(find.byType(FluidArtwork)).first, same(old));
    final arriving = tester.elementList(find.byType(FluidArtwork)).last;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FluidArtwork), findsOneWidget);
    expect(tester.element(find.byType(FluidArtwork)), same(arriving));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'pausing and drift selection stop or replace only the moving layer',
      (tester) async {
    final source = (await tester.runAsync(_source))!;
    await tester.pumpWidget(_app(source));
    await _ready(tester, source);
    await tester.pump(const Duration(milliseconds: 64));
    final flow =
        tester.widget<Flow>(find.byType(Flow)).delegate as ArtworkFlowDelegate;
    await tester.pumpWidget(_app(source, playing: false));
    final frozen = flow.phase.value;
    await tester.pump(const Duration(seconds: 1));
    expect(flow.phase.value, frozen);
    await tester.pumpWidget(_app(source, layered: false));
    expect(find.byType(FluidArtwork), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
        tester
            .widget<BackgroundImageMotion>(find.byType(BackgroundImageMotion))
            .refreshInterval,
        BackgroundImageMotion.frameInterval);
    await tester.pumpWidget(_app(source, enabled: false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('background style survives persistence and legacy defaults', () {
    const original = BackgroundAppearance(motion: true, layeredMotion: false);
    expect(
        BackgroundAppearance.fromMap(original.toMap(),
            fallback: const BackgroundAppearance()),
        original);
    expect(
        BackgroundAppearance.fromMap({'motion': true},
                fallback: const BackgroundAppearance())
            .layeredMotion,
        isTrue);
  });
}
