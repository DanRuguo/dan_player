import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/lyric_glyph_morph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, sizePlaylistFeature;

const _shortText = '音楽伴毎一天';
const _wrapText = '音楽伴毎一天夜空星光未来';
const _tolerance = .05;

class _Word extends SyncLyricWord {
  _Word(String text) : super(Duration.zero, const Duration(seconds: 4), text);
}

class _Line extends SyncLyricLine {
  _Line(String text)
      : super(Duration.zero, const Duration(seconds: 12), [_Word(text)]);
}

typedef _Consumer = ({
  RenderCustomPaint render,
  LyricGlyphMorphConsumer painter,
  double? alignmentX,
});

List<_Consumer> _consumers(WidgetTester tester, String text) {
  final result = <_Consumer>[];
  for (final element in find.byType(CustomPaint).evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter is! PlainLyricWordFollowPainter &&
        painter is! LyricWordHighlightPainter) {
      continue;
    }
    final consumer = painter as LyricGlyphMorphConsumer;
    if (consumer.glyphParagraph.text!.toPlainText() != text) {
      continue;
    }
    result.add((
      render: element.renderObject! as RenderCustomPaint,
      painter: consumer,
      alignmentX: switch (painter) {
        PlainLyricWordFollowPainter() => painter.alignmentX,
        LyricWordHighlightPainter() => painter.alignmentX,
        _ => null,
      },
    ));
  }
  return result;
}

_Consumer _presented(WidgetTester tester, String text) {
  final consumers = _consumers(tester, text);
  final moving = consumers.where((p) => p.painter.glyphMorph != null).toList();
  if (moving.isNotEmpty) {
    expect(moving, hasLength(1), reason: 'Only the source endpoint paints ink');
    return moving.single;
  }
  expect(consumers, hasLength(1), reason: 'A settled row has one paragraph');
  return consumers.single;
}

/// Mirrors the existing painter's line alignment for the settled paragraph.
/// Moving paragraphs already include this alignment in their glyph geometry.
List<Rect> _localBoxes(_Consumer consumer, int start, int end,
    {double? progress}) {
  final frame = consumer.painter.glyphMorph;
  if (frame != null) {
    return frame.geometry.boxes(start, end, progress ?? frame.progress);
  }
  final paragraph = consumer.painter.glyphParagraph;
  final lines = paragraph.computeLineMetrics();
  return [
    for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end)))
      if (consumer.alignmentX == null || consumer.alignmentX! <= -1)
        box.toRect()
      else
        box.toRect().shift(Offset(
            lyricAlignedOffset(
                paragraph.width,
                lines
                    .reduce((a, b) => (a.baseline - a.ascent - box.top).abs() <
                            (b.baseline - b.ascent - box.top).abs()
                        ? a
                        : b)
                    .width,
                consumer.alignmentX!),
            0)),
  ];
}

/// Capture immutable viewport rectangles, including the real parent transforms,
/// paragraph origin and its ink guard. Reading only a CustomPaint's box would
/// miss a retarget that retained glyphs in the preceding source's coordinates.
List<Rect> _viewportGlyphs(_Consumer consumer, String text,
    {double? progress}) {
  final result = <Rect>[];
  var start = 0;
  for (final cluster in text.characters) {
    final end = start + cluster.length;
    final boxes = _localBoxes(consumer, start, end, progress: progress);
    expect(boxes, isNotEmpty, reason: 'The actual character $cluster has ink');
    Rect? global;
    for (final box in boxes) {
      final origin = consumer.painter.glyphInkOffset;
      final first = consumer.render.localToGlobal(box.topLeft + origin);
      final last = consumer.render.localToGlobal(box.bottomRight + origin);
      final rectangle = Rect.fromPoints(first, last);
      expect(rectangle.width, greaterThan(0));
      expect(rectangle.height, greaterThan(0));
      global = global == null ? rectangle : global.expandToInclude(rectangle);
    }
    result.add(global!);
    start = end;
  }
  return List.unmodifiable(result);
}

