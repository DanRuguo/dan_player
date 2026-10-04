import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/component/category_cover_flight.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Artwork extends StatefulWidget {
  const _Artwork(this.image, this.identity);
  final ImageProvider image;
  final Object identity;
  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork> {
  @override
  Widget build(BuildContext context) =>
      Image(image: widget.image, fit: BoxFit.cover);
}

Future<Uint8List> _png() async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 128);
  try {
    return (await image.toByteData(format: drawing.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

Future<Color> _capture(
        WidgetTester tester, GlobalKey key, String name, Offset point) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!;
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final color = Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2));
        final directory =
            Platform.environment['DAN_CATEGORY_NATIVE_RENDER_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          final png =
              (await image.toByteData(format: drawing.ImageByteFormat.png))!;
          await File('$directory/$name.png')
              .writeAsBytes(png.buffer.asUint8List());
        }
        return color;
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  late ImageProvider image;
  setUpAll(() async => image = MemoryImage(await _png()));
  testWidgets(
      'category cover respects native gate before navigation and preserves artwork state',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox.square(
                dimension: 112,
                child: CategoryCoverFlight(
                    tag: 'native-category',
                    radius: 16,
                    image: image,
                    child: _Artwork(image, 'source'))))));
    await _decode(tester);
    final state = tester.state(find.byType(_Artwork));
    expect(
        MediaQuery.disableAnimationsOf(tester.element(find.byType(_Artwork))),
        isFalse);
    expect(find.byType(Hero), findsNothing,
        reason:
            'Native reduceMotion is a distinct flag from MediaQuery disableAnimations');
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsOneWidget);
    expect(tester.state(find.byType(_Artwork)), same(state));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    expect(tester.state(find.byType(_Artwork)), same(state));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final playlist in [false, true]) {
    testWidgets(
        'native gate removes the active ${playlist ? 'playlist' : 'category'} shuttle and reveals destination pixels',
        (tester) async {
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final navigator = GlobalKey<NavigatorState>();
      final boundary = GlobalKey();
      Widget cover(double size, double radius, Object identity) {
        final artwork = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: _Artwork(image, identity));
        return SizedBox.square(
            dimension: size,
            child: playlist
                ? PlaylistCoverRouteFlight(
                    playlistId: 'native-category',
                    borderRadius: BorderRadius.circular(radius),
                    child: artwork)
                : CategoryCoverFlight(
                    tag: 'native-category',
                    radius: radius,
                    image: image,
                    child: artwork));
      }

      await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => RepaintBoundary(key: boundary, child: child),
          home:
              const ColoredBox(color: Colors.black, child: SizedBox.expand())));
      // Both pages use the real Navigator Hero controller, with a neutral route
      // surface so its independent fade cannot masquerade as a cover-gate result.
      navigator.currentState!.pushReplacement(PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => ColoredBox(
              color: Colors.black,
              child: Stack(children: [
                Positioned(left: 520, top: 380, child: cover(48, 24, 'source'))
              ]))));
      await tester.pumpAndSettle();
      await _decode(tester);
      navigator.currentState!.push(PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => ColoredBox(
              color: Colors.black,
              child: Stack(children: [
                Positioned(
                    left: 20, top: 20, child: cover(112, 16, 'destination'))
              ]))));
      await tester.pump();
      await tester.pump();
      await _decode(tester);
      await tester.pump(const Duration(milliseconds: 160));
      final flight = find.byKey(ValueKey(
          playlist ? 'playlist-route-flight-image' : 'category-flight-image'));
      expect(flight, findsOneWidget);
      final midpoint = tester.getCenter(flight);
      expect(midpoint.dx, greaterThan(150));
      final prefix = playlist ? 'playlist-native' : 'category-native';
      expect(
          (await _capture(tester, boundary, '$prefix-before', midpoint))
              .toARGB32(),
          Colors.red.toARGB32());
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      final cleared =
          await _capture(tester, boundary, '$prefix-after', midpoint);
      expect(flight, findsNothing,
          reason:
              'An already started Hero must stop painting its cached moving surface');
      expect(cleared.toARGB32(), Colors.black.toARGB32());
      expect(
          (await _capture(tester, boundary, '$prefix-destination',
                  const Offset(76, 76)))
              .toARGB32(),
          Colors.red.toARGB32());
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      expect(flight, findsNothing,
          reason: 'Restoring motion must not revive this cancelled flight');
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
