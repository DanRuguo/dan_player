import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// This must run on Windows Impeller, not flutter_tester's software rasterizer.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native text stays horizontally stable during blur and entry',
      (tester) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final boundary = GlobalKey();
    final results = <String, Object>{};
    for (final scenario in [
      for (final captureScale in [1.0, 1.25, 1.5])
        for (final mode in ['blur', 'entry'])
          (mode: mode, captureScale: captureScale),
    ]) {
      final mode = scenario.mode;
      final label = '$mode-${scenario.captureScale}';
      final centers = <double>[];
      final masses = <double>[];
      final profiles = <List<double>>[];
      // Repeat the naturally completed frame to expose a late cache handoff.
      for (var frame = 0; frame <= 43; frame++) {
        final t = (frame / 40).clamp(0.0, 1.0);
        const style = TextStyle(
            fontFamily: danEmbeddedFontFamily,
            fontSize: 33,
            color: Colors.black);
        Widget content = mode == 'blur'
            ? LyricLineMotion(
                opacity: 1,
                scale: .6613333333,
                activation: 1,
                alignment: Alignment.topLeft,
                presentation: const (
                  fontSize: 22,
                  translationFontSize: 18,
                  alignment: Alignment.topLeft,
                ),
                reducedMotion: false,
                builder: (context, _, __, ___) => LyricFollowEffects(
                  clock: const AlwaysStoppedAnimation<double>(1),
                  transition: null,
                  // The production follow scope retains fractional sampling
                  // while the neighbouring line settles from blur to clear.
                  blur: 4 * (1 - t),
                  child: const RepaintBoundary(
                    child: ScopedLyricFractionalFilter(
                      child: BalancedLyricText('词：谢贤菁',
                          style: style, textAlign: TextAlign.left),
                    ),
                  ),
                ),
              )
            : Transform.translate(
                offset: Offset(0, 6 * (1 - t)),
                child: Opacity(
                    opacity: .15 + .85 * t,
                    child: const Text('晨光 Morning', style: style)));
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                scrollBehavior: const DanPlayerScrollBehavior(),
                home: Scaffold(
                    backgroundColor: Colors.white,
                    body: Align(
                        alignment: Alignment.topLeft,
                        child: Transform.translate(
                            offset: const Offset(.35, .2),
                            child: SizedBox(
                                width: 650,
                                height: 350,
                                child: SingleChildScrollView(
                                    primary: false,
                                    child: Padding(
                                        padding: const EdgeInsets.only(
                                            left: 60.3, top: 90.2),
                                        child: Align(
                                            alignment: Alignment.topLeft,
                                            child: content))))))))));
        await tester.pumpAndSettle();
        if (frame == 0) {
          expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
          await windowManager.ensureInitialized();
          await windowManager.hide();
        }
        final center = await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(
                  pixelRatio:
                      tester.view.devicePixelRatio * scenario.captureScale);
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          final ratio = tester.view.devicePixelRatio * scenario.captureScale;
          var mass = 0.0, moment = 0.0;
          final profile = List<double>.filled(image.width, 0);
          for (var y = (50 * ratio).floor(); y < (240 * ratio).floor(); y++) {
            for (var x = (30 * ratio).floor(); x < (450 * ratio).floor(); x++) {
              final ink = 255 - data[(y * image.width + x) * 4];
              mass += ink;
              moment += ink * x;
              profile[x] += ink;
            }
          }
          const output = String.fromEnvironment('DAN_TEXT_MOTION_RENDER');
          if (output.isNotEmpty && frame % 10 == 0) {
            final file = File('$output/$label-$frame.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
                (await image.toByteData(format: ui.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
          }
          image.dispose();
          expect(mass, greaterThan(100));
          return (moment / mass, mass, profile);
        });
        centers.add(center!.$1);
        masses.add(center.$2);
        profiles.add(center.$3);
      }
      final drift = centers.reduce(math.max) - centers.reduce(math.min);
      final reference = profiles[40];
      final shifts = [
        for (final profile in profiles) _registeredShift(reference, profile)
      ];
      final worstShift = shifts.map((v) => v.abs()).reduce(math.max);
      // Verify that registration exposes an injected one-pixel displacement.
      for (final delta in [-1, 1]) {
        final shifted = List<double>.generate(
            reference.length,
            (x) => x - delta >= 0 && x - delta < reference.length
                ? reference[x - delta]
                : 0);
        expect(_registeredShift(reference, shifted), closeTo(delta, .005));
        final mid = profiles[20];
        final shiftedMid = List<double>.generate(
            mid.length,
            (x) =>
                x - delta >= 0 && x - delta < mid.length ? mid[x - delta] : 0);
        expect(
            _registeredShift(reference, shiftedMid) -
                _registeredShift(reference, mid),
            closeTo(delta, .05),
            reason: '$label must detect a one-pixel jump during blur');
      }
      results[label] = {
        'centroidDrift': drift,
        'registeredShift': worstShift,
        'shifts': shifts,
        'centers': centers,
        'masses': masses
      };
      expect(_registeredShift(profiles[40], profiles.last), closeTo(0, .005),
          reason: '$label completed frames must keep the same raster origin');
      expect(masses.last, closeTo(masses[40], masses[40] * .005),
          reason: '$label completed frames must retain the same ink');
      if (mode == 'entry') {
        expect(masses.first / masses[40], closeTo(.15, .02),
            reason: 'Entry opacity must remain effective');
      }
      debugPrint(
          'Native $label registeredShift=$worstShift centroidDrift=$drift');
      if (mode == 'blur') {
        final largestFrameStep = [
          for (var frame = 1; frame < shifts.length; frame++)
            (shifts[frame] - shifts[frame - 1]).abs()
        ].reduce(math.max);
        expect(largestFrameStep, lessThan(.5),
            reason: '$label changed a full pixel between blur frames');
      }
    }
    const output = String.fromEnvironment('DAN_TEXT_MOTION_RENDER');
    if (output.isNotEmpty) {
      await File('$output/metrics.json').writeAsString(jsonEncode(results));
    }
    for (final result in results.entries) {
      final changingBlur = result.key.startsWith('blur-');
      // Changing Gaussian strength changes native glyph sampling slightly;
      // the one-pixel calibration above still rejects visible origin jumps.
      // These scales change screenshot sampling, not the Windows view DPI.
      expect((result.value as Map)['registeredShift'],
          lessThan(changingBlur ? .35 : .05),
          reason: result.key);
    }
  });
}

// Blurring/8-bit alpha quantization changes the brightness centroid even when
// ink has not moved. Register the horizontal ink profiles instead: a symmetric
// blur broadens their cross-correlation without moving its peak.
double _registeredShift(List<double> reference, List<double> current) {
  double correlation(int shift) {
    var value = 0.0;
    for (var x = 3; x < reference.length - 3; x++) {
      value += reference[x] * current[x + shift];
    }
    return value;
  }

  var peak = 0;
  for (var shift = -2; shift <= 2; shift++) {
    if (correlation(shift) > correlation(peak)) peak = shift;
  }
  final left = correlation(peak - 1),
      center = correlation(peak),
      right = correlation(peak + 1);
  return peak + .5 * (left - right) / (left - 2 * center + right);
}
