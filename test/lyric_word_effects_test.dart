import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(int start, int length, String text)
      : super(Duration(milliseconds: start), Duration(milliseconds: length),
            text);
}

class _Line extends SyncLyricLine {
  _Line(List<SyncLyricWord> words)
      : super(Duration.zero, const Duration(seconds: 8), words);
}

class _Position extends ValueNotifier<Duration> {
  _Position() : super(Duration.zero);
  int listeners = 0;
  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}

Widget _host(LyricLine line, _Position position, LyricViewController settings,
        {bool reduced = false,
        int distance = 0,
        double width = 340,
        ValueNotifier<RenderingPreferences>? preferences,
        TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
        builder: preferences == null
            ? null
            : (context, child) => RenderingPreferencesScope(
                preferences: preferences, child: child!),
        theme: ThemeData(
            fontFamily: 'Ahem',
            colorScheme: const ColorScheme.light(
                primary: Color(0xff00ffff),
                onSecondaryContainer: Color(0xffff0000))),
        home: Directionality(
            textDirection: direction,
            child: Center(
                child: SizedBox(
                    width: width,
                    child: Material(
                        color: Colors.transparent,
                        child: ChangeNotifierProvider.value(
                            value: settings,
                            child: SingleChildScrollView(
                                child: LyricViewTile(
                                    line: line,
                                    position: position,
                                    opacity: 1,
                                    distance: distance,
                                    reducedMotion: reduced))))))));

Finder _paintFinder() => find.byWidgetPredicate((widget) =>
    widget is CustomPaint && widget.painter is LyricWordHighlightPainter);
LyricWordHighlightPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_paintFinder()).painter!
        as LyricWordHighlightPainter;

Future<({Uint8List bytes, int width, int height})> _pixels(
    WidgetTester tester) async {
  final size = tester.getSize(_paintFinder());
  final recorder = drawing.PictureRecorder();
  _painter(tester).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final width = size.width.ceil();
  final height = size.height.ceil();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(width, height);
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
  return (bytes: bytes!, width: width, height: height);
}

({int top, int bottom, int count}) _ink(
    ({Uint8List bytes, int width, int height}) image) {
  var top = image.height;
  var bottom = -1;
  var count = 0;
  for (var index = 0; index < image.bytes.length; index += 4) {
    if (image.bytes[index + 3] < 230) continue;
    final y = (index ~/ 4) ~/ image.width;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
    count++;
  }
  return (top: top, bottom: bottom, count: count);
}

