import 'dart:ui' as ui;

import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:flutter/material.dart';
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
