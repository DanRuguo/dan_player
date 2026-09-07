import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/desktop_tray_appearance.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(danEmbeddedFontFamily)
      ..addFont(File('assets/fonts/PingFangSC-Regular.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  });

  test('separate payload budgets and old thumbnail protocol', () {
    for (final (width, height, length) in [
      (0, 1, 0),
      (2049, 1, 8196),
      (2048, 513, 4202496),
      (1440, 720, 3),
    ]) {
      expect(() => TaskbarPeekImage(width, height, Uint8List(length)),
          throwsArgumentError);
    }
    final small = TaskbarThumbnail(1, 1, Uint8List(4));
    expect(small.toMap().keys, ['width', 'height', 'pixels']);
    final large = TaskbarPeekImage(1440, 720, Uint8List(1440 * 720 * 4));
    final pair = TaskbarThumbnail(1, 1, Uint8List(4), peek: large);
    expect(pair.toMap()['peek'], large.toMap());
  });

  test('tray constants keep all nine Material Symbols in release subset', () {
    expect(desktopTrayIcons, hasLength(9));
    expect(desktopTrayIcons.map((icon) => icon.codePoint), [
      0xe89e,
      0xe911,
      0xe045,
      0xe037,
      0xe034,
      0xe044,
      0xec0b,
      0xf8c7,
      0xe668
    ]);
    expect(
        desktopTrayIcons
            .every((icon) => icon.fontFamily == 'MaterialSymbolsOutlined'),
        isTrue);
    final configuration = desktopTrayIconConfiguration();
    expect(configuration['trayIconCodepoints'],
        desktopTrayIcons.map((icon) => icon.codePoint).toList());
    expect(configuration['trayIconFontPath'],
        endsWith('MaterialSymbolsOutlined.ttf'));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '$brightness Peek has independent large composition, thumbnail stays 480',
        (tester) async {
      const track = TaskbarPreviewTrack(
          identity: 'synthetic',
          title: '清晰 Clear Ágj かな',
          artist: '艺术家 Artist',
          album: '专辑 Album');
      final card = await tester.runAsync(() => renderTaskbarSongPreview(
          track,
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
          danEmbeddedFontFamily));
      expect((card!.width, card.height), (480, 240));
      final peek = card.peek!;
      expect((peek.width, peek.height), (1280, 800));
      expect(peek.pixels.length, lessThanOrEqualTo(4 * 1024 * 1024));
      var differentFromNearest = 0, differentFromBilinear = 0;
      for (var y = 180; y < 316; y++) {
        for (var x = 592; x < 1166; x++) {
          final offset = (y * peek.width + x) * 4;
          expect(peek.pixels[offset + 3], 255);
          final sx = ((x + .5) * 480 / 1280 - .5).clamp(0.0, 479.0);
          final sy = ((y + .5) * 240 / 800 - .5).clamp(0.0, 239.0);
          final left = sx.floor(), top = sy.floor();
          final right = (left + 1).clamp(0, 479),
              bottom = (top + 1).clamp(0, 239);
          final fx = sx - left, fy = sy - top;
          int sample(int px, int py) => card.pixels[(py * card.width + px) * 4];
          final bilinear =
              ((sample(left, top) * (1 - fx) + sample(right, top) * fx) *
                          (1 - fy) +
                      (sample(left, bottom) * (1 - fx) +
                              sample(right, bottom) * fx) *
                          fy)
                  .round();
          if ((peek.pixels[offset] - bilinear).abs() > 4) {
            differentFromBilinear++;
          }
          if (peek.pixels[offset] != sample(x * 480 ~/ 1280, y * 240 ~/ 800)) {
            differentFromNearest++;
          }
        }
      }
      expect(differentFromNearest, greaterThan(200));
      expect(differentFromBilinear, greaterThan(200),
          reason:
              'large cover and separately rasterized title must not stretch the small card');
    });

    testWidgets(
        '$brightness synthetic artwork and status produce bounded exportable previews',
        (tester) async {
      await tester.runAsync(() async {
        final recorder = raster.PictureRecorder();
        final canvas = Canvas(recorder);
        const bounds = Rect.fromLTWH(0, 0, 448, 448);
        canvas.drawRect(
            bounds,
            Paint()
              ..shader = const LinearGradient(
                      colors: [Color(0xff0b5e6b), Color(0xff8fc9be)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)
                  .createShader(bounds));
        canvas.drawCircle(const Offset(324, 108), 60,
            Paint()..color = const Color(0xffffd49b));
        for (var i = 0; i < 5; i++) {
          canvas.drawOval(
              Rect.fromLTWH(-140 + i * 30, 210 + i * 42, 740, 390),
              Paint()
                ..color = Color.lerp(
                    const Color(0xff0b5c70), const Color(0xffbfdccd), i / 5)!);
        }
        final picture = recorder.endRecording();
        final art = await picture.toImage(448, 448);
        final png = await art.toByteData(format: raster.ImageByteFormat.png);
        final provider = MemoryImage(png!.buffer.asUint8List());
        art.dispose();
        picture.dispose();
        final card = await renderTaskbarSongPreview(
            TaskbarPreviewTrack(
                identity: 'synthetic-qa',
                title: '海岸回声 · Coastal Echoes',
                artist: 'Dan Player Studio',
                album: 'Blue Hour / 合成视觉样例',
                durationSeconds: 237,
                playing: brightness == Brightness.light,
                statusLabel: brightness == Brightness.light ? '正在播放' : '已暂停',
                loadArtwork: () async => provider),
            ColorScheme.fromSeed(
                seedColor: Colors.teal, brightness: brightness),
            danEmbeddedFontFamily);
        expect(card.peek!.pixels.length, 4096000);
        expect(card.peek!.pixels.length, lessThan(4 * 1024 * 1024));
        final output = Platform.environment['DAN_PLAYER_PREVIEW_QA_DIR'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          Future<void> write(
              String kind, int width, int height, Uint8List rgba) async {
            final result = Completer<raster.Image>();
            raster.decodeImageFromPixels(rgba, width, height,
                raster.PixelFormat.rgba8888, result.complete);
            final image = await result.future;
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            image.dispose();
            await File('$output/taskbar-$kind-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            if (kind == 'peek') {
              await File('$output/taskbar-$kind-${brightness.name}.rgba')
                  .writeAsBytes(rgba);
            }
          }

          await write('small', card.width, card.height, card.pixels);
          await write(
              'peek', card.peek!.width, card.peek!.height, card.peek!.pixels);
        }
      });
    });
  }

  test('latest generation sends matching thumbnail and Peek in one atomic RPC',
      () async {
    final pending = Completer<TaskbarThumbnail>();
    final received = <Map<String, Object>>[];
    TaskbarThumbnail pair(int value) => TaskbarThumbnail(
        1, 1, Uint8List.fromList([value, 0, 0, 255]),
        peek: TaskbarPeekImage(1, 1, Uint8List.fromList([value, 0, 0, 255])));
    final publisher = TaskbarPreviewPublisher(
        invoke: (method, [arguments]) async {
          if (method == 'setThumbnail') received.add(arguments!);
          return null;
        },
        renderer: (track, _, __) =>
            track.identity == 1 ? pending.future : Future.value(pair(2)));
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    publisher.synchronize(
        enabled: true,
        scheme: scheme,
        track: const TaskbarPreviewTrack(
            identity: 1, title: 'old', artist: '', album: ''));
    publisher.synchronize(
        enabled: true,
        scheme: scheme,
        track: const TaskbarPreviewTrack(
            identity: 2, title: 'new', artist: '', album: ''));
    pending.complete(pair(1));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect((received.single['pixels'] as Uint8List).first, 2);
    expect(((received.single['peek'] as Map)['pixels'] as Uint8List).first, 2);
    await publisher.dispose();
  });
}
