import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemoryImage> _image(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final bitmap = await picture.toImage(8, 8);
  try {
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(bytes!.buffer.asUint8List());
  } finally {
    bitmap.dispose();
    picture.dispose();
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final effect in ['acrylic', 'blur']) {
      testWidgets(
          '$brightness $effect transparency paints a single neutral veil',
          (tester) async {
        final scheme =
            ColorScheme.fromSeed(seedColor: Colors.red, brightness: brightness);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: const SizedBox.expand()));
        final native = WindowBackdropStatus(available: true, effect: effect);
        for (final opacity in [.25, .70, .95]) {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(colorScheme: scheme),
              home: BackgroundLayer(
                appearance: BackgroundAppearance(opacity: opacity),
                status: native,
                neutralFallback: true,
                loadArtwork: () => throw StateError(
                    'Desktop must never request album artwork'),
              )));
          final color = tester
              .widget<ColoredBox>(find.descendant(
                  of: find.byType(BackgroundLayer),
                  matching: find.byType(ColoredBox)))
              .color;
          expect(color.a, closeTo(opacity, .001));
          expect(color.r, closeTo(color.g, .0001));
          expect(color.g, closeTo(color.b, .0001));
          expect(find.byType(ImageFiltered), findsNothing);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final reason in [
    'high_contrast',
    'transparency_disabled',
    'energy_saver',
    'unsupported_platform'
  ]) {
    testWidgets('$reason desktop uses opaque fallback', (tester) async {
      const fallback = Color(0xFF223344);
      await tester.pumpWidget(MaterialApp(
          home: BackgroundLayer(
        appearance: const BackgroundAppearance(opacity: .25),
        status: WindowBackdropStatus(reason: reason, fallbackColor: fallback),
        neutralFallback: true,
      )));
      final box = tester.widget<ColoredBox>(find.descendant(
          of: find.byType(BackgroundLayer), matching: find.byType(ColoredBox)));
      expect(box.color, fallback);
      expect(find.byType(ImageFiltered), findsNothing);
    });
  }

  testWidgets('high contrast also blocks artwork decoding', (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: BackgroundLayer(
      appearance: const BackgroundAppearance(source: BackgroundSource.artwork),
      status: const WindowBackdropStatus(reason: 'high_contrast'),
      loadArtwork: () async {
        reads++;
        return null;
      },
    )));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.byType(ArtworkBackdrop), findsNothing);
  });

  testWidgets(
      'opacity/blur changes reuse artwork and do not filter foreground content',
      (tester) async {
    final cover = (await tester.runAsync(() => _image(Colors.teal)))!;
    var reads = 0;
    var foregroundBuilds = 0;
    final preferences = ValueNotifier(
        const BackgroundAppearance(source: BackgroundSource.artwork));
    addTearDown(preferences.dispose);
    final editor = TextEditingController(text: 'keep this text');
    addTearDown(editor.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: Stack(fit: StackFit.expand, children: [
      ValueListenableBuilder<BackgroundAppearance>(
          valueListenable: preferences,
          builder: (_, value, __) => BackgroundLayer(
                appearance: value,
                status: const WindowBackdropStatus(),
                artworkKey: 'same-track',
                loadArtwork: () async {
                  reads++;
                  return cover;
                },
              )),
      Builder(builder: (_) {
        foregroundBuilds++;
        return Center(
            child: TextField(
                key: const ValueKey('foreground'), controller: editor));
      }),
    ]))));
    await tester.pumpAndSettle();
    for (final value in [16.0, 48.0, 92.0]) {
      preferences.value = preferences.value.copyWith(blur: value, opacity: .6);
      await tester.pumpAndSettle();
      expect(tester.widget<ArtworkBackdrop>(find.byType(ArtworkBackdrop)).blur,
          value);
    }
    expect(reads, 1);
    expect(foregroundBuilds, 1);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('foreground')),
            matching: find.byType(ImageFiltered)),
        findsNothing);
    expect(editor.text, 'keep this text');
    preferences.value =
        preferences.value.copyWith(source: BackgroundSource.solid);
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkBackdrop), findsNothing);
    expect(foregroundBuilds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new main/mini appearance cannot eagerly create the playback engine',
      (tester) async {
    final original = AppSettings.instance.backgrounds.value;
    addTearDown(() => AppSettings.instance.backgrounds.value = original);
    expect(PlayService.isInitialized, isFalse);
    for (final scene in BackgroundScene.values) {
      AppSettings.instance.backgrounds.value = const BackgroundPreferences()
          .withScene(scene,
              const BackgroundAppearance(source: BackgroundSource.artwork));
      await tester.pumpWidget(MaterialApp(home: SceneBackground(scene: scene)));
      await tester.pumpAndSettle();
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an outdated background future cannot bring old artwork back',
      (tester) async {
    final old = Completer<ImageProvider?>();
    final next = Completer<ImageProvider?>();
    Widget app(Object key, Future<ImageProvider?> value) => MaterialApp(
            home: BackgroundLayer(
          appearance:
              const BackgroundAppearance(source: BackgroundSource.artwork),
          status: const WindowBackdropStatus(),
          artworkKey: key,
          loadArtwork: () => value,
        ));
    await tester.pumpWidget(app('old', old.future));
    await tester.pumpWidget(app('next', next.future));
    next.complete(null);
    await tester.pumpAndSettle();
    final image = (await tester.runAsync(() => _image(Colors.red)))!;
    old.complete(image);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });
}
