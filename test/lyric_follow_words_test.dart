import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_follow_words.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(String text, [int start = 0])
      : super(Duration(seconds: start), const Duration(seconds: 4), text);
}

class _Line extends SyncLyricLine {
  _Line(String text, [int start = 0])
      : super(Duration(seconds: start), const Duration(seconds: 4),
            [_Word(text, start)]);
}

class _SampleWord extends SyncLyricWord {
  _SampleWord(String text, int startMs, int lengthMs)
      : super(Duration(milliseconds: startMs), Duration(milliseconds: lengthMs),
            text);
}

class _SampleTimedLine extends SyncLyricLine {
  _SampleTimedLine()
      : super(const Duration(milliseconds: 19150),
            const Duration(milliseconds: 5200), [
          _SampleWord('音', 19150, 440),
          _SampleWord('も', 19590, 260),
          _SampleWord('な', 19850, 250),
          _SampleWord('い', 20100, 380),
          _SampleWord('世', 20480, 300),
          _SampleWord('界', 20780, 670),
          _SampleWord('、', 21450, 40),
          _SampleWord('何', 21490, 830),
          _SampleWord('を', 22320, 140),
          _SampleWord('見', 22460, 520),
          _SampleWord('て', 22980, 250),
          _SampleWord('る', 23230, 250),
          _SampleWord('の', 23480, 660),
          _SampleWord('？', 24140, 210),
        ]);
}

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final latinFont = File('C:/Windows/Fonts/segoeui.ttf');
    if (await latinFont.exists()) {
      await (FontLoader('FollowLatin')
            ..addFont(Future.value(
                ByteData.sublistView(await latinFont.readAsBytes()))))
          .load();
    }
  });
  test('visual tokens keep CJK graphemes and complete Western words', () {
    const text = "明日かな 한국어 It's café time";
    expect([
      for (final r in lyricFollowWordRanges(text))
        text.substring(r.start, r.end)
    ], [
      '明',
      '日',
      'か',
      'な',
      '한',
      '국',
      '어',
      "It's",
      'café',
      'time'
    ]);
    const combined = 'e\u0301lan 👨‍👩‍👧‍👦';
    expect([
      for (final r in lyricFollowWordRanges(combined))
        combined.substring(r.start, r.end)
    ], [
      'e\u0301lan',
      '👨‍👩‍👧‍👦'
    ]);
  });
  test('right edge retains original spring; left leads ascent and return', () {
    final curve = LyricMotion.scrollCurveFor(spring: true, distance: 80);
    for (final phase in [0.0, .25, .5, .75, 1.0]) {
      double offset(double progress) =>
          LyricWordFollow(AlwaysStoppedAnimation(progress), curve, 80)
              .offset(phase, 40);
      expect(offset(0), 0);
      expect(offset(1), 0);
      expect(offset(.99999).abs(), lessThan(.00001));
      if (phase == 1) {
        for (final t in [.05, .25, .55, .7, .9, .99]) {
          expect(offset(t), 0);
        }
      } else {
        expect(offset(.25), lessThan(0));
        expect(offset(.8), greaterThan(0));
      }
      for (var frame = 0; frame <= 144; frame++) {
        expect(offset(frame / 144).abs(), lessThanOrEqualTo(8.8));
      }
    }
    final wave = LyricWordFollow(const AlwaysStoppedAnimation(.25), curve, 80);
    final offsets = [
      for (var index = 0; index < 5; index++) wave.offset(index / 4, 40)
    ];
    expect(offsets.first.abs(), greaterThan(4));
    for (var index = 1; index < offsets.length; index++) {
      expect(offsets[index], greaterThan(offsets[index - 1]));
    }
  });
  test('visual rows use equally spaced phases and retain joined words', () {
    final painter = TextPainter(
        text: const TextSpan(
            text: 'one two three four five',
            style: TextStyle(fontFamily: 'Ahem', fontSize: 20)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 600);
    final slots = lyricFollowWordSlots(painter, 'one two three four five');
    expect(slots.map((slot) => slot.phase), [0, .25, .5, .75, 1]);
    painter.dispose();
  });
  test('font fallback boxes share their real text baseline and complete masks',
      () {
    const text = '音もない世界、何を見てるの?';
    final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(
            style: TextStyle(
                fontSize: 33, fontWeight: FontWeight.w800, height: 1.3),
            children: [
              TextSpan(
                  text: '音もない世界、何を見てるの',
                  style: TextStyle(fontFamily: danEmbeddedFontFamily)),
              TextSpan(
                  text: '?',
                  style: TextStyle(fontFamily: 'FollowLatin', height: 1.1)),
            ]))
      ..layout(maxWidth: 520);
    final slots = lyricFollowWordSlots(painter, text);
    expect(painter.computeLineMetrics(), hasLength(1));
    final fontRunBoxes = [
      for (final range in lyricFollowWordRanges(text))
        ...painter
            .getBoxesForSelection(
                TextSelection(baseOffset: range.start, extentOffset: range.end))
            .map((box) => box.toRect()),
    ];
    expect(fontRunBoxes.map((box) => box.top).toSet().length, greaterThan(1),
        reason: 'Exercise different font-run tops on the same baseline');
    final fontRunClips = lyricFollowClipPartitions(
        fontRunBoxes, painter.size, painter.computeLineMetrics());
    expect(fontRunClips.map((box) => box.top).toSet(), hasLength(1));
    expect(fontRunClips.map((box) => box.bottom).toSet(), hasLength(1));
    expect(slots.map((slot) => slot.phase),
        [for (var i = 0; i < slots.length; i++) i / (slots.length - 1)]);
    expect(
        slots.map((slot) => slot.paintBoxes.first.top).toSet(), hasLength(1));
    expect(slots.map((slot) => slot.paintBoxes.first.bottom).toSet(),
        hasLength(1));
    for (final slot in slots) {
      expect(slot.paintBoxes.first.contains(slot.boxes.first.toRect().center),
          isTrue);
    }
    painter.dispose();
  });
  testWidgets('malformed timed ranges retain every visible glyph during follow',
      (tester) async {
    final line = _Line('音もない世界');
    line.content += '？'; // A provider can expose a tail outside its word list.
    final clock = AnimationController(
        vsync: tester, duration: LyricMotion.springScrollDuration);
    final settings = LyricViewController()..lyricFontSize = 22;
    final position = ValueNotifier(const Duration(seconds: 2));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
            body: SizedBox(
                width: 400,
                child: RepaintBoundary(
                    key: key,
                    child: ChangeNotifierProvider.value(
                        value: settings,
                        child: LyricWordFollowScope(
                            follow: LyricWordFollow(
                                clock,
                                LyricMotion.scrollCurveFor(
                                    spring: true, distance: 120),
                                120),
                            child: LyricViewTile(
                                line: line,
                                position: position,
                                opacity: 1,
                                distance: 0,
                                reducedMotion: false))))))));
    final paintFinder = find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is LyricWordHighlightPainter);
    final origin =
        tester.getTopLeft(paintFinder) - tester.getTopLeft(find.byKey(key));
    final expected = TextPainter(
        text: TextSpan(
            text: line.content,
            style: const TextStyle(
                fontFamily: danEmbeddedFontFamily,
                fontSize: 33,
                fontWeight: FontWeight.w800,
                height: 1.3)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 376);
    final questionBox = expected
        .getBoxesForSelection(TextSelection(
            baseOffset: line.content.length - 1,
            extentOffset: line.content.length))
        .single
        .toRect()
        .shift(origin)
        .inflate(2);
    for (final phase in [0.0, .3, .8, 1.0]) {
      clock.value = phase;
      await tester.pump();
      final alpha = (await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final rgba =
            (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        var alpha = 0;
        for (var y = (questionBox.top * 2).floor();
            y < (questionBox.bottom * 2).ceil();
            y++) {
          for (var x = (questionBox.left * 2).floor();
              x < (questionBox.right * 2).ceil();
              x++) {
            alpha += rgba[(y * image.width + x) * 4 + 3];
          }
        }
        image.dispose();
        return alpha;
      }))!;
      expect(alpha, greaterThan(1000),
          reason: 'The unlisted question mark must remain legible at $phase');
    }
    expected.dispose();
    await tester.pumpWidget(const SizedBox());
    clock.dispose();
    settings.dispose();
    position.dispose();
  });
  for (final timed in [false, true]) {
    for (final sample in [
      ('zh', '当微风轻轻吹过我们身边的时候请记住眼前的风景以及那些仍在继续的梦想'),
      ('ja', '君が好きだと叫びたい明日を変えてみよう凍りついてく時間をぶち壊したい'),
      (
        'en',
        'The light of tomorrow keeps shining across the ocean and we will keep singing together'
      ),
      // User-reported and I'm home second line, from the actual cached LRC.
      ('real480', '音もない世界、何を見てるの?'),
      ('real420', '音もない世界、何を見てるの?'),
      ('real480mixed', '音もない世界、何を見てるの?'),
      ('real480timed', '音もない世界、何を見てるの？'),
      ('real592timed', '音もない世界、何を見てるの？'),
    ]) {
      final real = sample.$1.startsWith('real');
      if (real && timed != sample.$1.endsWith('timed')) continue;
      testWidgets(
          'wrapped rightmost words remain complete ${sample.$1} timed=$timed',
          (tester) async {
        final clock = AnimationController(
            vsync: tester, duration: LyricMotion.springScrollDuration);
        final settings = LyricViewController()..lyricFontSize = real ? 22 : 30;
        final position = ValueNotifier(real
            ? const Duration(milliseconds: 20500)
            : const Duration(seconds: 4));
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                fontFamily: sample.$1.endsWith('mixed')
                    ? 'FollowLatin'
                    : danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback),
            home: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: sample.$1.startsWith('real592')
                            ? 592
                            : sample.$1.startsWith('real480')
                                ? 480
                                : 420,
                        child: RepaintBoundary(
                            key: key,
                            child: ChangeNotifierProvider.value(
                                value: settings,
                                child: LyricWordFollowScope(
                                    follow: LyricWordFollow(
                                        clock,
                                        LyricMotion.scrollCurveFor(
                                            spring: true, distance: 160),
                                        160),
                                    child: LyricViewTile(
                                        line: timed
                                            ? (real
                                                ? _SampleTimedLine()
                                                : _Line(sample.$2))
                                            : LrcLine(
                                                real
                                                    ? const Duration(
                                                        microseconds: 19480000)
                                                    : Duration.zero,
                                                sample.$2,
                                                length: real
                                                    ? const Duration(
                                                        microseconds: 4900000)
                                                    : const Duration(
                                                        seconds: 4),
                                                isBlank: false),
                                        position: position,
                                        distance: 0,
                                        opacity: 1,
                                        reducedMotion: false)))))))));
        final paintFinder = find.byWidgetPredicate((w) =>
            w is CustomPaint &&
            (w.painter is PlainLyricWordFollowPainter ||
                w.painter is LyricWordHighlightPainter));
        final painter = tester.widget<CustomPaint>(paintFinder).painter!;
        final rects = painter is LyricWordHighlightPainter
            ? painter.followStationaryWordBounds
            : [
                for (final slot
                    in (painter as PlainLyricWordFollowPainter).slots)
                  if (slot.phase == 1)
                    for (final box in slot.boxes)
                      box.toRect().shift(painter.inkOffset)
              ];
        expect(rects.length, greaterThan(real ? 0 : 1),
            reason:
                'Synthetic long fixtures must wrap; real LRC covers the boundary');
        final origin =
            tester.getTopLeft(paintFinder) - tester.getTopLeft(find.byKey(key));
        Future<({List<int> rgba, int width})> capture(double phase) async {
          clock.value = phase;
          await tester.pump();
          return (await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            const output = String.fromEnvironment('DAN_WORD_FOLLOW_RENDER');
            if (output.isNotEmpty) {
              await Directory(output).create(recursive: true);
              await File(
                      '$output/long-${sample.$1}-$timed-${(phase * 100).round()}.png')
                  .writeAsBytes((await image.toByteData(
                          format: drawing.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
            }
            final value = (
              rgba: (await image.toByteData(
                      format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List()
                  .toList(),
              width: image.width
            );
            image.dispose();
            return value;
          }))!;
        }

        final settled = await capture(1);
        for (final phase in [.05, .3, .66, .8, .95]) {
          final frame = await capture(phase);
          for (final box in rects) {
            final area = box.deflate(2).shift(origin);
            double mass = 0, difference = 0;
            for (var y = (area.top * 2).ceil();
                y < (area.bottom * 2).floor();
                y++) {
              for (var x = (area.left * 2).ceil();
                  x < (area.right * 2).floor();
                  x++) {
                final at = (y * settled.width + x) * 4 + 3;
                mass += settled.rgba[at];
                difference += (frame.rgba[at] - settled.rgba[at]).abs();
              }
            }
            expect(mass, greaterThan(100));
            expect(difference / mass, lessThan(.02),
                reason:
                    'Rightmost word must remain complete through phase $phase');
          }
        }
        await tester.pumpWidget(const SizedBox());
        clock.dispose();
        settings.dispose();
        position.dispose();
      });
    }

    testWidgets(
        'word follow respects live lyrics policy, hidden and pause timed=$timed',
        (tester) async {
      final settings = LyricViewController()..lyricFontSize = 24;
      final preferences = ValueNotifier(const RenderingPreferences());
      final hidden = ValueNotifier(false);
      final stream = StreamController<double>.broadcast(sync: true);
      var position = 0.0, playing = false;
      final lyric = _Lyric([
        for (var i = 0; i < 10; i++)
          if (timed)
            _Line('我们继续向前 hello world $i', i * 4)
          else
            LrcLine(Duration(seconds: i * 4), '我们继续向前 hello world $i',
                isBlank: false, length: const Duration(seconds: 4)),
      ]);
      Widget host() => MaterialApp(
          theme: ThemeData(fontFamily: danEmbeddedFontFamily),
          home: Scaffold(
              body: RenderingPreferencesScope(
                  preferences: preferences,
                  child: ChangeNotifierProvider.value(
                      value: settings,
                      child: SizedBox(
                          width: 440,
                          height: 480,
                          child: VerticalLyricScrollView(
                              lyric: lyric,
                              positionStream: stream.stream,
                              readPosition: () => position,
                              onSeek: (_) {},
                              hidden: hidden,
                              playing: playing,
                              springLyrics: true))))));
      Iterable<double> offsets() sync* {
        for (final p in tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)) {
          if (p is LyricWordHighlightPainter && p.active) {
            yield* p.followWordOffsets;
          } else if (p is PlainLyricWordFollowPainter) {
            for (final slot in p.slots) {
              yield p.follow?.offset(slot.phase, 36) ?? 0;
            }
          }
        }
      }

      Future<void> emit(double seconds) async {
        position = seconds;
        stream.add(position);
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
      }

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await emit(4.1);
      expect(offsets().any((value) => value.abs() > .3), isTrue);
      final filters = find.byType(LyricFractionalFilter);
      expect(filters, findsWidgets);
      for (final element in filters.evaluate()) {
        final render = element.renderObject! as RenderProxyBox;
        expect(render.child!.needsCompositing, isFalse,
            reason: 'Text and its sampling filter must share one display list');
      }
      preferences.value = preferences.value.copyWith(
          animations: const MotionPreferences(disabled: {MotionKind.lyrics}));
      await tester.pumpAndSettle();
      expect(offsets(), everyElement(0));
      expect(tester.binding.transientCallbackCount, 0);
      await emit(8.1);
      expect(offsets(), everyElement(0));
      preferences.value = const RenderingPreferences();
      await tester.pumpAndSettle();
      await emit(12.1);
      expect(offsets().any((value) => value.abs() > .3), isTrue);
      hidden.value = true;
      await tester.pump();
      expect(offsets(), everyElement(0));
      await emit(16.1);
      expect(tester.binding.transientCallbackCount, 0);
      hidden.value = false;
      await tester.pumpAndSettle();
      expect(offsets(), everyElement(0),
          reason: 'No replay of hidden transitions');
      playing = true;
      await tester.pumpWidget(host());
      await emit(20.1);
      expect(offsets().any((value) => value.abs() > .3), isTrue);
      playing = false;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(offsets(), everyElement(0));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      await stream.close();
      settings.dispose();
      preferences.dispose();
      hidden.dispose();
    });

    testWidgets('word follow shapes and colors stay stable timed=$timed',
        (tester) async {
      final clock = AnimationController(
          vsync: tester, duration: LyricMotion.springScrollDuration);
      final settings = LyricViewController()..lyricFontSize = 30;
      final position = ValueNotifier(const Duration(seconds: 2));
      LyricLine line = timed
          ? _Line('在这里左右错速 hello world')
          : LrcLine(Duration.zero, '在这里左右错速 hello world', isBlank: false);
      final key = GlobalKey();
      final curve = LyricMotion.scrollCurveFor(spring: true, distance: 80);
      Widget host(bool reduced) => MaterialApp(
          theme: ThemeData(fontFamily: danEmbeddedFontFamily),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 420,
                      child: RepaintBoundary(
                          key: key,
                          child: ChangeNotifierProvider.value(
                              value: settings,
                              child: LyricWordFollowScope(
                                  follow: LyricWordFollow(clock, curve, 80),
                                  child: LyricViewTile(
                                      line: line,
                                      position: position,
                                      opacity: 1,
                                      distance: 0,
                                      reducedMotion: reduced))))))));
      await tester.pumpWidget(host(false));
      final size = tester.getSize(find.byKey(key));
      Object? layout;
      for (final t in [0.0, .15, .3, .5, .66, .8, .95, 1.0]) {
        clock.value = t;
        await tester.pump();
        expect(tester.getSize(find.byKey(key)), size);
        if (timed) {
          final p = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((widget) => widget.painter)
              .whereType<LyricWordHighlightPainter>()
              .single;
          layout ??= p.layoutIdentity;
          expect(p.layoutIdentity, same(layout));
          expect(p.progressForWord(0), .5);
          expect(p.followWordOffsets.last, 0);
        }
        const output = String.fromEnvironment('DAN_WORD_FOLLOW_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            await Directory(output).create(recursive: true);
            await File(
                    '$output/${timed ? "timed" : "plain"}-${(t * 100).round()}.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
      }
      Future<List<int>> endpointPixels(double phase) async {
        clock.value = phase;
        await tester.pump();
        return (await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes =
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List()
                  .toList();
          image.dispose();
          return bytes;
        }))!;
      }

      final beforeRest = await endpointPixels(.999999);
      final atRest = await endpointPixels(1);
      var changedChannels = 0, largestChange = 0;
      for (var i = 0; i < atRest.length; i++) {
        final change = (atRest[i] - beforeRest[i]).abs();
        if (change > 4) changedChannels++;
        if (change > largestChange) largestChange = change;
      }
      expect(changedChannels, 0,
          reason:
              'Ending follow must not switch glyph masks/glow; largest $largestChange');
      if (timed) {
        for (final heldText in ['微风轻轻吹过', '微风轻轻 hello']) {
          line = _Line(heldText);
          await tester.pumpWidget(host(false));
          final moving = await endpointPixels(.999999);
          final still = await endpointPixels(1);
          var largest = 0;
          for (var i = 0; i < still.length; i++) {
            final difference = (moving[i] - still[i]).abs();
            if (difference > largest) largest = difference;
          }
          expect(largest, lessThanOrEqualTo(4),
              reason: 'Held-word glow must remain continuous: $heldText');
        }
      }
      clock.value = .3;
      await tester.pumpWidget(host(true));
      if (timed) {
        final p = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<LyricWordHighlightPainter>()
            .single;
        expect(p.followWordOffsets, everyElement(0));
      } else {
        expect(
            tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((widget) => widget.painter)
                .whereType<PlainLyricWordFollowPainter>(),
            isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      clock.dispose();
      position.dispose();
      settings.dispose();
    });
  }
}
