import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _primary = 'Moonlight';
const _translation =
    'A long translation beneath the short lyric wraps in a narrow window';

class _LyricHarness {
  _LyricHarness(this.settings);

  final LyricViewController settings;
}

Future<_LyricHarness> _mount(WidgetTester tester,
    {bool reducedMotion = false}) async {
  final settings = LyricViewController(
    preferences: NowPlayingPagePreference.fromMap(const {
      'lyricTextAlign': 'left',
      'lyricFontSize': 22,
      'translationFontSize': 18,
      'showLyricTimestamps': true,
      'showLyricTranslation': true,
      'showLyricRomanization': false,
    }),
  );
  final position = ValueNotifier(Duration.zero);
  final line = LrcLine(
    const Duration(seconds: 16, milliseconds: 570),
    '$_primary┃$_translation',
    isBlank: false,
  );
  addTearDown(() {
    settings.dispose();
    position.dispose();
  });

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: danEmbeddedFontFamily),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 420,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: LyricViewTile(
              line: line,
              position: position,
              opacity: 1,
              distance: 0,
              reducedMotion: reducedMotion,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return _LyricHarness(settings);
}

Rect _timestamp(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('lyric-line-timestamp')));

Rect _primaryRect(WidgetTester tester) {
  final paragraph = find.byWidgetPredicate(
      (widget) => widget is BalancedLyricText && widget.text == _primary);
  final paint =
      find.descendant(of: paragraph, matching: find.byType(CustomPaint));
  final custom = tester.widget<CustomPaint>(paint.first);
  final painter = custom.painter! as PlainLyricWordFollowPainter;
  final line = painter.text.computeLineMetrics().first;
  final fraction = ((painter.alignmentX! + 1) / 2).clamp(0.0, 1.0);
  final box = tester.getRect(paint.first);
  final left = box.left +
      painter.inkOffset.dx +
      (painter.text.width - line.width) * fraction;
  return Rect.fromLTWH(left, box.top, line.width, line.height);
}

List<double> _fontSizes(WidgetTester tester, String text) => tester
    .widgetList<BalancedLyricText>(find.byType(BalancedLyricText))
    .where((widget) => widget.text == text)
    .map((widget) => widget.style.fontSize!)
    .toList()
  ..sort();

Element _paragraphElement(WidgetTester tester, String text, double fontSize) =>
    tester.element(find.byWidgetPredicate((widget) =>
        widget is BalancedLyricText &&
        widget.text == text &&
        (widget.style.fontSize! - fontSize).abs() < .01));

void _expectSingleSettledParagraph(WidgetTester tester) {
  final morphs = tester.widgetList<LyricFontMorph>(find.byType(LyricFontMorph));
  expect(morphs.length, 2);
  expect(morphs.every((morph) => morph.children.length == 1), isTrue,
      reason: 'Idle lyric rows retain only one shaped paragraph');
}

