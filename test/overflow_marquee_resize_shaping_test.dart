import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/overflow_marquee_text.dart';
import 'package:dan_player/page/now_playing_page/component/now_playing_metadata_header.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

const _retained = ValueKey('retained-marquee');
const _fresh = ValueKey('fresh-marquee');
const _scripts = {
  'zh': '晨光再次照亮世界，完整歌曲标题与艺术家专辑资料需要阅读',
  'en': "Morning returns with don't-stop music, artists and album details",
  'ja': '夜空に戻る歌 君が好きだと叫びたい 曲名とアルバムの記憶',
  'ko': '아침에 돌아온 긴 노래 제목과 아티스트 및 앨범 정보를 읽습니다',
  // Exercise right-to-left paragraph geometry with the same loaded font and
  // authored metadata alphabet as the player's supported languages.
  'rtl': "Morning returns with don't-stop music, artists and album details",
};

Finder _paint(Finder marquee) =>
    find.descendant(of: marquee, matching: find.byType(CustomPaint));

dynamic _painter(WidgetTester tester, Key key) =>
    tester.widget<CustomPaint>(_paint(find.byKey(key))).painter!;

TextPainter _shape(WidgetTester tester, Key key) =>
    _painter(tester, key).text as TextPainter;

Widget _host(String text, double width,
    {double scale = 1,
    TextDirection direction = TextDirection.ltr,
    Locale locale = const Locale('en'),
    TextStyle style = const TextStyle(fontSize: 23),
    bool header = false}) {
  Widget marquee(Key key) => SizedBox(
      width: width, child: OverflowMarqueeText(text, key: key, style: style));
  return UiLanguageScope(
    child: MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      locale: locale,
      supportedLocales: UiLanguage.values.map((value) => value.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: header
                  ? SizedBox(
                      width: width,
                      child: NowPlayingMetadataHeader(
                          title: '${_scripts['zh']} · ${_scripts['en']}',
                          artist: '${_scripts['ja']} · artist',
                          album: '${_scripts['ko']} · album'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        marquee(_retained),
                        // Replace only the reference. Production state remains
                        // mounted across every adjacent-width round trip.
                        KeyedSubtree(key: UniqueKey(), child: marquee(_fresh)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, Key key) async {
  final size = tester.getSize(find.byKey(key));
  final recorder = raster.PictureRecorder();
  (_painter(tester, key) as CustomPainter).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  return (await tester.runAsync(() async {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      final bytes =
          await image.toByteData(format: raster.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

Future<void> _expectFreshPixels(WidgetTester tester) async {
  final actual = await _pixels(tester, _retained);
  final expected = await _pixels(tester, _fresh);
  expect(actual, orderedEquals(expected),
      reason:
          'Retaining natural shaping must preserve fresh clipped/faded ink');
  var ink = false;
  for (var index = 3; index < actual.length; index += 4) {
    if (actual[index] != 0) {
      ink = true;
      break;
    }
  }
  expect(ink, isTrue,
      reason: 'The compared paragraphs must really paint glyphs at '
          '${tester.getSize(find.byKey(_retained))}, '
          'natural width ${_shape(tester, _retained).width}');
}

Future<void> _advance(WidgetTester tester, int milliseconds) async {
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 20) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  for (final script in _scripts.entries) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'marquee ${script.key} retains natural shaping through '
          'adjacent widths at $scale', (tester) async {
        final direction =
            script.key == 'rtl' ? TextDirection.rtl : TextDirection.ltr;
        await tester.pumpWidget(
            _host(script.value, 200, scale: scale, direction: direction));
        final shapes = <TextPainter>{_shape(tester, _retained)};
        await _advance(tester, 1700);
        expect(_painter(tester, _retained).pose.value.offset, greaterThan(0));
        for (final width in [201.0, 199.0, 240.0, 120.0, 200.0]) {
          await tester.pumpWidget(
              _host(script.value, width, scale: scale, direction: direction));
          shapes.add(_shape(tester, _retained));
          expect(_painter(tester, _retained).pose.value.offset, 0,
              reason: 'Every width change retains the existing leading reset');
          expect(tester.binding.transientCallbackCount, 0,
              reason: 'The reading hold schedules no animation frames');
          await _expectFreshPixels(tester);
        }
        expect(shapes, hasLength(1),
            reason: 'Six widths must reuse one constraint-independent natural '
                'paragraph, rather than shaping six identical copies');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('marquee fitting round trip retains shaping and width reset',
      (tester) async {
    final text = _scripts['en']!;
    await tester.pumpWidget(_host(text, 160));
    final shape = _shape(tester, _retained);
    await _advance(tester, 1700);
    expect(_painter(tester, _retained).pose.value.offset, greaterThan(0));
    await tester.pumpWidget(_host(text, 780));
    expect(_paint(find.byKey(_retained)), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(text, 160));
    expect(_painter(tester, _retained).pose.value.offset, 0);
    expect(_shape(tester, _retained), same(shape));
    await _expectFreshPixels(tester);
    await _advance(tester, 1700);
    expect(_painter(tester, _retained).pose.value.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('marquee text and typography still invalidate retained shaping',
      (tester) async {
    var text = _scripts['en']!;
    var scale = 1.0;
    var direction = TextDirection.ltr;
    var locale = const Locale('en');
    var style = const TextStyle(fontSize: 23);
    Widget host() => _host(text, 160,
        scale: scale, direction: direction, locale: locale, style: style);
    await tester.pumpWidget(host());
    var previous = _shape(tester, _retained);
    for (final change in <VoidCallback>[
      () => text = _scripts['ja']!,
      () => style = style.copyWith(fontSize: 29),
      () => style = style.copyWith(letterSpacing: 1.2),
      () => scale = 1.5,
      () => direction = TextDirection.rtl,
      () => locale = const Locale('ja'),
    ]) {
      change();
      await tester.pumpWidget(host());
      final current = _shape(tester, _retained);
      expect(current, isNot(same(previous)));
      expect(_painter(tester, _retained).pose.value.offset, 0);
      await _expectFreshPixels(tester);
      previous = current;
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('actual lyric metadata reuses title artist and album shaping',
      (tester) async {
    final shapes = <String, Set<TextPainter>>{};
    for (final width in [240.0, 241.0, 239.0, 280.0, 210.0, 240.0]) {
      await tester.pumpWidget(_host('', width, header: true));
      final lines = find.byType(OverflowMarqueeText);
      expect(lines, findsNWidgets(3));
      for (final line in lines.evaluate()) {
        final widget = line.widget as OverflowMarqueeText;
        final painter = tester
            .widget<CustomPaint>(_paint(find.byWidget(widget)))
            .painter! as dynamic;
        (shapes[widget.text] ??= {}).add(painter.text as TextPainter);
        expect(painter.pose.value.offset, 0);
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
    expect(shapes, hasLength(3));
    for (final paragraph in shapes.values) {
      expect(paragraph, hasLength(1),
          reason: 'Each real metadata consumer has one natural paragraph '
              'through the six-window-width scan');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
