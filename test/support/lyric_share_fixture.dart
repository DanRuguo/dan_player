import 'dart:io';
import 'dart:ui' as raster;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playlist_feature_fixture.dart';

Future<void> loadLyricShareFonts() async {
  await loadPlaylistFeatureFonts();
  final windows = Platform.environment['WINDIR'];
  if (windows != null) {
    final emoji = File('$windows/Fonts/seguiemj.ttf');
    if (await emoji.exists()) {
      await (FontLoader('Segoe UI Emoji')
            ..addFont(
                Future.value(ByteData.sublistView(await emoji.readAsBytes()))))
          .load();
    }
  }
}

Future<Uint8List> captureLyricShare(WidgetTester tester, GlobalKey boundary,
    {double ratio = 1, String? name}) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: raster.ImageByteFormat.png);
      final bytes = Uint8List.fromList(data!.buffer.asUint8List());
      await saveLyricShareRender(bytes, name);
      return bytes;
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> saveLyricShareRender(Uint8List bytes, String? name) async {
  final directory = Platform.environment['DAN_LYRIC_SHARE_RENDER_DIR'];
  if (directory == null || name == null) return;
  await Directory(directory).create(recursive: true);
  await File('$directory/$name.png').writeAsBytes(bytes);
}

Future<({int width, int height, int ink})> decodeLyricSharePng(
    WidgetTester tester, Uint8List bytes) async {
  return (await tester.runAsync(() async {
    final codec = await raster.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final raw = await image.toByteData();
        final pixels = raw!.buffer.asUint8List();
        var ink = 0;
        for (var i = 0; i < pixels.length; i += 4) {
          if (pixels[i + 3] > 200 &&
              pixels[i] < 120 &&
              pixels[i + 1] < 120 &&
              pixels[i + 2] < 120) {
            ink++;
          }
        }
        return (width: image.width, height: image.height, ink: ink);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }))!;
}

const lyricShareSamples = {
  'zh': '月光穿过窗边，星星仍在闪耀 ✨\nKeep every character 😀',
  'en': 'Moonlight stays beside the window ✨\nEvery character remains 😀',
  'ja': '窓辺に月明かり、星はまだ輝く ✨\n文字をすべて残す 😀',
  'ko': '창가에 달빛이 머물고 별이 빛나요 ✨\n모든 글자를 남겨요 😀',
};
