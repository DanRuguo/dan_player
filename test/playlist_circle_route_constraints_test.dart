import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

void main() {
  late Directory directory;
  late String artworkPath;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playlist-circle-route-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    final recorder = drawing.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 128);
    picture.dispose();
    try {
      final bytes =
          (await image.toByteData(format: drawing.ImageByteFormat.png))!;
      artworkPath = '${directory.path}/circle.png';
      await File(artworkPath).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  for (final narrow in [false, true]) {
    testWidgets(
        'real circular browser keeps square covers and circular pixels narrow=$narrow',
        (tester) async {
      sizePlaylistFeature(tester, width: narrow ? 360 : 1080, height: 1000);
      final tree = PlaylistTree([]);
      final artwork = tree.createPlaylist('喜欢的音乐');
      tree.setImagePath(artwork, artworkPath);
      final placeholder = tree.createPlaylist('未设置封面的歌单');
      tree.createPlaylist('旅行与现场录音');
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applyAppControlTheme(ThemeData(
              useMaterial3: true,
              platform: TargetPlatform.windows,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
          builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(narrow ? 2 : 1),
                      disableAnimations: narrow),
                  child: child!)),
          home: Scaffold(
              body: PlaylistBrowser(
                  tree: tree,
                  initialView: PlaylistViewMode.circular,
                  library: const [],
                  persist: () async {},
                  trackBuilder: (_, __, ___, ____) =>
                      const SizedBox.shrink()))));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await capturePlaylistFeature(
          tester, boundary, 'circle-route-${narrow ? 'narrow-large' : 'wide'}');

      for (final playlist in [artwork, placeholder]) {
        final cover =
            find.byKey(ValueKey('playlist-circle-cover-${playlist.id}'));
        final rect = tester.getRect(cover);
        expect(rect.width, closeTo(rect.height, .001),
            reason:
                'A route wrapper must retain the circle tile natural square');
        expect(rect.size, const Size(112, 112));
        expect(
            tester.getSize(find.descendant(
                of: cover, matching: find.byType(PlaylistCoverRouteFlight))),
            const Size(112, 112));
      }

      final rect = tester
          .getRect(find.byKey(ValueKey('playlist-circle-cover-${artwork.id}')));
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        try {
          final bytes = (await image.toByteData())!;
          int pixel(Offset point) {
            final index =
                (point.dy.floor() * image.width + point.dx.floor()) * 4;
            return Color.fromARGB(
                    bytes.getUint8(index + 3),
                    bytes.getUint8(index),
                    bytes.getUint8(index + 1),
                    bytes.getUint8(index + 2))
                .toARGB32();
          }

          final red = Colors.red.toARGB32();
          expect(pixel(rect.center), red);
          for (final point in [
            rect.topLeft + const Offset(2, 2),
            rect.topRight + const Offset(-3, 2),
            rect.bottomLeft + const Offset(2, -3),
            rect.bottomRight + const Offset(-3, -3),
          ]) {
            expect(pixel(point), isNot(red),
                reason: 'Circle clipping removes all four artwork corners');
          }
          for (final point in [
            Offset(rect.left + 2, rect.center.dy),
            Offset(rect.right - 3, rect.center.dy),
            Offset(rect.center.dx, rect.top + 2),
            Offset(rect.center.dx, rect.bottom - 3),
          ]) {
            expect(pixel(point), red,
                reason: 'Each axis retains its full artwork diameter');
          }
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