void _sameGlyphs(List<Rect> actual, List<Rect> expected, String reason) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    final a = actual[index], e = expected[index];
    expect(a.center.dx, closeTo(e.center.dx, _tolerance),
        reason: '$reason: character $index viewport X');
    expect(a.center.dy, closeTo(e.center.dy, _tolerance),
        reason: '$reason: character $index viewport Y');
    expect(a.top, closeTo(e.top, _tolerance),
        reason: '$reason: character $index top ink geometry');
    expect(a.bottom, closeTo(e.bottom, _tolerance),
        reason: '$reason: character $index bottom ink geometry');
    expect(a.width, closeTo(e.width, _tolerance),
        reason: '$reason: character $index glyph extent');
  }
}

double _movement(List<Rect> from, List<Rect> to) => [
      for (var index = 0; index < from.length; index++)
        (to[index].center - from[index].center).distance,
    ].reduce(math.max);

Widget _host({
  required LyricViewController controller,
  required LyricLine line,
  required ValueNotifier<Duration> position,
  required ValueNotifier<double> width,
  required GlobalKey boundary,
  required Key tileKey,
}) {
  final policy = AppFontPolicy.defaults();
  return MaterialApp(
    theme: ThemeData(
      fontFamily: policy.uiFamily,
      fontFamilyFallback: policy.fallback,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    ),
    home: AppFontScope(
      policy: policy,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: ChangeNotifierProvider.value(
            value: controller,
            child: RepaintBoundary(
              key: boundary,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, value, __) => SizedBox(
                  width: value,
                  child: LyricViewTile(
                    key: tileKey,
                    line: line,
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
  );
}

void main({bool onlyRender = false, String onlyCase = ''}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output != null && output.isNotEmpty) {
      final absolute = Directory(output).absolute.path.replaceAll('\\', '/');
      expect(absolute, contains('/tool/qa-local/'));
    }
    await loadLetterSpacingFonts();
  });

  // All three cases use the real rendered paragraph and may run in the native
  // onlyRender wrapper. Keep the same registration/filter contract as that UI.
  void register(String name, WidgetTesterCallback body, {bool render = true}) {
    if ((onlyRender && !render) ||
        (onlyCase.isNotEmpty && !name.contains(onlyCase))) {
      return;
    }
    testWidgets(name, body);
  }

  for (final (timed, alignment) in [
    (false, LyricTextAlign.center),
    (true, LyricTextAlign.right),
  ]) {
    register(
        'spacing retarget keeps viewport glyphs continuous '
        'timed=$timed align=${alignment.name}', (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 600);
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance,
      )
        ..lyricFontSize = 32
        ..lyricTextAlign = alignment;
      // Finish playback/follow before beginning the geometry-only transition;
      // this does not disable existing word emphasis to make a pixel test pass.
      final position = ValueNotifier(const Duration(seconds: 20));
      final width = ValueNotifier(600.0);
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(position.dispose);
      addTearDown(width.dispose);
      final LyricLine line = timed
          ? _Line(_shortText)
          : LrcLine(Duration.zero, _shortText, isBlank: false);
      final boundary = GlobalKey();
      Widget build(Key tileKey) => _host(
          controller: controller,
          line: line,
          position: position,
          width: width,
          boundary: boundary,
          tileKey: tileKey);
      await tester.pumpWidget(build(const ValueKey('retained')));
      await tester.pumpAndSettle();
      final warm = _viewportGlyphs(_presented(tester, _shortText), _shortText);
      controller.setLyricLetterSpacing(8);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final presented = _presented(tester, _shortText);
      expect(
          presented.painter.glyphMorph!.progress, inExclusiveRange(0.0, 1.0));
      final before = _viewportGlyphs(presented, _shortText);
      expect(_movement(warm, before), greaterThan(.2));
      await capturePlaylistFeature(
          tester, boundary, 'retarget-$timed-${alignment.name}-before');

      controller.setLyricLetterSpacing(2);
      await tester.pump(); // First presented frame, with no elapsed media time.
      final reversed = _presented(tester, _shortText);
      expect(reversed.painter.glyphMorph!.progress, 0);
      final first = _viewportGlyphs(reversed, _shortText);
      _sameGlyphs(first, before, 'Rapid reversal starts at the visible glyphs');
      await capturePlaylistFeature(
          tester, boundary, 'retarget-$timed-${alignment.name}-first');
      await tester.pump(const Duration(milliseconds: 40));
      final middle =
          _viewportGlyphs(_presented(tester, _shortText), _shortText);
      expect(_movement(first, middle), greaterThan(.1),
          reason: 'The reversed transition continues rather than snapping');
      await capturePlaylistFeature(
          tester, boundary, 'retarget-$timed-${alignment.name}-mid');
      await tester.pumpAndSettle();
      final settled =
          _viewportGlyphs(_presented(tester, _shortText), _shortText);
      expect(_presented(tester, _shortText).painter.glyphMorph, isNull);
      await capturePlaylistFeature(
          tester, boundary, 'retarget-$timed-${alignment.name}-end');

      await tester.pumpWidget(build(const ValueKey('fresh-target')));
      await tester.pumpAndSettle();
      _sameGlyphs(
          settled,
          _viewportGlyphs(_presented(tester, _shortText), _shortText),
          'Settled retarget matches a fresh paragraph with spacing 2');
      expect(position.value, const Duration(seconds: 20));
      expect(controller.lyricLetterSpacing, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  register('spacing flight resize refreshes retained target wrap geometry',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 600);
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap({}),
      appearance: appearance,
    )
      ..lyricFontSize = 32
      ..lyricTextAlign = LyricTextAlign.center;
    final position = ValueNotifier(const Duration(seconds: 20));
    final width = ValueNotifier(720.0);
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(position.dispose);
    addTearDown(width.dispose);
    final line = LrcLine(Duration.zero, _wrapText, isBlank: false);
    final boundary = GlobalKey();
    Widget build(Key tileKey) => _host(
        controller: controller,
        line: line,
        position: position,
        width: width,
        boundary: boundary,
        tileKey: tileKey);
    await tester.pumpWidget(build(const ValueKey('retained')));
    await tester.pumpAndSettle();
    controller.setLyricLetterSpacing(8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final oldTarget = _consumers(tester, _wrapText)
        .singleWhere((p) => p.painter.glyphMorph == null);
    final retainedParagraph = oldTarget.painter.glyphParagraph;
    final oldIdentity = oldTarget.painter.glyphLayoutIdentity;
    expect(retainedParagraph.computeLineMetrics(), hasLength(1));

    width.value = 300;
    await tester.pump();
    final source = _presented(tester, _wrapText);
    final target = _consumers(tester, _wrapText)
        .singleWhere((p) => p.painter.glyphMorph == null);
    expect(target.painter.glyphParagraph, same(retainedParagraph),
        reason: 'The real width-only consumer retains native shaping');
    expect(target.painter.glyphLayoutIdentity, isNot(oldIdentity),
        reason: 'Mutable TextPainter identity cannot identify a wrap snapshot');
    expect(target.painter.glyphParagraph.computeLineMetrics().length,
        greaterThan(1));
    final frame = source.painter.glyphMorph!;
    expect(frame.progress, inExclusiveRange(0.0, 1.0));
    _sameGlyphs(
        _viewportGlyphs(source, _wrapText, progress: 1),
        _viewportGlyphs(target, _wrapText),
        'The ongoing glyph geometry targets the newly wrapped paragraph');
    final resized = _viewportGlyphs(source, _wrapText);
    await capturePlaylistFeature(tester, boundary, 'retarget-resize-first');
    await tester.pump(const Duration(milliseconds: 40));
    expect(
        _movement(
            resized, _viewportGlyphs(_presented(tester, _wrapText), _wrapText)),
        greaterThan(.1));
    await capturePlaylistFeature(tester, boundary, 'retarget-resize-mid');
    await tester.pumpAndSettle();
    final settled = _viewportGlyphs(_presented(tester, _wrapText), _wrapText);
    await capturePlaylistFeature(tester, boundary, 'retarget-resize-end');
    await tester.pumpWidget(build(const ValueKey('fresh-target')));
    await tester.pumpAndSettle();
    _sameGlyphs(
        settled,
        _viewportGlyphs(_presented(tester, _wrapText), _wrapText),
        'A width-retargeted flight settles to fresh wrapped geometry');
    expect(position.value, const Duration(seconds: 20));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
