import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TextPainter paragraph(String text,
          {TextDirection direction = TextDirection.ltr}) =>
      TextPainter(
          text: TextSpan(
              text: text,
              style: const TextStyle(fontFamily: 'Ahem', fontSize: 20)),
          textDirection: direction);

  test('short final row balances without changing line count or text offsets',
      () {
    final painter = paragraph('She so pretty girl tell me');
    addTearDown(painter.dispose);
    painter.layout(maxWidth: 430);
    final before = painter.computeLineMetrics();
    final balancedWidth = layoutBalancedLyric(painter, 430);
    final after = painter.computeLineMetrics();
    expect(after.length, before.length);
    expect(balancedWidth, lessThan(430));
    expect((after.first.width - after.last.width).abs(),
        lessThan((before.first.width - before.last.width).abs()));
    expect(painter.text!.toPlainText(), 'She so pretty girl tell me');
    final lastWord = painter.getBoxesForSelection(
        const TextSelection(baseOffset: 23, extentOffset: 25));
    expect(lastWord, isNotEmpty);
    expect(lastWord.single.right, lessThanOrEqualTo(balancedWidth));
  });

  test('keeps explicit breaks, single rows, RTL and long paragraphs untouched',
      () {
    for (final text in [
      'One line',
      'An explicit long first line\nme',
      'a ' * 300
    ]) {
      final painter = paragraph(text)..layout(maxWidth: 220);
      final oldHeight = painter.height;
      expect(layoutBalancedLyric(painter, 220), 220);
      expect(painter.height, oldHeight);
      painter.dispose();
    }
    final rtl = paragraph('Some longer words me', direction: TextDirection.rtl);
    expect(layoutBalancedLyric(rtl, 300), 300);
    rtl.dispose();
  });

  test('long fitting words do not acquire new internal breaks', () {
    const text = 'extraordinary a b';
    final painter = paragraph(text);
    addTearDown(painter.dispose);
    layoutBalancedLyric(painter, 300);
    final word = painter.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 13));
    expect(word.length, 1);
  });

  test('a steadily wider lyric does not move words back to a later line',
      () async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    const text = 'Maybe we should let this go';
    final words = RegExp(r'\S+').allMatches(text).toList();
    var previousFirstLineWords = 0;
    for (var width = 150.0; width <= 500; width += 1) {
      final painter = TextPainter(
          text: const TextSpan(
              text: text,
              style: TextStyle(
                  fontFamily: danEmbeddedFontFamily,
                  fontSize: 33,
                  fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr);
      try {
        layoutBalancedLyric(painter, width);
        final firstLine = painter.computeLineMetrics().first;
        final count = words.where((word) {
          final boxes = painter.getBoxesForSelection(
              TextSelection(baseOffset: word.start, extentOffset: word.end));
          return boxes.isNotEmpty &&
              boxes.first.top < firstLine.baseline + firstLine.descent;
        }).length;
        expect(count, greaterThanOrEqualTo(previousFirstLineWords),
            reason: 'width $width moved a word from the first line back');
        previousFirstLineWords = count;
      } finally {
        painter.dispose();
      }
    }
  });

  test('mixed-script phrases which fit intact keep their original boundaries',
      () {
    const text = '離さない 揺るがない Crazy for you';
    for (final width in [260.0, 300.0, 340.0, 400.0]) {
      final painter = paragraph(text)..layout(maxWidth: width);
      final intact = [
        for (final phrase in RegExp(r'\S+').allMatches(text))
          TextSelection(baseOffset: phrase.start, extentOffset: phrase.end)
      ]
          .where((range) => painter.getBoxesForSelection(range).length == 1)
          .toList();
      layoutBalancedLyric(painter, width);
      for (final range in intact) {
        expect(painter.getBoxesForSelection(range).length, 1);
      }
      painter.dispose();
    }
  });

  testWidgets(
      'focus colour changes leave layout stable and width changes reflow',
      (tester) async {
    Widget host(double width, Color color) => MaterialApp(
        home: Center(
            child: SizedBox(
                width: width,
                child: BalancedLyricText('She so pretty girl tell me',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                        fontFamily: 'Ahem', fontSize: 20, color: color)))));
    await tester.pumpWidget(host(430, Colors.black));
    final initial = tester.getRect(find.text('She so pretty girl tell me'));
    await tester.pumpWidget(host(430, Colors.red));
    expect(tester.getRect(find.text('She so pretty girl tell me')), initial);
    await tester.pumpWidget(host(190, Colors.red));
    expect(tester.getSize(find.text('She so pretty girl tell me')).height,
        greaterThan(initial.height));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('retained ink reserves the same paragraph size and semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const cases = <({
      String text,
      double width,
      double fontSize,
      double scale,
      TextDirection direction,
      bool customHeight
    })>[
      (
        text: 'Short lyric',
        width: 340,
        fontSize: 20,
        scale: 1,
        direction: TextDirection.ltr,
        customHeight: false
      ),
      (
        text: 'A long translation underneath the current line',
        width: 190,
        fontSize: 20,
        scale: 1,
        direction: TextDirection.ltr,
        customHeight: false
      ),
      (
        text: '音もない世界、何を見てるの?音もない世界、何を見てるの?',
        width: 210,
        fontSize: 25,
        scale: 1.25,
        direction: TextDirection.ltr,
        customHeight: false
      ),
      (
        text: 'Romanization o to mo na i se ka i',
        width: 190,
        fontSize: 18,
        scale: 1.25,
        direction: TextDirection.ltr,
        customHeight: true
      ),
      (
        text: 'مرحبا بالعالم مرة أخرى',
        width: 170,
        fontSize: 22,
        scale: 1,
        direction: TextDirection.rtl,
        customHeight: false
      ),
      (
        text: '',
        width: 180,
        fontSize: 20,
        scale: 1,
        direction: TextDirection.ltr,
        customHeight: false
      ),
    ];
    for (final sample in cases) {
      const customBehavior = ui.TextHeightBehavior(
          applyHeightToFirstAscent: false, applyHeightToLastDescent: false);
      const style = TextStyle(fontFamily: 'Ahem', height: 1.3);
      Widget host(Widget child) => MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: sample.direction,
                child: MediaQuery(
                  data: MediaQueryData(
                      textScaler: TextScaler.linear(sample.scale)),
                  child: DefaultTextHeightBehavior(
                    textHeightBehavior: sample.customHeight
                        ? customBehavior
                        : const ui.TextHeightBehavior(),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(width: sample.width, child: child),
                    ),
                  ),
                ),
              ),
            ),
          );
      final styled = style.copyWith(fontSize: sample.fontSize);
      await tester.pumpWidget(host(BalancedLyricText(sample.text,
          style: styled, textAlign: TextAlign.left, alignmentX: -1)));
      final balanced = find.byType(BalancedLyricText);
      final painting = find
          .descendant(of: balanced, matching: find.byType(CustomPaint))
          .first;
      final paint = tester.widget<CustomPaint>(painting);
      final ink = paint.painter! as PlainLyricWordFollowPainter;
      final canvasSize = tester.getSize(painting);
      final painterWidth = ink.text.width;
      final painterHeight = ink.text.height;
      expect(
          canvasSize.width, closeTo(painterWidth + ink.inkOffset.dx * 2, .02));
      expect(canvasSize.height,
          closeTo(painterHeight + ink.inkOffset.dy * 2, .02));
      if (sample.text.isNotEmpty) {
        expect(find.bySemanticsLabel(sample.text), findsOneWidget);
      }
      await tester.pumpWidget(host(SizedBox(
        width: painterWidth,
        child: Text(sample.text, style: styled, textAlign: TextAlign.left),
      )));
      expect(tester.getSize(find.text(sample.text)).height,
          closeTo(painterHeight, .02),
          reason: 'Painter and Text must reserve equal line height');
    }
    semantics.dispose();
  });

  testWidgets('word-follow changes reuse the shaped lyric paragraph',
      (tester) async {
    Widget host(bool follow) => MaterialApp(
        home: SizedBox(
            width: 300,
            child: BalancedLyricText('Morning light returns',
                style: const TextStyle(fontFamily: 'Ahem', fontSize: 24),
                textAlign: TextAlign.left,
                alignmentX: -1,
                wordFollow: follow)));
    PlainLyricWordFollowPainter painter() => tester
        .widget<CustomPaint>(find
            .descendant(
                of: find.byType(BalancedLyricText),
                matching: find.byType(CustomPaint))
            .first)
        .painter! as PlainLyricWordFollowPainter;
    await tester.pumpWidget(host(false));
    final shaped = painter().text;
    expect(painter().slots, isEmpty);
    await tester.pumpWidget(host(true));
    expect(painter().text, same(shaped));
    expect(painter().slots, isNotEmpty);
    await tester.pumpWidget(host(false));
    expect(painter().text, same(shaped));
    expect(painter().slots, isEmpty);
  });

  test('CJK and emoji use original shaping and legal selection bounds', () {
    final painter = paragraph('夏夜空中出现在遥远的记忆👨‍👩‍👧‍👦');
    addTearDown(painter.dispose);
    final width = layoutBalancedLyric(painter, 280);
    for (final box in painter.getBoxesForSelection(
        TextSelection(
            baseOffset: 0, extentOffset: painter.text!.toPlainText().length),
        boxHeightStyle: ui.BoxHeightStyle.tight)) {
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(width + .01));
    }
  });
}
