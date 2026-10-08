import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// Run explicitly on Windows, not in flutter_tester's software renderer:
// flutter build windows --profile --target integration_test/edge_stretch_shader_test.dart
// flutter drive --profile -d windows --driver integration_test/edge_stretch_driver.dart
//   --target integration_test/edge_stretch_shader_test.dart
//   --use-application-binary (Resolve-Path 'build/windows/x64/runner/Profile/Dan Player.exe').Path
// The explicit binary is required by the host's CMake OUTPUT_NAME.
// Use an isolated DAN_PLAYER_DATA_DIR and workspace TEMP/TMP in the calling shell.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'native stretch preserves letters and punctuation across the spring',
      (tester) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue,
        reason: 'This regression requires the actual Impeller image sampler.');
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final key = GlobalKey();
    final textKey = GlobalKey();
    const series = [
      0.0,
      .0001,
      .001,
      .002,
      .003,
      .005,
      .01,
      .02,
      .03,
      .04,
      .03,
      .02,
      .01,
      .005,
      .003,
      .002,
      .001,
      .0001,
      0.0,
    ];
    var captures = 0;
    var hidden = false;
    for (final layout in [
      (340.0, 14.0, Axis.vertical),
      (560.0, 20.5, Axis.vertical),
      (340.0, 28.0, Axis.vertical),
      (560.0, 14.0, Axis.horizontal),
      (340.0, 28.0, Axis.horizontal),
    ]) {
      final (width, fontSize, axis) = layout;
      for (final text in axis == Axis.vertical
          ? ['format:flac,mp3', 'title:晴天 artist:zjl']
          // Leave a blank raster column/row between groups after rotation.
          : ['f , l a c', '晴 天 z j l']) {
        for (final direction in [1, -1]) {
          final profiles = <List<double>>[];
          List<(int, int)>? spans;
          Uint8List? idle;
          for (final strength in series) {
            await tester.pumpWidget(RepaintBoundary(
                key: key,
                child: MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: IgnorePointer(
                        child: Transform.translate(
                          offset: const Offset(.35, .2),
                          child: Dialog(
                            backgroundColor: Colors.white,
                            child: SizedBox(
                              width: width,
                              height: 400,
                              child: AppStretchEffect(
                                  axis: axis,
                                  stretchStrength: strength * direction,
                                  child: RotatedBox(
                                      // Rotate the text line for the horizontal
                                      // case so each glyph's ink can be integrated
                                      // along the stretched axis independently.
                                      // Whole-line mass would change naturally as
                                      // different letters widen by different amounts.
                                      quarterTurns:
                                          axis == Axis.horizontal ? 1 : 0,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            left: 24.25, top: 210.3),
                                        child: Align(
                                          alignment: Alignment.topLeft,
                                          child: SelectableText(text,
                                              key: textKey,
                                              style: TextStyle(
                                                  fontFamily:
                                                      danEmbeddedFontFamily,
                                                  fontSize: fontSize,
                                                  height: 1.5,
                                                  color: Colors.black)),
                                        ),
                                      ))),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )));
            await tester.pumpAndSettle();
            if (!hidden) {
              await windowManager.ensureInitialized();
              await windowManager.hide();
              hidden = true;
            }
            final textBox =
                textKey.currentContext!.findRenderObject()! as RenderBox;
            final textRect = MatrixUtils.transformRect(
                textBox.getTransformTo(null), Offset.zero & textBox.size);
            final ratio = tester.view.devicePixelRatio;
            final frame = await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: ratio);
              try {
                final bytes = (await image.toByteData(
                        format: ui.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
                const output = String.fromEnvironment('DAN_EDGE_SHADER_RENDER');
                if (output.isNotEmpty) {
                  final png =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final file = File('$output/frame-${captures++}.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(png!.buffer.asUint8List());
                }
                // Capture above the dialog in window coordinates: a boundary
                // directly around the effect conceals its fractional origin.
                // Integrate along the stretched axis, measure the other axis.
                final ink = List<double>.filled(
                    axis == Axis.vertical ? image.width : image.height, 0);
                for (var y =
                        ((textRect.top - (axis == Axis.vertical ? 40 : 0)) *
                                ratio)
                            .floor();
                    y <
                        ((textRect.bottom + (axis == Axis.vertical ? 40 : 0)) *
                                ratio)
                            .ceil();
                    y++) {
                  for (var x = ((textRect.left -
                                  (axis == Axis.horizontal ? 40 : 0)) *
                              ratio)
                          .floor();
                      x <
                          ((textRect.right +
                                      (axis == Axis.horizontal ? 40 : 0)) *
                                  ratio)
                              .ceil();
                      x++) {
                    ink[axis == Axis.vertical ? x : y] +=
                        255 - bytes[(y * image.width + x) * 4];
                  }
                }
                return (bytes, ink);
              } finally {
                image.dispose();
              }
            });
            final bytes = frame!.$1;
            final ink = frame.$2;
            if (spans == null) {
              idle = bytes;
              spans = [];
              int? start;
              for (var x = 0; x < ink.length; x++) {
                if (ink[x] > 10 && start == null) start = x;
                if (ink[x] <= 10 && start != null) {
                  spans.add((math.max(0, start - 1), x + 1));
                  start = null;
                }
              }
              expect(spans.length, greaterThan(3));
            } else if (strength == 0) {
              expect(bytes, orderedEquals(idle!),
                  reason:
                      'Returning to rest must preserve the original raster.');
            }
            profiles.add([
              for (final span in spans) _center(ink, span.$1, span.$2),
            ]);
          }
          var worst = 0.0;
          for (var group = 0; group < spans!.length; group++) {
            final centers = profiles.map((profile) => profile[group]);
            worst = math.max(
                worst, centers.reduce(math.max) - centers.reduce(math.min));
          }
          expect(worst, lessThan(.05),
              reason:
                  '$text width=$width size=$fontSize axis=$axis direction=$direction: cross-axis glyph jitter');
          debugPrint(
              'Native stretch $text width=$width size=$fontSize axis=$axis direction=$direction drift=$worst');
        }
      }
    }
  });
}

double _center(List<double> ink, int start, int end) {
  var mass = 0.0, moment = 0.0;
  for (var x = start; x < end; x++) {
    mass += ink[x];
    moment += x * ink[x];
  }
  return moment / mass;
}
