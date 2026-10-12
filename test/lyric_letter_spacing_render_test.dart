import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/desktop_lyric_test_support.dart';

const _parts = [
  '晨光かな ',
  'English e\u0301 ',
  '한글 ',
  '👩',
  '🏽‍🚀 ',
  'שלום العربية'
];
final _text = _parts.join();
// Split author fragments share one complete glyph and their original interval.
const _displayTimes = [
  (0, 600),
  (400, 600),
  (800, 600),
  (1200, 1000),
  (2000, 600)
];

class _Word extends SyncLyricWord {
  _Word(int index, String content)
      : super(Duration(milliseconds: index * 400),
            const Duration(milliseconds: 600), content);
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 8),
            [for (final (index, part) in _parts.indexed) _Word(index, part)]);
}

class _Document extends Lyric {
  _Document(super.lines);
}

class _Source extends TaskbarLyricSource {
  @override
  Future<Lyric?> lyric = Future.value(_Document([_Line()]));
  @override
  int get generation => 1;
  @override
  int get session => 1;
  @override
  bool get hasTrack => true;
  @override
  double get position => 1.55;
  @override
  bool get playing => false;
}

Future<void> loadLetterSpacingFonts() =>
    ensureAppFontsLoaded(AppFontPolicy.defaults());

({TextPainter text, CustomPainter painter, Size size}) _mainPaint(
    GlobalKey key) {
  ({TextPainter text, CustomPainter painter, Size size})? result;
  void visit(Element element) {
    if (element.widget case CustomPaint(painter: final painter)) {
      final text = switch (painter) {
        PlainLyricWordFollowPainter() => painter.text,
        LyricWordHighlightPainter() => painter.text,
        _ => null,
      };
      if (text != null && text.text!.toPlainText() == _text) {
        result = (
          text: text,
          painter: painter!,
          size: (element.renderObject! as RenderBox).size
        );
      }
    }
    element.visitChildren(visit);
  }

  visit(key.currentContext! as Element);
  return result!;
}

