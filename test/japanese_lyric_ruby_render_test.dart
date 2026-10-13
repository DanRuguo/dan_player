import 'dart:ui' as drawing;
import 'dart:convert';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/lyric_ruby.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'lyric_letter_spacing_visible_feedback_test.dart'
    show expectMainSpacingGroup;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, sizePlaylistFeature;

const _text = '夜空 e\u0301 航海';
const _spans = [
  JapaneseLyricReadingSpan(start: 0, end: 2, text: 'よぞら'),
  JapaneseLyricReadingSpan(start: 6, end: 8, text: 'こうかい'),
];
const _desktopSpans = [
  DesktopJapaneseReadingSpan(start: 0, end: 2, text: 'よぞら'),
  DesktopJapaneseReadingSpan(start: 6, end: 8, text: 'こうかい'),
];

class _Word extends SyncLyricWord {
  _Word(int start, String text)
      : super(Duration(milliseconds: start), const Duration(milliseconds: 1800),
            text);
}

class _Line extends SyncLyricLine {
  _Line()
      : super(
            Duration.zero,
            const Duration(seconds: 8),
            [_Word(0, '夜空 '), _Word(700, 'e\u0301 '), _Word(1400, '航海')],
            'Night sailing') {
    romanization = 'yozora koukai';
    japaneseReading = 'よぞら e\u0301 こうかい';
    japaneseReadingSpans = _spans;
  }
}

List<CustomPainter> _painters(WidgetTester tester, Finder root) => tester
    .widgetList<CustomPaint>(
        find.descendant(of: root, matching: find.byType(CustomPaint)))
    .map((paint) => paint.painter)
    .whereType<CustomPainter>()
    .toList();

void _horizontalRuby(LyricRubyLayout ruby, double primarySize) {
  expect(ruby.glyphs, hasLength(2));
  for (final glyph in ruby.glyphs) {
    expect(glyph.painter.text!.toPlainText(), glyph.span.text);
    expect(glyph.painter.text!.style!.fontSize,
        inInclusiveRange(primarySize * .225, primarySize * .45));
    expect(glyph.offset.dx + glyph.painter.width / 2,
        closeTo(glyph.source.center.dx, .05));
    expect(
        glyph.offset.dy + glyph.painter.height, lessThan(glyph.sourceInkTop));
  }
  final first = ruby.glyphs.first.offset & ruby.glyphs.first.painter.size;
  final last = ruby.glyphs.last.offset & ruby.glyphs.last.painter.size;
  expect(first.overlaps(last), isFalse);
}

Widget _host(Widget child,
    {UiLanguage language = UiLanguage.zh, double scale = 1}) {
  final policy = AppFontPolicy.defaults(language: language);
  return MaterialApp(
    theme: ThemeData(
        fontFamily: policy.uiFamily,
        fontFamilyFallback: policy.fallback,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    home: AppFontScope(
        policy: policy,
        child: Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(body: SingleChildScrollView(child: child))))),
  );
}

