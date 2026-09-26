import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final positions = StreamController<double>.broadcast(sync: true);
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });
  tearDownAll(positions.close);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('automatic bars retain physical width as track width changes', () {
    final narrow = waveformBarLayout(72, WaveformBarDensity.automatic);
    final normal = waveformBarLayout(252, WaveformBarDensity.automatic);
    final wide = waveformBarLayout(752, WaveformBarDensity.automatic);
    expect(narrow.count, 24);
    expect(normal.count, 84);
    expect(wide.count, 250);
    expect({narrow.width, normal.width, wide.width}, {2.25});
    expect(wide.step, greaterThanOrEqualTo(3));
    expect(waveformBarLayout(2000, WaveformBarDensity.automatic).count, 512);
    for (final width in [0.0, -2.0, double.infinity, double.nan]) {
      expect(waveformBarLayout(width, WaveformBarDensity.automatic).count, 0);
    }
    final minimum = waveformBarLayout(1, WaveformBarDensity.automatic);
    expect(minimum.count, 0,
        reason: 'use the stock line when no 3px slot fits');
    expect(minimum.width, 0);
  });

  test('three fixed counts adapt bar and gap widths without changing count',
      () {
    for (final pair in const [
      (WaveformBarDensity.sparse, 48),
      (WaveformBarDensity.medium, 96),
      (WaveformBarDensity.dense, 192)
    ]) {
      for (final width in [1.0, 72.0, 252.0, 752.0]) {
        final layout = waveformBarLayout(width, pair.$1);
        expect(layout.count, pair.$2);
        expect(layout.step * layout.count, closeTo(width, .000001));
        expect(layout.width / layout.step, closeTo(.65, .000001));
        expect(layout.width, lessThan(layout.step));
      }
    }
  });

  Widget host(GlobalKey key, WaveformBarDensity density,
          {List<double> peaks = const [1, 1],
          TextDirection direction = TextDirection.ltr,
          double position = 0}) =>
      MaterialApp(
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          home: Directionality(
              textDirection: direction,
              child: Scaffold(
                  body: Center(
                      child: RepaintBoundary(
                          key: key,
                          child: SizedBox(
                              width: 816,
                              child: DetailProgressSlider(
                                  positions: positions.stream,
                                  readPosition: () => position,
                                  duration: 100,
                                  trackIdentity: 'fixture',
                                  waveform: peaks,
                                  waveformDensity: density,
                                  onSeek: (_) {})))))));

  Future<ByteData> pixels(WidgetTester tester, GlobalKey key) async =>
      (await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        try {
          return (await image.toByteData(
              format: drawing.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }))!;

  testWidgets(
      'fixed density paints the requested real number of columns in both directions',
      (tester) async {
    tester.view.physicalSize = const Size(900, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final pair in const [
      (WaveformBarDensity.sparse, 48),
      (WaveformBarDensity.medium, 96),
      (WaveformBarDensity.dense, 192)
    ]) {
      for (final direction in TextDirection.values) {
        final key = GlobalKey();
        // Place the now amplitude-aware handle on a real column, so its tall
        // silhouette is not counted as a separate endpoint waveform column.
        await tester.pumpWidget(
            host(key, pair.$1, direction: direction, position: 50 / pair.$2));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byKey(key));
        final row =
            (tester.getRect(find.byType(Slider)).center.dy - bounds.top - 10)
                .round();
        final data = (await pixels(tester, key)).buffer.asUint8List();
        var count = 0;
        var inBar = false;
        for (var x = 0; x < bounds.width.round(); x++) {
          final painted = data[(row * bounds.width.round() + x) * 4 + 3] > 22;
          if (painted && !inBar) count++;
          inBar = painted;
        }
        expect(count, pair.$2, reason: '${pair.$1.name} ${direction.name}');
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'two source buckets retain silent and loud halves without synthetic fill',
      (tester) async {
    tester.view.physicalSize = const Size(900, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final density in WaveformBarDensity.values) {
      for (final direction in TextDirection.values) {
        final key = GlobalKey();
        await tester.pumpWidget(
            host(key, density, peaks: const [0, 1], direction: direction));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byKey(key));
        final row =
            (tester.getRect(find.byType(Slider)).center.dy - bounds.top - 10)
                .round();
        final data = (await pixels(tester, key)).buffer.asUint8List();
        var left = 0, right = 0;
        for (var x = 0; x < bounds.width.round(); x++) {
          if (data[(row * bounds.width.round() + x) * 4 + 3] > 22) {
            if (x < bounds.width / 2) {
              left++;
            } else {
              right++;
            }
          }
        }
        expect(direction == TextDirection.ltr ? left : right, 0);
        expect(direction == TextDirection.ltr ? right : left, greaterThan(50));
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    }
  });

  testWidgets(
      'density preserves fallback and seek coordinates at minimum width',
      (tester) async {
    for (final density in WaveformBarDensity.values) {
      for (final width in [72.0, 120.0]) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: width,
                    child: DetailProgressSlider(
                        positions: positions.stream,
                        readPosition: () => 50,
                        duration: 100,
                        trackIdentity: 'fixture',
                        waveform: const [0, 1],
                        waveformDensity: density,
                        onSeek: (_) {})))));
        await tester.pumpAndSettle();
        final theme =
            tester.widget<SliderTheme>(find.byType(SliderTheme).last).data;
        final box = tester.renderObject<RenderBox>(find.byType(Slider));
        expect(
            theme.trackShape!
                .getPreferredRect(parentBox: box, sliderTheme: theme),
            const RoundedRectSliderTrackShape()
                .getPreferredRect(parentBox: box, sliderTheme: theme));
        expect(tester.getSize(find.byType(Slider)).height, 48);
        expect(tester.takeException(), isNull);
      }
    }
    final key = GlobalKey();
    await tester
        .pumpWidget(host(key, WaveformBarDensity.dense, peaks: const []));
    expect(
        tester
            .widget<SliderTheme>(find.byType(SliderTheme).last)
            .data
            .trackShape
            .runtimeType,
        RoundedRectSliderTrackShape);
  });

  testWidgets(
      'three density options render with app fonts in four languages at two widths',
      (tester) async {
    const output = String.fromEnvironment('DAN_WAVEFORM_DENSITY_RENDER');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final peaks = List<double>.generate(512, (index) => (index % 48) / 47);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final density in WaveformBarDensity.values
          .where((item) => item != WaveformBarDensity.automatic)) {
        for (final width in [800.0, 300.0]) {
          tester.view.physicalSize = Size(width, 240);
          final key = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Entry(welcome: false).fromSchemeAndFontFamily(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal,
                        brightness:
                            width == 800 ? Brightness.light : Brightness.dark)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(width == 800 ? 1 : 2),
                        disableAnimations: true),
                    child: child!),
                home: Scaffold(
                    body: Center(
                        child: DetailProgressSlider(
                            positions: positions.stream,
                            readPosition: () => 38,
                            duration: 100,
                            trackIdentity: 'fixture',
                            waveform: peaks,
                            waveformDensity: density,
                            onSeek: (_) {}))),
              )));
          await tester.pumpAndSettle();
          expect(find.text('0:38'), findsOneWidget);
          expect(find.text('1:40'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              try {
                final bytes =
                    await image.toByteData(format: drawing.ImageByteFormat.png);
                final file = File(
                    '$output/${language.name}-${density.name}-${width.toInt()}.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
      }
    }
  });
}
