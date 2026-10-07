import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/playlist_feature_fixture.dart';

const _actual = ValueKey('taskbar-single-line-text');
const _reference = ValueKey('projected-word-reference');

DesktopLyricTextPainter _painter(WidgetTester tester, Key key) => tester
    .widget<CustomPaint>(find.descendant(
      of: find.byKey(key),
      matching: find.byType(CustomPaint),
    ))
    .painter! as DesktopLyricTextPainter;

Future<Uint8List> _pixels(WidgetTester tester, Key key) async {
  final size = tester.getSize(find.byKey(key));
  final recorder = drawing.PictureRecorder();
  _painter(tester, key).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final pixels = await tester.runAsync(() async {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
  return pixels!;
}

int _difference(Uint8List left, Uint8List right) {
  if (left.length != right.length) return left.length + right.length;
  var result = 0;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) result++;
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  final cases = <({
    String name,
    String? raw,
    List<String> authored,
    List<String> projected,
  })>[
    (
      name: 'CRLF in one span',
      raw: null,
      authored: ['Hello\r\n', 'world'],
      projected: ['Hello ', 'world'],
    ),
    (
      name: 'CRLF across spans',
      raw: null,
      authored: ['Hello\r', '\n', 'world'],
      projected: ['Hello ', '', 'world'],
    ),
    (
      name: 'separator run across spans',
      raw: null,
      authored: ['Hello\t', '\t\r\n', 'world'],
      projected: ['Hello ', '', 'world'],
    ),
    (
      name: 'CJK and divided combining glyph after separators',
      raw: null,
      authored: ['你\r', '\n', 'e', '\u0301', '世界'],
      projected: ['你 ', '', 'e', '\u0301', '世界'],
    ),
    (
      name: 'whole grapheme cutoff at word boundary',
      raw: null,
      authored: ['${'中' * 2047}e\u0301', 'tail'],
      projected: ['${'中' * 2047}e\u0301'],
    ),
    (
      name: 'whole grapheme cutoff across authored spans',
      raw: null,
      authored: ['${'中' * 2047}e', '\u0301X', 'tail'],
      projected: ['${'中' * 2047}e', '\u0301'],
    ),
    (
      name: 'unmatched authored text stays untimed',
      raw: 'Hello world',
      authored: ['Unrelated ', 'word'],
      projected: [],
    ),
  ];
  for (final fixture in cases) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'taskbar text and timing projection ${fixture.name} at $scale',
          (tester) async {
        final clock = PlaybackClock(automaticTicks: false);
        final source =
            DesktopLyricController.detached(clock: clock, sendMessage: (_) {});
        addTearDown(source.dispose);
        final words = [
          for (var index = 0; index < fixture.authored.length; index++)
            DesktopLyricWord(index * 600, 900, fixture.authored[index]),
        ];
        final raw = fixture.raw ?? fixture.authored.join();
        final message = LyricLineTimelineMessage(
            sequence: 1,
            lineIndex: 0,
            startMilliseconds: 0,
            lengthMilliseconds: 10000,
            content: raw,
            translation: null,
            words: words);
        final originalJson = message.buildMessageJson();
        source.handleMessage(originalJson);
        source.appearance.setStrokeEnabled(true);
        final layout =
            DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
        addTearDown(layout.dispose);
        DesktopLyricText? reference;
        Widget host() => ValueListenableProvider<ThemeChangedMessage>.value(
              value: source.theme,
              child: MaterialApp(
                theme: ThemeData(
                    fontFamily: danEmbeddedFontFamily,
                    fontFamilyFallback: danFontFamilyFallback),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Column(children: [
                    SizedBox(
                      width: 600,
                      height: 56,
                      child: TaskbarLyricRow(
                          controller: source,
                          windowLayout: layout,
                          sendMessage: (_) {}),
                    ),
                    if (reference != null) reference,
                  ]),
                ),
              ),
            );
        await tester.pumpWidget(host());
        final text = tester.widget<DesktopLyricText>(find.byKey(_actual));
        final expectedText = raw
            .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
            .characters
            .take(2048)
            .toString();
        expect(text.text, expectedText);
        reference = DesktopLyricText(
            key: _reference,
            text: expectedText,
            clock: clock,
            style: text.style,
            playedColor: text.playedColor,
            unplayedColor: text.unplayedColor,
            strokeColor: text.strokeColor,
            maxHorizontalWidth: text.maxHorizontalWidth,
            words: [
              for (var index = 0; index < fixture.projected.length; index++)
                DesktopLyricWord(index * 600, 900, fixture.projected[index]),
            ]);
        await tester.pumpWidget(host());
        for (final position in [350, 1200, 2300]) {
          clock.sync(PlaybackTimelineMessage(1, position, false));
          await tester.pump();
          expect(
              _difference(await _pixels(tester, _actual),
                  await _pixels(tester, _reference)),
              0,
              reason: 'Visible UTF-16 ranges must reveal the same glyphs as '
                  'normalized authored spans at position=$position');
        }
        final projected =
            tester.widget<DesktopLyricText>(find.byKey(_actual)).words;
        expect(projected.map((word) => word.content), fixture.projected);
        for (var index = 0; index < projected.length; index++) {
          expect(projected[index].startMilliseconds,
              words[index].startMilliseconds);
          expect(projected[index].lengthMilliseconds,
              words[index].lengthMilliseconds);
        }
        expect(message.buildMessageJson(), originalJson,
            reason:
                'Projection must never rewrite the protocol or author data');
        final original = source.detailedLyricLine.value!;
        expect(original.content, raw);
        expect(original.words.map((word) => word.content), fixture.authored);
        final cache = _painter(tester, _actual).cachedShapingIdentities;
        source.appearance.setTextOpacity(.8);
        await tester.pump();
        expect(_painter(tester, _actual).cachedShapingIdentities, cache,
            reason:
                'Nontext appearance updates retain the projected word list');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('taskbar projection follows source ownership and title fallback',
      (tester) async {
    DesktopLyricController controller(int start) {
      final result = DesktopLyricController.detached(
          clock: PlaybackClock(automaticTicks: false), sendMessage: (_) {});
      addTearDown(result.dispose);
      result.detailedLyricLine.value = LyricLineTimelineMessage(
          sequence: 1,
          lineIndex: 0,
          startMilliseconds: start,
          lengthMilliseconds: 10000,
          content: 'Hello\r\nworld',
          translation: null,
          words: [
            DesktopLyricWord(start, 900, 'Hello\r\n'),
            DesktopLyricWord(start + 600, 900, 'world'),
          ]);
      result.playbackClock.sync(const PlaybackTimelineMessage(1, 1200, false));
      return result;
    }

    final first = controller(0);
    final second = controller(3000);
    var source = first;
    var width = 600.0;
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    addTearDown(layout.dispose);
    Widget host() => ValueListenableProvider<ThemeChangedMessage>.value(
          value: source.theme,
          child: MaterialApp(
            theme: ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback),
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: 56,
                child: TaskbarLyricRow(
                    controller: source,
                    windowLayout: layout,
                    sendMessage: (_) {}),
              ),
            ),
          ),
        );
    await tester.pumpWidget(host());
    final projected =
        tester.widget<DesktopLyricText>(find.byKey(_actual)).words;
    final shaping = _painter(tester, _actual).cachedShapingIdentities;
    width = 650;
    await tester.pumpWidget(host());
    expect(tester.widget<DesktopLyricText>(find.byKey(_actual)).words,
        same(projected),
        reason: 'Width belongs to geometry, not text/timing projection');
    expect(_painter(tester, _actual).cachedShapingIdentities, shaping);

    source = second;
    await tester.pumpWidget(host());
    var text = tester.widget<DesktopLyricText>(find.byKey(_actual));
    expect(text.words, isNot(same(projected)));
    expect(text.words.first.startMilliseconds, 3000);
    expect(text.words.map((word) => word.content), ['Hello ', 'world']);
    expect(text.clock, same(second.playbackClock));
    first.detailedLyricLine.value = null;
    first.lyricLine.value =
        const LyricLineChangedMessage('Retired source', Duration.zero);
    await tester.pump();
    expect(tester.widget<DesktopLyricText>(find.byKey(_actual)).text,
        'Hello world',
        reason: 'The retired controller must no longer own the row');

    second.nowPlaying.value =
        const NowPlayingChangedMessage('Title fallback', '', '');
    second.detailedLyricLine.value = const LyricLineTimelineMessage(
        sequence: 2,
        lineIndex: 0,
        startMilliseconds: 0,
        lengthMilliseconds: 10000,
        content: ' \r\n\t',
        translation: null,
        words: [DesktopLyricWord(8000, 5000, ' \r\n\t')]);
    await tester.pump();
    text = tester.widget<DesktopLyricText>(find.byKey(_actual));
    expect(text.text, 'Title fallback');
    expect(text.words, isEmpty,
        reason: 'Blank lyric timing cannot color the unrelated title fallback');
    expect(second.detailedLyricLine.value!.words.single.content, ' \r\n\t');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
