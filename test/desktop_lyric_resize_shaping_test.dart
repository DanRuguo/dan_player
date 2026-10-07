import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

const _retained = ValueKey('retained-desktop-lyric');
const _fresh = ValueKey('fresh-desktop-lyric');

DesktopLyricTextPainter _painter(WidgetTester tester, Key key) => tester
    .widget<CustomPaint>(find.descendant(
      of: find.byKey(key),
      matching: find.byType(CustomPaint),
    ))
    .painter! as DesktopLyricTextPainter;

Widget _host(PlaybackClock clock, List<DesktopLyricWord> words,
    {required bool vertical,
    required double? width,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
    double fontSize = 26,
    Color playedColor = const Color(0xff11bbee),
    bool stroke = true}) {
  Widget text(Key key) => DesktopLyricText(
        key: key,
        clock: clock,
        text: words.map((word) => word.content).join(),
        words: words,
        vertical: vertical,
        maxHorizontalWidth: vertical ? null : width,
        maxVerticalUnitWidth: vertical ? width : null,
        style: TextStyle(
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            fontSize: fontSize,
            height: 1.3),
        playedColor: playedColor,
        unplayedColor: const Color(0xffee3311),
        strokeColor: stroke ? Colors.black : null,
      );
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: SingleChildScrollView(
          child: Column(children: [
            text(_retained),
            // Only the reference is replaced; the production state remains
            // mounted throughout every adjacent-width round trip.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  final scripts = {
    'Chinese': ['晨光 ', 'Hello ', '再次照亮世界。'],
    'English': ['Morning ', "don't-stop ", 'returns to the world.'],
    'Japanese': ['夜空 ', 'Hello ', 'もう一度輝きます。'],
    'Korean': ['아침 ', 'Hello ', '다시 세상을 비춥니다.'],
    'RTL': ['שלום ', 'Hello ', 'עולם שירה חדשה'],
  };
  for (final sample in scripts.entries) {
    for (final vertical in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
            'desktop resize retains shaping and fresh pixels ${sample.key} vertical=$vertical scale=$scale',
            (tester) async {
          final clock = PlaybackClock(automaticTicks: false);
          addTearDown(clock.dispose);
          final words = [
            for (var i = 0; i < sample.value.length; i++)
              DesktopLyricWord(i * 1000, 1000, sample.value[i]),
          ];
          final widths = vertical
              ? [180.0, 120.0, 119.0, 24.0, 25.0, 121.0, 180.0]
              : [360.0, 220.0, 219.0, 50.0, 51.0, 221.0, 360.0];
          final allocated = <Object>{};
          int? initialCount;
          DesktopLyricTextPainter? previous;
          List<Rect>? previousRects;
          for (final width in widths) {
            clock.sync(const PlaybackTimelineMessage(1, 150, false));
            await tester.pumpWidget(_host(clock, words,
                vertical: vertical,
                width: width,
                scale: scale,
                direction: sample.key == 'RTL'
                    ? TextDirection.rtl
                    : TextDirection.ltr));
            final current = _painter(tester, _retained);
            final identities = current.cachedShapingIdentities;
            initialCount ??= identities.length;
            allocated.addAll(identities);
            if (previous != null) {
              expect(current.layoutCacheIdentity,
                  isNot(same(previous.layoutCacheIdentity)));
              expect(current.shouldRepaint(previous), isTrue,
                  reason: 'Width changes publish fresh immutable geometry');
              expect(previous.highlightRectsForWord(0), previousRects,
                  reason: 'Reflow cannot overwrite the old word-box snapshot');
            }
            previous = current;
            previousRects = current.highlightRectsForWord(0);
            for (final position in [150, 1150, 3200]) {
              clock.sync(PlaybackTimelineMessage(1, position, false));
              await tester.pump();
              expect(
                  _difference(await _pixels(tester, _retained),
                      await _pixels(tester, _fresh)),
                  0,
                  reason:
                      'Retained stroke, ellipsis and word reveal must match a '
                      'new paragraph at width=$width position=$position');
            }
          }
          expect(allocated.length, initialCount,
              reason: 'Seven width layouts must retain the original fill and '
                  'stroke shaping objects rather than allocate seven copies');
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('retained desktop width cache invalidates source and typography',
      (tester) async {
    final firstClock = PlaybackClock(automaticTicks: false);
    final replacementClock = PlaybackClock(automaticTicks: false);
    addTearDown(firstClock.dispose);
    addTearDown(replacementClock.dispose);
    firstClock.sync(const PlaybackTimelineMessage(1, 650, false));
    replacementClock.sync(const PlaybackTimelineMessage(2, 1200, false));
    var clock = firstClock;
    var words = const [
      DesktopLyricWord(0, 1000, 'First '),
      DesktopLyricWord(1000, 1000, '最初の詞。'),
    ];
    var vertical = false;
    double? width = 160;
    var scale = 1.0;
    var fontSize = 26.0;
    var direction = TextDirection.ltr;
    var playedColor = const Color(0xff11bbee);
    var stroke = true;
    Widget host() => _host(clock, words,
        vertical: vertical,
        width: width,
        scale: scale,
        fontSize: fontSize,
        direction: direction,
        playedColor: playedColor,
        stroke: stroke);
    await tester.pumpWidget(host());
    var previous = _painter(tester, _retained);
    final changes = <(String, VoidCallback)>[
      ('font', () => fontSize = 34),
      ('text scale', () => scale = 1.5),
      ('direction', () => direction = TextDirection.rtl),
      ('palette', () => playedColor = const Color(0xffaaaa00)),
      ('stroke', () => stroke = false),
      ('unbounded mode', () => width = null),
      ('bounded mode', () => width = 90),
      ('vertical mode', () => vertical = true),
      (
        'new song',
        () => words = const [
              DesktopLyricWord(0, 1800, '새로운 '),
              DesktopLyricWord(1800, 1000, '第二首歌詞。'),
            ]
      ),
    ];
    for (final (name, change) in changes) {
      final oldShaping = previous.cachedShapingIdentities;
      change();
      await tester.pumpWidget(host());
      final current = _painter(tester, _retained);
      expect(
          current.cachedShapingIdentities.first, isNot(same(oldShaping.first)),
          reason: '$name invalidates retained text shaping');
      expect(current.shouldRepaint(previous), isTrue);
      expect(
          _difference(
              await _pixels(tester, _retained), await _pixels(tester, _fresh)),
          0,
          reason: '$name cannot retain the previous source/typography pixels');
      previous = current;
    }

    final oldShaping = previous.cachedShapingIdentities;
    final oldGeometry = previous.layoutCacheIdentity;
    clock = replacementClock;
    await tester.pumpWidget(host());
    final current = _painter(tester, _retained);
    expect(current.cachedShapingIdentities, oldShaping,
        reason: 'A media clock handoff does not reshape unchanged text');
    expect(current.layoutCacheIdentity, same(oldGeometry));
    expect(current.shouldRepaint(previous), isTrue,
        reason: 'The newly owned media clock still repaints immediately');
    expect(
        _difference(
            await _pixels(tester, _retained), await _pixels(tester, _fresh)),
        0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
