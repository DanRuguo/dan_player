import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets(
        'interlude keeps round lower edges through row sampling at $dpr',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = LyricViewController()
        ..lyricTextAlign = LyricTextAlign.center;
      final position = ValueNotifier(const Duration(milliseconds: 3125));
      addTearDown(settings.dispose);
      addTearDown(position.dispose);
      final imageKey = GlobalKey();
      final line = LrcLine(Duration.zero, '',
          isBlank: true, length: const Duration(seconds: 12));
      var offset = 0.0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider.value(
              value: settings,
              child: Center(
                  child: RepaintBoundary(
                      key: imageKey,
                      child: SizedBox(
                          width: 240,
                          height: 100,
                          child: Material(
                              type: MaterialType.transparency,
                              child:
                                  StatefulBuilder(builder: (context, setState) {
                                update = setState;
                                return Center(
                                    child: Transform.translate(
                                        offset: Offset(0, offset),
                                        child: LyricFractionalFilterScope(
                                            sigma: .1,
                                            dpr: dpr,
                                            enabled: true,
                                            repaintToken: offset,
                                            child: LyricViewTile(
                                                line: line,
                                                position: position,
                                                opacity: 1,
                                                distance: 0,
                                                reducedMotion: false))));
                              }))))))));
      await tester.pumpAndSettle();
      for (final milliseconds in [1410, 3125, 5750, 11750, 11850]) {
        position.value = Duration(milliseconds: milliseconds);
        final radius = 4.2 *
            LyricMotion.interludePose(position.value, line.length).scale *
            dpr;
        for (final fraction in [0.0, .2, .5, .8]) {
          update(() => offset = fraction);
          await tester.pump();
          final dots =
              tester.renderObject<RenderBox>(find.byType(LyricTransitionTile));
          final boundary = imageKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final center = MatrixUtils.transformPoint(
                  dots.getTransformTo(boundary),
                  dots.size.center(Offset.zero)) *
              dpr;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: dpr);
            try {
              final output = Platform
                  .environment['DAN_LYRIC_INTERLUDE_COMPOSITING_RENDER'];
              if (output != null &&
                  fraction == .5 &&
                  (milliseconds == 3125 || milliseconds == 11850)) {
                await Directory(output).create(recursive: true);
                await File('$output/interlude-$dpr-$milliseconds.png')
                    .writeAsBytes((await image.toByteData(
                            format: ui.ImageByteFormat.png))!
                        .buffer
                        .asUint8List());
              }
              final bytes =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                      .buffer
                      .asUint8List();
              var mass = 0.0;
              var moment = 0.0;
              var lowest = 0;
              var highest = image.height;
              for (var y = 0; y < image.height; y++) {
                for (var x = 0; x < image.width; x++) {
                  final alpha = bytes[(y * image.width + x) * 4 + 3];
                  mass += alpha;
                  moment += alpha * (y + .5);
                  if (alpha > 20) {
                    if (y > lowest) lowest = y;
                    if (y < highest) highest = y;
                  }
                }
              }
              expect(mass, greaterThan(100));
              expect(moment / mass, closeTo(center.dy, .18),
                  reason:
                      'A clipped lower semicircle shifts the ink centroid ($milliseconds/$fraction)');
              expect(lowest + 1 - center.dy, greaterThan(radius - 1.5));
              expect(center.dy - highest, greaterThan(radius - 1.5));
            } finally {
              image.dispose();
            }
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
