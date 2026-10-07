import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/playlist_feature_fixture.dart';

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

_Lyrics _document([String prefix = '']) => _Lyrics([
      for (var index = 0; index < 18; index++)
        LrcLine(
            Duration(seconds: 5 * (index + 1)),
            '$prefix第 $index 行 Needle 夜空を読む 밤의 노래┃Translation line $index: '
            'the distant night sky keeps the words readable.',
            isBlank: false,
            length: const Duration(seconds: 5))
          ..romanization = 'Dì $index háng · yèkōng yuedu',
    ]);

LyricReadingTarget _searchTarget(Lyric document, int index) =>
    lyricSearchRows(document,
            project: (line) => lyricReadingText(line,
                translation: true, romanization: true))[index]
        .target;

Finder _primary(LrcLine line) => find.byWidgetPredicate((widget) =>
    widget is BalancedLyricText &&
    widget.text == line.content.split('┃').first);

double _glyphY(WidgetTester tester, LrcLine line, int offset) {
  final element = tester.element(_primary(line));
  return ((element as StatefulElement).state as LyricTextReadingGeometry)
      .readingGlobalY(offset)!;
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

class _ReadingSurface extends ChangeNotifier {
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
  final hidden = ValueNotifier(false);
  final positions = StreamController<double>.broadcast(sync: true);
  _Lyrics document = _document();
  double width = 600;
  bool tickerEnabled = true;
  bool playing = false;
  double position = 0;
  var seeks = 0;

  Future<void> mount(WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 800, height: 720);
    await tester.pumpWidget(playlistFeatureHost(ChangeNotifierProvider.value(
        value: settings,
        child: Center(
            child: ListenableBuilder(
                listenable: this,
                builder: (context, _) => SizedBox(
                    width: width,
                    height: 600,
                    child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(disableAnimations: false),
                        child: TickerMode(
                            enabled: tickerEnabled,
                            child: VerticalLyricScrollView(
                                lyric: document,
                                positionStream: positions.stream,
                                readPosition: () => position,
                                onSeek: (_) => seeks++,
                                hidden: hidden,
                                playing: playing,
                                springLyrics: false)))))))));
    await tester.pumpAndSettle();
    settings.revealForReading(_searchTarget(document, 12));
    await tester.pumpAndSettle();
  }

  void change(VoidCallback action) {
    action();
    notifyListeners();
  }

  CustomScrollView getScroll(WidgetTester tester) => tester.widget(
      find.byKey(const ValueKey('vertical-lyric-scroll'), skipOffstage: false));

  Future<void> close(WidgetTester tester) async {
    expect(seeks, 0);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
    hidden.dispose();
    await positions.close();
    dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  for (final reduced in [false, true]) {
    for (final change in ['translation', 'romanization', 'timestamp']) {
      testWidgets(
          'found reading glyph survives $change content reflow reduced=$reduced',
          (tester) async {
        sizePlaylistFeature(tester, width: 800, height: 720);
        final document = _document();
        final target = document.lines[12] as LrcLine;
        final readingTarget = _searchTarget(document, 12);
        // Timed search results locate an original row, with no invented hit
        // offset. Its first shaped primary glyph is the reading anchor.
        expect(readingTarget.textOffset, isNull);
        const offset = 0;
        final settings = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}));
        addTearDown(settings.dispose);
        var seeks = 0;
        final boundary = GlobalKey();
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
                                    readPosition: () => 0,
                                    onSeek: (_) => seeks++,
                                    playing: false,
                                    springLyrics: false)))))),
            boundary: boundary));
        await tester.pumpAndSettle();
        settings.revealForReading(readingTarget);
        await tester.pumpAndSettle();
        final viewport =
            tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
        final before = _glyphY(tester, target, offset);
        expect(before, inInclusiveRange(viewport.top, viewport.bottom));
        final ink = tester.getRect(_primary(target));
        final region = Rect.fromLTRB(
            ink.left.ceilToDouble(),
            ink.top.ceilToDouble(),
            ink.right.floorToDouble(),
            ink.bottom.floorToDouble());
        final reference = await _pixels(tester, boundary, region);
        switch (change) {
          case 'translation':
            settings.setShowTranslation(false);
          case 'romanization':
            settings.setShowRomanization(false);
          case 'timestamp':
            settings.setShowTimestamps(true);
        }
        await tester.pump();
        expect(_glyphY(tester, target, offset), closeTo(before, .05),
            reason: 'Content changes must preserve the selected glyph in '
                'the first layout, even before the first lyric starts');
        for (var frame = 0; frame < 36; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(_glyphY(tester, target, offset), closeTo(before, .05),
              reason: 'Content reveal frame $frame retains the reading glyph');
          if (frame == 9) {
            expect(await _pixels(tester, boundary, region),
                orderedEquals(reference),
                reason: 'The selected primary ink stays identical mid-reveal');
          }
        }
        await tester.pumpAndSettle();
        expect(_glyphY(tester, target, offset), closeTo(before, .05));
        expect(
            await _pixels(tester, boundary, region), orderedEquals(reference),
            reason: 'The settled primary ink stays in its original pixels');
        expect(settings.readingMode, isTrue);
        expect(settings.readingTarget!.line, same(target));
        expect(seeks, 0);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final interruption in [
    'retarget',
    'width',
    'find',
    'wheel',
    'hidden',
    'ticker',
    'document',
    'return',
  ]) {
    testWidgets('reading content anchor releases for $interruption',
        (tester) async {
      final surface = _ReadingSurface();
      await surface.mount(tester);
      final original = surface.document;
      final target = original.lines[12] as LrcLine;
      final before = _glyphY(tester, target, 0);
      surface.settings.setShowTranslation(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 144));
      expect(_glyphY(tester, target, 0), closeTo(before, .05));
      final scroll = surface.getScroll(tester).controller!;
      switch (interruption) {
        case 'retarget':
          surface.settings.setShowTranslation(true);
          surface.settings.setShowRomanization(false);
          await tester.pump();
          for (var frame = 0; frame < 36; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(_glyphY(tester, target, 0), closeTo(before, .05));
          }
        case 'width':
          surface.change(() => surface.width = 320);
          await tester.pump();
          for (var frame = 0; frame < 36; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(_glyphY(tester, target, 0), closeTo(before, .05));
          }
        case 'find':
          final next = original.lines[5] as LrcLine;
          surface.settings.revealForReading(_searchTarget(original, 5));
          await tester.pumpAndSettle();
          final viewport = tester
              .getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
          expect(_glyphY(tester, next, 0),
              closeTo(viewport.top + viewport.height * .2, .05));
          expect(surface.settings.readingTarget!.line, same(next));
        case 'wheel':
          final foundOffset = scroll.offset;
          await tester.sendEventToBinding(PointerScrollEvent(
              position: tester.getCenter(
                  find.byKey(const ValueKey('vertical-lyric-scroll'))),
              scrollDelta: const Offset(0, -240)));
          await tester.pump();
          final held = scroll.offset;
          expect(held, lessThan(foundOffset - 200));
          await tester.pumpAndSettle();
          expect(scroll.offset, closeTo(held, .05));
          surface.hidden.value = true;
          await tester.pump();
          surface.hidden.value = false;
          await tester.pumpAndSettle();
          expect(scroll.offset, closeTo(held, .05),
              reason: 'Hidden return cannot revive the superseded find');
        case 'hidden':
        case 'ticker':
          if (interruption == 'hidden') {
            surface.hidden.value = true;
          } else {
            surface.change(() => surface.tickerEnabled = false);
          }
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          final pausedOffset = scroll.offset;
          await tester.pump(const Duration(seconds: 1));
          expect(scroll.offset, pausedOffset);
          if (interruption == 'hidden') {
            surface.hidden.value = false;
          } else {
            surface.change(() => surface.tickerEnabled = true);
          }
          await tester.pumpAndSettle();
          final viewport = tester
              .getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
          expect(_glyphY(tester, target, 0),
              closeTo(viewport.top + viewport.height * .2, .05));
          surface.settings.setShowTranslation(true);
          await tester.pumpAndSettle();
          expect(_glyphY(tester, target, 0),
              closeTo(viewport.top + viewport.height * .2, .05));
        case 'document':
          surface.change(() => surface.document = _document('New '));
          await tester.pumpAndSettle();
          expect(_primary(target), findsNothing);
          surface.settings.revealForReading(_searchTarget(surface.document, 3));
          await tester.pumpAndSettle();
          final current = surface.document.lines[3] as LrcLine;
          final viewport = tester
              .getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
          expect(_glyphY(tester, current, 0),
              closeTo(viewport.top + viewport.height * .2, .05));
          surface.settings.setShowTranslation(true);
          await tester.pumpAndSettle();
          expect(_glyphY(tester, current, 0),
              closeTo(viewport.top + viewport.height * .2, .05));
        case 'return':
          surface.position = 20;
          surface.positions.add(surface.position);
          await tester.pump();
          surface.settings.returnToCurrent();
          await tester.pumpAndSettle();
          expect(surface.settings.readingMode, isFalse);
          expect(surface.settings.readingTarget, isNull);
          final current = find.byWidgetPredicate((widget) =>
              widget is LyricViewTile &&
              identical(widget.line, original.lines[3]));
          final row = tester.getRect(current);
          final viewport = tester
              .getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
          expect(row.top + row.height * .34,
              closeTo(viewport.top + viewport.height * .34, .05));
      }
      await tester.pumpAndSettle();
      await surface.close(tester);
    });
  }

  testWidgets('playing line changes keep the finite reading content owner',
      (tester) async {
    final surface = _ReadingSurface()
      ..playing = true
      ..position = 20;
    await surface.mount(tester);
    final target = surface.document.lines[12] as LrcLine;
    final before = _glyphY(tester, target, 0);
    surface.settings.setShowTranslation(false);
    await tester.pump();
    for (var frame = 0; frame < 36; frame++) {
      if (frame == 8 || frame == 17) {
        surface.position = frame == 8 ? 25.2 : 35.2;
        surface.positions.add(surface.position);
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(_glyphY(tester, target, 0), closeTo(before, .05),
          reason: 'Media line changes cannot take the reading reveal owner '
              'at frame $frame');
    }
    surface.change(() => surface.playing = false);
    await tester.pumpAndSettle();
    expect(_glyphY(tester, target, 0), closeTo(before, .05));
    expect(surface.settings.readingTarget!.line, same(target));
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'The content/line transitions end after playback is paused');
    surface.settings.returnToCurrent();
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate((widget) =>
        widget is LyricViewTile &&
        identical(widget.line, surface.document.lines[6]));
    final row = tester.getRect(current);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
    expect(row.top + row.height * .34,
        closeTo(viewport.top + viewport.height * .34, .05));
    expect(surface.settings.readingMode, isFalse);
    await surface.close(tester);
  });
}
