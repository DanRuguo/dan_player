import 'dart:async';
import 'dart:convert';

import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

class _Fixture {
  _Fixture({bool vertical = true}) {
    clock = PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
    source = DesktopLyricController.detached(
        clock: clock,
        setIgnoreMouseEvents: (value) async {
          locks.add(value);
        });
    source.vertical.value = vertical;
    layout = DesktopLyricWindowLayout(adapter: native);
    addTearDown(() {
      source.dispose();
      texts.dispose();
    });
  }

  int now = 0;
  late final PlaybackClock clock;
  late final DesktopLyricController source;
  late final DesktopLyricWindowLayout layout;
  final native = FakeDesktopLyricWindow();
  final texts = TextDisplayController();
  final messages = <String>[];
  final locks = <bool>[];

  Future<void> initialize() async {
    native.bounds = Rect.fromLTWH(
        100,
        100,
        DesktopLyricGeometry.defaultSize(source.vertical.value).width,
        DesktopLyricGeometry.defaultSize(source.vertical.value).height);
    await layout.initialize(vertical: source.vertical.value);
    source.vertical.addListener(
        () => unawaited(layout.setVertical(source.vertical.value)));
  }

  void send(Message message) =>
      source.handleMessage(message.buildMessageJson());
  void line(String content,
      {String? translation,
      int sequence = 1,
      int index = 0,
      int length = 10000,
      List<DesktopLyricWord> words = const []}) {
    send(LyricLineTimelineMessage(
        sequence: sequence,
        lineIndex: index,
        startMilliseconds: 0,
        lengthMilliseconds: length,
        content: content,
        translation: translation,
        words: words));
  }

  Widget app(
          {double width = 248,
          double height = 560,
          double textScale = 1,
          bool controls = false,
          bool reduced = false,
          bool ticker = true,
          bool highContrast = false}) =>
      MaterialApp(
        theme: ThemeData(
            platform: TargetPlatform.windows,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        home: Scaffold(
            body: Builder(
                builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(textScale),
                          disableAnimations: reduced,
                          highContrast: highContrast),
                      child: TickerMode(
                        enabled: ticker,
                        child: Center(
                            child: SizedBox(
                          width: width,
                          height: height,
                          child: Provider<ThemeChangedMessage>.value(
                            value: source.theme.value,
                            child: DesktopLyricForeground(
                                controller: source,
                                textController: texts,
                                windowLayout: layout,
                                isHovering: controls,
                                sendMessage: messages.add),
                          ),
                        )),
                      ),
                    ))),
      );
}

DesktopLyricTextPainter _painter(WidgetTester tester,
        {bool translation = false}) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byKey(ValueKey(translation
              ? 'desktop-translation-lyric'
              : 'desktop-primary-lyric')),
          matching: find.byType(CustomPaint),
        ))
        .painter! as DesktopLyricTextPainter;

ScrollController _scroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
        find.byKey(const ValueKey('desktop-lyric-scroll')))
    .controller!;

