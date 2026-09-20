import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/component/player_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows and installer default to the same normal player emblem', () {
    expect(
      File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      File(PlayerLogo.normalAsset).readAsBytesSync(),
    );
  });

  test('both bundled ICO emblems decode with transparent corners', () async {
    final assets = [PlayerLogo.normalAsset, PlayerLogo.darkAsset];
    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Check the actual icon directory, not an external generated preview.
      expect(data.getUint16(0, Endian.little), 0);
      expect(data.getUint16(2, Endian.little), 1);
      expect(data.getUint16(4, Endian.little), 10);
      final dimensions = <int>{};
      for (var frame = 0; frame < 10; frame++) {
        final offset = 6 + frame * 16;
        final width = data.getUint8(offset);
        final height = data.getUint8(offset + 1);
        expect(height, width);
        dimensions.add(width == 0 ? 256 : width);
      }
      expect(dimensions, {16, 20, 24, 32, 40, 48, 64, 96, 128, 256});

      final codec = await raster.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, 256);
          expect(image.height, 256);
          final rgba = await image.toByteData();
          expect(rgba, isNotNull);
          for (final point in [(0, 0), (255, 0), (0, 255), (255, 255)]) {
            expect(rgba!.getUint8((point.$2 * 256 + point.$1) * 4 + 3), 0);
          }
          expect(rgba!.getUint8((128 * 256 + 128) * 4 + 3), greaterThan(240));
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  });

  testWidgets('logo follows live theme changes and limits small-icon decoding',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    var brightness = Brightness.light;
    late StateSetter change;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      change = setState;
      return MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(brightness: brightness),
        home: const Center(child: PlayerLogo()),
      );
    }));

    Future<void> verify(String asset) async {
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;
      expect((provider.imageProvider as AssetImage).assetName, asset);
      expect(provider.width, 72);
      expect(provider.height, 72);
      expect(image.gaplessPlayback, isTrue);
      await tester.runAsync(() async {
        await precacheImage(
            image.image, tester.element(find.byType(PlayerLogo)));
      });
      await tester.pump();
      final rendered = tester.renderObject<RenderImage>(find.byType(RawImage));
      expect(rendered.image?.width, 72);
      expect(rendered.image?.height, 72);
      expect(tester.getSize(find.byType(PlayerLogo)), const Size(24, 24));
      expect(tester.takeException(), isNull);
    }

    await verify(PlayerLogo.normalAsset);
    change(() => brightness = Brightness.dark);
    await tester.pump();
    await verify(PlayerLogo.darkAsset);
    change(() => brightness = Brightness.light);
    await tester.pump();
    await verify(PlayerLogo.normalAsset);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
