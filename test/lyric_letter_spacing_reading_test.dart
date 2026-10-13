import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart';

({Finder finder, TextPainter painter, Offset ink}) _primary(
    WidgetTester tester, LyricLine line, String text) {
  final timed = find.byWidgetPredicate((widget) =>
      widget is CustomPaint &&
      widget.painter is LyricWordHighlightPainter &&
      identical((widget.painter as LyricWordHighlightPainter).line, line));
  if (timed.evaluate().isNotEmpty) {
    // Only the target paragraph receives hit testing/semantics during the
    // fixed-endpoint spacing morph. Read that actual target glyph geometry.
    final target = timed.last;
    final painter = tester.widget<CustomPaint>(target).painter!
        as LyricWordHighlightPainter;
    return (finder: target, painter: painter.text, ink: painter.inkOffset);
  }
  final plain = find.byWidgetPredicate((widget) =>
      widget is CustomPaint &&
      widget.painter is PlainLyricWordFollowPainter &&
      (widget.painter as PlainLyricWordFollowPainter)
              .text
              .text!
              .toPlainText() ==
          text);
  final target = plain.last;
  final painter = tester.widget<CustomPaint>(target).painter!
      as PlainLyricWordFollowPainter;
  return (finder: target, painter: painter.text, ink: painter.inkOffset);
}

double _glyphY(WidgetTester tester, LyricLine line, String text, int offset) {
  final primary = _primary(tester, line, text);
  final cluster = text.substring(offset).characters.first;
  final box = primary.painter
      .getBoxesForSelection(TextSelection(
          baseOffset: offset, extentOffset: offset + cluster.length))
      .first;
  return tester
      .renderObject<RenderBox>(primary.finder)
      .localToGlobal(Offset(0, box.top + primary.ink.dy))
      .dy;
}