DesktopLyricTextPainter _desktopPaint(WidgetTester tester, Key key) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byKey(key), matching: find.byType(CustomPaint)))
    .painter! as DesktopLyricTextPainter;

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return Uint8List.fromList(
            (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

Future<Uint8List> _desktopPixels(WidgetTester tester, Key key) async {
  final size = tester.getSize(find.byKey(key));
  final recorder = drawing.PictureRecorder();
  _desktopPaint(tester, key).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  return (await tester.runAsync(() async {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      return Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

int _ink(Uint8List rgba) {
  var ink = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] > 0 &&
        (rgba[i] < 245 || rgba[i + 1] < 245 || rgba[i + 2] < 245)) {
      ink++;
    }
  }
  return ink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  test('letter spacing persists once in the legacy-compatible appearance', () {
    final old = DesktopLyricAppearance.defaults.toJson()
      ..remove('lyricLetterSpacing');
    expect(DesktopLyricAppearance.tryFromJson(old)!.lyricLetterSpacing, 0);
    for (final value in [0.0, .5, 12.0]) {
      final appearance =
          DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: value);
      expect(
          DesktopLyricAppearance.tryFromJson(appearance.toJson()), appearance);
      expect(DesktopLyricAppearance.fromJson(appearance.toJson()), appearance);
      expect(appearance.toJson()['lyricLetterSpacing'], value);
    }
  });
  test('invalid spacing cannot overwrite a good pipe snapshot', () {
    for (final invalid in [-.5, 12.5, double.nan, double.infinity, '3', null]) {
      final map = DesktopLyricAppearance.defaults.toJson()
        ..['lyricLetterSpacing'] = invalid;
      expect(DesktopLyricAppearance.tryFromJson(map), isNull);
      expect(DesktopLyricAppearance.fromJson(map).lyricLetterSpacing, 0);
    }
  });
  test('desktop edits clamp spacing and applying snapshots does not echo', () {
    final sent = <DesktopLyricAppearance>[];
    final controller = TextDisplayController(onChanged: sent.add);
    addTearDown(controller.dispose);
    controller.setLyricLetterSpacing(-2);
    controller.setLyricLetterSpacing(double.nan);
    expect(sent, isEmpty);
    controller.setLyricLetterSpacing(20);
    expect(sent.single.lyricLetterSpacing, 12);
    controller.value = controller.value.copyWith(lyricLetterSpacing: 3);
    expect(sent, hasLength(1));
    expect(controller.lyricLetterSpacing, 3);
  });
  test('main spacing follows only the shared geometry value and detaches',
      () async {
    final source = ValueNotifier(DesktopLyricAppearance.defaults);
    final preferences = NowPlayingPagePreference.fromMap({});
    var saved = 0, changes = 0;
    final controller = LyricViewController(
        preferences: preferences,
        appearance: source,
        persistAppearance: () async {
          saved++;
        });
    controller.addListener(() => changes++);
    source.value = source.value.copyWith(backgroundOpacity: .5);
    expect(changes, 0);
    controller.setLyricLetterSpacing(3);
    expect(changes, 1);
    expect(source.value.lyricLetterSpacing, 3);
    expect(saved, 0);
    await controller.persistLetterSpacing();
    expect(saved, 1);
    controller.dispose();
    source.value = source.value.copyWith(lyricLetterSpacing: 4);
    expect(changes, 1);
    source.dispose();
  });

  test(
      'initial and canonical spacing IPC retain the media clock and never echo',
      () {
    final sent = <String>[];
    final source = DesktopLyricController.detached(
        sendMessage: sent.add, clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    final initial = InitArgsMessage(
        false, 'title', '', '', false, 0xff000000, 0xffffffff, 0xff000000,
        appearance:
            DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: 3));
    source.applyInitialState(InitArgsMessage.fromJson(initial.toJson()));
    source.handleMessage(
        const PlaybackTimelineMessage(3, 1550, false, playbackRate: 2)
            .buildMessageJson());
    source.handleMessage(DesktopLyricAppearanceMessage(
            source.appearance.value.copyWith(lyricLetterSpacing: 6),
            revision: 1)
        .buildMessageJson());
    expect(source.appearance.lyricLetterSpacing, 6);
    expect(source.playbackClock.positionMilliseconds, 1550);
    expect(source.playbackClock.playbackRate, 2);
    expect(sent, isEmpty);
  });

  for (final language in UiLanguage.values) {
    for (final timed in [false, true]) {
      testWidgets(
          'main ${language.code} ${timed ? 'timed' : 'plain'} spacing reflows complete glyphs and retains width shaping',
          (tester) async {
        final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
        final settings = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}),
            appearance: appearance)
          ..lyricFontSize = 20
          ..lyricTextAlign = LyricTextAlign.left;
        final position = ValueNotifier(const Duration(milliseconds: 1550));
        final render =
            ValueNotifier(const RenderingPreferences(surfaceBlur: false));
        addTearDown(settings.dispose);
        addTearDown(appearance.dispose);
        addTearDown(position.dispose);
        addTearDown(render.dispose);
        final line =
            timed ? _Line() : LrcLine(Duration.zero, _text, isBlank: false);
        final author = line is SyncLyricLine
            ? [
                for (final word in line.words)
                  (word.start, word.length, word.content)
              ]
            : null;
        final retained = GlobalKey(), fresh = GlobalKey();
        TextPainter? previousSpacing;
        var revision = 0;
        for (final spacing in [0.0, 3.0, 12.0, 0.0]) {
          settings.setLyricLetterSpacing(spacing);
          TextPainter? shaped;
          for (final width in [340.0, 260.0, 259.0, 340.0]) {
            revision++;
            Widget pane(GlobalKey key, Key identity) => RepaintBoundary(
                key: key,
                child: Material(
                    color: Colors.white,
                    textStyle: const TextStyle(
                        fontSize: 20, letterSpacing: .5, color: Colors.black),
                    child: SizedBox(
                        width: width,
                        height: 450,
                        child: SingleChildScrollView(
                            child: LyricViewTile(
                                key: identity,
                                line: line,
                                position: position,
                                opacity: 1,
                                distance: 0,
                                reducedMotion: false)))));
            await tester.pumpWidget(MaterialApp(
                home: AppFontScope(
                    policy: AppFontPolicy.defaults(language: language),
                    child: RenderingPreferencesScope(
                        preferences: render,
                        child: Directionality(
                            textDirection: language == UiLanguage.en
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: DefaultTextStyle(
                                style: const TextStyle(
                                    fontSize: 20,
                                    letterSpacing: .5,
                                    color: Colors.black),
                                child: ChangeNotifierProvider.value(
                                    value: settings,
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          pane(retained,
                                              const ValueKey('retained')),
                                          const SizedBox(width: 16),
                                          pane(fresh, ValueKey(revision))
                                        ]))))))));
            await tester.pumpAndSettle();
            final actual = _mainPaint(retained), expected = _mainPaint(fresh);
            expect(actual.text.text!.toPlainText(), _text);
            expect(actual.text.text!.style!.letterSpacing, spacing + .5);
            expect(actual.text.size, expected.text.size);
            expect(actual.text.height, lessThan(420));
            if (shaped != null) {
              expect(actual.text, same(shaped),
                  reason: 'Pure adjacent width changes must not shape again');
            }
            shaped = actual.text;
            final rgba = await _pixels(tester, retained);
            expect(_ink(rgba), greaterThan(100));
            expect(listEquals(rgba, await _pixels(tester, fresh)), isTrue);
            if (actual.painter case final LyricWordHighlightPainter highlight) {
              final reference = expected.painter as LyricWordHighlightPainter;
              expect(highlight.shapedWordCount, reference.shapedWordCount);
              final progress = [
                for (var i = 0; i < (line as SyncLyricLine).words.length; i++)
                  highlight.progressForWord(i)
              ];
              expect(progress, [
                for (var i = 0; i < line.words.length; i++)
                  reference.progressForWord(i)
              ]);
              for (final (index, word) in line.words.indexed) {
                expect(
                    progress[index],
                    ((position.value - word.start).inMicroseconds /
                            word.length.inMicroseconds)
                        .clamp(0.0, 1.0));
              }
            }
            final tail = _text.length - 'العربية'.length;
            expect(
                actual.text.getBoxesForSelection(TextSelection(
                    baseOffset: tail, extentOffset: _text.length)),
                isNotEmpty,
                reason: 'The last authored characters cannot disappear');
          }
          if (previousSpacing != null) {
            expect(shaped, isNot(same(previousSpacing)));
          }
          previousSpacing = shaped;
        }
        if (line is SyncLyricLine) {
          expect([
            for (final word in line.words)
              (word.start, word.length, word.content)
          ], author);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final vertical in [false, true]) {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      testWidgets(
          'desktop spacing stroke and timed geometry match fresh vertical=$vertical direction=$direction',
          (tester) async {
        final clock = PlaybackClock(automaticTicks: false);
        addTearDown(clock.dispose);
        clock.sync(const PlaybackTimelineMessage(1, 1550, false));
        final words = [
          for (final (index, part) in _parts.indexed)
            DesktopLyricWord(index * 400, 600, part)
        ];
        const retained = ValueKey('spacing-retained'),
            fresh = ValueKey('spacing-fresh');
        List<Object>? previousSpacing;
        for (final spacing in [0.0, 3.0, 12.0, 0.0]) {
          List<Object>? shaping;
          for (final width in vertical
              ? [160.0, 48.0, 47.0, 160.0]
              : [340.0, 160.0, 159.0, 340.0]) {
            Widget text(Key key) => DesktopLyricText(
                key: key,
                text: _text,
                words: words,
                clock: clock,
                vertical: vertical,
                verticalLetterSpacing: spacing,
                maxHorizontalWidth: vertical ? null : width,
                maxVerticalUnitWidth: vertical ? width : null,
                style: TextStyle(
                    fontSize: 26, height: 1.3, letterSpacing: .5 + spacing),
                playedColor: Colors.blue,
                unplayedColor: Colors.red,
                strokeColor: Colors.black);
            await tester.pumpWidget(MaterialApp(
                home: AppFontScope(
                    policy: AppFontPolicy.defaults(),
                    child: Directionality(
                        textDirection: direction,
                        child: SingleChildScrollView(
                            child: Column(children: [
                          text(retained),
                          KeyedSubtree(key: UniqueKey(), child: text(fresh))
                        ]))))));
            // Compare the complete settled glyphs. A retained spacing edit
            // now follows the player's finite lyric presentation transition.
            await tester.pumpAndSettle();
            final actual = _desktopPaint(tester, retained);
            final identities = actual.cachedShapingIdentities;
            if (shaping != null) expect(identities, orderedEquals(shaping));
            shaping = identities;
            expect(
                listEquals(await _desktopPixels(tester, retained),
                    await _desktopPixels(tester, fresh)),
                isTrue);
            for (final (index, interval) in _displayTimes.indexed) {
              expect(actual.progressForWord(index),
                  ((1550 - interval.$1) / interval.$2).clamp(0.0, 1.0));
            }
            if (vertical) {
              final units = desktopLyricVerticalUnits(_text);
              expect(
                  actual.glyphs
                      .map((glyph) => (glyph.text, glyph.start, glyph.end)),
                  units.map((glyph) => (glyph.text, glyph.start, glyph.end)));
            }
          }
          if (previousSpacing != null) {
            expect(shaping!.first, isNot(same(previousSpacing.first)));
          }
          previousSpacing = shaping;
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets(
      'desktop vertical tracking adds one gap per upright unit and preserves natural style',
      (tester) async {
    final clock = PlaybackClock(automaticTicks: false);
    addTearDown(clock.dispose);
    const text = '晨光👩🏽‍🚀';
    final heights = <double>[];
    for (final spacing in [0.0, 3.0]) {
      await tester.pumpWidget(MaterialApp(
          home: DefaultTextStyle(
              style: const TextStyle(fontSize: 22, letterSpacing: .75),
              child: Center(
                  child: DesktopLyricLineContent(
                      detailedLine: null,
                      legacyLine: const LyricLineChangedMessage(
                          text, Duration(seconds: 3)),
                      clock: clock,
                      vertical: true,
                      color: Colors.blue,
                      lyricLetterSpacing: spacing)))));
      await tester.pumpAndSettle();
      final textWidget = tester.widget<DesktopLyricText>(
          find.byKey(const ValueKey('desktop-primary-lyric')));
      expect(textWidget.style.letterSpacing, spacing == 0 ? null : 3.75);
      final painter =
          _desktopPaint(tester, const ValueKey('desktop-primary-lyric'));
      expect(painter.glyphs, hasLength(3));
      heights.add(tester
          .getSize(find.byKey(const ValueKey('desktop-primary-lyric')))
          .height);
    }
    expect(heights.last - heights.first, closeTo(6, .001),
        reason: 'Two inter-unit gaps, no intra-emoji or extra trailing gap');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'taskbar shared spacing invalidates fitted glyphs and preserves complete authored text',
      (tester) async {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false), sendMessage: (_) {});
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    addTearDown(source.dispose);
    addTearDown(layout.dispose);
    final words = [
      for (final (index, part) in _parts.indexed)
        DesktopLyricWord(index * 400, 600, part)
    ];
    final message = LyricLineTimelineMessage(
        sequence: 1,
        lineIndex: 0,
        startMilliseconds: 0,
        lengthMilliseconds: 8000,
        content: _text,
        translation: null,
        words: words);
    final author = message.buildMessageJson();
    source.handleMessage(author);
    source.playbackClock.sync(const PlaybackTimelineMessage(1, 1550, false));
    DesktopLyricText? reference;
    Widget host() => ValueListenableProvider<ThemeChangedMessage>.value(
        value: source.theme,
        child: MaterialApp(
            home: AppFontScope(
                policy: AppFontPolicy.defaults(),
                child: Scaffold(
                    body: DefaultTextStyle(
                        style: const TextStyle(fontSize: 22, letterSpacing: .5),
                        child: Column(children: [
                          SizedBox(
                              width: 500,
                              height: 56,
                              child: TaskbarLyricRow(
                                  controller: source,
                                  windowLayout: layout,
                                  sendMessage: (_) {})),
                          if (reference != null) reference
                        ]))))));
    List<Object>? previous;
    for (final spacing in [0.0, 3.0, 12.0, 0.0]) {
      source.appearance.setLyricLetterSpacing(spacing);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      const actualKey = ValueKey('taskbar-single-line-text');
      final actual = tester.widget<DesktopLyricText>(find.byKey(actualKey));
      expect(actual.text, _text);
      expect(actual.style.letterSpacing, spacing + .5);
      final current = _desktopPaint(tester, actualKey).cachedShapingIdentities;
      if (previous != null) expect(current.first, isNot(same(previous.first)));
      previous = current;
      reference = DesktopLyricText(
          key: const ValueKey('taskbar-spacing-reference'),
          text: actual.text,
          clock: actual.clock,
          words: actual.words,
          style: actual.style,
          playedColor: actual.playedColor,
          unplayedColor: actual.unplayedColor,
          strokeColor: actual.strokeColor,
          maxHorizontalWidth: actual.maxHorizontalWidth,
          reducedMotion: actual.reducedMotion);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
          listEquals(
              await _desktopPixels(tester, actualKey),
              await _desktopPixels(
                  tester, const ValueKey('taskbar-spacing-reference'))),
          isTrue);
      expect(message.buildMessageJson(), author);
      expect(source.playbackClock.positionMilliseconds, 1550);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  test(
      'native taskbar publishes spacing on appearance refresh without changing media or authored words',
      () async {
    final source = _Source();
    final writes = <Map<String, Object>>[];
    var spacing = 0.0;
    final publisher = TaskbarLyricsPublisher(
        source: source,
        appearance: () => TaskbarLyricAppearance(
            accent: 42,
            fontFamily: 'fixture',
            fontPath: 'fixture.ttf',
            lyricLetterSpacing: spacing),
        send: (payload) async {
          writes.add(payload);
        },
        onError: (error, stack) => fail('$error\n$stack'),
        elapsed: () => Duration.zero);
    addTearDown(() async {
      await publisher.close();
      source.dispose();
    });
    await Future<void>.delayed(Duration.zero);
    final before = Map<String, Object>.of(writes.last);
    expect(before['lyricLetterSpacing'], 0);
    spacing = 3;
    publisher.refresh();
    await Future<void>.delayed(Duration.zero);
    final after = writes.last;
    expect(after['lyricLetterSpacing'], 3);
    for (final key in [
      'text',
      'words',
      'positionMilliseconds',
      'lineStartMilliseconds',
      'lineEndMilliseconds'
    ]) {
      expect(after[key], before[key],
          reason: '$key is media data, not typography');
    }
    final count = writes.length;
    publisher.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(writes, hasLength(count));
  });
}
