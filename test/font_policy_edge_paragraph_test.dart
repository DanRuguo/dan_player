import 'dart:ui' as raster;

import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _breaks = {'LF': '\n', 'CRLF': '\r\n', 'LS': '\u2028', 'PS': '\u2029'};

class _CountingPolicy extends AppFontPolicy {
  _CountingPolicy()
      : super(
            language: UiLanguage.zh,
            mixedScripts: true,
            zh: appBundledFonts[0],
            en: appBundledFonts[1],
            ja: appBundledFonts[2],
            ko: appBundledFonts[3]);
  int fallbackReads = 0;
  @override
  List<String> get fallback {
    fallbackReads++;
    return super.fallback;
  }
}

List<({int start, int end, String? family})> _extents(InlineSpan root) {
  var offset = 0;
  final result = <({int start, int end, String? family})>[];
  void visit(InlineSpan span, String? inherited) {
    final family = span.style?.fontFamily ?? inherited;
    if (span is TextSpan) {
      final text = span.text;
      if (text != null) {
        result.add((start: offset, end: offset + text.length, family: family));
        offset += text.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, family);
      }
    }
  }

  visit(root, null);
  return result;
}

void _completeClusters(String text, Iterable<(int, int)> extents) {
  final boundaries = <int>{0};
  var offset = 0;
  for (final cluster in text.characters) {
    offset += cluster.length;
    boundaries.add(offset);
  }
  for (final (start, end) in extents) {
    expect(boundaries.contains(start), isTrue);
    expect(boundaries.contains(end), isTrue,
        reason: 'Do not split combining/ZWJ clusters or the CRLF cluster.');
  }
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.rawRgba);
        return Uint8List.fromList(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));
  if (!onlyRender) {
    for (final separator in _breaks.entries) {
      for (final second in {'ja': 'かな', 'ko': '한글'}.entries) {
        test(
            '${separator.key} isolates Han from following ${second.key} paragraph',
            () {
          final policy = AppFontPolicy.defaults();
          final text = '骨直${separator.value}${second.value}';
          final span = appFontSpan(text,
              style: const TextStyle(fontSize: 24), policy: policy);
          final painter =
              TextPainter(text: span, textDirection: TextDirection.ltr)
                ..layout(maxWidth: 400);
          addTearDown(painter.dispose);
          expect(painter.computeLineMetrics(), hasLength(2),
              reason: 'This separator is a real engine paragraph break.');
          expect(span.toPlainText(), text);
          final extents = _extents(span);
          expect(extents.first.family, policy.zh.family,
              reason:
                  'Kana/Hangul after a hard break must not select the Han font.');
          final secondOffset = 2 + separator.value.length;
          expect(
              extents
                  .singleWhere((extent) =>
                      extent.start <= secondOffset && secondOffset < extent.end)
                  .family,
              second.key == 'ja' ? policy.ja.family : policy.ko.family);
          _completeClusters(
              text, extents.map((extent) => (extent.start, extent.end)));
        });
      }
    }
    test('short multiline projections share immutable cached cluster runs', () {
      const text = '骨直\r\nかな e\u0301\u2028한글 👩🏽‍🚀\u2029שלום';
      final first = appFontRuns(text, UiLanguage.zh);
      final again =
          appFontRuns(String.fromCharCodes(text.codeUnits), UiLanguage.zh);
      expect(again, same(first),
          reason: 'Repeated timed ink paints must reuse the whole projection.');
      expect(first.map((run) => run.text).join(), text);
      var offset = 0;
      _completeClusters(text, first.map((run) {
        final start = offset;
        offset += run.text.length;
        return (start, offset);
      }));
      expect(() => first.add(const AppFontRun('bad', UiLanguage.en)),
          throwsUnsupportedError);
      expect(appFontRuns(text, UiLanguage.ja), isNot(same(first)),
          reason: 'UI language resolves ambiguous Han independently.');
    });
    test('whole paragraph reuse stays within the existing bounded LRU', () {
      const text = 'cache anchor 骨直\nかな';
      final first = appFontRuns(text, UiLanguage.zh);
      expect(appFontRuns(text, UiLanguage.zh), same(first));
      for (var i = 0; i < 256; i++) {
        appFontRuns('unique paragraph eviction $i', UiLanguage.en);
      }
      final afterEviction = appFontRuns(text, UiLanguage.zh);
      expect(afterEviction, isNot(same(first)),
          reason: 'Multiline entries cannot grow an unbounded second cache.');
      expect(appFontRuns(text, UiLanguage.zh), same(afterEviction));
      expect(afterEviction.map((run) => run.text).join(), text);
    });
    test(
        'oversized multiline documents retain original clusters without caching',
        () {
      final text = '${'骨' * 4100}\r\n${'e\u0301' * 4100}\u2028👩🏽‍🚀한글';
      final first = appFontRuns(text, UiLanguage.zh);
      expect(first.map((run) => run.text).join(), text);
      expect(appFontRuns(text, UiLanguage.zh), isNot(same(first)),
          reason: 'The existing 8192 UTF-16 retention budget still applies.');
      var offset = 0;
      _completeClusters(text, first.map((run) {
        final start = offset;
        offset += run.text.length;
        return (start, offset);
      }));
    });
    test('CR-only and NEL keep the engine single paragraph context', () {
      final policy = AppFontPolicy.defaults();
      for (final separator in ['\r', '\u0085']) {
        final text = '骨直$separatorかな';
        final span = appFontSpan(text,
            style: const TextStyle(fontSize: 24), policy: policy);
        final painter =
            TextPainter(text: span, textDirection: TextDirection.ltr)
              ..layout(maxWidth: 400);
        expect(painter.computeLineMetrics(), hasLength(1));
        expect(_extents(span).first.family, policy.ja.family);
        expect(span.toPlainText(), text);
        painter.dispose();
      }
    });
    test(
        'mixed projection shares one fallback snapshot across long script runs',
        () {
      final policy = _CountingPolicy();
      final text = '骨かな English e\u0301 한글 ' * 100;
      final span = appFontSpan(text,
          style: const TextStyle(fontSize: 24), policy: policy);
      expect(span.toPlainText(), text);
      expect(span.children!.length, greaterThan(200));
      expect(policy.fallbackReads, 1,
          reason:
              'Mixed word ink must not allocate the identical fallback list per run.');
      final fallbackLists = Set<List<String>>.identity();
      for (final child in span.children!) {
        final fallback = child.style!.fontFamilyFallback!;
        fallbackLists.add(fallback);
        expect(fallback, [
          for (final i in [0, 2, 3, 1]) appBundledFonts[i].family,
          'Segoe UI',
          'Segoe UI Symbol',
          'Segoe UI Emoji'
        ]);
      }
      expect(fallbackLists, hasLength(1));
    });
  }
  for (final separator in {'LS': '\u2028', 'PS': '\u2029'}.entries) {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      testWidgets(
          '${separator.key} mixed font paragraph matches explicit glyphs $direction',
          (tester) async {
        final policy = AppFontPolicy.defaults();
        final text = '骨直${separator.value}かな';
        final retained = GlobalKey(), fresh = GlobalKey();
        RenderParagraph? paragraph;
        for (final width in [219.0, 218.0, 151.0]) {
          Widget pane(GlobalKey key, bool actual) => RepaintBoundary(
              key: key,
              child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                      width: width,
                      height: 150,
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Builder(builder: (context) {
                            const style = TextStyle(
                                fontSize: 24,
                                height: 1.3,
                                color: Colors.black,
                                fontWeight: FontWeight.w500);
                            if (actual) return AppFontText(text, style: style);
                            return Text.rich(TextSpan(
                                style: DefaultTextStyle.of(context)
                                    .style
                                    .merge(style),
                                children: [
                                  TextSpan(
                                      text: '骨直${separator.value}',
                                      style: TextStyle(
                                          fontFamily: policy.zh.family,
                                          fontFamilyFallback: policy.fallback),
                                      locale: UiLanguage.zh.locale),
                                  TextSpan(
                                      text: 'かな',
                                      style: TextStyle(
                                          fontFamily: policy.ja.family,
                                          fontFamilyFallback: policy.fallback),
                                      locale: UiLanguage.ja.locale),
                                ]));
                          })))));
          await tester.pumpWidget(MaterialApp(
              home: AppFontScope(
                  policy: policy,
                  child: Directionality(
                      textDirection: direction,
                      child: Material(
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            pane(retained, true),
                            const SizedBox(width: 16),
                            pane(fresh, false)
                          ]))))));
          await tester.pumpAndSettle();
          final actualFinder = find.descendant(
              of: find.byKey(retained), matching: find.byType(RichText));
          final actual = tester.renderObject<RenderParagraph>(actualFinder);
          final reference = tester.renderObject<RenderParagraph>(
              find.descendant(
                  of: find.byKey(fresh), matching: find.byType(RichText)));
          if (paragraph != null) expect(actual, same(paragraph));
          paragraph = actual;
          expect(actual.text.toPlainText(), text);
          expect(actual.size, reference.size);
          expect(actual.size.height, lessThanOrEqualTo(150));
          for (final selection in [
            const TextSelection(baseOffset: 0, extentOffset: 2),
            TextSelection(
                baseOffset: 2 + separator.value.length,
                extentOffset: text.length)
          ]) {
            final boxes = actual.getBoxesForSelection(selection);
            expect(boxes, isNotEmpty);
            expect(boxes, reference.getBoxesForSelection(selection));
            final boundary = retained.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final origin =
                actual.localToGlobal(Offset.zero, ancestor: boundary);
            expect(
                boxes.every((box) =>
                    box.left + origin.dx >= 0 &&
                    box.right + origin.dx <= boundary.size.width &&
                    box.top + origin.dy >= 0 &&
                    box.bottom + origin.dy <= boundary.size.height),
                isTrue,
                reason:
                    'The complete natural glyph box must fit the captured viewport.');
          }
          final actualPixels = await _pixels(tester, retained);
          expect(actualPixels.where((value) => value != 255 && value != 0),
              isNotEmpty);
          expect(listEquals(actualPixels, await _pixels(tester, fresh)), isTrue,
              reason:
                  'Compare real SC/JP glyphs with an independent explicit reference.');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
