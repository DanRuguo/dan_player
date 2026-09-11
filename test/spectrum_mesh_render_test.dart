import 'dart:io';
import 'dart:ui' as graphics;
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'spectrum_painter_reference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('batched spectrum retains geometry, gradient and edge fade', () async {
    const output = String.fromEnvironment('DAN_SPECTRUM_RENDER');
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final height in [24.0, 32.0, 72.0]) {
        final size = Size(720, height);
        final levels = ValueNotifier<List<double>>([0, .1, .3, .8, 1, .2, .65]);
        final images = <graphics.Image>[];
        for (final painter in <CustomPainter>[
          OriginalSpectrumPainter(
              levels: levels, startColor: Colors.blue, endColor: Colors.pink),
          FrequencySpectrumPainter(
              levels: levels,
              startColor: Colors.blue,
              endColor: Colors.pink,
              pixelRatio: scale),
        ]) {
          final recorder = graphics.PictureRecorder();
          final canvas = Canvas(recorder)..scale(scale);
          painter.paint(canvas, size);
          final picture = recorder.endRecording();
          images.add(await picture.toImage(
              (size.width * scale).round(), (size.height * scale).round()));
          picture.dispose();
        }
        final old = (await images[0].toByteData())!.buffer.asUint8List();
        final current = (await images[1].toByteData())!.buffer.asUint8List();
        var total = 0;
        var ink = 0;
        for (var i = 0; i < old.length; i += 4) {
          for (var c = 0; c < 4; c++) {
            total += (old[i + c] - current[i + c]).abs();
          }
          if (old[i + 3] > 0 || current[i + 3] > 0) ink++;
        }
        // Coverage AA differs slightly at the outline; filled pixels and shape stay close.
        expect(total / (ink * 4), lessThan(12),
            reason: '$scale/$height mean channel error');
        if (output.isNotEmpty) {
          await Directory(output).create(recursive: true);
          for (var i = 0; i < 2; i++) {
            await File('$output/spectrum-$scale-$height-$i.png').writeAsBytes(
                (await images[i]
                        .toByteData(format: graphics.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
          }
        }
        for (final image in images) {
          image.dispose();
        }
        levels.dispose();
      }
    }
  });
}
