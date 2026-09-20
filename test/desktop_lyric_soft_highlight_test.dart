import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _textKey = ValueKey('soft-lyric-text');

DesktopLyricTextPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byKey(_textKey), matching: find.byType(CustomPaint)))
    .painter! as DesktopLyricTextPainter;

Widget _host(PlaybackClock clock,
        {String text = 'HHHH',
        bool vertical = false,
        bool stroke = false,
        bool reduced = false,
        bool systemReduced = false,
        bool lyricsEnabled = true,
        TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: systemReduced),
        child: MotionPreferencesScope(
          preferences: MotionPreferences(
              disabled: lyricsEnabled ? const {} : const {MotionKind.lyrics}),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: DesktopLyricText(
                key: _textKey,
                text: text,
                clock: clock,
                style: const TextStyle(fontFamily: 'Ahem', fontSize: 40),
                playedColor: const Color(0xff00ffff),
                unplayedColor: const Color(0xffff0000),
                strokeColor: stroke ? Colors.black : null,
                words: [DesktopLyricWord(0, 1000, text)],
                vertical: vertical,
                reducedMotion: reduced,
              ),
            ),
          ),
        ),
      ),
    );

Future<({Uint8List rgba, int width})> _pixels(WidgetTester tester) async {
  final bounds = tester.getSize(find.byKey(_textKey));
  final recorder = drawing.PictureRecorder();
  _painter(tester).paint(Canvas(recorder), bounds);
  final picture = recorder.endRecording();
  final width = bounds.width.ceil();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(width, bounds.height.ceil());
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
  return (rgba: bytes!, width: width);
}

Set<int> _softCoordinates(({Uint8List rgba, int width}) before,
    ({Uint8List rgba, int width}) partial, ({Uint8List rgba, int width}) after,
    {bool vertical = false}) {
  final result = <int>{};
  for (var i = 0; i < partial.rgba.length; i += 4) {
    if (before.rgba[i + 3] < 250 || after.rgba[i + 3] < 250) continue;
    // Interior pixels between both endpoint colours identify the feather;
    // ordinary antialiasing at the glyph outline is excluded by the endpoints.
    if ((partial.rgba[i] - before.rgba[i]).abs() > 8 &&
        (partial.rgba[i] - after.rgba[i]).abs() > 8) {
      result
          .add(vertical ? (i ~/ 4) ~/ partial.width : (i ~/ 4) % partial.width);
    }
  }
  return result;
}

void main() {
  for (final rtl in [false, true]) {
    testWidgets('desktop soft word edge follows shaped direction rtl=$rtl',
        (tester) async {
      final clock = PlaybackClock(automaticTicks: false);
      addTearDown(clock.dispose);
      await tester.pumpWidget(_host(clock,
          text: rtl ? 'אבגד' : 'HHHH',
          direction: rtl ? TextDirection.rtl : TextDirection.ltr));
      final painter = _painter(tester);
      final cache = painter.layoutCacheIdentity;
      final before = await _pixels(tester);
      clock.sync(const PlaybackTimelineMessage(1, 370, false));
      await tester.pump();
      final partial = await _pixels(tester);
      clock.sync(const PlaybackTimelineMessage(1, 1000, false));
      await tester.pump();
      final after = await _pixels(tester);
      final columns = _softCoordinates(before, partial, after);
      expect(columns.length, greaterThanOrEqualTo(4),
          reason: 'The advancing edge must blend over pixels, not hard clip.');
      expect(columns.length, lessThanOrEqualTo(12));
      final center = columns.reduce((a, b) => a + b) / columns.length;
      expect(center,
          rtl ? greaterThan(partial.width / 2) : lessThan(partial.width / 2));
      expect(_painter(tester), same(painter));
      expect(_painter(tester).layoutCacheIdentity, same(cache));
      clock.sync(const PlaybackTimelineMessage(1, 0, false));
      await tester.pump();
      expect((await _pixels(tester)).rgba, orderedEquals(before.rgba),
          reason: 'Seeking backwards must immediately erase completed fills.');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('vertical soft reveal preserves CJK and complete emoji units',
      (tester) async {
    final clock = PlaybackClock(automaticTicks: false);
    addTearDown(clock.dispose);
    await tester
        .pumpWidget(_host(clock, text: '甲👩‍👩‍👧‍👦乙', vertical: true));
    final before = await _pixels(tester);
    clock.sync(const PlaybackTimelineMessage(1, 220, false));
    await tester.pump();
    final partial = await _pixels(tester);
    clock.sync(const PlaybackTimelineMessage(1, 1000, false));
    await tester.pump();
    final after = await _pixels(tester);
    expect(_painter(tester).glyphs.map((glyph) => glyph.text),
        ['甲', '👩‍👩‍👧‍👦', '乙']);
    final rows = _softCoordinates(before, partial, after, vertical: true);
    expect(rows.length, greaterThanOrEqualTo(4));
    expect(rows.length, lessThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('soft fill leaves cached outline intact and pause stays still',
      (tester) async {
    var now = 0;
    final clock =
        PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
    addTearDown(clock.dispose);
    await tester.pumpWidget(_host(clock, text: 'H H', stroke: true));
    final before = await _pixels(tester);
    final painter = _painter(tester);
    clock.sync(const PlaybackTimelineMessage(1, 330, false));
    await tester.pump();
    final partial = await _pixels(tester);
    var outlinePixels = 0;
    for (var i = 0; i < before.rgba.length; i += 4) {
      if (before.rgba[i] == 0 &&
          before.rgba[i + 1] == 0 &&
          before.rgba[i + 2] == 0 &&
          before.rgba[i + 3] > 128) {
        expect(partial.rgba.sublist(i, i + 4), before.rgba.sublist(i, i + 4));
        outlinePixels++;
      }
    }
    expect(outlinePixels, greaterThan(0));
    expect(painter.cachedStrokePainterCount, 1);
    now = 9000;
    await tester.pump(const Duration(seconds: 2));
    expect((await _pixels(tester)).rgba, orderedEquals(partial.rgba));
    expect(_painter(tester), same(painter));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final disabledBy in ['widget', 'system', 'lyrics']) {
    testWidgets('desktop soft effect obeys $disabledBy motion control',
        (tester) async {
      final clock = PlaybackClock(automaticTicks: false);
      addTearDown(clock.dispose);
      clock.sync(const PlaybackTimelineMessage(1, 1000, false));
      await tester.pumpWidget(_host(clock));
      final fullyPlayed = await _pixels(tester);
      clock.sync(const PlaybackTimelineMessage(1, 370, false));
      await tester.pumpWidget(_host(clock,
          reduced: disabledBy == 'widget',
          systemReduced: disabledBy == 'system',
          lyricsEnabled: disabledBy != 'lyrics'));
      expect(_painter(tester).reducedMotion, isTrue);
      expect((await _pixels(tester)).rgba, orderedEquals(fullyPlayed.rgba));
      await tester.pump();
      clock.sync(const PlaybackTimelineMessage(1, 700, false));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'Disabled text must not subscribe to clock repaint ticks.');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
