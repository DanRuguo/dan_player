import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(int index, String text)
      : super(Duration(milliseconds: index * 250),
            const Duration(milliseconds: 600), text);
}

class _Line extends SyncLyricLine {
  _Line(String text)
      : super(Duration.zero, const Duration(seconds: 20), [
          for (final (index, part) in text.characters.indexed)
            _Word(index, part),
        ]);
}

({LyricWordHighlightPainter painter, Size size}) _paint(GlobalKey key) {
  LyricWordHighlightPainter? painter;
  Size? size;
  void visit(Element element) {
    if (element.widget
        case CustomPaint(painter: final LyricWordHighlightPainter value)) {
      painter = value;
      size = (element.renderObject! as RenderBox).size;
    }
    element.visitChildren(visit);
  }

  visit(key.currentContext! as Element);
  return (painter: painter!, size: size!);
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey boundary) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    try {
      final data =
          await image.toByteData(format: raster.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
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

  testWidgets('timed width sweeps retain shaping and match fresh sung pixels',
      (tester) async {
    const samples = [
      '穿过月光与星河，等你归来的漫长夜晚',
      'Maybe we should let this go, through the moonlit night',
      '離さない 揺るがない Crazy for you 音もない世界',
      '달빛 아래 긴 밤을 지나 집으로 돌아가는 노래',
      '👨‍👩‍👧‍👦 e\u0301 العربية mixed 歌词',
    ];
    final settings = LyricViewController()..lyricFontSize = 22;
    final position = ValueNotifier(const Duration(milliseconds: 2300));
    addTearDown(settings.dispose);
    addTearDown(position.dispose);
    final retained = GlobalKey(), fresh = GlobalKey();
    var revision = 0;
    for (final sample in samples) {
      final line = _Line(sample);
      for (final scale in [1.0, 1.5]) {
        for (final alignment in LyricTextAlign.values) {
          settings.lyricTextAlign = alignment;
          final paragraphs = <TextPainter>{};
          final layouts = <Object>{};
          LyricWordHighlightPainter? previous;
          final widths = [
            340.0,
            300.0,
            260.0,
            259.0,
            190.0,
            191.0,
            261.0,
            299.0,
            300.0,
            340.0
          ];
          for (final (index, width) in widths.indexed) {
            position.value = Duration(
                milliseconds: const [
              0,
              1100,
              2300,
              4700,
              8700,
              15000
            ][index % 6]);
            revision++;
            Widget pane(GlobalKey key, Key tileKey) => RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: width,
                    height: 560,
                    child: SingleChildScrollView(
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
                );
            await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  fontFamily: danEmbeddedFontFamily,
                  textTheme: ThemeData().textTheme.apply(
                      fontFamily: danEmbeddedFontFamily,
                      fontFamilyFallback: danFontFamilyFallback)),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Material(
                  child: ChangeNotifierProvider.value(
                    value: settings,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          pane(retained, const ValueKey('retained-timed-line')),
                          const SizedBox(width: 16),
                          pane(fresh, ValueKey(revision)),
                        ]),
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            final actual = _paint(retained), reference = _paint(fresh);
            paragraphs.add(actual.painter.text);
            layouts.add(actual.painter.layoutIdentity);
            expect(actual.painter.text.text!.toPlainText(), sample);
            expect(actual.size, reference.size);
            expect(actual.painter.shapedWordCount,
                reference.painter.shapedWordCount);
            if (previous != null) {
              expect(actual.painter.layoutIdentity,
                  isNot(same(previous.layoutIdentity)));
              expect(actual.painter.shouldRepaint(previous), isTrue,
                  reason: 'Reused paragraphs still need a fresh wrap repaint');
            }
            expect(
                listEquals(await _pixels(tester, retained),
                    await _pixels(tester, fresh)),
                isTrue,
                reason: '$sample scale=$scale align=$alignment width=$width');
            previous = actual.painter;
            expect(tester.takeException(), isNull);
          }
          expect(paragraphs, hasLength(1),
              reason: 'A width change must not discard timed glyph shaping');
          expect(layouts, hasLength(widths.length),
              reason:
                  'Every changed width needs its own complete word geometry');
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
