import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word() : super(Duration.zero, const Duration(seconds: 5), '今まで私の心を埋めていたもの');
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 5), [_Word()],
            '一直以来充满我心中的东西') {
    romanization = 'i ma ma de wa ta shi no ko ko ro wo u me te i ta mo no';
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  testWidgets('sung frames retain independent phonetic and translation paints',
      (tester) async {
    final settings = LyricViewController();
    final position = ValueNotifier(const Duration(milliseconds: 500));
    final line = _Line();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Material(
          child: ChangeNotifierProvider.value(
        value: settings,
        child: Center(
            child: SizedBox(
                width: 600,
                child: LyricFractionalFilterScope(
                  sigma: .1,
                  dpr: 1,
                  enabled: true,
                  repaintToken: 0,
                  child: LyricViewTile(
                      line: line,
                      position: position,
                      opacity: 1,
                      reducedMotion: false,
                      distance: 0),
                ))),
      )),
    ));
    await tester.pumpAndSettle();
    final painters = find.byWidgetPredicate((widget) =>
        widget is CustomPaint &&
        (widget.painter is PlainLyricWordFollowPainter ||
            widget.painter is LyricWordHighlightPainter));
    final boundaries = <RenderRepaintBoundary>[];
    RenderRepaintBoundary? sungBoundary;
    for (final element in painters.evaluate()) {
      RenderObject? render = element.renderObject;
      while (render != null && render is! RenderRepaintBoundary) {
        render = render.parent;
      }
      boundaries.add(render! as RenderRepaintBoundary);
      if ((element.widget as CustomPaint).painter
          is LyricWordHighlightPainter) {
        sungBoundary = render as RenderRepaintBoundary;
      }
    }
    expect(boundaries.toSet(), hasLength(3),
        reason: 'Sung ink must not invalidate the static secondary paragraphs');
    int paints(RenderRepaintBoundary boundary) =>
        boundary.debugSymmetricPaintCount + boundary.debugAsymmetricPaintCount;
    final initial = [for (final boundary in boundaries) paints(boundary)];
    for (final milliseconds in [600, 1300, 2700, 4000]) {
      position.value = Duration(milliseconds: milliseconds);
      await tester.pump();
    }
    expect(sungBoundary, isNotNull);
    for (var i = 0; i < boundaries.length; i++) {
      expect(paints(boundaries[i]),
          boundaries[i] == sungBoundary ? greaterThan(initial[i]) : initial[i]);
    }
    for (final element in find.byType(LyricFractionalFilter).evaluate()) {
      expect((element.renderObject! as RenderProxyBox).child!.needsCompositing,
          isFalse);
    }
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    position.dispose();
  });

  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets('loading ink follows fractional transform at DPR $dpr',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(800 * dpr, 400 * dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final pending = Completer<Lyric?>();
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 600,
                  height: 160,
                  child: VerticalLyricContent(
                      lyricFuture: pending.future,
                      positionStream: const Stream.empty(),
                      readPosition: () => 0,
                      onSeek: (_) {}),
                ))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 340));
      final text = tester.renderObject<RenderBox>(find.text('正在加载歌词'));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      double? localCenter;
      // Sample ordinary movement, the turning point, and the next loop.
      final steps = [
        ...List.filled(18, const Duration(milliseconds: 8)),
        const Duration(milliseconds: 144),
        ...List.filled(18, const Duration(milliseconds: 8)),
        const Duration(milliseconds: 556),
        ...List.filled(18, const Duration(milliseconds: 8)),
      ];
      for (var frame = 0; frame < steps.length; frame++) {
        await tester.pump(steps[frame]);
        final center = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: dpr);
          try {
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
            var mass = 0.0, moment = 0.0;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                final alpha = bytes[(y * image.width + x) * 4 + 3];
                mass += alpha;
                moment += alpha * (y + .5);
              }
            }
            expect(mass, greaterThan(1000));
            return moment / mass;
          } finally {
            image.dispose();
          }
        }))!;
        final transform = text.getTransformTo(boundary);
        localCenter ??= (center / dpr - transform[13]) / transform[5];
        final expected = (transform[13] + localCenter * transform[5]) * dpr;
        expect(center, closeTo(expected, .14),
            reason:
                'Frame $frame should sample the fractional pose, not snap glyph baselines');
      }
      await tester.pumpWidget(const SizedBox());
      pending.complete(null);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
