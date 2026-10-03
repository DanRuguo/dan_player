import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const resizeShapingCase =
    'width sweeps retain shaping and match fresh four-script glyph pixels';

PlainLyricWordFollowPainter _paint(GlobalKey boundary) {
  final element = boundary.currentContext! as Element;
  PlainLyricWordFollowPainter? result;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is CustomPaint &&
        widget.painter is PlainLyricWordFollowPainter) {
      result = widget.painter! as PlainLyricWordFollowPainter;
    }
    element.visitChildren(visit);
  }

  visit(element);
  return result!;
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key,
    {File? png}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data =
          await image.toByteData(format: raster.ImageByteFormat.rawRgba);
      if (png != null) {
        await png.parent.create(recursive: true);
        final encoded =
            await image.toByteData(format: raster.ImageByteFormat.png);
        await png.writeAsBytes(encoded!.buffer.asUint8List());
      }
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main({String? onlyCase}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final korean = File('$windows/Fonts/malgun.ttf');
      if (await korean.exists()) {
        await (FontLoader('Malgun Gothic')
              ..addFont(Future.value(
                  ByteData.sublistView(await korean.readAsBytes()))))
            .load();
      }
    }
  });

  void check(String name, WidgetTesterCallback callback) {
    if (onlyCase == null || onlyCase == name) testWidgets(name, callback);
  }

  check(resizeShapingCase, (tester) async {
    const samples = {
      'zh': '穿过月光与星河，等你归来的漫长夜晚',
      'en': 'Maybe we should let this go, through the moonlit night',
      'ja': '離さない 揺るがない Crazy for you 音もない世界',
      'ko': '달빛 아래 긴 밤을 지나 집으로 돌아가는 노래',
    };
    final retained = GlobalKey(), fresh = GlobalKey();
    var revision = 0;
    final render = Platform.environment['DAN_LYRIC_RESIZE_RENDER_DIR'];
    for (final sample in samples.entries) {
      for (final scale in [1.0, 1.5]) {
        for (final align in [-1.0, 0.0, 1.0]) {
          final painters = <TextPainter>{};
          for (final width in [
            340.0,
            300.0,
            260.0,
            190.0,
            261.0,
            299.0,
            340.0
          ]) {
            revision++;
            Widget pane(GlobalKey boundary, Key? textKey) => RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                    color: Colors.white,
                    child: SizedBox(
                      width: width,
                      height: 520,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: BalancedLyricText(sample.value,
                            key: textKey,
                            alignmentX: align,
                            wordFollow: true,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                                fontFamily: danEmbeddedFontFamily,
                                fontFamilyFallback: danFontFamilyFallback,
                                fontSize: 26,
                                color: Colors.black)),
                      ),
                    ),
                  ),
                );
            await tester.pumpWidget(MaterialApp(
                home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                        body: Center(
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                      pane(retained, const ValueKey('retained-lyric')),
                      const SizedBox(width: 16),
                      pane(fresh, ValueKey(revision)),
                    ]))))));
            await tester.pump();
            final actual = _paint(retained), reference = _paint(fresh);
            painters.add(actual.text);
            expect(actual.text.text!.toPlainText(), sample.value);
            expect(actual.text.height + lyricVerticalInkGuard * 2,
                lessThanOrEqualTo(520),
                reason: 'The complete lyric must fit in the pixel capture.');
            expect(actual.slots.last.end, sample.value.length);
            expect(actual.text.size, reference.text.size);
            expect(actual.slots.map((s) => (s.start, s.end)),
                reference.slots.map((s) => (s.start, s.end)));
            for (var i = 0; i < actual.slots.length; i++) {
              expect(actual.slots[i].paintBoxes, reference.slots[i].paintBoxes);
            }
            final pixels = await _pixels(tester, retained,
                png: render == null || width != 190 || align != 0
                    ? null
                    : File('$render/${sample.key}-$scale.png'));
            expect(listEquals(pixels, await _pixels(tester, fresh)), isTrue,
                reason: '${sample.key} scale=$scale align=$align width=$width');
            expect(tester.takeException(), isNull);
          }
          expect(painters, hasLength(1),
              reason:
                  'Resizing unchanged glyphs must reuse shaped paragraphs.');
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  check('text font scale and direction changes invalidate retained shaping',
      (tester) async {
    final boundary = GlobalKey();
    TextPainter? previous;
    for (final sample in [
      ('First lyric', 22.0, 1.0, TextDirection.ltr),
      ('Next lyric', 22.0, 1.0, TextDirection.ltr),
      ('Next lyric', 30.0, 1.0, TextDirection.ltr),
      ('Next lyric', 30.0, 1.5, TextDirection.ltr),
      ('Next lyric', 30.0, 1.5, TextDirection.rtl),
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(sample.$3)),
              child: Directionality(
                  textDirection: sample.$4,
                  child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                          width: 200,
                          child: BalancedLyricText(sample.$1,
                              alignmentX: -1,
                              wordFollow: true,
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                  fontFamily: danEmbeddedFontFamily,
                                  fontSize: sample.$2,
                                  color: Colors.black))))))));
      final painter = _paint(boundary).text;
      if (previous != null) expect(identical(painter, previous), isFalse);
      expect(painter.text!.toPlainText(), sample.$1);
      expect(painter.textScaler.scale(sample.$2), sample.$2 * sample.$3);
      expect(painter.textDirection, sample.$4);
      previous = painter;
      expect(tester.takeException(), isNull);
    }
  });
}
