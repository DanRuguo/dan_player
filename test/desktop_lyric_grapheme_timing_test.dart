import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

DesktopLyricTextPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<DesktopLyricTextPainter>()
    .single;

Widget _host(PlaybackClock clock, String text, List<DesktopLyricWord> words,
        {required bool vertical, double scale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Center(
          child: DesktopLyricText(
            key: UniqueKey(),
            clock: clock,
            text: text,
            words: words,
            vertical: vertical,
            style: const TextStyle(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: [
                  'Segoe UI Emoji',
                  ...danFontFamilyFallback
                ],
                fontSize: 32,
                height: 1.3),
            playedColor: const Color(0xff11bbee),
            unplayedColor: const Color(0xffee3311),
          ),
        ),
      ),
    );

Future<Uint8List> _pixels(WidgetTester tester) async {
  final size = tester.getSize(find.byType(DesktopLyricText));
  final recorder = drawing.PictureRecorder();
  _painter(tester).paint(Canvas(recorder), size);
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
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) difference++;
  }
  return difference;
}

void main({bool includeAutomaticSampling = true}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final emoji = File('$windows/Fonts/seguiemj.ttf');
      if (await emoji.exists()) {
        await (FontLoader('Segoe UI Emoji')
              ..addFont(Future.value(
                  ByteData.sublistView(await emoji.readAsBytes()))))
            .load();
      }
    }
  });

  final clusters = <String, List<String>>{
    'accent': ['e', '\u0301'],
    'family emoji': ['👨', '‍👩‍👧‍👦'],
    'flag': ['🇨', '🇳'],
    'Hangul jamo': ['ᄒ', 'ᅡ', 'ᆫ'],
  };
  for (final entry in clusters.entries) {
    for (final vertical in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'split ${entry.key} matches complete glyph timing vertical=$vertical scale=$scale',
            (tester) async {
          final clock = PlaybackClock(automaticTicks: false);
          addTearDown(clock.dispose);
          final text = '${entry.value.join()} X';
          final split = <DesktopLyricWord>[
            for (var index = 0; index < entry.value.length; index++)
              DesktopLyricWord(index * 600, 800, entry.value[index]),
            const DesktopLyricWord(2500, 500, ' X'),
          ];
          final end = (entry.value.length - 1) * 600 + 800;
          final complete = [
            DesktopLyricWord(0, end, entry.value.join()),
            const DesktopLyricWord(2500, 500, ' X'),
          ];
          Uint8List? before;
          Uint8List? partial;
          Uint8List? after;
          for (final position in [0, end ~/ 2, end - 1, 3200]) {
            clock.sync(PlaybackTimelineMessage(1, position, false));
            await tester.pumpWidget(
                _host(clock, text, split, vertical: vertical, scale: scale));
            final actual = await _pixels(tester);
            await tester.pumpWidget(
                _host(clock, text, complete, vertical: vertical, scale: scale));
            final reference = await _pixels(tester);
            expect(_difference(actual, reference), 0,
                reason: 'A shared glyph uses the union of authored timing at '
                    '$position ms, including its following independent word');
            if (position == 0) before = reference;
            if (position == end ~/ 2) partial = reference;
            if (position == 3200) after = reference;
          }
          expect(_difference(before!, partial!), greaterThan(0));
          expect(_difference(partial, after!), greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  // Native painting uses fixed media positions. The automated binding alone
  // advances fake time for the two independent sampler ownership cases.
  if (!includeAutomaticSampling) return;
  for (final vertical in [false, true]) {
    testWidgets(
        'split glyph retains sampling until its final fragment vertical=$vertical',
        (tester) async {
      final clock = PlaybackClock(
          nowMilliseconds: () =>
              tester.binding.clock.now().millisecondsSinceEpoch);
      addTearDown(clock.dispose);
      var samples = 0;
      clock.addListener(() => samples++);
      clock.sync(const PlaybackTimelineMessage(1, 0, true));
      await tester.pumpWidget(_host(
          clock,
          '👨‍👩‍👧‍👦',
          const [
            DesktopLyricWord(0, 300, '👨'),
            DesktopLyricWord(300, 1700, '‍👩‍👧‍👦'),
          ],
          vertical: vertical));
      await tester.pump(const Duration(milliseconds: 500));
      samples = 0;
      await tester.pump(const Duration(milliseconds: 300));
      expect(samples, greaterThan(0),
          reason: 'Its second authored fragment is still being sung');
      await tester.pump(const Duration(seconds: 2));
      samples = 0;
      final position = clock.positionMilliseconds;
      await tester.pump(const Duration(seconds: 1));
      expect(samples, 0);
      expect(clock.positionMilliseconds, position + 1000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