void main() {
  test(
      'grapheme segmentation preserves ZWJ, flags, accents and supplementary CJK',
      () {
    const input = '你👨‍👩‍👧‍👦e\u0301🇨🇳𠮷👍🏽';
    final glyphs = desktopLyricGlyphs(input);
    expect(glyphs.map((glyph) => glyph.text),
        ['你', '👨‍👩‍👧‍👦', 'e\u0301', '🇨🇳', '𠮷', '👍🏽']);
    expect(glyphs.first.start, 0);
    expect(glyphs.last.end, input.length);
    expect(glyphs.map((glyph) => glyph.text).join(), input);
    for (var i = 1; i < glyphs.length; i++) {
      expect(glyphs[i].start, glyphs[i - 1].end);
    }
  });

  test('vertical segmentation keeps foreign words but separates CJK and emoji',
      () {
    const input =
        "你 Hello, don't stop-believin' 2026.08 👨‍👩‍👧‍👦夢。Love-you世界";
    final units = desktopLyricVerticalUnits(input);
    expect(units.map((unit) => unit.text), [
      '你',
      'Hello,',
      "don't",
      "stop-believin'",
      '2026.08',
      '👨‍👩‍👧‍👦',
      '夢',
      '。',
      'Love-you',
      '世',
      '界',
    ]);
    expect(units.map((unit) => unit.horizontal), [
      false,
      true,
      true,
      true,
      true,
      false,
      false,
      false,
      true,
      false,
      false,
    ]);
    for (final unit in units) {
      expect(input.substring(unit.start, unit.end), unit.text);
      expect(unit.text.trim(), isNotEmpty,
          reason: 'spaces delimit words but must not consume a lyric row');
    }
  });

  testWidgets(
      'vertical primary and translation are separate top-aligned columns',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('主歌词', translation: '译文内容');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final columns = tester
        .widget<Flex>(find.byKey(const ValueKey('desktop-lyric-columns')));
    expect(columns.direction, Axis.horizontal);
    final primary =
        tester.getRect(find.byKey(const ValueKey('desktop-primary-lyric')));
    final translation =
        tester.getRect(find.byKey(const ValueKey('desktop-translation-lyric')));
    expect(translation.left, greaterThan(primary.right));
    expect(primary.top, closeTo(translation.top, .01));
    expect(primary.height, greaterThan(primary.width));
    expect(_painter(tester).vertical, true);
    expect(_painter(tester, translation: true).vertical, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real word timing fills vertical glyphs from top to bottom at 2x',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('甲乙丙', words: const [
      DesktopLyricWord(0, 2000, '甲乙'),
      DesktopLyricWord(2000, 1000, '丙'),
    ]);
    fixture
        .send(const PlaybackTimelineMessage(1, 1000, false, playbackRate: 2));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final painter = _painter(tester);
    expect(painter.progressForWord(0), .5);
    expect(painter.progressForWord(1), 0);
    final half = painter.highlightRectsForWord(0);
    expect(half, hasLength(1));
    expect(half.first.top, 0);
    fixture
        .send(const PlaybackTimelineMessage(1, 1500, false, playbackRate: 2));
    await tester.pump();
    expect(identical(_painter(tester), painter), true,
        reason: 'clock correction must not rebuild the glyph layout');
    final threeQuarters = painter.highlightRectsForWord(0);
    expect(threeQuarters, hasLength(2));
    expect(threeQuarters[1].top, half.first.bottom);
    expect(threeQuarters[1].height, closeTo(half.first.height / 2, .01));
    fixture.send(const PlaybackTimelineMessage(1, 1000, true, playbackRate: 2));
    fixture.now = 250;
    expect(painter.progressForWord(0), .75);
    expect(painter.glyphs.map((glyph) => glyph.text), ['甲', '乙', '丙']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('foreign timed words fill left to right on one vertical row',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('Hello world', words: const [
      DesktopLyricWord(0, 1000, 'Hello'),
      DesktopLyricWord(1000, 1000, ' world'),
    ]);
    fixture.send(const PlaybackTimelineMessage(1, 500, false, playbackRate: 1));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final painter = _painter(tester);
    expect(painter.glyphs.map((glyph) => glyph.text), ['Hello', 'world']);
    expect(painter.glyphs.every((glyph) => glyph.horizontal), true);
    final half = painter.highlightRectsForWord(0).single;
    fixture.send(const PlaybackTimelineMessage(1, 750, false, playbackRate: 1));
    await tester.pump();
    final threeQuarters = painter.highlightRectsForWord(0).single;
    expect(threeQuarters.left, closeTo(half.left, .01));
    expect(threeQuarters.top, closeTo(half.top, .01));
    expect(threeQuarters.bottom, closeTo(half.bottom, .01));
    expect(threeQuarters.right, greaterThan(half.right));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long bilingual words fit a narrow vertical window at 200%',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line(
      'supercalifragilisticexpialidocious',
      translation: 'pneumonoultramicroscopicsilicovolcanoconiosis',
    );
    await tester.pumpWidget(fixture.app(width: 200, height: 360, textScale: 2));
    await tester.pumpAndSettle();
    final foreground = tester.getRect(find.byType(DesktopLyricForeground));
    for (final key in const [
      ValueKey('desktop-primary-lyric'),
      ValueKey('desktop-translation-lyric'),
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.left, greaterThanOrEqualTo(foreground.left));
      expect(rect.right, lessThanOrEqualTo(foreground.right));
    }
    expect(_painter(tester).glyphs.single.text,
        'supercalifragilisticexpialidocious');
    expect(_painter(tester, translation: true).glyphs.single.text,
        'pneumonoultramicroscopicsilicovolcanoconiosis');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'emoji remains a single painted glyph even if source timing splits it',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('👨‍👩‍👧‍👦e\u0301', words: const [
      DesktopLyricWord(0, 1000, '👨'),
      DesktopLyricWord(1000, 1000, '‍👩‍👧‍👦'),
      DesktopLyricWord(2000, 1000, 'e\u0301'),
    ]);
    await tester.pumpWidget(fixture.app(width: 600));
    await tester.pumpAndSettle();
    expect(_painter(tester).glyphs.map((glyph) => glyph.text),
        ['👨‍👩‍👧‍👦', 'e\u0301']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final vertical in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          '${vertical ? 'vertical' : 'horizontal'} controls fit narrow window at ${scale * 100}%',
          (tester) async {
        final fixture = _Fixture(vertical: vertical);
        await fixture.initialize();
        fixture.line('歌词标题和很长的歌词内容', translation: '翻译是另一列而不是旋转整句');
        await tester.pumpWidget(fixture.app(
            width: vertical ? 200 : 360,
            height: vertical ? 360 : 300,
            textScale: scale,
            controls: true));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final button
            in tester.widgetList<IconButton>(find.byType(IconButton))) {
          final rect = tester.getRect(find.byWidget(button));
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(
              tester
                  .getRect(find.byType(DesktopLyricForeground))
                  .contains(rect.center),
              true);
        }
        expect(_scroll(tester).position.viewportDimension, greaterThan(60));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'orientation button emits preference and leaves paused time unchanged',
      (tester) async {
    final fixture = _Fixture(vertical: false);
    await fixture.initialize();
    fixture.line('左右上下', translation: '翻译');
    fixture.send(
        const PlaybackTimelineMessage(1, 3200, false, playbackRate: 1.75));
    await tester
        .pumpWidget(fixture.app(width: 360, height: 400, controls: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-lyric-direction')));
    await tester.pumpAndSettle();
    expect(fixture.source.vertical.value, true);
    expect(fixture.layout.vertical, true);
    expect(json.decode(fixture.messages.last)['type'],
        'DesktopLyricDisplayChangedMessage');
    expect(json.decode(fixture.messages.last)['message']['vertical'], true);
    expect(fixture.clock.positionMilliseconds, 3200);
    expect(fixture.clock.playbackRate, 1.75);
    expect(fixture.clock.playing, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'vertical lock, player unlock and close controls remain functional',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('测试歌词');
    await tester.pumpWidget(fixture.app(controls: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-lyric-lock')));
    await tester.pump();
    expect(fixture.locks, [true]);
    expect(fixture.source.locked.value, true);
    expect(json.decode(fixture.messages.last)['message']['event'],
        ControlEvent.lock.code);
    fixture.send(const UnlockMessage());
    await tester.pump();
    expect(fixture.locks, [true, false]);
    expect(fixture.source.locked.value, false);
    await tester.tap(find.byKey(const ValueKey('desktop-lyric-close')));
    await tester.pump();
    expect(json.decode(fixture.messages.last)['message']['event'],
        ControlEvent.close.code);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'paused forward/backward seek immediately repositions long vertical line',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('很长的歌词' * 30, translation: '对应译文' * 40);
    fixture
        .send(const PlaybackTimelineMessage(1, 7000, false, playbackRate: 2));
    await tester.pumpWidget(fixture.app(height: 360));
    await tester.pumpAndSettle();
    final scroll = _scroll(tester);
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .7, .1));
    fixture.now = 10000;
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .7, .1));
    fixture
        .send(const PlaybackTimelineMessage(1, 2000, false, playbackRate: .5));
    await tester.pump();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .2, .1));
    fixture
        .send(const PlaybackTimelineMessage(1, 9000, false, playbackRate: 2));
    await tester.pump();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .9, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'stale lyric/timeline and old layout callbacks cannot revive an old song',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('旧歌' * 40);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture
        .send(const PlaybackTimelineMessage(2, 0, false, playbackRate: 1.25));
    fixture.line('新歌', sequence: 2);
    fixture.line('旧歌晚到', sequence: 1);
    fixture.send(const PlaybackTimelineMessage(1, 9500, true, playbackRate: 2));
    await tester.pumpAndSettle();
    final primary = tester.widget<DesktopLyricText>(
        find.byKey(const ValueKey('desktop-primary-lyric')));
    expect(primary.text, '新歌');
    expect(fixture.clock.positionMilliseconds, 0);
    expect(fixture.clock.playbackRate, 1.25);
    expect(_scroll(tester).offset, 0);
    fixture.line('卸载前待排版', sequence: 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reduced motion and disabled ticker show fully visible text immediately',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('可访问歌词', translation: '可访问译文');
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(
        fixture.app(reduced: true, ticker: false, highContrast: true));
    await tester.pump();
    final lineOpacity = tester.widget<Opacity>(find
        .descendant(
            of: find.byType(DesktopLyricLineContent),
            matching: find.byType(Opacity))
        .first);
    expect(lineOpacity.opacity, 1);
    expect(_painter(tester).reducedMotion, true);
    final primary = tester.widget<DesktopLyricText>(
        find.byKey(const ValueKey('desktop-primary-lyric')));
    expect(primary.unplayedColor.a, greaterThanOrEqualTo(.84));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'plain LRC does not acquire fabricated word timing or rebuild on ticks',
      (tester) async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.line('只有行时间', translation: '无逐字时间');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final primary = tester.widget<DesktopLyricText>(
        find.byKey(const ValueKey('desktop-primary-lyric')));
    final painter = _painter(tester);
    expect(primary.words, isEmpty);
    fixture.clock
        .sync(const PlaybackTimelineMessage(1, 1500, true, playbackRate: 2));
    await tester.pump();
    expect(identical(_painter(tester), painter), true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