Future<List<int>> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData(
                format: drawing.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    }))!;

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  if (!onlyRender) {
    test(
        'desktop ruby protocol is optional and preserves source offsets and authors',
        () {
      const message = LyricLineTimelineMessage(
          sequence: 4,
          lineIndex: 2,
          startMilliseconds: 700,
          lengthMilliseconds: 4000,
          content: _text,
          translation: 'Night sailing',
          romanization: 'yozora koukai',
          japaneseReading: 'よぞら e\u0301 こうかい',
          japaneseReadingSpans: _desktopSpans,
          words: [DesktopLyricWord(700, 1800, _text)]);
      final payload = Map<String, dynamic>.from(
          (jsonDecode(message.buildMessageJson()) as Map)['message'] as Map);
      final copy = LyricLineTimelineMessage.fromJson(payload);
      expect(copy.romanization, 'yozora koukai');
      expect(copy.japaneseReading, message.japaneseReading);
      expect(
          copy.japaneseReadingSpans
              .map((span) => (span.start, span.end, span.text)),
          _desktopSpans.map((span) => (span.start, span.end, span.text)));
      expect(copy.words.single.content, _text);
      expect(copy.words.single.startMilliseconds, 700);
      final legacy = Map<String, dynamic>.of(payload)
        ..remove('japaneseReading')
        ..remove('japaneseReadingSpans');
      final old = LyricLineTimelineMessage.fromJson(legacy);
      expect(old.japaneseReading, isNull);
      expect(old.japaneseReadingSpans, isEmpty);
      final line = _Line();
      final reading = lyricReadingText(line);
      expect(reading.indexOf('yozora'), lessThan(reading.indexOf('よぞら')));
      expect(reading.indexOf('よぞら'), lessThan(reading.indexOf('夜空')));
      expect(reading.indexOf('夜空'), lessThan(reading.indexOf('Night sailing')));
    });
  }

  for (final language in UiLanguage.values) {
    if (onlyRender && language != UiLanguage.zh && language != UiLanguage.ja) {
      continue;
    }
    for (final (width, scale) in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'ruby stays on source glyphs ${language.code} width=$width scale=$scale',
          (tester) async {
        sizePlaylistFeature(tester, width: width, height: 1500);
        final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
        final controller = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}),
            appearance: appearance)
          ..lyricFontSize = 22
          ..translationFontSize = 16
          ..lyricTextAlign = LyricTextAlign.left;
        final position = ValueNotifier(const Duration(milliseconds: 1400));
        final clock = PlaybackClock(automaticTicks: false);
        addTearDown(controller.dispose);
        addTearDown(appearance.dispose);
        addTearDown(position.dispose);
        addTearDown(clock.dispose);
        final timed = _Line();
        final plain =
            LrcLine(Duration.zero, '$_text┃Night sailing', isBlank: false)
              ..romanization = timed.romanization
              ..japaneseReading = timed.japaneseReading
              ..japaneseReadingSpans = _spans;
        final boundary = GlobalKey();
        const plainKey = ValueKey('ruby-plain');
        const timedKey = ValueKey('ruby-timed');
        await tester.pumpWidget(_host(
            ChangeNotifierProvider.value(
                value: controller,
                child: RepaintBoundary(
                  key: boundary,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        LyricViewTile(
                            key: plainKey,
                            line: plain,
                            position: position,
                            opacity: 1,
                            distance: 0,
                            reducedMotion: false),
                        LyricViewTile(
                            key: timedKey,
                            line: timed,
                            position: position,
                            opacity: 1,
                            distance: 0,
                            reducedMotion: false),
                        for (final vertical in [false, true])
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: DesktopLyricLineContent(
                                key: ValueKey(('ruby-desktop', vertical)),
                                detailedLine: LyricLineTimelineMessage(
                                    sequence: 1,
                                    lineIndex: 0,
                                    startMilliseconds: 0,
                                    lengthMilliseconds: 8000,
                                    content: _text,
                                    translation: 'Night sailing',
                                    romanization: timed.romanization,
                                    japaneseReading: timed.japaneseReading,
                                    japaneseReadingSpans: _desktopSpans,
                                    words: [
                                      for (final word in timed.words)
                                        DesktopLyricWord(
                                            word.start.inMilliseconds,
                                            word.length.inMilliseconds,
                                            word.content)
                                    ]),
                                legacyLine: const LyricLineChangedMessage(
                                    '', Duration.zero, null),
                                clock: clock,
                                vertical: vertical,
                                color: Colors.teal,
                                lyricFontSize: 22,
                                translationFontSize: 16,
                              )),
                      ])),
                )),
            language: language,
            scale: scale));
        await tester.pumpAndSettle();
        final plainPainter = _painters(tester, find.byKey(plainKey))
            .whereType<PlainLyricWordFollowPainter>()
            .firstWhere((paint) => paint.text.text!.toPlainText() == _text);
        final timedPainter = _painters(tester, find.byKey(timedKey))
            .whereType<LyricWordHighlightPainter>()
            .single;
        _horizontalRuby(plainPainter.ruby!, 33);
        _horizontalRuby(timedPainter.rubyLayout!, 33);
        expect(plainPainter.ruby!.glyphs.first.painter.text!.style!.fontFamily,
            isNotNull);
        for (final vertical in [false, true]) {
          final root = find.byKey(ValueKey(('ruby-desktop', vertical)));
          final primary = _painters(tester, root)
              .whereType<DesktopLyricTextPainter>()
              .firstWhere((paint) => paint.rubyLayout != null);
          final ruby = primary.rubyLayout!;
          expect(ruby.glyphs, hasLength(2));
          if (!vertical) {
            _horizontalRuby(ruby, 22);
          } else {
            for (final glyph in ruby.glyphs) {
              expect(glyph.offset.dx, greaterThan(glyph.source.right));
              expect(glyph.offset.dy + glyph.painter.height / 2,
                  closeTo(glyph.source.center.dy, .05));
              expect(glyph.painter.text!.toPlainText().replaceAll('\n', ''),
                  glyph.span.text);
            }
          }
          final semantics = tester
              .widget<Semantics>(find
                  .descendant(of: root, matching: find.byType(Semantics))
                  .first)
              .properties
              .label!;
          expect(semantics,
              'yozora koukai\nよぞら e\u0301 こうかい\n$_text\nNight sailing');
        }
        expect(timed.words.map((word) => word.content).join(), _text);
        expect(timed.words.map((word) => word.start.inMilliseconds),
            [0, 700, 1400]);
        final pixels = await _pixels(tester, boundary);
        expect(pixels.any((value) => value != 255 && value != 0), isTrue);
        await capturePlaylistFeature(
            tester, boundary, 'ruby-${language.code}-${width.toInt()}-$scale');
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  if (onlyRender) return;

  testWidgets(
      'a wrapped Han word keeps its complete reading on the first real fragment',
      (tester) async {
    const text = '東京航海';
    const spans = [
      JapaneseLyricReadingSpan(start: 0, end: 4, text: 'とうきょうこうかい')
    ];
    await tester.pumpWidget(_host(const SizedBox(
        width: 90,
        child: BalancedLyricText(text,
            style: TextStyle(fontSize: 40, color: Colors.black),
            textAlign: TextAlign.left,
            rubySpans: spans))));
    await tester.pumpAndSettle();
    final painter = _painters(tester, find.byType(BalancedLyricText))
        .whereType<PlainLyricWordFollowPainter>()
        .single;
    final boxes = painter.text.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4));
    expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
    final ruby = painter.ruby!.glyphs.single;
    expect(ruby.painter.text!.toPlainText(), spans.single.text);
    expect(ruby.source.top, closeTo(boxes.first.top, .05));
    expect(ruby.source.bottom, closeTo(boxes.first.bottom, .05));
    expect(ruby.offset.dx, greaterThanOrEqualTo(0));
    expect(ruby.offset.dx + ruby.painter.width,
        lessThanOrEqualTo(painter.text.width + .05));
    expect(ruby.painter.text!.style!.fontSize, greaterThanOrEqualTo(9));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final timed in [false, true]) {
    testWidgets(
        'ruby keeps cached font shapes through spacing and font morph '
        'timed=$timed', (tester) async {
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance)
        ..lyricFontSize = 22
        ..lyricTextAlign = LyricTextAlign.left;
      final position = ValueNotifier(const Duration(seconds: 20));
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(position.dispose);
      final line =
          timed ? _Line() : LrcLine(Duration.zero, _text, isBlank: false)
            ..japaneseReading = 'よぞら e\u0301 こうかい'
            ..japaneseReadingSpans = _spans;
      var width = 500.0;
      var fresh = false;
      final boundary = GlobalKey();
      Widget host() => _host(ChangeNotifierProvider.value(
          value: controller,
          child: RepaintBoundary(
              key: boundary,
              child: Material(
                  color: Colors.white,
                  child: SizedBox(
                      width: width,
                      child: LyricViewTile(
                          key: ValueKey(fresh),
                          line: line,
                          position: position,
                          opacity: 1,
                          distance: 0,
                          reducedMotion: false))))));
      List<({TextPainter text, LyricRubyLayout ruby})> endpoints() => [
            for (final painter in _painters(tester, find.byKey(boundary)))
              if (painter is LyricWordHighlightPainter)
                (text: painter.text, ruby: painter.rubyLayout!)
              else if (painter is PlainLyricWordFollowPainter &&
                  painter.text.text!.toPlainText() == _text)
                (text: painter.text, ruby: painter.ruby!)
          ];
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final before = await _pixels(tester, boundary);
      controller.setLyricLetterSpacing(8);
      await tester.pump();
      final shapes = endpoints();
      expect(shapes, hasLength(1),
          reason:
              'Spacing enters the final primary and ruby layout immediately');
      Finder primary() => find.descendant(
          of: find.byKey(boundary),
          matching: find.byWidgetPredicate((widget) =>
              widget is CustomPaint &&
              (widget.painter is LyricWordHighlightPainter ||
                  (widget.painter is PlainLyricWordFollowPainter &&
                      (widget.painter as PlainLyricWordFollowPainter)
                              .text
                              .text!
                              .toPlainText() ==
                          _text))));
      expectMainSpacingGroup(tester, primary(), 0);
      for (final endpoint in shapes) {
        _horizontalRuby(endpoint.ruby, 33);
      }
      await tester.pump(const Duration(milliseconds: 32));
      expectMainSpacingGroup(
          tester,
          primary(),
          LyricMotion.curve
              .transform(32 / LyricMotion.spacingDuration.inMilliseconds));
      final group = find
          .ancestor(
              of: primary(),
              matching: find.byWidgetPredicate((widget) =>
                  widget is Transform &&
                  widget.filterQuality == FilterQuality.low))
          .evaluate()
          .single;
      for (final auxiliary in find
          .descendant(
              of: find.byKey(boundary),
              matching: find.byWidgetPredicate((widget) =>
                  widget is CustomPaint &&
                  widget.painter is PlainLyricWordFollowPainter))
          .evaluate()) {
        final owner = find
            .ancestor(
                of: find.byWidget(auxiliary.widget),
                matching: find.byWidgetPredicate((widget) =>
                    widget is Transform &&
                    widget.filterQuality == FilterQuality.low))
            .evaluate()
            .single;
        expect(owner, same(group),
            reason:
                'Romanization and translation use the exact same group transform');
      }
      expect(await _pixels(tester, boundary), isNot(before));
      expect(endpoints(), shapes,
          reason:
              'Presentation frames reuse the fixed target primary/ruby shapes');
      await capturePlaylistFeature(
          tester, boundary, 'ruby-spacing-${timed ? 'timed' : 'plain'}-mid');
      await tester.pumpAndSettle();
      // A+ uses the existing two-endpoint font morph; preset/slider setFontSize
      // deliberately uses one target painter with the direct-size transform.
      for (var step = 0; step < 10; step++) {
        controller.increaseFontSize();
      }
      await tester.pump();
      final fontEndpoints = endpoints();
      expect(fontEndpoints, hasLength(2));
      for (final endpoint in fontEndpoints) {
        _horizontalRuby(endpoint.ruby, endpoint.text.text!.style!.fontSize!);
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(endpoints(), fontEndpoints);
      await tester.pumpAndSettle();
      final settled = endpoints().single;
      expect(settled.text.text!.style!.fontSize, 48);
      width = 490;
      await tester.pumpWidget(host());
      final resized = endpoints().single;
      expect(resized.text, same(settled.text));
      expect(resized.ruby.glyphs.map((glyph) => glyph.painter),
          settled.ruby.glyphs.map((glyph) => glyph.painter),
          reason:
              'Width-only geometry does not reshape the same ruby font fit');
      final cached = await _pixels(tester, boundary);
      fresh = true;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(await _pixels(tester, boundary), cached,
          reason:
              'Retained primary/ruby geometry equals fresh actual glyph ink');
      expect(position.value, const Duration(seconds: 20));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a timed Han reading follows the union of its actual moving glyphs',
      (tester) async {
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance)
      ..lyricFontSize = 22
      ..lyricTextAlign = LyricTextAlign.left;
    final position = ValueNotifier(const Duration(seconds: 20));
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(position.dispose);
    final line = _Line();
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(ChangeNotifierProvider.value(
        value: controller,
        child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
                width: 500,
                child: LyricViewTile(
                    line: line,
                    position: position,
                    opacity: 1,
                    distance: 0,
                    reducedMotion: false))))));
    await tester.pumpAndSettle();
    LyricWordHighlightPainter painter() =>
        _painters(tester, find.byKey(boundary))
            .whereType<LyricWordHighlightPainter>()
            .single;
    final original = painter();
    final stationary = original.paintedRubyBounds;
    final pixels = await _pixels(tester, boundary);
    expect(original.rubyLayout!.glyphs.first.motionParts.length,
        greaterThanOrEqualTo(2),
        reason: 'Both Han glyphs own the full word reading');
    position.value = const Duration(milliseconds: 500);
    await tester.pump();
    final moving = painter();
    expect(moving.layoutIdentity, same(original.layoutIdentity));
    expect(moving.rubyLayout, same(original.rubyLayout));
    expect(moving.movingWordCount, greaterThan(0));
    expect(moving.paintedRubyBounds.first.top,
        lessThan(stationary.first.top - .1));
    expect(await _pixels(tester, boundary), isNot(pixels));
    await capturePlaylistFeature(tester, boundary, 'ruby-timed-emphasis-mid');
    position.value = const Duration(seconds: 20);
    await tester.pump();
    expect(painter().paintedRubyBounds, stationary);
    expect(await _pixels(tester, boundary), pixels);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
