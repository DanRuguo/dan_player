import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

class _Surface {
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
  final hidden = ValueNotifier(false);
  final boundary = GlobalKey();
  final document = Qrc.fromQrcText([
    for (var index = 0; index < 18; index++)
      '[${(index + 1) * 5000},5000]夜第$index行 Moonlight 夜空を読む 밤의 노래'
          '(${(index + 1) * 5000},4500)',
  ].join('\n'));
  var seeks = 0;

  QrcLine line(int index) => document.lines[index] as QrcLine;
  LyricReadingTarget search(int index) => lyricSearchRows(document,
          project: (line) => lyricReadingText(line,
              translation: true, romanization: true))[index]
      .target;

  Finder primary(int index) => find.byWidgetPredicate((widget) =>
      widget is CustomPaint &&
      widget.painter is LyricWordHighlightPainter &&
      identical(
          (widget.painter as LyricWordHighlightPainter).line, line(index)));

  Finder get controls => find.byKey(const ValueKey('lyric-font-size-open'));
  Finder get viewport => find.byKey(const ValueKey('vertical-lyric-scroll'));
  ScrollController scroll(WidgetTester tester) =>
      tester.widget<CustomScrollView>(viewport).controller!;

  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    sizePlaylistFeature(tester, width: 800, height: 720);
    for (final (index, line) in document.lines.indexed) {
      line.romanization = 'yè dì $index háng · yèkōng yuedu';
      (line as QrcLine).translation = 'Translation line $index: '
          'the distant night sky keeps the words readable.';
    }
    await tester.pumpWidget(playlistFeatureHost(
        ChangeNotifierProvider.value(
            value: settings,
            child: Center(
                child: SizedBox(
                    width: 600,
                    height: 600,
                    child: Builder(
                        builder: (context) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(disableAnimations: reduced),
                            child: Stack(children: [
                              VerticalLyricScrollView(
                                  lyric: document,
                                  positionStream: const Stream<double>.empty(),
                                  readPosition: () => 2.3,
                                  onSeek: (_) => seeks++,
                                  hidden: hidden,
                                  playing: false,
                                  springLyrics: false),
                              Align(
                                  alignment: Alignment.topRight,
                                  child: LyricFontSizeMenu(hidden: hidden)),
                            ])))))),
        boundary: boundary));
    await tester.pumpAndSettle();
    final target = search(12);
    expect(target.textOffset, isNull,
        reason: 'Real QRC search selects the authored row');
    settings.revealForReading(target);
    await tester.pumpAndSettle();
    await expectInk(tester, 12);
    await tester.tap(controls);
    await tester.pumpAndSettle();
  }

  Future<void> preset(WidgetTester tester, int size) async {
    await tester.tap(find.byKey(ValueKey('lyric-font-size-preset-$size')));
    await tester.pump();
  }

  Future<void> closeMenu(WidgetTester tester, {bool settle = true}) async {
    if (find
        .byKey(const ValueKey('lyric-font-size-preset-48'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(controls);
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Rect glyph(WidgetTester tester, int index) {
    final paint = primary(index);
    final painter =
        tester.widget<CustomPaint>(paint).painter! as LyricWordHighlightPainter;
    final first = painter.text
        .getBoxesForSelection(TextSelection(
            baseOffset: 0,
            extentOffset: line(index).content.characters.first.length))
        .first
        .toRect();
    final metrics = painter.text.computeLineMetrics().first;
    final alignment = ((painter.alignmentX ?? -1) + 1) / 2;
    final ink = first.shift(painter.inkOffset +
        Offset((painter.text.width - metrics.width) * alignment, 0));
    final box = tester.renderObject<RenderBox>(paint);
    return Rect.fromPoints(
        box.localToGlobal(ink.topLeft), box.localToGlobal(ink.bottomRight));
  }

  void expectVisible(WidgetTester tester, int index, Rect controlsRect) {
    final visible = tester.getRect(viewport);
    final primaryGlyph = glyph(tester, index);
    expect(primaryGlyph.top, greaterThanOrEqualTo(visible.top));
    expect(primaryGlyph.bottom, lessThanOrEqualTo(visible.bottom),
        reason: 'The actual found primary glyph stays inside the viewport');
    expect(tester.getRect(controls), controlsRect);
    expect(settings.readingMode, isTrue);
    expect(settings.readingTarget!.line, same(line(index)));
    expect(seeks, 0);
  }

  Future<void> expectInk(WidgetTester tester, int index) async {
    final region = glyph(tester, index).inflate(2);
    final colors = await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final rgba =
            (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
                .buffer
                .asUint32List();
        final colors = <int>{};
        for (var y = math.max(0, region.top.floor());
            y < math.min(image.height, region.bottom.ceil());
            y++) {
          for (var x = math.max(0, region.left.floor());
              x < math.min(image.width, region.right.ceil());
              x++) {
            colors.add(rgba[y * image.width + x]);
          }
        }
        return colors.length;
      } finally {
        image.dispose();
      }
    });
    expect(colors, greaterThan(8),
        reason: 'The observed first-glyph rectangle contains real ink');
  }

  Future<void> saveFrame(WidgetTester tester, String name) async {
    final output = Platform.environment['DAN_LYRIC_READING_FONT_RENDER_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        await Directory(output).create(recursive: true);
        final png = await image.toByteData(format: raster.ImageByteFormat.png);
        await File(path.join(output, '$name.png'))
            .writeAsBytes(png!.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> finish(WidgetTester tester) async {
    expect(seeks, 0);
    expect(tester.takeException(), isNull);
    // The real menu has finite hover/scrollbar feedback. Close it while
    // keeping production lyric rows mounted before checking their idle clock.
    final mountedPrimary = tester.element(primary(12));
    await closeMenu(tester);
    expect(tester.element(primary(12)), same(mountedPrimary));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
    hidden.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final output = Platform.environment['DAN_LYRIC_READING_FONT_RENDER_DIR'];
    if (output != null &&
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            output)) {
      throw StateError('Font render output must stay in workspace QA');
    }
    await loadPlaylistFeatureFonts();
  });
  for (final reduced in [false, true]) {
    testWidgets('QRC reading survives real A± presets reduced=$reduced',
        (tester) async {
      final surface = _Surface();
      await surface.mount(tester, reduced: reduced);
      final controls = tester.getRect(surface.controls);
      for (final size in [48, 22]) {
        await surface.preset(tester, size);
        double? firstHeight;
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          surface.expectVisible(tester, 12, controls);
          firstHeight ??= surface.glyph(tester, 12).height;
          if (frame == 17) {
            await surface.expectInk(tester, 12);
            if (!reduced && size == 48) {
              await surface.saveFrame(tester, 'qrc-font-48-mid');
            }
          }
          if (!reduced && frame == 0) {
            expect(tester.binding.transientCallbackCount, greaterThan(0),
                reason: 'Normal font animation retains its finite clock');
          }
        }
        await tester.pumpAndSettle();
        if (!reduced) {
          expect((surface.glyph(tester, 12).height - firstHeight!).abs(),
              greaterThan(.1),
              reason: 'The existing size morph must remain animated');
        }
        await surface.expectInk(tester, 12);
        if (!reduced && size == 48) {
          await surface.saveFrame(tester, 'qrc-font-48-final');
        }
        final settled = surface.glyph(tester, 12);
        await tester.pump(const Duration(seconds: 2));
        expect(surface.glyph(tester, 12), settled,
            reason: 'Idle singer follow cannot take the reading target');
      }
      await surface.finish(tester);
    });
  }

  for (final first in ['font', 'content']) {
    testWidgets('QRC reading waits for both $first-first setting endpoints',
        (tester) async {
      final surface = _Surface();
      await surface.mount(tester);
      final controls = tester.getRect(surface.controls);
      if (first == 'font') {
        await surface.preset(tester, 48);
      } else {
        surface.settings.setShowTimestamps(true);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 80));
      if (first == 'font') {
        surface.settings.setShowTimestamps(true);
        await tester.pump();
      } else {
        await surface.preset(tester, 48);
      }
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        surface.expectVisible(tester, 12, controls);
      }
      await tester.pumpAndSettle();
      await surface.expectInk(tester, 12);
      await surface.finish(tester);
    });
  }

  for (final interrupt in ['find', 'wheel', 'hidden', 'return']) {
    testWidgets('QRC reading font ownership releases for $interrupt',
        (tester) async {
      final surface = _Surface();
      await surface.mount(tester);
      await surface.preset(tester, 48);
      await tester.pump(const Duration(milliseconds: 128));
      switch (interrupt) {
        case 'find':
          surface.settings.revealForReading(surface.search(5));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(surface.viewport);
          expect(surface.glyph(tester, 5).top,
              closeTo(viewport.top + viewport.height * .2, .05));
          await surface.expectInk(tester, 5);
        case 'wheel':
          final before = surface.scroll(tester).offset;
          await tester.sendEventToBinding(PointerScrollEvent(
              position: tester.getCenter(surface.viewport),
              scrollDelta: const Offset(0, -240)));
          await tester.pump();
          final held = surface.scroll(tester).offset;
          expect(held, lessThan(before - 200));
          await tester.pumpAndSettle();
          expect(surface.scroll(tester).offset, closeTo(held, .05),
              reason:
                  'The finished font callback cannot revive a found anchor');
          surface.settings.revealForReading(surface.search(3));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(surface.viewport);
          expect(surface.glyph(tester, 3).top,
              closeTo(viewport.top + viewport.height * .2, .05));
        case 'hidden':
          await surface.closeMenu(tester, settle: false);
          surface.hidden.value = true;
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          final held = surface.scroll(tester).offset;
          await tester.pump(const Duration(seconds: 1));
          expect(surface.scroll(tester).offset, held);
          surface.hidden.value = false;
          await tester.pumpAndSettle();
          final viewport = tester.getRect(surface.viewport);
          expect(surface.glyph(tester, 12).top,
              closeTo(viewport.top + viewport.height * .2, .05));
        case 'return':
          surface.settings.returnToCurrent();
          await tester.pumpAndSettle();
          expect(surface.settings.readingMode, isFalse);
          expect(surface.settings.readingTarget, isNull);
          final viewport = tester.getRect(surface.viewport);
          final glyph = surface.glyph(tester, 0);
          expect(glyph.top, greaterThanOrEqualTo(viewport.top));
          expect(glyph.bottom, lessThanOrEqualTo(viewport.bottom));
      }
      final settledOffset = surface.scroll(tester).offset;
      await tester.pump(const Duration(seconds: 2));
      expect(surface.scroll(tester).offset, closeTo(settledOffset, .05));
      await surface.finish(tester);
    });
  }
}
