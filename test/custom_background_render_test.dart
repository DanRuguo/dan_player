import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = '${'a' * 64}.png';

class _MemoryStore extends BackgroundImageStore {
  _MemoryStore(this.image)
      : super(directory: () async => throw StateError('No filesystem reads'));
  final MemoryImage image;
  int reads = 0;
  @override
  Future<ImageProvider?> imageFor(String? id) async {
    reads++;
    expect(id, _id);
    return image;
  }
}

Future<MemoryImage> _image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return MemoryImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ArtworkSize> _decode(ImageProvider provider) async {
  final ready = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((info, _) {
    if (!ready.isCompleted) ready.complete(info);
  }, onError: (Object error, StackTrace? stack) {
    if (!ready.isCompleted) ready.completeError(error, stack);
  });
  stream.addListener(listener);
  try {
    final info = await ready.future.timeout(const Duration(seconds: 5));
    try {
      return ArtworkSize(info.image.width, info.image.height);
    } finally {
      info.dispose();
    }
  } finally {
    stream.removeListener(listener);
  }
}

Widget _host(BackgroundLayer layer, {double dpr = 1}) => MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: dpr),
          child:
              Center(child: SizedBox(width: 300, height: 180, child: layer))),
    );

void main() {
  testWidgets(
      'settings thumbnail follows its real width/DPR without rereading or upscaling',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final source in [(2048, 1280), (1280, 2048), (20, 10)]) {
      final image =
          (await tester.runAsync(() => _image(source.$1, source.$2)))!;
      final store = _MemoryStore(image);
      final preferences = ValueNotifier(BackgroundPreferences(
          main: BackgroundAppearance(
              source: BackgroundSource.customImage, customImageId: _id)));
      final status = ValueNotifier(const WindowBackdropStatus());
      ArtworkImageProvider? old;
      for (final dpr in [1.0, 2.0]) {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(900 * dpr, 1000 * dpr);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: BackgroundSettingsPanel(
                  preferences: preferences,
                  status: status,
                  imageStore: store,
                  pickImage: () => throw StateError('No file picker'),
                  onSave: () async => fail('No settings writes'),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        final selected = tester.widget<ChoiceChip>(
            find.byKey(const ValueKey('background-source-customImage')));
        expect(selected.selected, isTrue);
        expect(selected.showCheckmark, isFalse);
        final widget = tester.widget<Image>(find.byType(Image));
        final bounds = tester.getSize(find.byType(Image));
        expect(bounds.height, 112);
        final provider = widget.image as ArtworkImageProvider;
        final expected = ArtworkSize.forDisplay(
            logicalWidth: bounds.width,
            logicalHeight: bounds.height,
            devicePixelRatio: dpr);
        expect(provider.size, expected);
        expect(widget.filterQuality, FilterQuality.high);
        expect(widget.gaplessPlayback, isTrue);
        final decoded = (await tester.runAsync(() => _decode(provider)))!;
        expect(decoded, expected.decodeSize(source.$1, source.$2));
        expect(decoded.width, lessThanOrEqualTo(source.$1));
        expect(decoded.height, lessThanOrEqualTo(source.$2));
        expect(decoded.decodedRgbaBytes, lessThanOrEqualTo(16 * 1024 * 1024));
        if (old != null) expect(provider, isNot(old));
        old = provider;
      }
      expect(store.reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
      status.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  });

  for (final source in [(1600, 900), (900, 1600), (20, 10)]) {
    testWidgets(
        'custom ${source.$1}x${source.$2} uses physical cover sampling at both DPIs',
        (tester) async {
      final image =
          (await tester.runAsync(() => _image(source.$1, source.$2)))!;
      var reads = 0;
      final layer = BackgroundLayer(
        appearance: BackgroundAppearance(
            source: BackgroundSource.customImage, customImageId: _id, blur: 8),
        status: const WindowBackdropStatus(),
        loadCustomImage: (id) async {
          reads++;
          expect(id, _id);
          return image;
        },
      );
      ArtworkImageProvider? old;
      for (final dpr in [1.0, 2.0]) {
        await tester.pumpWidget(_host(layer, dpr: dpr));
        await tester.pump();
        final provider = tester.widget<Image>(find.byType(Image)).image
            as ArtworkImageProvider;
        final expected = ArtworkSize.forDisplay(
            logicalWidth: 300, logicalHeight: 180, devicePixelRatio: dpr);
        expect(provider.size, expected);
        final decoded = (await tester.runAsync(() => _decode(provider)))!;
        expect(decoded, expected.decodeSize(source.$1, source.$2));
        expect(decoded.width, lessThanOrEqualTo(source.$1));
        expect(decoded.height, lessThanOrEqualTo(source.$2));
        if (old != null) expect(provider, isNot(old));
        old = provider;
      }
      expect(reads, 1,
          reason: 'DPR changes decoding, not the source file request');
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  testWidgets('high contrast blocks custom loading and motion entirely',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(_host(BackgroundLayer(
      appearance: BackgroundAppearance(
          source: BackgroundSource.customImage,
          customImageId: _id,
          motion: true),
      status: const WindowBackdropStatus(reason: 'high_contrast'),
      isPlaying: true,
      loadCustomImage: (_) async {
        reads++;
        return null;
      },
    )));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.byType(ArtworkBackdrop), findsNothing);
    expect(find.byType(BackgroundImageMotion), findsNothing);
  });

  testWidgets(
      'desktop with a saved image/motion still never draws or decodes one',
      (tester) async {
    await tester.pumpWidget(_host(BackgroundLayer(
      appearance: BackgroundAppearance(customImageId: _id, motion: true),
      status: const WindowBackdropStatus(available: true),
      isPlaying: true,
      loadCustomImage: (_) =>
          throw StateError('desktop must not read a picture'),
      loadArtwork: () => throw StateError('desktop must not read a cover'),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundImageMotion), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing and invalid custom images use a stable fallback',
      (tester) async {
    for (final id in [_id, '../outside.png']) {
      await tester.pumpWidget(_host(BackgroundLayer(
        appearance: BackgroundAppearance(
            source: BackgroundSource.customImage,
            customImageId: id,
            motion: true),
        status: const WindowBackdropStatus(),
        isPlaying: true,
        loadCustomImage: (_) async => null,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(BackgroundImageMotion), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
