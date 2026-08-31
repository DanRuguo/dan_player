import 'dart:async';
import 'dart:io';

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
        '$brightness Peek has newly rasterized glyph detail, thumbnail stays 480',
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
      expect((peek.width, peek.height), (1440, 720));
      expect(peek.pixels.length, lessThanOrEqualTo(4 * 1024 * 1024));
      var differentFromNearest = 0, differentFromBilinear = 0;
      for (var y = 105; y < 280; y++) {
        for (var x = 660; x < 1368; x++) {
          final offset = (y * peek.width + x) * 4;
          expect(peek.pixels[offset + 3], 255);
          final sx = ((x + .5) / 3 - .5).clamp(0.0, 479.0);
          final sy = ((y + .5) / 3 - .5).clamp(0.0, 239.0);
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
          if (peek.pixels[offset] != sample(x ~/ 3, y ~/ 3)) {
            differentFromNearest++;
          }
        }
      }
      expect(differentFromNearest, greaterThan(200));
      expect(differentFromBilinear, greaterThan(200),
          reason:
              '3x vector re-rasterization must not be a stretched 480px bitmap');
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