void main() {
  late _Position position;
  late LyricViewController settings;
  setUp(() {
    position = _Position();
    settings = LyricViewController()
      ..lyricFontSize = 40
      ..translationFontSize = 20
      ..lyricTextAlign = LyricTextAlign.left;
  });
  tearDown(() {
    position.dispose();
    settings.dispose();
  });

  test('long-note envelope is bounded and settles continuously at both ends',
      () {
    for (final length in [0, 200, 650, 651, 1200, 9000]) {
      for (final progress in [
        -1.0,
        0.0,
        .000001,
        .2,
        .5,
        .8,
        .999999,
        1.0,
        2.0
      ]) {
        final pose = LyricWordEffects.sustain(
            progress: progress, durationMilliseconds: length, fontSize: 120);
        expect(pose.lift, inInclusiveRange(0, 6));
        expect(pose.scale, inInclusiveRange(1, 1.08));
        if (length <= 0 || progress <= 0 || progress >= 1) {
          expect(pose, (lift: 0.0, scale: 1.0));
        }
        if (progress == .000001 || progress == .999999) {
          expect(pose.lift, lessThan(.00001));
          expect(pose.scale, closeTo(1, .00001));
        }
      }
    }
  });

  test('brief syllables have a visible bounded pose without a 650ms cliff', () {
    final brief = LyricWordEffects.sustain(
        progress: .5, durationMilliseconds: 240, fontSize: 40);
    expect(brief.lift, greaterThan(1.5));
    expect(brief.scale, greaterThan(1.03));
    final before = LyricWordEffects.sustain(
        progress: .5, durationMilliseconds: 650, fontSize: 40);
    final after = LyricWordEffects.sustain(
        progress: .5, durationMilliseconds: 651, fontSize: 40);
    expect(after.lift, closeTo(before.lift, .001));
  });

  testWidgets('short inner syllable animates without changing layout or clock',
      (tester) async {
    final line =
        _Line([_Word(0, 240, '你'), _Word(240, 240, '好'), _Word(480, 240, '呀')]);
    await tester.pumpWidget(_host(line, position, settings));
    await tester.pumpAndSettle();
    final layout = _painter(tester).layoutIdentity;
    final size = tester.getSize(_paintFinder());
    position.value = const Duration(milliseconds: 360);
    await tester.pump();
    expect(_painter(tester).movingWordCount, 1);
    expect(_painter(tester).progressForWord(1), .5);
    expect(_painter(tester).layoutIdentity, same(layout));
    expect(tester.getSize(_paintFinder()), size);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_host(line, position, settings, reduced: true));
    await tester.pumpAndSettle();
    expect(_painter(tester).movingWordCount, 0);
    expect(position.listeners, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final rtl in [false, true]) {
    testWidgets('main lyric edge is feathered without relayout rtl=$rtl',
        (tester) async {
      // Joining text keeps its shape fixed so this isolates the reveal edge
      // from the separately tested syllable transform.
      final line = _Line([
        _Word(0, 500, rtl ? 'אבגד' : 'HHHH'),
        if (!rtl) _Word(500, 0, 'H'),
      ]);
      await tester.pumpWidget(_host(line, position, settings,
          direction: rtl ? TextDirection.rtl : TextDirection.ltr));
      await tester.pumpAndSettle();
      final painter = _painter(tester);
      final layout = painter.layoutIdentity;
      final initial = await _pixels(tester);
      position.value = const Duration(milliseconds: 185);
      await tester.pump();
      final middle = await _pixels(tester);
      position.value = const Duration(milliseconds: 500);
      await tester.pump();
      final complete = await _pixels(tester);
      final columns = <int>{};
      for (var index = 0; index < middle.bytes.length; index += 4) {
        if (initial.bytes[index + 3] < 250 ||
            complete.bytes[index + 3] < 250 ||
            middle.bytes[index + 3] < 250) {
          continue;
        }
        if ((middle.bytes[index] - initial.bytes[index]).abs() > 8 &&
            (middle.bytes[index] - complete.bytes[index]).abs() > 8) {
          columns.add((index ~/ 4) % middle.width);
        }
      }
      expect(columns.length, inInclusiveRange(4, 12));
      expect(_painter(tester), same(painter));
      expect(_painter(tester).layoutIdentity, same(layout));
      position.value = Duration.zero;
      await tester.pump();
      expect((await _pixels(tester)).bytes, orderedEquals(initial.bytes));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final text in ['微风轻轻吹过我的心', 'きらきらひかるよ', '우리함께노래해']) {
    testWidgets(
        'authored CJK word staggers graphemes without splitting time $text',
        (tester) async {
      final line = _Line([_Word(0, 2400, text)]);
      await tester.pumpWidget(_host(line, position, settings, width: 780));
      await tester.pumpAndSettle();
      final layout = _painter(tester).layoutIdentity;
      final size = tester.getSize(_paintFinder());
      position.value = const Duration(milliseconds: 360);
      await tester.pump();
      final entry = _painter(tester).movingWordCount;
      expect(entry, greaterThan(0));
      expect(entry, lessThan(text.characters.length));
      position.value = const Duration(milliseconds: 800);
      await tester.pump();
      expect(_painter(tester).movingWordCount, text.characters.length);
      expect(_painter(tester).movingWordLifts.toSet().length, greaterThan(1));
      expect(_painter(tester).progressForWord(0), closeTo(1 / 3, .00001));
      expect(line.words, hasLength(1));
      expect(_painter(tester).layoutIdentity, same(layout));
      expect(tester.getSize(_paintFinder()), size);
      position.value = const Duration(milliseconds: 2400);
      await tester.pump();
      expect(_painter(tester).movingWordCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('long word lifts as one mask with no original glyph left behind',
      (tester) async {
    final line = _Line([_Word(0, 2400, 'HHH')]);
    await tester.pumpWidget(_host(line, position, settings));
    await tester.pumpAndSettle();
    final size = tester.getSize(_paintFinder());
    final original = _ink(await _pixels(tester));
    position.value = const Duration(milliseconds: 1200);
    await tester.pump();
    expect(_painter(tester).movingWordCount, 1);
    final raised = _ink(await _pixels(tester));
    expect(raised.top, lessThan(original.top));
    expect(raised.bottom, lessThan(original.bottom),
        reason: 'An untransformed duplicate would still occupy the old bottom');
    expect(raised.count / original.count, inInclusiveRange(.97, 1.18),
        reason: '8% scale permits 1.08 squared ink, never a second copy');
    expect(tester.getSize(_paintFinder()), size);
    final paused = await _pixels(tester);
    await tester.pump(const Duration(seconds: 3));
    expect((await _pixels(tester)).bytes, orderedEquals(paused.bytes));
    expect(tester.binding.transientCallbackCount, 0);
    position.value = const Duration(milliseconds: 2400);
    await tester.pump();
    expect(_painter(tester).movingWordCount, 0);
    expect(_ink(await _pixels(tester)), original);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('departing focus releases held-word pose through finite fade',
      (tester) async {
    final line = _Line([_Word(0, 2400, 'HHH')]);
    position.value = const Duration(milliseconds: 1200);
    await tester.pumpWidget(_host(line, position, settings));
    await tester.pumpAndSettle();
    final lift = _painter(tester).movingWordLifts.single;
    await tester.pumpWidget(_host(line, position, settings, distance: 1));
    expect(_painter(tester).movingWordCount, 1);
    expect(_painter(tester).movingWordLifts.single, closeTo(lift, .001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_painter(tester).movingWordLifts.single, lessThan(lift));
    await tester.pumpAndSettle();
    expect(_painter(tester).movingWordCount, 0);
    expect(position.listeners, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('graphemes, joining scripts and wrapped words stay shaped',
      (tester) async {
    final line = _Line([
      _Word(0, 2400, '👩‍'),
      _Word(0, 2400, '👩‍👧‍👦'),
      _Word(0, 2400, 'אבגד '),
      _Word(0, 2400, 'longword' * 12),
    ]);
    await tester.pumpWidget(_host(line, position, settings, width: 200));
    await tester.pumpAndSettle();
    final initial = tester.getSize(_paintFinder());
    final layout = _painter(tester).layoutIdentity;
    expect(_painter(tester).shapedWordCount, 3,
        reason: 'The provider-split family emoji must keep one shaped range');
    for (var i = 1; i < 24; i++) {
      position.value = Duration(milliseconds: i * 100);
      await tester.pump();
      expect(tester.getSize(_paintFinder()), initial);
      expect(_painter(tester).layoutIdentity, same(layout));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'overlapping word timings bound layers and reduced motion detaches sampling',
      (tester) async {
    final line = _Line([for (var i = 0; i < 8; i++) _Word(0, 2400, 'H ')]);
    await tester.pumpWidget(_host(line, position, settings, width: 780));
    await tester.pumpAndSettle();
    position.value = const Duration(milliseconds: 1200);
    await tester.pump();
    expect(_painter(tester).movingWordCount, 4);
    expect(position.listeners, 1);
    await tester
        .pumpWidget(_host(line, position, settings, reduced: true, width: 780));
    await tester.pumpAndSettle();
    expect(position.listeners, 0);
    final before = await _pixels(tester);
    position.value = const Duration(milliseconds: 1900);
    await tester.pump(const Duration(seconds: 3));
    expect((await _pixels(tester)).bytes, orderedEquals(before.bytes));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fifth overlapping note cannot snap the other four lift poses',
      (tester) async {
    final line = _Line([
      for (var index = 0; index < 4; index++) _Word(0, 8000, 'H '),
      _Word(2500, 1500, 'H'),
    ]);
    await tester.pumpWidget(_host(line, position, settings, width: 780));
    await tester.pumpAndSettle();
    final layout = _painter(tester).layoutIdentity;
    final size = tester.getSize(_paintFinder());
    for (final milliseconds in [1200, 2490, 2510, 3250, 3990, 4010, 6000]) {
      position.value = Duration(milliseconds: milliseconds);
      await tester.pump();
      expect(_painter(tester).movingWordCount, 4,
          reason:
              'The layer policy cannot change when the fifth word enters/exits');
      expect(_painter(tester).layoutIdentity, same(layout));
      expect(tester.getSize(_paintFinder()), size);
      expect(_painter(tester).progressForWord(0),
          closeTo(milliseconds / 8000, .00001));
    }
    // Exactly four simultaneous long notes still retain the intended effect.
    await tester.pumpWidget(_host(
        _Line(line.words.take(4).toList()), position, settings,
        width: 780));
    await tester.pumpAndSettle();
    expect(_painter(tester).movingWordCount, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'surface blur disables word glow live without disabling word timing',
      (tester) async {
    final preferences = ValueNotifier(const RenderingPreferences());
    addTearDown(preferences.dispose);
    final line = _Line([_Word(0, 2400, 'HHH')]);
    position.value = const Duration(milliseconds: 1200);
    await tester
        .pumpWidget(_host(line, position, settings, preferences: preferences));
    await tester.pumpAndSettle();
    final layout = _painter(tester).layoutIdentity;
    expect(_painter(tester).glowAllowed, true);
    final glow = await _pixels(tester);
    preferences.value = preferences.value.copyWith(surfaceBlur: false);
    await tester.pumpAndSettle();
    expect(_painter(tester).glowAllowed, false);
    expect(_painter(tester).movingWordCount, 1);
    expect(_painter(tester).layoutIdentity, same(layout));
    expect(position.listeners, 1);
    final plain = await _pixels(tester);
    var removedGlowPixels = 0;
    for (var index = 0; index < glow.bytes.length; index += 4) {
      if (glow.bytes[index + 3] > plain.bytes[index + 3] + 3) {
        removedGlowPixels++;
      }
      if (plain.bytes[index + 3] == 255) {
        expect(glow.bytes.sublist(index, index + 4),
            orderedEquals(plain.bytes.sublist(index, index + 4)));
      }
    }
    expect(removedGlowPixels, greaterThan(20));
    position.value = const Duration(milliseconds: 1800);
    await tester.pump();
    expect(_painter(tester).progressForWord(0), .75);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('plain LRC remains line-timed with no synthetic word mask',
      (tester) async {
    final line = LrcLine(Duration.zero, 'Plain lyric',
        isBlank: false, length: const Duration(seconds: 8));
    await tester.pumpWidget(_host(line, position, settings));
    await tester.pumpAndSettle();
    expect(_paintFinder(), findsNothing);
    expect(find.text('Plain lyric'), findsOneWidget);
    expect(position.listeners, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
