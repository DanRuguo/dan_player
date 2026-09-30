import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

class _FixtureLyric extends Lyric {
  _FixtureLyric(super.lines);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('sweep native lyric focus endpoints across narrow width bands',
      (tester) async {
    const fixture = String.fromEnvironment('DAN_LYRIC_WIDTH_FIXTURE');
    final lines = fixture.isEmpty
        ? [
            for (var i = 0; i < 43; i++)
              LrcLine(
                Duration(seconds: i * 4),
                i == 5 ? 'Maybe we should let this go' : 'Line $i',
                length: const Duration(seconds: 4),
                isBlank: false,
              ),
          ]
        : ((jsonDecode(await File(fixture).readAsString()) as Map)['lines']
                as List)
            .cast<Map>()
            .map((entry) => LrcLine(
                  Duration(microseconds: entry['start'] as int),
                  entry['text'] as String,
                  length: Duration(microseconds: entry['length'] as int),
                  isBlank: false,
                ))
            .toList();
    final lyric = _FixtureLyric(lines);
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final settings = LyricViewController();
    final boundary = GlobalKey();
    final positions = StreamController<double>.broadcast();
    var position = (lines[4].start.inMicroseconds + 100000) / 1e6;
    final targetTime = (lines[5].start.inMicroseconds + 100000) / 1e6;

    Widget host(double outerWidth) => RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.red).copyWith(
                surface: Colors.white,
                primary: Colors.red,
                onSecondaryContainer: Colors.black,
              ),
            ),
            home: Scaffold(
              backgroundColor: Colors.white,
              body: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  children: [
                    // The wide player divides its body into equal artwork and
                    // lyric panes. Subtract an integral screen translation so
                    // the same half-pixel phase fits the test window.
                    SizedBox(width: 100 + (outerWidth - 928) / 2),
                    SizedBox(
                      width: (outerWidth - 64) / 2,
                      height: 560,
                      child: ChangeNotifierProvider.value(
                        value: settings,
                        child: VerticalLyricScrollView(
                          lyric: lyric,
                          playing: false,
                          positionStream: positions.stream,
                          readPosition: () => position,
                          onSeek: (_) {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    Future<(List<double>, List<double>)> profile(Rect bounds) async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        final left = math.max(0, bounds.left.floor() - 8);
        final right = math.min(image.width, bounds.right.ceil() + 8);
        final top = math.max(0, bounds.top.floor() - 8);
        final bottom = math.min(image.height, bounds.bottom.ceil() + 8);
        final horizontal = List<double>.filled(right - left, 0);
        final vertical = List<double>.filled(bottom - top, 0);
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final value = 255.0 - bytes[(y * image.width + x) * 4];
            horizontal[x - left] += value;
            vertical[y - top] += value;
          }
        }
        return (horizontal, vertical);
      } finally {
        image.dispose();
      }
    }

    double shift(List<double> first, List<double> last) {
      final a = [0.0, 0, 0, ...first, 0, 0, 0];
      final b = [0.0, 0, 0, ...last, 0, 0, 0];
      final scores = <double>[];
      for (var offset = -2; offset <= 2; offset++) {
        var score = 0.0;
        for (var i = 3; i < a.length - 3; i++) {
          score += a[i] * b[i + offset];
        }
        scores.add(score);
      }
      final peak = scores.indexOf(scores.reduce(math.max));
      if (peak == 0 || peak == 4) return (peak - 2).toDouble();
      final left = scores[peak - 1];
      final center = scores[peak];
      final right = scores[peak + 1];
      final denominator = left - 2 * center + right;
      return peak -
          2 +
          (denominator == 0 ? 0 : .5 * (left - right) / denominator);
    }

    for (final alignment in LyricTextAlign.values) {
      settings.lyricTextAlign = alignment;
      await tester.pumpWidget(host(928));
      await tester.pumpAndSettle();
      for (var width = 928; width <= 935; width++) {
        position = (lines[4].start.inMicroseconds + 100000) / 1e6;
        positions.add(position);
        await tester.pumpWidget(host(width.toDouble()));
        await tester.pumpAndSettle();
        position = targetTime;
        positions.add(position);
        await tester.pump();
        // Isolate the glyph/focus endpoint from a still-running scroll activity.
        final scroll = tester
            .widget<CustomScrollView>(
                find.byKey(const ValueKey('vertical-lyric-scroll')))
            .controller!;
        scroll.jumpTo(scroll.offset);
        await tester.pump();
        final row = find.byWidgetPredicate((widget) =>
            widget is LyricViewTile && identical(widget.line, lines[5]));
        final paint = find.descendant(
            of: row,
            matching: find.byWidgetPredicate((widget) =>
                widget is CustomPaint &&
                widget.painter is PlainLyricWordFollowPainter));
        expect(paint, findsOneWidget);
        final bounds = tester.getRect(paint);
        final clocks = tester
            .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
            .map((effect) => effect.clock)
            .whereType<AnimationController>()
            .toSet();
        final motions = tester
            .stateList<AnimatedWidgetBaseState<LyricLineMotion>>(
                find.byType(LyricLineMotion))
            .toList();
        const motionCapture = String.fromEnvironment('DAN_LYRIC_MOTION_CAPTURE');
        if (motionCapture.isNotEmpty &&
            alignment == LyricTextAlign.left &&
            width == 929) {
          final directory = Directory(motionCapture);
          await directory.create(recursive: true);
          await File('${directory.path}/bounds.txt').writeAsString(
              '${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}');
          for (var frame = 0; frame <= 10; frame++) {
            final progress = frame / 10;
            for (final clock in clocks) {
              clock.stop();
              clock.value = progress;
            }
            for (final motion in motions) {
              // ignore: invalid_use_of_protected_member
              motion.controller.stop();
              // ignore: invalid_use_of_protected_member
              motion.controller.value = progress;
            }
            await tester.pump();
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final png = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('${directory.path}/frame-$frame.png')
                  .writeAsBytes(png!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          }
        }
        for (final clock in clocks) {
          clock.stop();
          clock.value = .999;
        }
        for (final motion in motions) {
          // ignore: invalid_use_of_protected_member
          motion.controller.stop();
          // ignore: invalid_use_of_protected_member
          motion.controller.value = .999;
        }
        await tester.pump();
        final before = await profile(bounds);
        for (final clock in clocks) {
          clock.value = 1;
        }
        for (final motion in motions) {
          // ignore: invalid_use_of_protected_member
          motion.controller.value = 1;
        }
        await tester.pump();
        final after = await profile(bounds);
        final dx = shift(before.$1, after.$1).abs();
        final dy = shift(before.$2, after.$2).abs();
        expect(dx, lessThan(.05),
            reason: '$alignment horizontal focus endpoint at width $width');
        expect(dy, lessThan(.05),
            reason: '$alignment vertical focus endpoint at width $width');
      }
    }
    await tester.pumpWidget(const SizedBox());
    await positions.close();
    settings.dispose();
  });
}
