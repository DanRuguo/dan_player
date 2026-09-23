import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_follow_words.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(String text) : super(Duration.zero, const Duration(seconds: 5), text);
}

class _TimedLine extends SyncLyricLine {
  _TimedLine(String text, String translation)
      : super(Duration.zero, const Duration(seconds: 5), [_Word(text)],
            translation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  const japanese = '音もない世界、何を見てるの？';
  const chinese = '寂静无比的世界，你到底看见了什么？';
  const romaji = 'o to mo na i se ka i、 na ni wo mi te ru no ?';
  const western =
      'and I’m home beyond the horizon, still waiting for tomorrow?';

  for (final timed in [false, true]) {
    for (final width in [592.0, 270.0]) {
      testWidgets(
          'final active layout wraps complete Japanese punctuation and translation '
          'timed=$timed width=$width', (tester) async {
        final settings = LyricViewController()
          ..lyricFontSize = 22
          ..translationFontSize = 18;
        final clock = AnimationController(
            vsync: tester, duration: LyricMotion.springScrollDuration);
        final position = ValueNotifier(const Duration(seconds: 2));
        final line = timed
            ? (_TimedLine(japanese, chinese)..romanization = romaji)
            : LrcLine(Duration.zero, '$japanese┃$chinese',
                length: const Duration(seconds: 5), isBlank: false);

        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: danEmbeddedFontFamily),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ChangeNotifierProvider.value(
                  value: settings,
                  child: LyricWordFollowScope(
                    follow: LyricWordFollow(
                        clock,
                        LyricMotion.scrollCurveFor(spring: true, distance: 160),
                        160),
                    child: LyricViewTile(
                      line: line,
                      position: position,
                      opacity: 1,
                      reducedMotion: false,
                      distance: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        final primary = find.byWidgetPredicate((widget) {
          if (widget is! CustomPaint) return false;
          final painter = widget.painter;
          return painter is LyricWordHighlightPainter ||
              (painter is PlainLyricWordFollowPainter &&
                  painter.text.text?.toPlainText() == japanese);
        });
        expect(primary, findsOneWidget);
        final primaryPaint = tester.widget<CustomPaint>(primary).painter!;
        final paintSize = tester.getSize(primary);
        final lastGlyph = primaryPaint is PlainLyricWordFollowPainter
            ? primaryPaint.slots.last.boxes.last
                .toRect()
                .shift(primaryPaint.inkOffset)
            : (primaryPaint as LyricWordHighlightPainter)
                .followStationaryWordBounds
                .last;

        expect(paintSize.width, lessThanOrEqualTo(width - 24 + .1));
        expect(lastGlyph.left, greaterThanOrEqualTo(3));
        expect(lastGlyph.top, greaterThanOrEqualTo(2));
        expect(lastGlyph.right, lessThanOrEqualTo(paintSize.width - 3),
            reason: 'The final punctuation needs source ink room at its edge');
        expect(lastGlyph.bottom, lessThanOrEqualTo(paintSize.height - 3));
        if (primaryPaint is PlainLyricWordFollowPainter) {
          expect(primaryPaint.text.text?.style?.fontSize,
              22 * LyricMotion.focusedFontScale);
          expect(primaryPaint.text.text?.style?.fontWeight,
              LyricMotion.focusedFontWeight);
          expect(primaryPaint.text.computeLineMetrics().length,
              width < 300 ? greaterThan(1) : 1);
        } else {
          // The final punctuation must move to a following line only when the
          // actual focused-font paragraph no longer fits the available width.
          final bounds = (primaryPaint as LyricWordHighlightPainter)
              .followStationaryWordBounds;
          expect(bounds.length, width < 300 ? greaterThan(1) : 1);
        }

        final translation = find.text(chinese);
        expect(translation, findsOneWidget);
        final paragraphs =
            find.descendant(of: translation, matching: find.byType(RichText));
        final translationRender =
            tester.renderObject<RenderParagraph>(paragraphs);
        expect(translationRender.didExceedMaxLines, isFalse);
        expect(
            translationRender.size.width, lessThanOrEqualTo(width - 24 + .1));
        if (timed) {
          final romanization = find.text(romaji);
          expect(romanization, findsOneWidget);
          final romanRender = tester.renderObject<RenderParagraph>(find
              .descendant(of: romanization, matching: find.byType(RichText)));
          expect(romanRender.didExceedMaxLines, isFalse);
        }

        final secondaryPainters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<PlainLyricWordFollowPainter>()
            .where((painter) => painter.text.text?.toPlainText() != japanese)
            .toList();
        expect(secondaryPainters, hasLength(timed ? 2 : 1));
        expect(
            secondaryPainters
                .map((painter) => painter.text.text?.style?.fontFamily),
            everyElement(danEmbeddedFontFamily));
        for (final painter in secondaryPainters) {
          expect(painter.follow?.clock, same(clock));
          expect(painter.slots.length, greaterThan(1));
          final paint = find.byWidgetPredicate((widget) =>
              widget is CustomPaint && identical(widget.painter, painter));
          final size = tester.getSize(paint);
          for (final slot in painter.slots) {
            for (final box in slot.boxes) {
              final ink = box.toRect().shift(painter.inkOffset);
              expect(ink.left, greaterThanOrEqualTo(3));
              expect(ink.right, lessThanOrEqualTo(size.width - 3));
            }
          }
        }

        final beforeSize = tester.getSize(primary);
        for (final phase in [.25, .55, .82, 1.0]) {
          clock.value = phase;
          await tester.pump();
          expect(tester.getSize(primary), beforeSize,
              reason: 'Follow motion cannot change the paragraph wrap width');
          expect(lastGlyph.right, lessThanOrEqualTo(paintSize.width - 3));
          for (final painter in secondaryPainters) {
            final first = painter.slots.first;
            final offset = painter.follow!
                .offset(first.phase, settings.translationFontSize);
            expect(offset.abs(), phase == 1 ? 0 : greaterThan(.1),
                reason: 'Secondary lines share the main finite follow clock');
            expect(
                painter.follow!.offset(
                    painter.slots.last.phase, settings.translationFontSize),
                0);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        clock.dispose();
        position.dispose();
        settings.dispose();
      });
    }
  }

  testWidgets('Latin words wrap at the focused size rather than after scale',
      (tester) async {
    final settings = LyricViewController()..lyricFontSize = 24;
    final position = ValueNotifier(Duration.zero);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: LyricViewTile(
              line: LrcLine(Duration.zero, western, isBlank: false),
              position: position,
              opacity: 1,
              reducedMotion: true,
              distance: 0,
            ),
          ),
        ),
      ),
    ));
    final text =
        tester.widget<BalancedLyricText>(find.byType(BalancedLyricText));
    expect(text.style.fontSize, 24 * LyricMotion.focusedFontScale);
    final rich = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.text(western), matching: find.byType(RichText)));
    expect(
        rich
            .getBoxesForSelection(const TextSelection(
                baseOffset: 0, extentOffset: western.length))
            .length,
        greaterThan(1));
    expect(rich.didExceedMaxLines, isFalse);
    expect(rich.size.width, lessThanOrEqualTo(276.1));
    settings.dispose();
    position.dispose();
  });

  testWidgets('inactive or reduced secondary lines use no follow painter',
      (tester) async {
    final settings = LyricViewController();
    final position = ValueNotifier(const Duration(seconds: 2));
    final clock = AnimationController(
        vsync: tester, duration: LyricMotion.springScrollDuration);
    final line = _TimedLine(japanese, chinese)..romanization = romaji;
    Widget host({required int distance, required bool reducedMotion}) =>
        MaterialApp(
          theme: ThemeData(fontFamily: danEmbeddedFontFamily),
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: settings,
              child: LyricWordFollowScope(
                follow: LyricWordFollow(clock, LyricMotion.scrollCurve, 80),
                child: LyricViewTile(
                  line: line,
                  position: position,
                  opacity: 1,
                  distance: distance,
                  reducedMotion: reducedMotion,
                ),
              ),
            ),
          ),
        );
    void expectStaticSecondary() {
      final secondary = tester
          .widgetList<BalancedLyricText>(find.byType(BalancedLyricText))
          .where((widget) => widget.text == chinese || widget.text == romaji);
      expect(secondary, hasLength(2));
      expect(secondary.map((widget) => widget.wordFollow), everyElement(false));
      expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((widget) => widget.painter)
              .whereType<PlainLyricWordFollowPainter>(),
          isEmpty);
      expect(find.text(chinese), findsOneWidget);
      expect(find.text(romaji), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(host(distance: 0, reducedMotion: true));
    clock.value = .45;
    await tester.pump();
    expectStaticSecondary();
    await tester.pumpWidget(host(distance: 2, reducedMotion: false));
    await tester.pumpAndSettle();
    expectStaticSecondary();
    await tester.pumpWidget(const SizedBox());
    clock.dispose();
    position.dispose();
    settings.dispose();
  });
}
