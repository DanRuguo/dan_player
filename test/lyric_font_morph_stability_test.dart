import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

const _primary = '音もない世界、何を見てるの?';
const _translation = 'In a silent world, what do you see?';
// Scoped software-raster samples may quantize by less than one physical pixel.
// The paired perturbation test below proves a full-pixel move still fails.
const _maxScopedVerticalResidual = .75;

class _LongLyric extends Lyric {
  _LongLyric(super.lines);
}

List<TextPainter> _painters(WidgetTester tester, String text) {
  final paragraph = find.byWidgetPredicate(
      (widget) => widget is BalancedLyricText && widget.text == text);
  return [
    for (final paint in tester.widgetList<CustomPaint>(
        find.descendant(of: paragraph, matching: find.byType(CustomPaint))))
      if (paint.painter is PlainLyricWordFollowPainter)
        (paint.painter! as PlainLyricWordFollowPainter).text,
  ];
}

Future<({double x, double y, double mass})> _inkCenter(
    WidgetTester tester, RenderRepaintBoundary boundary, double ratio,
    {File? png}) async {
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (png != null) {
        final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
        await png.writeAsBytes(encoded!.buffer.asUint8List(), flush: true);
      }
      final pixels = bytes!.buffer.asUint8List();
      var mass = 0.0;
      var xMoment = 0.0;
      var yMoment = 0.0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final at = (y * image.width + x) * 4;
          final ink =
              (765 - pixels[at] - pixels[at + 1] - pixels[at + 2]) / 765;
          if (ink < .02) continue;
          mass += ink;
          xMoment += x * ink;
          yMoment += y * ink;
        }
      }
      return (x: xMoment / mass, y: yMoment / mass, mass: mass);
    } finally {
      image.dispose();
    }
  }))!;
}

