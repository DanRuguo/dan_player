import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playlist_feature_fixture.dart';

Future<void> _save(TaskbarThumbnail card, String name) async {
  final output = Platform.environment['DAN_RESOURCE_PREVIEW_RENDER_DIR'];
  if (output == null) return;
  final decoded = Completer<raster.Image>();
  raster.decodeImageFromPixels(card.pixels, card.width, card.height,
      raster.PixelFormat.rgba8888, decoded.complete);
  final image = await decoded.future;
  final recorder = raster.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, card.width.toDouble(), card.height.toDouble()),
      const Rect.fromLTWH(0, 0, 240, 120),
      Paint()..filterQuality = FilterQuality.high);
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(240, 120);
  await Directory(output).create(recursive: true);
  for (final (suffix, value) in [('card', image), ('system-scale', scaled)]) {
    final png = await value.toByteData(format: raster.ImageByteFormat.png);
    await File('$output/$name-$suffix.png')
        .writeAsBytes(png!.buffer.asUint8List());
  }
  image.dispose();
  scaled.dispose();
  picture.dispose();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  testWidgets('larger cover and title raster keep bounded opaque thumbnail',
      (tester) async {
    await tester.runAsync(() async {
      final record = raster.PictureRecorder();
      Canvas(record).drawColor(const Color(0xffff0000), BlendMode.src);
      final picture = record.endRecording();
      final art = await picture.toImage(448, 448);
      final png = await art.toByteData(format: raster.ImageByteFormat.png);
      final provider = MemoryImage(png!.buffer.asUint8List());
      art.dispose();
      picture.dispose();
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final card = await renderTaskbarSongPreview(
          TaskbarPreviewTrack(
              identity: 'fixture',
              title: 'TRACK',
              artist: 'ARTIST',
              album: 'ALBUM',
              loadArtwork: () async => provider),
          scheme,
          danEmbeddedFontFamily);
      int pixel(int x, int y, int component) =>
          card.pixels[(y * card.width + x) * 4 + component];
      expect(pixel(218, 120, 0), 255);
      expect(pixel(218, 120, 1), 0);
      expect(pixel(116, 18, 0), 255);
      expect((card.width, card.height), (480, 240));
      expect(card.peek!.pixels.length, lessThanOrEqualTo(4 * 1024 * 1024));
      final ys = <int>[];
      for (var y = 50; y < 90; y++) {
        for (var x = 240; x < 456; x++) {
          if (pixel(x, y, 0) == (scheme.primary.r * 255).round() &&
              pixel(x, y, 1) == (scheme.primary.g * 255).round() &&
              pixel(x, y, 2) == (scheme.primary.b * 255).round()) {
            ys.add(y);
          }
        }
      }
      expect(ys, isNotEmpty);
      expect(
          ys.reduce((a, b) => a > b ? a : b) -
              ys.reduce((a, b) => a < b ? a : b),
          greaterThanOrEqualTo(19));
      for (var offset = 3; offset < card.pixels.length; offset += 4) {
        expect(card.pixels[offset], 255);
      }
      await _save(card, 'preview-short');
    });
  });
  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'preview ${language.code} ${brightness.name} long metadata actual font',
          (tester) async {
        uiLanguage.value = language;
        await tester.runAsync(() async {
          final card = await renderTaskbarSongPreview(
              TaskbarPreviewTrack(
                  identity: 'generated-${language.code}',
                  title: switch (language) {
                    UiLanguage.zh => '海岸回声与夏日的漫长旅途',
                    UiLanguage.en => 'Coastal Echoes on a Summer Journey',
                    UiLanguage.ja => '海辺の響きと夏の長い旅路',
                    UiLanguage.ko => '해안의 메아리와 여름의 긴 여행'
                  },
                  artist: 'Dan Player Studio · Ág 🧭',
                  album: 'Blue Hour / 夜色专辑 ·かな 한국어',
                  durationSeconds: 237,
                  playing: brightness == Brightness.light,
                  statusLabel:
                      ui(brightness == Brightness.light ? '正在播放' : '已暂停')),
              ColorScheme.fromSeed(
                  seedColor: brightness == Brightness.light
                      ? Colors.teal
                      : Colors.purple,
                  brightness: brightness),
              danEmbeddedFontFamily);
          expect(card.pixels.length, 480 * 240 * 4);
          await _save(card, 'preview-${language.code}-${brightness.name}');
        });
      });
    }
  }
}