double _morphProgress(WidgetTester tester, String text) {
  final paragraph = find.byWidgetPredicate(
      (widget) => widget is BalancedLyricText && widget.text == text);
  final morph =
      find.ancestor(of: paragraph.first, matching: find.byType(LyricFontMorph));
  return tester.widget<LyricFontMorph>(morph.first).progress;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  test('reflow handoff avoids two legible copies of the same words', () {
    final growingMidway = lyricFontBlendOpacities(.5, 52, 96);
    expect(growingMidway.outgoing, closeTo(1, .001));
    expect(growingMidway.incoming, closeTo(0, .001));
    final growingNearEnd = lyricFontBlendOpacities(.94, 52, 96);
    expect(growingNearEnd.outgoing, lessThan(.4));
    expect(growingNearEnd.incoming, greaterThan(.3));
    final growingEnd = lyricFontBlendOpacities(.99, 52, 96);
    expect(growingEnd.outgoing, closeTo(0, .001));
    expect(growingEnd.incoming, closeTo(1, .001));
    final shrinkingEarly = lyricFontBlendOpacities(.1, 96, 52);
    expect(shrinkingEarly.outgoing, lessThan(.3));
    expect(shrinkingEarly.incoming, greaterThan(.2));
    final shrinkingMidway = lyricFontBlendOpacities(.5, 96, 52);
    expect(shrinkingMidway.outgoing, closeTo(0, .001));
    expect(shrinkingMidway.incoming, closeTo(1, .001));
    final unwrapped = lyricFontBlendOpacities(.5, 52, 55);
    expect(unwrapped.outgoing, closeTo(1, .001));
    expect(unwrapped.incoming, closeTo(0, .001));
    final unwrappedHandoff = lyricFontBlendOpacities(.85, 52, 55);
    expect(unwrappedHandoff.outgoing, inExclusiveRange(0, 1));
    expect(unwrappedHandoff.incoming, inExclusiveRange(0, 1));
    final unwrappedEnd = lyricFontBlendOpacities(.99, 52, 55);
    expect(unwrappedEnd.outgoing, closeTo(0, .001));
    expect(unwrappedEnd.incoming, closeTo(1, .001));
    final movingSuffix =
        lyricFontBlendOpacities(.94, 52, 96, lateHandoff: true);
    expect(movingSuffix.outgoing, 1);
    expect(movingSuffix.incoming, 0);
    final alignedHandoff =
        lyricFontBlendOpacities(.99, 52, 96, lateHandoff: true);
    expect(alignedHandoff.outgoing, inExclusiveRange(0, 1));
    expect(alignedHandoff.incoming, inExclusiveRange(0, 1));
  });

  testWidgets('font morph aligns unequal endpoint widths before handoff',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            child: LyricFontMorph(
              progress: .5,
              alignmentX: 1,
              children: [
                SizedBox(
                    key: ValueKey('short-endpoint'), width: 100, height: 40),
                SizedBox(
                    key: ValueKey('wide-endpoint'), width: 200, height: 40),
              ],
            ),
          ),
        ),
      ),
    ));
    final morph = tester.getRect(find.byType(LyricFontMorph));
    final short = tester.getRect(find.byKey(const ValueKey('short-endpoint')));
    final wide = tester.getRect(find.byKey(const ValueKey('wide-endpoint')));
    expect(short.right, closeTo(morph.right, .01));
    expect(wide.right, closeTo(morph.right, .01));
  });

  testWidgets('timestamp follows the primary lyric at all three alignments',
      (tester) async {
    final harness = await _mount(tester);

    void expectSameEdge(LyricTextAlign alignment) {
      final time = _timestamp(tester);
      final lyric = _primaryRect(tester);
      final (timeEdge, lyricEdge) = switch (alignment) {
        LyricTextAlign.left => (time.left, lyric.left),
        LyricTextAlign.center => (time.center.dx, lyric.center.dx),
        LyricTextAlign.right => (time.right, lyric.right),
      };
      expect(timeEdge, closeTo(lyricEdge, 12));
    }

    expectSameEdge(LyricTextAlign.left);
    double paragraphHeight(String text) {
      final paragraph = find.byWidgetPredicate(
          (widget) => widget is BalancedLyricText && widget.text == text);
      return tester
          .getSize(find
              .descendant(of: paragraph, matching: find.byType(CustomPaint))
              .first)
          .height;
    }

    expect(
        paragraphHeight(_translation), greaterThan(paragraphHeight(_primary)),
        reason: 'The auxiliary line should exercise the narrow, wrapped case');
    harness.settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    expectSameEdge(LyricTextAlign.center);
    harness.settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    expectSameEdge(LyricTextAlign.right);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alignment moves through intermediate positions without snapping',
      (tester) async {
    final harness = await _mount(tester);
    final left = _timestamp(tester).center.dx;
    final primaryLeft = _primaryRect(tester).center.dx;
    harness.settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    final center = _timestamp(tester).center.dx;
    final primaryCenter = _primaryRect(tester).center.dx;
    expect(center, greaterThan(left + 25));

    // Return to the left endpoint so this transition has a known interval.
    harness.settings.switchLyricTextAlign();
    harness.settings.switchLyricTextAlign();
    await tester.pumpAndSettle();
    expect(_timestamp(tester).center.dx, closeTo(left, 1));

    harness.settings.switchLyricTextAlign();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final midway = _timestamp(tester).center.dx;
    expect(midway, greaterThan(left + 3));
    expect(midway, lessThan(center - 3));
    final primaryMidway = _primaryRect(tester).center.dx;
    expect(primaryMidway, greaterThan(primaryLeft + 3));
    expect(primaryMidway, lessThan(primaryCenter - 3));

    // A new target starts from the painted midpoint rather than teleporting.
    harness.settings.switchLyricTextAlign();
    await tester.pump();
    expect(_timestamp(tester).center.dx, closeTo(midway, 1));
    await tester.pumpAndSettle();
    expect(_timestamp(tester).center.dx, greaterThan(center + 25));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'font animation retains fixed endpoint glyph layouts while blending',
      (tester) async {
    final harness = await _mount(tester);
    List<double> primarySizes() => [
          for (final size in _fontSizes(tester, _primary))
            size / LyricMotion.focusedFontScale,
        ];
    List<double> translationSizes() => _fontSizes(tester, _translation);

    expect(primarySizes(), [closeTo(22, .01)]);
    expect(translationSizes(), [closeTo(18, .01)]);
    _expectSingleSettledParagraph(tester);
    Offset primaryInkOrigin(double size) {
      final paragraph = find.byWidgetPredicate((widget) =>
          widget is BalancedLyricText &&
          widget.text == _primary &&
          (widget.style.fontSize! - size).abs() < .01);
      final paint =
          find.descendant(of: paragraph, matching: find.byType(CustomPaint));
      return tester
          .renderObject<RenderBox>(paint.first)
          .localToGlobal(Offset.zero);
    }

    final initialInkOrigin =
        primaryInkOrigin(22 * LyricMotion.focusedFontScale);
    harness.settings.increaseFontSize();
    await tester.pump();
    expect(
        primaryInkOrigin(22 * LyricMotion.focusedFontScale), initialInkOrigin,
        reason: 'Font motion must not shift the paragraph layout origin');
    await tester.pump(const Duration(milliseconds: 160));
    expect(primarySizes(), [closeTo(22, .01), closeTo(23, .01)]);
    expect(translationSizes(), [closeTo(18, .01), closeTo(19, .01)]);
    expect(_morphProgress(tester, _primary), inExclusiveRange(0, 1));
    expect(_morphProgress(tester, _translation), inExclusiveRange(0, 1));
    final growingPrimary =
        _paragraphElement(tester, _primary, 23 * LyricMotion.focusedFontScale);
    final growingTranslation = _paragraphElement(tester, _translation, 19);
    await tester.pumpAndSettle();
    expect(primarySizes(), [closeTo(23, .01)]);
    expect(translationSizes(), [closeTo(19, .01)]);
    _expectSingleSettledParagraph(tester);
    expect(
        _paragraphElement(tester, _primary, 23 * LyricMotion.focusedFontScale),
        same(growingPrimary));
    expect(
        _paragraphElement(tester, _translation, 19), same(growingTranslation));

    harness.settings.decreaseFontSize();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(primarySizes(), [closeTo(22, .01), closeTo(23, .01)]);
    expect(translationSizes(), [closeTo(18, .01), closeTo(19, .01)]);
    final shrinkingPrimary =
        _paragraphElement(tester, _primary, 22 * LyricMotion.focusedFontScale);
    final shrinkingTranslation = _paragraphElement(tester, _translation, 18);
    await tester.pumpAndSettle();
    expect(primarySizes(), [closeTo(22, .01)]);
    expect(translationSizes(), [closeTo(18, .01)]);
    _expectSingleSettledParagraph(tester);
    expect(
        _paragraphElement(tester, _primary, 22 * LyricMotion.focusedFontScale),
        same(shrinkingPrimary));
    expect(_paragraphElement(tester, _translation, 18),
        same(shrinkingTranslation));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a font change across a wrap threshold moves the next row evenly',
      (tester) async {
    const lyric = '音もない世界、何を見てるの?';
    final renderDirectory = Platform.environment['DAN_WRAP_RENDER'];
    final boundary = GlobalKey();
    if (renderDirectory != null) {
      Directory(renderDirectory).createSync(recursive: true);
    }
    Future<void> record(int frame) async {
      if (renderDirectory == null) return;
      final bytes = (await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
        try {
          return await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
        }
      }))!;
      File('$renderDirectory/${frame.toString().padLeft(3, '0')}.png')
          .writeAsBytesSync(bytes.buffer.asUint8List());
    }

    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricTextAlign': 'left',
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': false,
        'showLyricTranslation': false,
        'showLyricRomanization': false,
      }),
    );
    final position = ValueNotifier(Duration.zero);
    addTearDown(() {
      settings.dispose();
      position.dispose();
    });

    double singleLineWidth(double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: lyric,
          style: const TextStyle(
            fontFamily: danEmbeddedFontFamily,
            fontWeight: LyricMotion.focusedFontWeight,
            height: 1.3,
          ).copyWith(fontSize: size * LyricMotion.focusedFontScale),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // The ink guard is 7 px at both sizes; the tile has 12 px side padding.
    final sourceWidth = singleLineWidth(22);
    final targetWidth = singleLineWidth(23);
    expect(targetWidth, greaterThan(sourceWidth + 1));
    final tileWidth = (sourceWidth + targetWidth) / 2 + 24 + 14;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: tileWidth,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: RepaintBoundary(
                key: boundary,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LyricViewTile(
                      key: const ValueKey('wrap-line'),
                      line: LrcLine(Duration.zero, lyric, isBlank: false),
                      position: position,
                      opacity: 1,
                      distance: 0,
                      reducedMotion: false,
                    ),
                    LyricViewTile(
                      key: const ValueKey('following-line'),
                      line: LrcLine(const Duration(seconds: 5), 'またねを言える顔を探すよ',
                          isBlank: false),
                      position: position,
                      opacity: 1,
                      distance: 1,
                      reducedMotion: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    List<int> lineCounts() {
      final paragraph = find.byWidgetPredicate(
          (widget) => widget is BalancedLyricText && widget.text == lyric);
      return [
        for (final widget in tester.widgetList<CustomPaint>(
            find.descendant(of: paragraph, matching: find.byType(CustomPaint))))
          if (widget.painter is PlainLyricWordFollowPainter)
            (widget.painter! as PlainLyricWordFollowPainter)
                .text
                .computeLineMetrics()
                .length,
      ];
    }

    LyricWrapFlight? movingSuffix() {
      final paragraph = find.byWidgetPredicate(
          (widget) => widget is BalancedLyricText && widget.text == lyric);
      for (final widget in tester.widgetList<CustomPaint>(
          find.descendant(of: paragraph, matching: find.byType(CustomPaint)))) {
        if (widget.painter case PlainLyricWordFollowPainter painter) {
          if (painter.wrapFlight case final flight?) return flight;
        }
      }
      return null;
    }

    double nextTop() =>
        tester.getTopLeft(find.byKey(const ValueKey('following-line'))).dy;

    expect(lineCounts(), [1]);
    await record(-1);
    final before = nextTop();
    settings.increaseFontSize();
    await tester.pump();
    final tops = <double>[before, nextTop()];
    final suffixPositions = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      tops.add(nextTop());
      final suffix = movingSuffix();
      if (suffix != null) suffixPositions.add(suffix.offset.dy);
      if (frame % 3 == 0) await record(frame);
      if (frame == 10) {
        expect(lineCounts(), containsAll([1, 2]));
        expect(suffix, isNotNull,
            reason: 'A wrapped trailing phrase should move as one block');
      }
    }
    await tester.pumpAndSettle();
    await record(40);
    tops.add(nextTop());
    expect(lineCounts(), [2]);
    expect(tops.last - tops.first, greaterThan(20));
    final largestStep = [
      for (var i = 1; i < tops.length; i++) (tops[i] - tops[i - 1]).abs(),
    ].reduce((a, b) => a > b ? a : b);
    expect(largestStep, lessThan(12),
        reason: 'A second visual line must not move the next row in one frame');
    expect(suffixPositions.length, greaterThan(8));
    expect(suffixPositions.last, greaterThan(suffixPositions.first + 10));
    for (var index = 1; index < suffixPositions.length; index++) {
      expect(suffixPositions[index],
          greaterThanOrEqualTo(suffixPositions[index - 1]));
    }

    settings.decreaseFontSize();
    await tester.pump();
    final reverseTop = nextTop();
    await record(100);
    final reverseSuffixPositions = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (movingSuffix() case final suffix?) {
        reverseSuffixPositions.add(suffix.offset.dy);
      }
      if (frame % 3 == 0) await record(101 + frame);
    }
    expect(nextTop(), lessThan(reverseTop));
    expect(reverseSuffixPositions.length, greaterThan(8));
    for (var index = 1; index < reverseSuffixPositions.length; index++) {
      expect(reverseSuffixPositions[index],
          lessThanOrEqualTo(reverseSuffixPositions[index - 1]));
    }
    await tester.pumpAndSettle();
    expect(nextTop(), closeTo(before, 1));
    expect(lineCounts(), [1]);

    settings.increaseFontSize();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final interruptedTop = nextTop();
    settings.decreaseFontSize();
    await tester.pump();
    expect(nextTop(), closeTo(interruptedTop, 2),
        reason: 'A rapid reversal must start at the visible row height');
    await tester.pumpAndSettle();
    expect(nextTop(), closeTo(before, 1));
    expect(lineCounts(), [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-to-three-line lyrics keep the ordinary handoff',
      (tester) async {
    const lyric = '音もない世界、何を見てるの?音もない世界、何を見てるの?';
    double fullWidth(double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: lyric,
          style: TextStyle(
            fontFamily: danEmbeddedFontFamily,
            fontSize: size * LyricMotion.focusedFontScale,
            fontWeight: LyricMotion.focusedFontWeight,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.maxIntrinsicWidth;
      painter.dispose();
      return width;
    }

    final tileWidth = (fullWidth(22) + fullWidth(23)) / 4 + 38;
    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricTextAlign': 'left',
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': false,
        'showLyricTranslation': false,
        'showLyricRomanization': false,
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
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: tileWidth,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: LyricViewTile(
                line: LrcLine(Duration.zero, lyric, isBlank: false),
                position: position,
                opacity: 1,
                distance: 0,
                reducedMotion: false,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    List<int> lineCounts() => [
          for (final custom in tester.widgetList<CustomPaint>(find.descendant(
              of: find.byWidgetPredicate((widget) =>
                  widget is BalancedLyricText && widget.text == lyric),
              matching: find.byType(CustomPaint))))
            if (custom.painter is PlainLyricWordFollowPainter)
              (custom.painter! as PlainLyricWordFollowPainter)
                  .text
                  .computeLineMetrics()
                  .length,
        ];
    expect(lineCounts(), [2]);
    settings.increaseFontSize();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(lineCounts(), [2, 3]);
    final morph = tester.widget<LyricFontMorph>(find.byType(LyricFontMorph));
    expect(morph.wrapStatus?.active, isFalse,
        reason: 'A short-suffix handoff applies only to one/two-line reflow');
    await tester.pumpAndSettle();
    expect(lineCounts(), [3]);
  });
}
