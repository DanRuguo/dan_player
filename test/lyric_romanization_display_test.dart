import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

class _Word extends SyncLyricWord {
  _Word(String text, int start)
      : super(Duration(milliseconds: start), const Duration(seconds: 2), text);
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 4),
            [_Word('青い', 0), _Word('鳥が飛ぶ', 2000)], '蓝色的鸟儿展翅飞翔') {
    romanization = 'aoi tori ga tobu';
  }
}

const _detailed = LyricLineTimelineMessage(
    sequence: 1,
    lineIndex: 0,
    startMilliseconds: 0,
    lengthMilliseconds: 4000,
    content: '青い鳥が飛ぶ',
    romanization: 'aoi tori ga tobu',
    translation: '蓝色的鸟儿展翅飞翔',
    words: [
      DesktopLyricWord(0, 2000, '青い'),
      DesktopLyricWord(2000, 2000, '鳥が飛ぶ')
    ]);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_ROMAN_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final data = (await image.toByteData(format: raster.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data, flush: true);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  for (final align in LyricTextAlign.values) {
    for (final reduced in [false, true]) {
      testWidgets(
          'main three tracks retain $align alignment and reduced=$reduced',
          (tester) async {
        final settings = LyricViewController()
          ..lyricTextAlign = align
          ..lyricFontSize = 30
          ..translationFontSize = 20;
        final position = ValueNotifier(const Duration(milliseconds: 1000));
        addTearDown(settings.dispose);
        addTearDown(position.dispose);
        final line = _Line();
        for (final width in [320.0, 720.0]) {
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: Entry(welcome: false).fromSchemeAndFontFamily(
                      colorScheme:
                          ColorScheme.fromSeed(seedColor: Colors.teal)),
                  home: Scaffold(
                      body: Center(
                          child: SizedBox(
                              width: width,
                              child: ChangeNotifierProvider.value(
                                  value: settings,
                                  child: LyricViewTile(
                                      line: line,
                                      position: position,
                                      opacity: 1,
                                      reducedMotion: reduced,
                                      distance: 0))))))));
          await tester.pumpAndSettle();
          final roman =
              tester.getRect(find.byKey(const ValueKey('lyric-romanization')));
          final primary = find.byWidgetPredicate((widget) =>
              widget is CustomPaint &&
              widget.painter is LyricWordHighlightPainter);
          final original = tester.getRect(primary);
          final translated = tester.getRect(find.byWidgetPredicate((widget) =>
              widget is BalancedLyricText && widget.text == line.translation));
          if (!reduced) {
            final aux = find.byWidgetPredicate((widget) =>
                widget is BalancedLyricText &&
                widget.text == line.romanization);
            final painted = tester.widget<CustomPaint>(
                find.descendant(of: aux, matching: find.byType(CustomPaint)));
            final painter = painted.painter! as PlainLyricWordFollowPainter;
            final boxes = painter.text.getBoxesForSelection(TextSelection(
                baseOffset: 0, extentOffset: line.romanization!.length));
            final left =
                boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
            final right =
                boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b);
            if (align == LyricTextAlign.center) {
              expect((left + right) / 2, closeTo(painter.text.width / 2, .5),
                  reason:
                      'Verify painted ink, not the full-size transparent widget');
            } else if (align == LyricTextAlign.right) {
              expect(right, closeTo(painter.text.width, .5));
            } else {
              expect(left, closeTo(0, .5));
            }
          }
          expect(roman.bottom, lessThanOrEqualTo(original.top));
          expect(original.bottom, lessThanOrEqualTo(translated.top));
          final semantics = tester.widget<Semantics>(find
              .descendant(
                  of: find.byType(LyricViewTile),
                  matching: find.byType(Semantics))
              .first);
          expect(semantics.properties.label,
              '${line.romanization}\n${line.content}\n${line.translation}');
          final before = [roman, original, translated];
          position.value = const Duration(milliseconds: 2500);
          await tester.pump();
          expect(tester.getRect(primary), before[1]);
          expect(
              tester.getRect(find.byKey(const ValueKey('lyric-romanization'))),
              before[0]);
          if (align == LyricTextAlign.center) {
            await _capture(tester, boundary,
                'main-${width.toInt()}-${reduced ? 'reduced' : 'motion'}');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  for (final vertical in [false, true]) {
    for (final reduced in [false, true]) {
      for (final width in [240.0, 560.0]) {
        testWidgets(
            'desktop three tracks vertical=$vertical reduced=$reduced width=$width',
            (tester) async {
          final clock = PlaybackClock(automaticTicks: false);
          final source = DesktopLyricController.detached(clock: clock);
          source.vertical.value = vertical;
          final native = FakeDesktopLyricWindow();
          final window = DesktopLyricWindowLayout(adapter: native);
          await window.initialize(vertical: vertical);
          addTearDown(source.dispose);
          addTearDown(window.dispose);
          source.handleMessage(_detailed.buildMessageJson());
          source.handleMessage(
              const PlaybackTimelineMessage(1, 1000, false).buildMessageJson());
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: Entry(welcome: false).fromSchemeAndFontFamily(
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: Colors.teal,
                          brightness:
                              vertical ? Brightness.dark : Brightness.light)),
                  home: Scaffold(
                      body: MediaQuery(
                          data: MediaQueryData(
                              disableAnimations: reduced,
                              textScaler:
                                  TextScaler.linear(width == 240 ? 1.6 : 1)),
                          child: Center(
                              child: SizedBox(
                                  width: width,
                                  height: 500,
                                  child: Provider<ThemeChangedMessage>.value(
                                      value: source.theme.value,
                                      child: DesktopLyricForeground(
                                          isHovering: false,
                                          controller: source,
                                          windowLayout: window)))))))));
          await tester.pumpAndSettle();
          final keys = [
            'desktop-romanization-lyric',
            'desktop-primary-lyric',
            'desktop-translation-lyric'
          ];
          final rects = [
            for (final key in keys) tester.getRect(find.byKey(ValueKey(key)))
          ];
          for (var i = 1; i < rects.length; i++) {
            if (vertical) {
              expect(rects[i].left, greaterThan(rects[i - 1].right));
              expect(rects[i].top, closeTo(rects[0].top, .01));
            } else {
              expect(rects[i].top, greaterThan(rects[i - 1].bottom));
            }
          }
          for (final index in [0, 2]) {
            expect(
                tester
                    .widget<DesktopLyricText>(find.byKey(ValueKey(keys[index])))
                    .words,
                isEmpty);
          }
          final painter = tester
              .widget<CustomPaint>(find.descendant(
                  of: find.byKey(ValueKey(keys[1])),
                  matching: find.byType(CustomPaint)))
              .painter! as DesktopLyricTextPainter;
          expect(painter.progressForWord(0), .5);
          source.handleMessage(
              const PlaybackTimelineMessage(1, 2500, false).buildMessageJson());
          await tester.pump();
          expect(painter.progressForWord(0), 1);
          expect(tester.takeException(), isNull);
          await _capture(tester, boundary,
              'desktop-${vertical ? 'vertical' : 'horizontal'}-${width.toInt()}-${reduced ? 'reduced' : 'motion'}');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets(
      'desktop native minimum grows for pronunciation and fits all three horizontal rows',
      (tester) async {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    final native = FakeDesktopLyricWindow();
    final window = DesktopLyricWindowLayout(adapter: native);
    await window.initialize(vertical: false);
    addTearDown(source.dispose);
    addTearDown(window.dispose);
    source.appearance.value = source.appearance.value
        .copyWith(lyricFontSize: 64, translationFontSize: 60);
    var fitMinimum = false;
    Widget app() => MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 800,
                    height: fitMinimum ? native.minimum.height : 450,
                    child: Provider<ThemeChangedMessage>.value(
                        value: source.theme.value,
                        child: DesktopLyricForeground(
                            isHovering: false,
                            controller: source,
                            windowLayout: window))))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final twoHeight = native.minimum.height;
    source.handleMessage(_detailed.buildMessageJson());
    await tester.pumpAndSettle();
    expect(native.minimum.height, greaterThan(twoHeight + 70));
    fitMinimum = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final foreground = tester.getRect(find.byType(DesktopLyricForeground));
    final translated =
        tester.getRect(find.byKey(const ValueKey('desktop-translation-lyric')));
    expect(translated.bottom, lessThanOrEqualTo(foreground.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
