import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/detail_position_follow.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'waveform_transition_snapshot2_test.dart' show TransitionFixture, visual;

double progress(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  test(
      'retargeted finite motion retains its clock and never invents a position',
      () {
    final follow = DetailPositionFollow(
        from: 20, target: 20.033, duration: const Duration(milliseconds: 60));
    final atSample = follow.x(.032);
    follow.retarget(
        from: atSample,
        target: 20.066,
        elapsed: const Duration(milliseconds: 32));
    expect(follow.x(.032), atSample);
    expect(follow.x(.04), greaterThan(atSample));
    expect(follow.x(.04), lessThan(20.066));
    expect(follow.isDone(.091), isFalse);
    expect(follow.isDone(.093), isTrue);
    expect(follow.x(100), 20.066);
    expect(follow.dx(100), 0);
  });

  test('bar contours are cached across position clips and rebuilt for geometry',
      () {
    final source = WaveformTrackSource(const [0, 1], WaveformBarDensity.sparse);
    Path path({double width = 300, double growth = 1, bool rtl = false}) =>
        source.barPath(
            width: width,
            trackHeight: 4,
            parentHeight: 48,
            growth: growth,
            rtl: rtl);
    final initial = path();
    expect(identical(path(), initial), isTrue);
    expect(initial.contains(const Offset(3.125, 8)), isFalse);
    expect(initial.contains(const Offset(296.875, 8)), isTrue);
    final reversed = path(rtl: true);
    expect(identical(initial, reversed), isFalse);
    expect(reversed.contains(const Offset(3.125, 8)), isTrue);
    expect(reversed.contains(const Offset(296.875, 8)), isFalse);
    expect(identical(reversed, path(rtl: true)), isTrue);
    final half = path(growth: .5);
    expect(half.getBounds().height, 14);
    expect(path(width: 150).getBounds().width, lessThan(150));
  });

  testWidgets(
      'continuous native updates survive drag cancellation, density changes, rapid tracks and reduced visibility',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    final peaks = List<double>.generate(512, (index) => index / 511);
    await tester.pumpWidget(fixture.host(peaks: peaks));
    await tester.pumpAndSettle();
    final timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      fixture.position += .033;
      fixture.positions.add(fixture.position);
    });
    addTearDown(timer.cancel);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final beforeDrag = progress(tester);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    final preview = progress(tester);
    expect(preview, greaterThan(beforeDrag));
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester), preview);
    await tester.pumpWidget(
        fixture.host(peaks: peaks, density: WaveformBarDensity.dense));
    expect(progress(tester), preview);
    await gesture.cancel();
    await tester.pump();
    expect(fixture.seeks, isEmpty);
    expect(progress(tester), fixture.position);

    fixture.identity = 'B';
    fixture.position = 10;
    await tester.pumpWidget(fixture.host());
    expect(progress(tester), 10);
    expect(visual(tester).layers, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    fixture.identity = 'C';
    fixture.position = 5;
    const silent = [0.0, 0.0];
    await tester.pumpWidget(
        fixture.host(peaks: silent, density: WaveformBarDensity.sparse));
    expect(visual(tester).layers, isEmpty);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(visual(tester).layers.single.source.peaks, everyElement(0));
    expect(progress(tester), greaterThan(5));
    expect(progress(tester), lessThanOrEqualTo(fixture.position));

    await tester.pumpWidget(fixture.host(peaks: silent, enabled: false));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    final disabledPosition = progress(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(progress(tester), greaterThan(disabledPosition));
    fixture.hidden.value = true;
    await tester.pump();
    expect(fixture.positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
    fixture.hidden.value = false;
    await tester.pump();
    expect(progress(tester), fixture.position);
    await tester
        .pumpWidget(fixture.host(peaks: silent, reduced: true, enabled: false));
    await tester.pump(const Duration(milliseconds: 33));
    expect(progress(tester), fixture.position);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(
        fixture.host(peaks: silent, feedback: false, enabled: false));
    await tester.pump(const Duration(milliseconds: 33));
    expect(progress(tester), fixture.position);
    expect(tester.binding.transientCallbackCount, 0);
    timer.cancel();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(fixture.seeks, isEmpty);
  });

  testWidgets(
      'continuous playback and density transition render at both widths',
      (tester) async {
    const output = String.fromEnvironment('DAN_CONTINUOUS_MOTION_RENDER');
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final peaks = List<double>.generate(
        512, (index) => (.25 + .75 * math.sin(index / 41).abs()).clamp(0, 1));
    for (final width in [800.0, 300.0]) {
      final boundary = GlobalKey();
      tester.view.physicalSize = Size(width, 240);
      fixture.identity = '$width';
      fixture.position = 38;
      await tester.pumpWidget(fixture.host(
          peaks: peaks,
          width: width,
          boundary: boundary,
          density: WaveformBarDensity.sparse));
      await tester.pumpAndSettle();
      final timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        fixture.position += .033;
        fixture.positions.add(fixture.position);
      });
      addTearDown(timer.cancel);
      var previous = progress(tester);
      for (final stage in ['moving', 'density-mid', 'density-final']) {
        if (stage == 'density-mid') {
          await tester.pumpWidget(fixture.host(
              peaks: peaks,
              width: width,
              boundary: boundary,
              density: WaveformBarDensity.dense));
        }
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(microseconds: 16667));
        }
        expect(progress(tester), greaterThan(previous));
        previous = progress(tester);
        expect(tester.takeException(), isNull);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final data =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              final file = File('$output/$stage-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
      timer.cancel();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  for (final preference in [
    const FrameRatePreference(mode: FrameRateMode.fixed, fps: 30),
    const FrameRatePreference(mode: FrameRateMode.fixed, fps: 60),
    const FrameRatePreference(),
    const FrameRatePreference(mode: FrameRateMode.adaptive),
  ]) {
    final fps = preference.target(120, interacting: false);
    testWidgets('33ms native samples move continuously at $fps preferred fps',
        (tester) async {
      final fixture = TransitionFixture();
      addTearDown(fixture.dispose);
      final peaks = List<double>.generate(512, (index) => index / 511);
      await tester.pumpWidget(fixture.host(peaks: peaks));
      await tester.pumpAndSettle();
      final timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        fixture.position += .033;
        fixture.positions.add(fixture.position);
      });
      addTearDown(timer.cancel);
      final positions = <double>[];
      final heights = <double>[];
      final frame = Duration(microseconds: (1000000 / fps).round());
      for (var index = 0; index < (fps * 1.5).ceil(); index++) {
        await tester.pump(frame);
        if (index < fps * .4) continue;
        positions.add(tester.widget<Slider>(find.byType(Slider)).value);
        final shape = tester
            .widget<SliderTheme>(find.byType(SliderTheme).last)
            .data
            .trackShape! as DetailWaveformTrackShape;
        heights.add(shape.handleHeight(0)!);
      }
      timer.cancel();
      final steps = [
        for (var index = 1; index < positions.length; index++)
          positions[index] - positions[index - 1]
      ];
      final stalled = steps.where((value) => value < .000001).length;
      final average = steps.reduce((a, b) => a + b) / steps.length;
      final deviation = math.sqrt(steps.fold<double>(
              0, (sum, value) => sum + math.pow(value - average, 2)) /
          steps.length);
      const output = String.fromEnvironment('DAN_CONTINUOUS_MOTION_REPORT');
      if (output.isNotEmpty) {
        await tester.runAsync(() =>
            File('$output/${fps.toInt()}fps.json').writeAsString(jsonEncode({
              'fps': fps,
              'nativeSampleMilliseconds': 33,
              'positions': positions,
              'heights': heights,
              'stalledFrames': stalled,
              'stepMean': average,
              'stepCoefficientOfVariation':
                  average == 0 ? null : deviation / average,
            })));
      }
      expect(stalled, lessThanOrEqualTo(1),
          reason:
              'ordinary playback must not restart its ticker on each native sample');
      expect(average, greaterThan(.7 / fps));
      expect(deviation / average, lessThan(.25));
      expect(heights.last, greaterThan(heights.first));
      expect(positions.last, lessThanOrEqualTo(fixture.position));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Slider>(find.byType(Slider)).value, fixture.position);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
