import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'waveform_transition_snapshot2_test.dart' show TransitionFixture;

SliderThemeData theme(WidgetTester tester) =>
    tester.widget<SliderTheme>(find.byType(SliderTheme).last).data;
Rect track(WidgetTester tester) => theme(tester).trackShape!.getPreferredRect(
    parentBox: tester.renderObject<RenderBox>(find.byType(Slider)),
    sliderTheme: theme(tester));
double valueForFraction(WidgetTester tester, double fraction) {
  return fraction * 100;
}

Future<double> paintedHeight(WidgetTester tester, GlobalKey boundary) async {
  final rect = track(tester);
  final sliderRect = tester.getRect(find.byType(Slider));
  final value = tester.widget<Slider>(find.byType(Slider)).value / 100;
  final direction = Directionality.of(tester.element(find.byType(Slider)));
  final x = (sliderRect.left +
          rect.left +
          (direction == TextDirection.ltr ? value : 1 - value) * rect.width)
      .floor();
  final background =
      Theme.of(tester.element(find.byType(Slider))).scaffoldBackgroundColor;
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes =
          (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final rows = <int>[];
      for (var y = sliderRect.top.ceil(); y < sliderRect.bottom.floor(); y++) {
        final offset = (y * image.width + x) * 4;
        if ((bytes[offset] - (background.r * 255).round()).abs() +
                (bytes[offset + 1] - (background.g * 255).round()).abs() +
                (bytes[offset + 2] - (background.b * 255).round()).abs() >
            25) {
          rows.add(y);
        }
      }
      return rows.isEmpty ? 0.0 : (rows.last - rows.first + 1).toDouble();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });
  final envelope = List<double>.generate(512, (index) => index < 256 ? 0 : 1);

  test(
      'height samples real displayed max buckets and interpolates adjacent columns',
      () {
    final coarse = WaveformTrackSource(
        List<double>.filled(512, 0)..[255] = 1, WaveformBarDensity.sparse);
    final fine = WaveformTrackSource(coarse.peaks, WaveformBarDensity.dense);
    expect(coarse.amplitudeAt(.48, 48), greaterThan(.5));
    expect(fine.amplitudeAt(.48, 192), 0);
    final source = WaveformTrackSource(const [0, 1], WaveformBarDensity.sparse);
    final wave = WaveformTrackVisual.wave(source);
    double height(double position) => waveformHandleHeight(wave,
        position: position, trackWidth: 752, trackHeight: 4, parentHeight: 48);
    expect(height(23.5 / 48), 8);
    expect(height(24 / 48), 18);
    expect(height(24.5 / 48), 28);
    expect(
        waveformHandleHeight(const WaveformTrackVisual.line(),
            position: .5,
            trackWidth: 752,
            trackHeight: 4,
            parentHeight: 48,
            emphasis: 2),
        24);
    final mixed = WaveformTrackVisual.interpolate(
        wave, const WaveformTrackVisual.line(), .5);
    expect(
        waveformHandleHeight(mixed,
            position: .75, trackWidth: 752, trackHeight: 4, parentHeight: 48),
        18);
  });

  testWidgets(
      'actual painter keeps a visible 8px silence handle and 28px loud handle without changing 48px input',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(fixture.host(
          peaks: envelope,
          density: WaveformBarDensity.sparse,
          boundary: boundary,
          direction: direction,
          reduced: true));
      await tester.pumpAndSettle();
      for (final pair in [(.25, 8.0), (.5, 18.0), (.75, 28.0)]) {
        fixture.position = valueForFraction(tester, pair.$1);
        fixture.positions.add(fixture.position);
        await tester.pumpAndSettle();
        expect(await paintedHeight(tester, boundary), closeTo(pair.$2, 1));
        expect(tester.getSize(find.byType(Slider)).height, 48);
        expect(theme(tester).thumbShape!.getPreferredSize(true, false),
            const Size(48, 48));
      }
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'large jumps move x and seek value immediately while actual handle height follows for only 80ms',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(fixture.host(
        peaks: envelope,
        density: WaveformBarDensity.sparse,
        boundary: boundary));
    await tester.pumpAndSettle();
    fixture.position = valueForFraction(tester, .25);
    fixture.positions.add(fixture.position);
    await tester.pumpAndSettle();
    expect(await paintedHeight(tester, boundary), closeTo(8, 1));
    fixture.position = valueForFraction(tester, .75);
    fixture.positions.add(fixture.position);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, fixture.position);
    expect(await paintedHeight(tester, boundary), closeTo(8, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(await paintedHeight(tester, boundary), inExclusiveRange(8, 28));
    await tester.pumpAndSettle();
    expect(await paintedHeight(tester, boundary), closeTo(28, 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'smooth sampled position interpolates neighboring dense columns, and reduced motion jumps to its final height',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    final peaks = List<double>.filled(192, 0)..[81] = 1;
    await tester.pumpWidget(fixture.host(
        peaks: peaks, density: WaveformBarDensity.dense, boundary: boundary));
    await tester.pumpAndSettle();
    fixture.position = valueForFraction(tester, 80.5 / 192);
    fixture.positions.add(fixture.position);
    await tester.pumpAndSettle();
    final start = (theme(tester).trackShape! as DetailWaveformTrackShape)
        .handleHeight(0)!;
    fixture.position = valueForFraction(tester, 81.5 / 192);
    fixture.positions.add(fixture.position);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final middle = (theme(tester).trackShape! as DetailWaveformTrackShape)
        .handleHeight(0)!;
    expect(middle, inExclusiveRange(start, 28));
    await tester.pumpAndSettle();
    expect(
        (theme(tester).trackShape! as DetailWaveformTrackShape).handleHeight(0),
        closeTo(28, .01));
    await tester.pumpWidget(fixture.host(
        peaks: peaks,
        density: WaveformBarDensity.dense,
        boundary: boundary,
        reduced: true));
    fixture.position = valueForFraction(tester, 80.5 / 192);
    fixture.positions.add(fixture.position);
    await tester.pumpAndSettle();
    expect(
        (theme(tester).trackShape! as DetailWaveformTrackShape).handleHeight(0),
        closeTo(8, .01));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'capture cancellation, density morph and rapid replacement never reuse previous track height',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(fixture.host(
        peaks: envelope,
        density: WaveformBarDensity.sparse,
        boundary: boundary));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump(const Duration(milliseconds: 40));
    final captured = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.pumpWidget(fixture.host(
        peaks: envelope,
        density: WaveformBarDensity.dense,
        boundary: boundary));
    expect(tester.widget<Slider>(find.byType(Slider)).value, captured);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    fixture.identity = 'replacement';
    await tester.pumpWidget(fixture.host(boundary: boundary));
    expect(theme(tester).trackShape, isNot(isA<DetailWaveformTrackShape>()));
    expect(await paintedHeight(tester, boundary), closeTo(18, 1));
    await tester
        .pumpWidget(fixture.host(peaks: const [0, 0], boundary: boundary));
    await tester.pumpAndSettle();
    expect(await paintedHeight(tester, boundary), closeTo(8, 1));
    fixture.position = 80;
    fixture.positions.add(80);
    fixture.hidden.value = true;
    await tester.pumpAndSettle();
    expect(fixture.positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'first midpoint and final handle heights render with app styling at wide and enlarged narrow widths',
      (tester) async {
    const output = String.fromEnvironment('DAN_WAVEFORM_HANDLE_RENDER');
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [800.0, 300.0]) {
      final boundary = GlobalKey();
      tester.view.physicalSize = Size(width, 240);
      fixture.identity = '$width';
      await tester.pumpWidget(fixture.host(
          peaks: envelope,
          density: WaveformBarDensity.sparse,
          boundary: boundary,
          width: width));
      await tester.pumpAndSettle();
      fixture.position = valueForFraction(tester, .25);
      fixture.positions.add(fixture.position);
      await tester.pumpAndSettle();
      fixture.position = valueForFraction(tester, .75);
      fixture.positions.add(fixture.position);
      await tester.pump();
      await tester.pump();
      for (final stage in ['first', 'mid', 'final']) {
        if (stage == 'mid') await tester.pump(const Duration(milliseconds: 40));
        if (stage == 'final') await tester.pumpAndSettle();
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              final file = File('$output/$stage-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(Slider), findsOneWidget);
    }
  });
}
