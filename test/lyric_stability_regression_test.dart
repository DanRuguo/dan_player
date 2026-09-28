import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _HeldWord extends SyncLyricWord {
  _HeldWord() : super(Duration.zero, const Duration(seconds: 4), 'Moonlight');
}

class _HeldLine extends SyncLyricLine {
  _HeldLine()
      : super(Duration.zero, const Duration(seconds: 4), [_HeldWord()],
            '月光洒满窗边') {
    romanization = 'yuè guāng sǎ mǎn chuāng biān';
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });
  testWidgets(
      'real timed glyphs stay visible through alignment changes and held notes rise',
      (tester) async {
    final settings = LyricViewController()
      ..lyricFontSize = 22
      ..translationFontSize = 18
      ..lyricTextAlign = LyricTextAlign.left;
    final position = ValueNotifier(const Duration(milliseconds: -400));
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          fontFamily: danEmbeddedFontFamily,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: Scaffold(
          body: Center(
              child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                      width: 680,
                      height: 270,
                      child: Center(
                          child: ChangeNotifierProvider.value(
                              value: settings,
                              child: LyricFractionalFilterScope(
                                  sigma: 0,
                                  dpr: 1,
                                  enabled: true,
                                  repaintToken: 0,
                                  child: LyricViewTile(
                                      line: _HeldLine(),
                                      position: position,
                                      opacity: 1,
                                      reducedMotion: false,
                                      distance: 0)))))))),
    ));
    await tester.pumpAndSettle();
    LyricWordHighlightPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<LyricWordHighlightPainter>()
        .single;
    Future<void> capture(String name) async {
      final output = Platform.environment['DAN_STABILITY_RENDER'];
      if (output == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        await Directory(output).create(recursive: true);
        await File('$output/timed-$name.png').writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List());
        image.dispose();
      });
    }

    await capture('before');
    position.value = const Duration(milliseconds: 2000);
    await tester.pump();
    final p = painter();
    expect(p.movingWordLifts.single, inInclusiveRange(5, 5.5),
        reason: 'A held syllable should visibly rise at its midpoint');
    await capture('held');
    Rect timedInk() => tester.getRect(find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is LyricWordHighlightPainter));
    final left = timedInk();
    settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    final center = timedInk();
    expect(center.center.dx, greaterThan(left.center.dx + 50));
    await capture('center');
    settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    final right = timedInk();
    expect(right.center.dx, greaterThan(center.center.dx + 50));
    expect(painter().line, same(p.line));
    await capture('right');
    position.value = const Duration(milliseconds: 4400);
    await tester.pump();
    expect(painter().movingWordCount, 0);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    position.dispose();
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets(
        'visible lyric ink translates without flashing or horizontal oscillation at $dpr',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(900 * dpr, 300 * dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey();
      const ink = '风吹过街角 Aあ歌词';
      final settings = LyricViewController();
      final position = ValueNotifier(Duration.zero);
      final line = LrcLine(Duration.zero, ink, isBlank: false);
      Widget host(LyricTextAlign alignment, double font,
          {bool enabled = true}) {
        settings
          ..lyricTextAlign = alignment
          ..lyricFontSize = font / 1.5;
        return MaterialApp(
          theme: ThemeData(fontFamily: danEmbeddedFontFamily),
          home: Material(
            type: MaterialType.transparency,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 650,
                  height: 200,
                  child: ChangeNotifierProvider.value(
                    value: settings,
                    child: LyricFractionalFilterScope(
                      sigma: 0,
                      enabled: enabled,
                      dpr: dpr,
                      repaintToken: (alignment, font, enabled),
                      child: LyricViewTile(
                        line: line,
                        position: position,
                        opacity: 1,
                        reducedMotion: true,
                        distance: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Future<({double x, double localX, double mass})> capture(
          String name) async {
        final origin = tester.getTopLeft(find.byKey(key));
        final paragraph = tester.getTopLeft(find.text(ink));
        final paragraphLeft = paragraph.dx - origin.dx;
        return (await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: dpr);
          try {
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
            double mass = 0, x = 0;
            for (var y = 0; y < image.height; y++) {
              for (var column = 0; column < image.width; column++) {
                final a = bytes[(y * image.width + column) * 4 + 3];
                mass += a;
                x += a * (column + .5);
              }
            }
            final output = Platform.environment['DAN_STABILITY_RENDER'];
            if (output != null &&
                (name == 'align-0' ||
                    name == 'align-10' ||
                    name == 'align-20' ||
                    name == 'font-20')) {
              await Directory(output).create(recursive: true);
              await File('$output/$dpr-$name.png').writeAsBytes(
                  (await image.toByteData(format: ui.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
            }
            final center = x / mass / dpr;
            return (x: center, localX: center - paragraphLeft, mass: mass);
          } finally {
            image.dispose();
          }
        }))!;
      }

      double? firstMass, firstX, lastX;
      for (final alignment in LyricTextAlign.values) {
        await tester.pumpWidget(host(alignment, 33));
        await tester.pumpAndSettle();
        final sample = await capture('align-${alignment.name}');
        firstMass ??= sample.mass;
        firstX ??= sample.x;
        expect(sample.mass / firstMass, closeTo(1, .04),
            reason: 'Translation must never fade or duplicate ink');
        if (lastX != null) expect(sample.x, greaterThan(lastX + 20));
        lastX = sample.x;
      }
      expect(lastX! - firstX!, greaterThan(200));
      await tester.pumpWidget(host(LyricTextAlign.left, 33));
      final automatic = await capture('auto');
      await tester.pumpWidget(host(LyricTextAlign.left, 33, enabled: false));
      final manual = await capture('manual');
      // The clear-row supersampling path is intentionally different from
      // direct paint. Its ink may shift within a physical pixel, but should
      // preserve the perceived position and visible glyph weight.
      expect((manual.x - automatic.x).abs() * dpr, lessThan(.5));
      expect(manual.mass / automatic.mass, closeTo(1, .01));
      double? normalizedCenter, previousFontX;
      for (var i = 0; i <= 20; i++) {
        final font = 33 + i * .1;
        await tester.pumpWidget(host(LyricTextAlign.left, font));
        final sample = await capture('font-$i');
        normalizedCenter ??= sample.localX / font;
        if (previousFontX != null) {
          expect(sample.localX, greaterThan(previousFontX));
        }
        previousFontX = sample.localX;
        // .015 of a 33px font is roughly half a physical pixel at 100%.
        expect(sample.localX / font, closeTo(normalizedCenter, .015),
            reason: 'Font scaling must preserve shaped glyph geometry');
      }
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      position.dispose();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
