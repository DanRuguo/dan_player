import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _retained = ValueKey('font-policy-retained');
const _fresh = ValueKey('font-policy-fresh');
const _text = '漢字かな English e\u0301 한글 👨🏽‍👩🏻‍👧🏾 שלום';
const _words = [
  DesktopLyricWord(0, 1000, '漢字かな '),
  DesktopLyricWord(1000, 1000, 'English e\u0301 '),
  DesktopLyricWord(2000, 1000, '한글 👨🏽‍👩🏻‍👧🏾 שלום'),
];

AppFontPolicy _uniform(UiLanguage language) => AppFontPolicy(
    language: language,
    mixedScripts: false,
    zh: appBundledFonts[0],
    en: appBundledFonts[0],
    ja: appBundledFonts[0],
    ko: appBundledFonts[0]);

DesktopLyricTextPainter _painter(WidgetTester tester, Key key) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byKey(key), matching: find.byType(CustomPaint)))
    .painter! as DesktopLyricTextPainter;

List<(String, String?)> _leaves(InlineSpan? span) {
  if (span is! TextSpan) return const [];
  return [
    if (span.text?.isNotEmpty == true) (span.text!, span.style?.fontFamily),
    for (final child in span.children ?? const <InlineSpan>[])
      ..._leaves(child),
  ];
}

Widget _host(PlaybackClock clock, AppFontPolicy policy,
    {required bool vertical,
    required TextDirection direction,
    required double width,
    required bool reduced}) {
  Widget text(Key key) => DesktopLyricText(
      key: key,
      text: _text,
      words: _words,
      clock: clock,
      style: TextStyle(
          fontFamily: appBundledFonts[0].family, fontSize: 26, height: 1.3),
      playedColor: const Color(0xff0088dd),
      unplayedColor: const Color(0xffdd4411),
      strokeColor: Colors.black,
      reducedMotion: reduced,
      vertical: vertical,
      maxHorizontalWidth: vertical ? null : width,
      maxVerticalUnitWidth: vertical ? width : null);
  return AppFontScope(
    policy: policy,
    child: MaterialApp(
      locale: policy.language.locale,
      home: Directionality(
        textDirection: direction,
        child: SingleChildScrollView(
          child: Column(children: [
            text(_retained),
            KeyedSubtree(key: UniqueKey(), child: text(_fresh)),
          ]),
        ),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, Key key) async {
  final size = tester.getSize(find.byKey(key));
  final recorder = drawing.PictureRecorder();
  _painter(tester, key).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  return (await tester.runAsync(() async {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));
  for (final vertical in [false, true]) {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      for (final reduced in [false, true]) {
        testWidgets(
            'desktop font policy rebuilds glyphs and reuses width '
            'vertical=$vertical direction=$direction reduced=$reduced',
            (tester) async {
          final clock = PlaybackClock(automaticTicks: false);
          addTearDown(clock.dispose);
          clock.sync(const PlaybackTimelineMessage(1, 1500, false));
          final uniform = _uniform(UiLanguage.zh);
          await tester.pumpWidget(_host(clock, uniform,
              vertical: vertical,
              direction: direction,
              width: 220,
              reduced: reduced));
          final initial = _painter(tester, _retained).cachedShapingIdentities;
          final mixed = AppFontPolicy.defaults();
          await tester.pumpWidget(_host(clock, mixed,
              vertical: vertical,
              direction: direction,
              width: 220,
              reduced: reduced));
          final mixedPainter = _painter(tester, _retained);
          expect(mixedPainter.cachedShapingIdentities.first,
              isNot(same(initial.first)),
              reason:
                  'An inherited policy change must invalidate font shaping.');
          final spans = mixedPainter.cachedShapingIdentities
              .cast<TextPainter>()
              .expand((painter) => _leaves(painter.text))
              .toList();
          expect(
              spans
                  .where((span) => span.$1.contains('English'))
                  .every((span) => span.$2 == mixed.en.family),
              isTrue);
          expect(
              spans
                  .where((span) => span.$1.contains('한'))
                  .every((span) => span.$2 == mixed.ko.family),
              isTrue);
          expect(
              spans
                  .where((span) => span.$1.contains('漢'))
                  .every((span) => span.$2 == mixed.ja.family),
              isTrue,
              reason:
                  'Vertical isolated Han preserves the complete line Kana context.');
          final allocated = mixedPainter.cachedShapingIdentities.toSet();
          for (final width in [219.0, 50.0, 51.0, 221.0, 220.0]) {
            await tester.pumpWidget(_host(clock, mixed,
                vertical: vertical,
                direction: direction,
                width: width,
                reduced: reduced));
            expect(_painter(tester, _retained).cachedShapingIdentities.toSet(),
                allocated,
                reason: 'Pure geometry keeps the active mixed-script shaping.');
            for (final time in [500, 1500, 2600]) {
              clock.sync(PlaybackTimelineMessage(1, time, false));
              final actual = await _pixels(tester, _retained);
              final fresh = await _pixels(tester, _fresh);
              expect(actual, orderedEquals(fresh),
                  reason:
                      'Fresh stroke, word clipping and glyphs at width=$width time=$time.');
              // At 50/51 the engine may omit the complete first unbreakable
              // token, including its ellipsis (the flat paragraph does too).
              // Wide samples and every vertical column must paint real glyphs.
              if (vertical || width >= 219) {
                expect(actual.where((value) => value != 0), isNotEmpty,
                    reason: 'Visible glyphs width=$width time=$time');
              }
            }
          }
          if (vertical) {
            expect(mixedPainter.glyphs.map((glyph) => glyph.text).join(),
                _text.replaceAll(' ', ''));
            expect(
                mixedPainter.glyphs
                    .where((glyph) => glyph.text.contains('👨'))
                    .single
                    .text,
                '👨🏽‍👩🏻‍👧🏾');
          }
          expect(clock.positionMilliseconds, 2600);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  }
}