Future<Uint8List> _rgba(
    WidgetTester tester, RenderRepaintBoundary boundary, double ratio) async {
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

double _relativeInkDifference(Uint8List a, Uint8List b) {
  assert(a.length == b.length);
  var difference = 0.0;
  var referenceMass = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    final oldInk = (765 - a[i] - a[i + 1] - a[i + 2]) / 765;
    final newInk = (765 - b[i] - b[i + 1] - b[i + 2]) / 765;
    difference += (oldInk - newInk).abs();
    referenceMass += oldInk;
  }
  return difference / referenceMass;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  testWidgets('font morph retains two shaped paragraphs only during motion',
      (tester) async {
    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': false,
        'showLyricTranslation': true,
      }),
    );
    final position = ValueNotifier(Duration.zero);
    addTearDown(() {
      settings.dispose();
      position.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        body: SizedBox(
          width: 440,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: LyricViewTile(
              line: LrcLine(Duration.zero, '$_primary┃$_translation',
                  isBlank: false),
              position: position,
              opacity: 1,
              distance: 0,
              reducedMotion: false,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(_painters(tester, _primary), hasLength(1));
    expect(_painters(tester, _translation), hasLength(1));

    settings.increaseFontSize();
    await tester.pump();
    final primary = _painters(tester, _primary);
    final translation = _painters(tester, _translation);
    expect(primary, hasLength(2));
    expect(translation, hasLength(2));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final nextPrimary = _painters(tester, _primary);
      final nextTranslation = _painters(tester, _translation);
      expect(identical(nextPrimary[0], primary[0]), isTrue);
      expect(identical(nextPrimary[1], primary[1]), isTrue);
      expect(identical(nextTranslation[0], translation[0]), isTrue);
      expect(identical(nextTranslation[1], translation[1]), isTrue);
    }
    await tester.pumpAndSettle();
    expect(_painters(tester, _primary), [same(primary[1])]);
    expect(_painters(tester, _translation), [same(translation[1])]);
    for (final morph
        in tester.widgetList<LyricFontMorph>(find.byType(LyricFontMorph))) {
      expect(morph.children, hasLength(1),
          reason: 'A settled line must not retain a second paragraph');
    }
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lyric keeps two font endpoints inside the viewport band',
      (tester) async {
    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': false,
        'showLyricTranslation': true,
      }),
    );
    final positions = StreamController<double>.broadcast();
    addTearDown(() async {
      settings.dispose();
      await positions.close();
    });
    final lyric = _LongLyric([
      for (var index = 0; index < 300; index++)
        LrcLine(
          Duration(seconds: index * 5),
          '音もない世界、何を見てるの? $index┃In a silent world, what do you see?',
          isBlank: false,
          length: const Duration(seconds: 5),
        ),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            height: 500,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: VerticalLyricScrollView(
                lyric: lyric,
                positionStream: positions.stream,
                readPosition: () => 100,
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    settings.increaseFontSize();
    final clock = Stopwatch()..start();
    await tester.pump();
    clock.stop();
    final firstUs = clock.elapsedMicroseconds;
    final firstRss = ProcessInfo.currentRss;
    ({int morphs, int moving, int wrapTargets}) counts() {
      final morphs = tester
          .widgetList<LyricFontMorph>(find.byType(LyricFontMorph))
          .toList();
      return (
        morphs: morphs.length,
        moving: morphs.where((morph) => morph.children.length == 2).length,
        wrapTargets: tester
            .widgetList<BalancedLyricText>(find.byType(BalancedLyricText))
            .where((text) => text.wrapTargetFontSize != null)
            .length,
      );
    }

    final first = counts();
    final samples = <int>[];
    late ({int morphs, int moving, int wrapTargets}) middle;
    for (var frame = 0; frame < 28; frame++) {
      clock
        ..reset()
        ..start();
      await tester.pump(const Duration(milliseconds: 16));
      clock.stop();
      samples.add(clock.elapsedMicroseconds);
      if (frame == 8) middle = counts();
    }
    final middleRss = ProcessInfo.currentRss;
    final middleSamples = samples.skip(1).take(19).toList()..sort();
    final middleP95 = middleSamples[(middleSamples.length * .95).ceil() - 1];
    debugPrint('300-row production isolated: firstUs=$firstUs '
        'middleP95Us=$middleP95 rss=$firstRss→$middleRss '
        'fontBand first=$first middle=$middle');
    expect(first.morphs, greaterThanOrEqualTo(300));
    expect(first.moving, lessThan(60));
    expect(middle.moving, lessThan(60));
    expect(first.wrapTargets, lessThan(60));
    expect(middle.wrapTargets, lessThan(60));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('300-row direct font morph CPU upper-bound sample',
      (tester) async {
    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': false,
        'showLyricTranslation': true,
      }),
    );
    final position = ValueNotifier(Duration.zero);
    addTearDown(() {
      settings.dispose();
      position.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: Column(children: [
                for (var index = 0; index < 300; index++)
                  LyricViewTile(
                    line: LrcLine(
                      Duration(seconds: index * 5),
                      '音もない世界、何を見てるの? $index┃In a silent world, what do you see?',
                      isBlank: false,
                    ),
                    position: position,
                    opacity: 1,
                    distance: index,
                    reducedMotion: false,
                  ),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final clock = Stopwatch();
    settings.increaseFontSize();
    clock.start();
    await tester.pump();
    clock.stop();
    final firstUs = clock.elapsedMicroseconds;
    final firstRss = ProcessInfo.currentRss;
    final samples = <int>[];
    for (var frame = 0; frame < 28; frame++) {
      clock
        ..reset()
        ..start();
      await tester.pump(const Duration(milliseconds: 16));
      clock.stop();
      samples.add(clock.elapsedMicroseconds);
    }
    final middleRss = ProcessInfo.currentRss;
    final middleSamples = samples.skip(1).take(19).toList()..sort();
    final middleP95 = middleSamples[(middleSamples.length * .95).ceil() - 1];
    debugPrint('300-row direct isolated: firstUs=$firstUs '
        'middleP95Us=$middleP95 rss=$firstRss→$middleRss');
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final ratio in [1.0, 1.25]) {
    testWidgets('scoped Latin and digit ink moves continuously at ${ratio}x',
        (tester) async {
      final capturePath = Platform.environment['DAN_GLYPH_MOTION_OUTPUT'];
      final captureDir = capturePath == null ? null : Directory(capturePath);
      if (captureDir != null) {
        final normalized =
            path.normalize(captureDir.path).replaceAll('\\', '/').toLowerCase();
        expect(path.isAbsolute(captureDir.path), isTrue);
        expect(normalized.contains('/tool/qa-local/'), isTrue);
        await tester.runAsync(() => captureDir.create(recursive: true));
      }
      File? frameFile(String label) => captureDir == null
          ? null
          : File(path.join(captureDir.path, 'latin-$ratio-$label.png'));
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap(const {
          'lyricFontSize': 22,
          'translationFontSize': 18,
          'showLyricTimestamps': false,
          'showLyricTranslation': false,
        }),
      );
      final position = ValueNotifier(Duration.zero);
      addTearDown(() {
        settings.dispose();
        position.dispose();
      });
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 140,
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ChangeNotifierProvider.value(
                      value: settings,
                      child: Builder(
                        builder: (context) => LyricFractionalFilterScope(
                          // The lyric viewport keeps this sampling scope
                          // enabled even when the row's blur has reached 0.
                          sigma: 0,
                          dpr: View.of(context).devicePixelRatio,
                          enabled: true,
                          repaintToken: 0,
                          child: LyricViewTile(
                            line: LrcLine(Duration.zero, 'Moonlight 2026',
                                isBlank: false),
                            position: position,
                            opacity: 1,
                            distance: 0,
                            reducedMotion: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final centers = <({double x, double y, double mass})>[
        await _inkCenter(tester, boundary, ratio, png: frameFile('before')),
      ];
      final sourceWidth = _painters(tester, 'Moonlight 2026')
          .single
          .computeLineMetrics()
          .first
          .width;
      final progress = <double>[0];
      settings.increaseFontSize();
      await tester.pump();
      final targetWidth = _painters(tester, 'Moonlight 2026')
          .last
          .computeLineMetrics()
          .first
          .width;
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        centers.add(await _inkCenter(tester, boundary, ratio,
            png: [0, 5, 12, 13, 15, 20, 23].contains(frame)
                ? frameFile('frame-${frame + 1}')
                : null));
        progress.add(tester
            .widget<LyricFontMorph>(find.byType(LyricFontMorph).first)
            .progress);
      }
      await tester.pumpAndSettle();
      centers.add(
          await _inkCenter(tester, boundary, ratio, png: frameFile('after')));
      progress.add(1);
      debugPrint(
          'Ink $ratio endpoints: oldWidth=$sourceWidth newWidth=$targetWidth firstX=${centers.first.x} oldAt72X=${centers[12].x} finalX=${centers.last.x} peakX=${centers.map((e) => e.x).reduce((a, b) => a > b ? a : b)}');
      final residuals = [
        for (var index = 0; index < centers.length; index++)
          centers[index].x -
              (centers.first.x +
                  (centers.last.x - centers.first.x) * progress[index]),
      ];
      if (captureDir != null) {
        await tester.runAsync(() =>
            File(path.join(captureDir.path, 'latin-$ratio-trajectory.json'))
                .writeAsString(
                    jsonEncode({
                      'ratio': ratio,
                      'sourceLineWidth': sourceWidth,
                      'targetLineWidth': targetWidth,
                      'frames': [
                        for (var index = 0; index < centers.length; index++)
                          {
                            'frame': index,
                            'progress': progress[index],
                            'x': centers[index].x,
                            'y': centers[index].y,
                            'mass': centers[index].mass,
                            'xResidual': residuals[index],
                          }
                      ]
                    }),
                    flush: true));
      }
      debugPrint('Ink $ratio x steps: ${[
        for (var index = 1; index < centers.length; index++)
          (centers[index].x - centers[index - 1].x).toStringAsFixed(3)
      ].join(', ')}');
      debugPrint('Ink $ratio y steps: ${[
        for (var index = 1; index < centers.length; index++)
          (centers[index].y - centers[index - 1].y).toStringAsFixed(3)
      ].join(', ')}');
      debugPrint('Ink $ratio progress: ${[
        for (final value in progress) value.toStringAsFixed(3)
      ].join(', ')}');
      debugPrint('Ink $ratio x residuals: ${[
        for (final value in residuals) value.toStringAsFixed(3)
      ].join(', ')}');
      expect(centers.every((center) => center.mass > 50), isTrue);
      expect(centers.last.x, greaterThan(centers.first.x + ratio));
      for (var index = 1; index < centers.length; index++) {
        final xStep = centers[index].x - centers[index - 1].x;
        final yStep = centers[index].y - centers[index - 1].y;
        final expectedYStep = (centers.last.y - centers.first.y) *
            (progress[index] - progress[index - 1]);
        // Increasing a fixed Latin line should not reverse its horizontal
        // expansion. At 1.0x, the scoped software renderer can move the ink
        // centre by 0.69 px at one sampling boundary without a whole-pixel
        // glyph hop; the forced 1 px control below must still breach this gate.
        expect(xStep, greaterThan(-.15 * ratio),
            reason: 'Frame $index moved glyph ink against the font growth');
        // _inkCenter reads the output image's physical pixel coordinates, so
        // this limit must not be multiplied by devicePixelRatio again.
        expect(
            (yStep - expectedYStep).abs(), lessThan(_maxScopedVerticalResidual),
            reason: 'Frame $index moved glyph ink beyond its size trajectory');
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scoped ink gate detects a forced physical pixel at ${ratio}x',
        (tester) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap(const {
          'lyricFontSize': 22,
          'translationFontSize': 18,
          'showLyricTimestamps': false,
          'showLyricTranslation': false,
        }),
      );
      final position = ValueNotifier(Duration.zero);
      final injectedShift = ValueNotifier(0.0);
      addTearDown(() {
        settings.dispose();
        position.dispose();
        injectedShift.dispose();
      });
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 140,
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ChangeNotifierProvider.value(
                      value: settings,
                      child: Builder(
                        builder: (context) => LyricFractionalFilterScope(
                          sigma: 0,
                          dpr: View.of(context).devicePixelRatio,
                          enabled: true,
                          repaintToken: 0,
                          child: ValueListenableBuilder<double>(
                            valueListenable: injectedShift,
                            builder: (context, shift, _) => Transform.translate(
                              offset: Offset(0, shift),
                              child: LyricViewTile(
                                line: LrcLine(Duration.zero, 'Moonlight 2026',
                                    isBlank: false),
                                position: position,
                                opacity: 1,
                                distance: 0,
                                reducedMotion: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final before = await _inkCenter(tester, boundary, ratio);
      injectedShift.value = -1 / ratio;
      await tester.pump();
      final after = await _inkCenter(tester, boundary, ratio);
      final delta = (after.y - before.y).abs();
      debugPrint('Forced one-physical-pixel shift at $ratio: $delta');
      expect(delta, greaterThanOrEqualTo(_maxScopedVerticalResidual),
          reason: 'The production ink gate must reject a full-pixel hop');
      expect(tester.takeException(), isNull);
    });

    testWidgets('single retained paragraph control at ${ratio}x',
        (tester) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final progress = ValueNotifier(0.0);
      addTearDown(progress.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 140,
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder<double>(
                      valueListenable: progress,
                      child: const BalancedLyricText(
                        'Moonlight 2026',
                        style: TextStyle(
                          color: Colors.black,
                          fontFamily: danEmbeddedFontFamily,
                          fontSize: 22 * LyricMotion.focusedFontScale,
                          fontWeight: LyricMotion.focusedFontWeight,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.left,
                        alignmentX: -1,
                      ),
                      builder: (context, value, child) => Transform.scale(
                        scale: 1 + value / 22,
                        alignment: Alignment.topLeft,
                        filterQuality: FilterQuality.medium,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final centers = <({double x, double y, double mass})>[
        await _inkCenter(tester, boundary, ratio),
      ];
      final eased = <double>[0];
      for (var frame = 1; frame <= 30; frame++) {
        final t = (frame * 16 / LyricMotion.lineDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        progress.value = LyricMotion.curve.transform(t);
        await tester.pump();
        centers.add(await _inkCenter(tester, boundary, ratio));
        eased.add(progress.value);
      }
      final xSteps = [
        for (var index = 1; index < centers.length; index++)
          centers[index].x - centers[index - 1].x
      ];
      final ySteps = [
        for (var index = 1; index < centers.length; index++)
          centers[index].y - centers[index - 1].y
      ];
      debugPrint('Single $ratio x steps: ${[
        for (final step in xSteps) step.toStringAsFixed(3)
      ].join(', ')}');
      debugPrint('Single $ratio y steps: ${[
        for (final step in ySteps) step.toStringAsFixed(3)
      ].join(', ')}');
      final output = Platform.environment['DAN_GLYPH_MOTION_OUTPUT'];
      if (output != null) {
        final normalized =
            path.normalize(output).replaceAll('\\', '/').toLowerCase();
        expect(path.isAbsolute(output), isTrue);
        expect(normalized.contains('/tool/qa-local/'), isTrue);
        await tester.runAsync(() =>
            File(path.join(output, 'single-$ratio-trajectory.json'))
                .writeAsString(
                    jsonEncode({
                      'ratio': ratio,
                      'frames': [
                        for (var index = 0; index < centers.length; index++)
                          {
                            'progress': eased[index],
                            'x': centers[index].x,
                            'y': centers[index].y,
                            'mass': centers[index].mass,
                          }
                      ]
                    }),
                    flush: true));
      }
      expect(centers.every((center) => center.mass > 50), isTrue);
      expect(centers.last.x, greaterThan(centers.first.x + ratio));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('target paragraph single-source candidate at ${ratio}x',
        (tester) async {
      final output = Platform.environment['DAN_GLYPH_MOTION_OUTPUT'];
      if (output != null) {
        final normalized =
            path.normalize(output).replaceAll('\\', '/').toLowerCase();
        expect(path.isAbsolute(output), isTrue);
        expect(normalized.contains('/tool/qa-local/'), isTrue);
        await tester.runAsync(() => Directory(output).create(recursive: true));
      }
      File? frameFile(String label) => output == null
          ? null
          : File(path.join(output, 'target-single-$ratio-$label.png'));
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final scale = ValueNotifier(1.0);
      addTearDown(scale.dispose);
      final capture = GlobalKey();
      Widget fixture(double fontSize, {FilterQuality? filterQuality}) =>
          MaterialApp(
            theme: ThemeData(fontFamily: danEmbeddedFontFamily),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 440,
                  height: 140,
                  child: RepaintBoundary(
                    key: capture,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ValueListenableBuilder<double>(
                          valueListenable: scale,
                          builder: (context, value, child) => Transform.scale(
                            scale: value,
                            alignment: Alignment.topLeft,
                            filterQuality: filterQuality,
                            child: child,
                          ),
                          child: BalancedLyricText(
                            'Moonlight 2026',
                            style: TextStyle(
                              color: Colors.black,
                              fontFamily: danEmbeddedFontFamily,
                              fontSize: fontSize * LyricMotion.focusedFontScale,
                              fontWeight: LyricMotion.focusedFontWeight,
                              height: 1.3,
                            ),
                            textAlign: TextAlign.left,
                            alignmentX: -1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(fixture(22));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final oldCenter = await _inkCenter(tester, boundary, ratio,
          png: frameFile('old-static'));
      final oldPixels = await _rgba(tester, boundary, ratio);
      final oldLine =
          _painters(tester, 'Moonlight 2026').single.computeLineMetrics().first;

      scale.value = 22 / 23;
      await tester.pumpWidget(fixture(23, filterQuality: FilterQuality.medium));
      final targetLine =
          _painters(tester, 'Moonlight 2026').single.computeLineMetrics().first;
      final centers = <({double x, double y, double mass})>[
        await _inkCenter(tester, boundary, ratio,
            png: frameFile('target-scaled-start')),
      ];
      final initialPixels = await _rgba(tester, boundary, ratio);
      final eased = <double>[0];
      for (var frame = 1; frame <= 30; frame++) {
        final t = (frame * 16 / LyricMotion.lineDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        eased.add(LyricMotion.curve.transform(t));
        scale.value = (22 + eased.last) / 23;
        await tester.pump();
        centers.add(await _inkCenter(tester, boundary, ratio,
            png: [1, 12, 21, 29, 30].contains(frame)
                ? frameFile('target-scaled-$frame')
                : null));
      }
      final animatedEndPixels = await _rgba(tester, boundary, ratio);
      await tester.pumpWidget(fixture(23));
      final staticEnd = await _inkCenter(tester, boundary, ratio,
          png: frameFile('target-static-end'));
      final staticEndPixels = await _rgba(tester, boundary, ratio);
      scale.value = 23 / 22;
      await tester.pumpWidget(fixture(22, filterQuality: FilterQuality.medium));
      final oldScaledEnd = await _inkCenter(tester, boundary, ratio,
          png: frameFile('old-scaled-end'));
      final oldScaledPixels = await _rgba(tester, boundary, ratio);
      final xSteps = [
        for (var i = 1; i < centers.length; i++)
          centers[i].x - centers[i - 1].x,
      ];
      final ySteps = [
        for (var i = 1; i < centers.length; i++)
          centers[i].y - centers[i - 1].y,
      ];
      final firstDifference = _relativeInkDifference(oldPixels, initialPixels);
      final lastDifference =
          _relativeInkDifference(animatedEndPixels, staticEndPixels);
      final oldHandoffDifference =
          _relativeInkDifference(oldScaledPixels, staticEndPixels);
      debugPrint('Target single $ratio: first delta '
          'x=${(centers.first.x - oldCenter.x).toStringAsFixed(3)} '
          'y=${(centers.first.y - oldCenter.y).toStringAsFixed(3)} '
          'raster=${firstDifference.toStringAsFixed(3)}, '
          'end delta x=${(staticEnd.x - centers.last.x).toStringAsFixed(3)} '
          'y=${(staticEnd.y - centers.last.y).toStringAsFixed(3)} '
          'raster=${lastDifference.toStringAsFixed(3)}; '
          'old→target handoff x=${(staticEnd.x - oldScaledEnd.x).toStringAsFixed(3)} '
          'y=${(staticEnd.y - oldScaledEnd.y).toStringAsFixed(3)} '
          'raster=${oldHandoffDifference.toStringAsFixed(3)}; '
          'min steps x=${xSteps.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)} '
          'y=${ySteps.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}; '
          'baseline metric delta=${((targetLine.baseline * 22 / 23 - oldLine.baseline) * ratio).toStringAsFixed(3)}');
      if (output != null) {
        await tester.runAsync(() =>
            File(path.join(output, 'target-single-$ratio-trajectory.json'))
                .writeAsString(
                    jsonEncode({
                      'ratio': ratio,
                      'firstDelta': {
                        'x': centers.first.x - oldCenter.x,
                        'y': centers.first.y - oldCenter.y,
                        'relativeInkDifference': firstDifference,
                      },
                      'lineMetrics': {
                        'oldBaseline': oldLine.baseline,
                        'targetBaseline': targetLine.baseline,
                        'oldAscent': oldLine.ascent,
                        'targetAscent': targetLine.ascent,
                        'oldHeight': oldLine.height,
                        'targetHeight': targetLine.height,
                      },
                      'endDelta': {
                        'x': staticEnd.x - centers.last.x,
                        'y': staticEnd.y - centers.last.y,
                        'relativeInkDifference': lastDifference,
                      },
                      'oldSourceHandoffDelta': {
                        'x': staticEnd.x - oldScaledEnd.x,
                        'y': staticEnd.y - oldScaledEnd.y,
                        'relativeInkDifference': oldHandoffDifference,
                      },
                      'frames': [
                        for (var i = 0; i < centers.length; i++)
                          {
                            'progress': eased[i],
                            'x': centers[i].x,
                            'y': centers[i].y,
                            'mass': centers[i].mass,
                          },
                      ],
                    }),
                    flush: true));
      }
      expect(centers.every((center) => center.mass > 50), isTrue);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
