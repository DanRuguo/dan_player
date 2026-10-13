import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Stroke extends CustomPainter {
  const _Stroke();

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
        Rect.fromLTWH(80, 0, 8, size.height),
        Paint()..color = Colors.black,
      );

  @override
  bool shouldRepaint(_Stroke oldDelegate) => false;
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey boundary) async =>
    (await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return Uint8List.fromList(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

double _sigma(RenderBackdropFilter filter) =>
    (filter.filterConfig.filter! as dynamic).sigmaX as double;

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          for (var row = 0; row < 8; row++)
            LrcLine(Duration(seconds: row * 5), 'Actual lyric $row',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

void main() {
  for (final opacity in [1.0, .35]) {
    testWidgets(
        'wide strokes soften without crossing the boundary opacity$opacity',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final reading = AnimationController(vsync: tester, value: 1);
      addTearDown(reading.dispose);
      Widget host({bool enabled = true, bool oldReference = false}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 240,
                  height: 360,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Opacity(
                      opacity: opacity,
                      child: oldReference
                          ? ClipRect(
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 2.4, sigmaY: 2.4),
                                child: const CustomPaint(painter: _Stroke()),
                              ),
                            )
                          : LyricViewportBlur(
                              enabled: enabled,
                              topFraction: .25,
                              bottomFraction: .25,
                              reading: reading,
                              child: const CustomPaint(painter: _Stroke()),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host(enabled: false));
      final clear = await _pixels(tester, boundary);
      await tester.pumpWidget(host(oldReference: true));
      final old = await _pixels(tester, boundary);
      await tester.pumpWidget(host());
      final blurred = await _pixels(tester, boundary);
      int ink(Uint8List data, int y) => 255 - data[(y * 240 + 84) * 4];
      for (final y in [16, 344]) {
        expect(ink(blurred, y), lessThan(ink(old, y)),
            reason: 'The outer band must remove more thick-stroke contrast '
                'than the former maximum 2.4 Gaussian.');
      }
      expect(
          Uint8List.sublistView(blurred, 90 * 240 * 4, 270 * 240 * 4),
          orderedEquals(
              Uint8List.sublistView(clear, 90 * 240 * 4, 270 * 240 * 4)),
          reason: 'The complete clear centre remains byte exact.');
      final filters = tester
          .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
          .toList();
      expect(filters, hasLength(24));
      for (final band in [filters.take(12), filters.skip(12)]) {
        final kernels = band.toList();
        expect(_sigma(kernels.first), lessThan(.05),
            reason:
                'The first band approaches identity at the clear boundary.');
        expect(kernels.first.enabled, isFalse,
            reason: 'The established 0.1 physical threshold remains intact.');
        for (var index = 1; index < kernels.length; index++) {
          expect(
              _sigma(kernels[index]), greaterThan(_sigma(kernels[index - 1])),
              reason: 'The whole band progresses; no early full-blur plateau.');
        }
        expect(_sigma(kernels.last), greaterThan(7.9));
      }
      reading.value = 0;
      await tester.pump();
      expect(await _pixels(tester, boundary), orderedEquals(clear));
      await tester.pump(const Duration(milliseconds: 240));
      expect(await _pixels(tester, boundary), orderedEquals(clear));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real lyric hover progressively clears stronger blur in 120ms',
      (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    final positions = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(false);
    final content = GlobalKey();
    addTearDown(settings.dispose);
    addTearDown(positions.close);
    addTearDown(hidden.dispose);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 550));
    addTearDown(mouse.removePointer);
    await tester.pumpWidget(MaterialApp(
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 420,
            height: 480,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: VerticalLyricContent(
                key: content,
                lyricFuture: Future<Lyric?>.value(_Lyrics()),
                positionStream: positions.stream,
                readPosition: () => 12,
                onSeek: (_) => fail('Hover cannot seek.'),
                hidden: hidden,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    double maximum() => tester
        .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
        .where((filter) => filter.enabled)
        .fold(0.0,
            (value, filter) => _sigma(filter) > value ? _sigma(filter) : value);
    final full = maximum();
    expect(full, greaterThan(7.9));
    final reading = tester
        .widget<LyricViewportBlur>(find.byType(LyricViewportBlur))
        .reading;
    await mouse.moveTo(tester.getCenter(find.byKey(content)));
    await tester.pump();
    var previous = full;
    var lastElapsed = 0;
    for (final elapsed in [16, 40, 88]) {
      await tester.pump(Duration(milliseconds: elapsed - lastElapsed));
      final current = maximum();
      expect(current, inExclusiveRange(0.0, previous),
          reason: 'The real MouseRegion keeps visible positive kernels at '
              '$elapsed milliseconds instead of jumping to clear.');
      previous = current;
      lastElapsed = elapsed;
    }
    await tester.pump(const Duration(milliseconds: 32));
    expect(reading.value, 0);
    expect(maximum(), 0);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 240));
    expect(reading.value, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
