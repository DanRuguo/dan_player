import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/playlist_feature_fixture.dart';

Qrc _document() {
  final document = Qrc.fromQrcText([
    for (var index = 0; index < 18; index++)
      '[${(index + 1) * 5000},5000]夜第$index行 Moonlight 夜空を読む 밤의 노래'
          '(${(index + 1) * 5000},4500)',
  ].join('\n'));
  for (final (index, line) in document.lines.indexed) {
    line.romanization = 'yè dì $index háng · yèkōng yuedu';
    (line as QrcLine).translation = 'Translation line $index: '
        'the distant night sky keeps the words readable.';
  }
  return document;
}

LyricReadingTarget _searchTarget(Lyric document, int index) =>
    lyricSearchRows(document,
            project: (line) => lyricReadingText(line,
                translation: true, romanization: true))[index]
        .target;

Finder _primary(QrcLine line) => find.byWidgetPredicate((widget) =>
    widget is CustomPaint &&
    widget.painter is LyricWordHighlightPainter &&
    identical((widget.painter as LyricWordHighlightPainter).line, line));

LyricWordHighlightPainter _painter(WidgetTester tester, QrcLine line) =>
    (tester.widget<CustomPaint>(_primary(line)).painter!
        as LyricWordHighlightPainter);

double _glyphY(WidgetTester tester, QrcLine line) {
  final painter = _painter(tester, line);
  // Independently observe the actual cached paragraph and mounted paint box,
  // rather than asking the reading-anchor implementation for its answer.
  final first = painter.text
      .getBoxesForSelection(TextSelection(
          baseOffset: 0, extentOffset: line.content.characters.first.length))
      .first;
  final box = tester.renderObject<RenderBox>(_primary(line));
  return box.localToGlobal(Offset(0, first.top + painter.inkOffset.dy)).dy;
}

Future<Uint8List> _pixels(
    WidgetTester tester, GlobalKey boundary, Rect region) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final rgba =
          (await image.toByteData(format: raster.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final width = region.width.toInt();
      final height = region.height.toInt();
      final result = Uint8List(width * height * 4);
      for (var row = 0; row < height; row++) {
        final source =
            ((region.top.toInt() + row) * image.width + region.left.toInt()) *
                4;
        result.setRange(row * width * 4, (row + 1) * width * 4, rgba, source);
      }
      return result;
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  for (final reduced in [false, true]) {
    for (final change in ['translation', 'romanization', 'timestamp']) {
      testWidgets(
          'QRC found primary glyph survives $change reflow reduced=$reduced',
          (tester) async {
        sizePlaylistFeature(tester, width: 800, height: 720);
        final document = _document();
        final target = document.lines[12] as QrcLine;
        final settings = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}));
        addTearDown(settings.dispose);
        final boundary = GlobalKey();
        var seeks = 0;
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
                                child: VerticalLyricScrollView(
                                    lyric: document,
                                    positionStream:
                                        const Stream<double>.empty(),
                                    readPosition: () => 2.3,
                                    onSeek: (_) => seeks++,
                                    playing: false,
                                    springLyrics: false)))))),
            boundary: boundary));
        await tester.pumpAndSettle();
        final search = _searchTarget(document, 12);
        expect(search.textOffset, isNull);
        settings.revealForReading(search);
        await tester.pumpAndSettle();
        final before = _glyphY(tester, target);
        final painter = _painter(tester, target);
        final paragraph = painter.text;
        final geometry = painter.layoutIdentity;
        final bounds = tester.getRect(_primary(target));
        final region = Rect.fromLTRB(
            bounds.left.ceilToDouble(),
            bounds.top.ceilToDouble(),
            bounds.right.floorToDouble(),
            bounds.bottom.floorToDouble());
        final reference = await _pixels(tester, boundary, region);
        expect(reference.buffer.asUint32List().toSet().length, greaterThan(8),
            reason: 'The reference contains actual multilingual glyph ink');

        switch (change) {
          case 'translation':
            settings.setShowTranslation(false);
          case 'romanization':
            settings.setShowRomanization(false);
          case 'timestamp':
            settings.setShowTimestamps(true);
        }
        await tester.pump();
        for (var frame = 0; frame < 36; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(_glyphY(tester, target), closeTo(before, .05),
              reason: 'Reveal frame $frame keeps the actual primary glyph');
          final current = _painter(tester, target);
          expect(identical(current.text, paragraph), isTrue,
              reason: 'Reading anchors do not reshape the timed paragraph');
          expect(identical(current.layoutIdentity, geometry), isTrue,
              reason: 'Content reveal reuses the timed glyph geometry');
          if (frame == 17) {
            expect(await _pixels(tester, boundary, region),
                orderedEquals(reference),
                reason: 'The complete primary ink is stable mid-transition');
          }
        }
        await tester.pumpAndSettle();
        expect(
            await _pixels(tester, boundary, region), orderedEquals(reference),
            reason: 'The complete primary ink keeps its original location');
        expect(settings.readingTarget, same(search));
        expect(seeks, 0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