Future<void> _checkInk(
    WidgetTester tester, GlobalKey boundary, Rect viewport) async {
  final colors = await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final rgba =
          (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final values = <int>{};
      for (var y = viewport.top.ceil(); y < viewport.bottom.floor(); y++) {
        for (var x = viewport.left.ceil(); x < viewport.right.floor(); x++) {
          final i = (y * image.width + x) * 4;
          values.add((rgba[i] << 24) |
              (rgba[i + 1] << 16) |
              (rgba[i + 2] << 8) |
              rgba[i + 3]);
        }
      }
      return values.length;
    } finally {
      image.dispose();
    }
  });
  expect(colors, greaterThan(20),
      reason: 'The visible reading body contains real glyph ink');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadLetterSpacingFonts();
    await loadPlaylistFeatureFonts();
  });
  for (final timed in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
          'found ${timed ? 'QRC' : 'plain'} target survives spacing width and content handoff reduced=$reduced',
          (tester) async {
        sizePlaylistFeature(tester, width: 800, height: 720);
        final Lyric document = timed
            ? Qrc.fromQrcText([
                for (var i = 0; i < 18; i++)
                  '[${(i + 1) * 5000},5000]夜第$i行 Moonlight é 👩🏽‍🚀 밤의 노래 終点'
                      '(${(i + 1) * 5000},4500)',
              ].join('\n'))
            : PlainLyric('${'雨に歌う reading é 👩🏽‍🚀 밤의 노래 ' * 100}Needle 终点');
        if (document is Qrc) {
          for (final line in document.lines) {
            line.romanization = 'yè dì háng · yèkōng yuedu';
            (line as QrcLine).translation =
                'Translation of the distant night sky.';
          }
        }
        final target = timed
            ? lyricSearchRows(document,
                    project: (line) => lyricReadingText(line))[12]
                .target
            : LyricReadingTarget(document, 0, document.lines.single,
                textOffset: (document as PlainLyric).text.indexOf('Needle'));
        final targetLine = target.line;
        final text = lyricReadingText(targetLine,
            translation: false, romanization: false);
        final offset = target.textOffset ?? 0;
        final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
        final settings = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}),
            appearance: appearance)
          ..lyricTextAlign = LyricTextAlign.left;
        final width = ValueNotifier(600.0), hidden = ValueNotifier(false);
        addTearDown(settings.dispose);
        addTearDown(appearance.dispose);
        addTearDown(width.dispose);
        addTearDown(hidden.dispose);
        final boundary = GlobalKey();
        var seeks = 0;
        await tester.pumpWidget(playlistFeatureHost(
            AppFontScope(
                policy: AppFontPolicy.defaults(),
                child: ChangeNotifierProvider.value(
                    value: settings,
                    child: Center(
                        child: ValueListenableBuilder(
                            valueListenable: width,
                            builder: (_, value, __) => SizedBox(
                                width: value,
                                height: 600,
                                child: Builder(
                                    builder: (context) => MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                            disableAnimations: reduced),
                                        child: VerticalLyricScrollView(
                                            lyric: document,
                                            positionStream:
                                                const Stream<double>.empty(),
                                            readPosition: () => 2.3,
                                            onSeek: (_) => seeks++,
                                            playing: false,
                                            hidden: hidden,
                                            springLyrics: false)))))))),
            boundary: boundary));
        await tester.pumpAndSettle();
        settings.revealForReading(target);
        await tester.pumpAndSettle();
        final viewportFinder =
            find.byKey(const ValueKey('vertical-lyric-scroll'));
        final before = _glyphY(tester, targetLine, text, offset);
        final viewport = tester.getRect(viewportFinder);
        expect(
            before, inInclusiveRange(viewport.top + 10, viewport.bottom - 10));
        await _checkInk(tester, boundary, viewport);
        settings.setLyricLetterSpacing(3);
        await tester.pump();
        expect(_glyphY(tester, targetLine, text, offset), closeTo(before, .1),
            reason:
                'Discrete tracking reflow preserves the actual found glyph');
        settings.setShowTranslation(false);
        width.value = 360;
        await tester.pump();
        for (var frame = 0; frame < 24; frame++) {
          if (frame == 5) settings.setLyricLetterSpacing(8);
          await tester.pump(const Duration(milliseconds: 16));
          final y = _glyphY(tester, targetLine, text, offset);
          expect(y, closeTo(before, .1),
              reason: 'Content frame $frame keeps reading ownership');
          expect(y, inInclusiveRange(viewport.top, viewport.bottom));
        }
        await tester.pumpAndSettle();
        await _checkInk(tester, boundary, tester.getRect(viewportFinder));
        expect(settings.readingTarget, same(target));
        expect(settings.readingMode, isTrue);
        expect(seeks, 0);
        hidden.value = true;
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        hidden.value = false;
        await tester.pumpAndSettle();
        expect(_glyphY(tester, targetLine, text, offset), closeTo(before, .1));
        settings.returnToCurrent();
        await tester.pumpAndSettle();
        expect(settings.readingMode, isFalse);
        expect(seeks, 0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('manual reading retires the found glyph scale origin',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 720);
    final text = '${'雨に歌う reading é 밤의 노래 ' * 24}Needle 终点';
    final actualDocument = PlainLyric(text);
    final referenceDocument = PlainLyric(text);
    final actualAppearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final referenceAppearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final actualSettings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: actualAppearance)
      ..lyricTextAlign = LyricTextAlign.left;
    final referenceSettings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: referenceAppearance)
      ..lyricTextAlign = LyricTextAlign.left
      ..setReadingMode(true);
    final actual = GlobalKey(), reference = GlobalKey(), boundary = GlobalKey();
    addTearDown(actualSettings.dispose);
    addTearDown(referenceSettings.dispose);
    addTearDown(actualAppearance.dispose);
    addTearDown(referenceAppearance.dispose);
    Widget surface(
            GlobalKey key, Lyric document, LyricViewController settings) =>
        SizedBox(
          key: key,
          width: 340,
          height: 600,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: VerticalLyricScrollView(
              lyric: document,
              positionStream: const Stream<double>.empty(),
              readPosition: () => 2.3,
              onSeek: (_) =>
                  fail('Changing a reading pose cannot seek playback'),
              playing: false,
              springLyrics: false,
            ),
          ),
        );
    await tester.pumpWidget(playlistFeatureHost(
        AppFontScope(
          policy: AppFontPolicy.defaults(),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                surface(actual, actualDocument, actualSettings),
                surface(reference, referenceDocument, referenceSettings),
              ],
            ),
          ),
        ),
        boundary: boundary));
    await tester.pumpAndSettle();
    final target = LyricReadingTarget(
        actualDocument, 0, actualDocument.lines.single,
        textOffset: text.indexOf('Needle'));
    actualSettings.revealForReading(target);
    await tester.pumpAndSettle();
    Finder scroll(GlobalKey key) => find.descendant(
        of: find.byKey(key),
        matching: find.byKey(const ValueKey('vertical-lyric-scroll')));
    ScrollController controller(GlobalKey key) =>
        tester.widget<CustomScrollView>(scroll(key)).controller!;
    controller(reference).jumpTo(controller(actual).offset);
    await tester.pump();

    // Both receive the same actual wheel input. Only the left surface has
    // stale search metadata, which must no longer select the scale pivot.
    for (final key in [actual, reference]) {
      tester.binding.handlePointerEvent(PointerScrollEvent(
          position: tester.getCenter(scroll(key)),
          scrollDelta: const Offset(0, -60)));
    }
    await tester.pumpAndSettle();
    expect(actualSettings.readingTarget, same(target));
    expect(referenceSettings.readingTarget, isNull);
    expect(
        controller(actual).offset, closeTo(controller(reference).offset, .1));
    double glyphY(GlobalKey key, int offset) {
      final finder = find.descendant(
          of: find.byKey(key),
          matching: find.byWidgetPredicate((widget) =>
              widget is CustomPaint &&
              widget.painter is PlainLyricWordFollowPainter));
      final painter = tester.widget<CustomPaint>(finder).painter!
          as PlainLyricWordFollowPainter;
      final cluster = text.substring(offset).characters.first;
      final box = painter.text
          .getBoxesForSelection(TextSelection(
              baseOffset: offset, extentOffset: offset + cluster.length))
          .first;
      return tester
          .renderObject<RenderBox>(finder)
          .localToGlobal(Offset(0, box.top + painter.inkOffset.dy))
          .dy;
    }

    actualSettings.setLyricLetterSpacing(3);
    referenceSettings.setLyricLetterSpacing(3);
    await tester.pump();
    for (var frame = 0; frame < 13; frame++) {
      for (final offset in [0, text.indexOf('Needle')]) {
        expect(glyphY(actual, offset), closeTo(glyphY(reference, offset), .1),
            reason:
                'Retired search metadata cannot move the scaled native glyph '
                'at frame $frame, offset $offset');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _checkInk(tester, boundary, tester.getRect(scroll(actual)));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
