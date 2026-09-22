import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _length = Duration(seconds: 12);

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  final result = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return result!;
}

Widget _fixture(GlobalKey key, ValueNotifier<Duration> position,
        {bool active = true, bool reduced = false}) =>
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 72,
              height: 24,
              child: LyricTransitionTile(
                line:
                    LrcLine(Duration.zero, '', isBlank: true, length: _length),
                length: _length,
                position: position,
                active: active,
                reducedMotion: reduced,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  test('interlude dots enter separately and breathe visibly inside the row',
      () {
    final waiting =
        LyricMotion.interludePose(const Duration(milliseconds: 490), _length);
    final early =
        LyricMotion.interludePose(const Duration(milliseconds: 600), _length);
    final peak =
        LyricMotion.interludePose(const Duration(milliseconds: 3125), _length);
    final rest =
        LyricMotion.interludePose(const Duration(milliseconds: 5750), _length);
    expect(waiting.opacity, 0);
    expect(early.dotOpacities.$1, greaterThan(early.dotOpacities.$2));
    expect(early.dotOpacities.$2, greaterThan(early.dotOpacities.$3));
    expect(early.dotOpacities.$3, 0);
    expect(peak.scale, closeTo(1.25, .000001));
    expect(rest.scale, closeTo(1, .000001));
    // Includes the dot radius, not just the centre: no extra layout/clip area.
    expect(36 - (24 + 4.2) * peak.scale, greaterThanOrEqualTo(0));
    expect(36 + (24 + 4.2) * peak.scale, lessThanOrEqualTo(72));
    expect(12 + 4.2 * peak.scale, lessThanOrEqualTo(24));
  });

  test('the final dot completes before the group visibly contracts and fades',
      () {
    final beforeExit =
        LyricMotion.interludePose(const Duration(seconds: 11), _length);
    final charged =
        LyricMotion.interludePose(const Duration(milliseconds: 11750), _length);
    final closing =
        LyricMotion.interludePose(const Duration(milliseconds: 11950), _length);
    final complete = LyricMotion.interludePose(_length, _length);
    expect(beforeExit.dotOpacities.$3, lessThan(beforeExit.dotOpacities.$2));
    expect(charged.dotOpacities.$3, closeTo(.9, .000001));
    expect(charged.scale, closeTo(1.25, .000001));
    expect(charged.opacity, 1);
    expect(closing.scale, lessThan(.5));
    expect(closing.opacity, lessThan(.12));
    expect(complete.opacity, 0);
    expect(complete.dotOpacities, (0, 0, 0));
  });

  test('all boundaries and 144 Hz samples stay continuous and finite', () {
    final boundariesMs = [
      500,
      680,
      1250,
      1330,
      1410,
      5750,
      11000,
      11750,
      12000
    ];
    List<double> visible(Duration elapsed) {
      final pose = LyricMotion.interludePose(elapsed, _length);
      return [
        pose.scale * pose.opacity,
        pose.opacity * pose.dotOpacities.$1,
        pose.opacity * pose.dotOpacities.$2,
        pose.opacity * pose.dotOpacities.$3,
      ];
    }

    for (final ms in boundariesMs) {
      final before = visible(Duration(microseconds: ms * 1000 - 1));
      final after = visible(Duration(microseconds: ms * 1000 + 1));
      for (var i = 0; i < before.length; i++) {
        expect((after[i] - before[i]).abs(), lessThan(.0001),
            reason: '$ms / $i');
      }
    }
    var previous = visible(Duration.zero);
    for (var sample = 1; sample <= 1728; sample++) {
      final time = Duration(microseconds: (sample * 1000000 / 144).round());
      final pose = LyricMotion.interludePose(time, _length);
      final values = visible(time);
      expect(pose.scale, inInclusiveRange(0, 1.25));
      expect(pose.opacity, inInclusiveRange(0, 1));
      for (var i = 0; i < values.length; i++) {
        expect(values[i].isFinite, isTrue);
        expect((values[i] - previous[i]).abs(), lessThan(.1));
      }
      previous = values;
    }
  });

  test('short remainders use a steady hold or stay hidden without flashing',
      () {
    final hidden = LyricMotion.interludePose(
        const Duration(milliseconds: 1500), const Duration(seconds: 2));
    final short = LyricMotion.interludePose(
        const Duration(milliseconds: 1500), const Duration(seconds: 3));
    expect(hidden.opacity, 0);
    expect(short.scale, 1);
    expect(short.opacity, 1);
    expect(short.dotOpacities.$1, closeTo(.9, .000001));
    expect(short.dotOpacities.$2, closeTo(.9, .000001));
    expect(short.dotOpacities.$3, closeTo(.9, .000001));
    const seekTime = Duration(milliseconds: 11750);
    final first = LyricMotion.interludePose(seekTime, _length);
    LyricMotion.interludePose(const Duration(milliseconds: 100), _length);
    expect(LyricMotion.interludePose(seekTime, _length), first);
  });

  testWidgets('paused media freezes dots without scheduling visual frames',
      (tester) async {
    final key = GlobalKey();
    final position = ValueNotifier(const Duration(seconds: 3));
    addTearDown(position.dispose);
    await tester.pumpWidget(_fixture(key, position));
    final before = await _pixels(tester, key);
    await tester.pump(const Duration(seconds: 2));
    expect(await _pixels(tester, key), orderedEquals(before));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    position.value = const Duration(seconds: 5);
    await tester.pump();
    expect(await _pixels(tester, key), isNot(orderedEquals(before)));
  });

  testWidgets('inactive or reduced dots do not refresh on playback samples',
      (tester) async {
    final position = ValueNotifier(const Duration(seconds: 3));
    addTearDown(position.dispose);
    for (final reduced in [false, true]) {
      final key = GlobalKey();
      position.value = const Duration(seconds: 3);
      await tester.pumpWidget(
          _fixture(key, position, active: reduced, reduced: reduced));
      final before = await _pixels(tester, key);
      position.value = const Duration(seconds: 8);
      await tester.pump(const Duration(seconds: 1));
      expect(await _pixels(tester, key), orderedEquals(before));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    final reduced = LyricMotion.interludePose(
        const Duration(seconds: 6), _length,
        reduced: true);
    expect(reduced.scale, 1);
    expect(reduced.opacity, 1);
    expect(reduced.dotOpacities, (1, 1, 1));
  });

  testWidgets('entry breathing and release preserve the allocated layout',
      (tester) async {
    final key = GlobalKey();
    final position = ValueNotifier(Duration.zero);
    addTearDown(position.dispose);
    await tester.pumpWidget(_fixture(key, position));
    final renderDirectory =
        Platform.environment['DAN_LYRIC_INTERLUDE_RENDER_DIR'];
    if (renderDirectory != null) {
      await tester
          .runAsync(() => Directory(renderDirectory).create(recursive: true));
    }
    for (final ms in [
      0,
      600,
      900,
      1410,
      3125,
      5750,
      11000,
      11750,
      11950,
      12000
    ]) {
      position.value = Duration(milliseconds: ms);
      await tester.pump();
      expect(tester.getSize(find.byKey(key)), const Size(72, 24));
      final pixels = await _pixels(tester, key);
      final hasInk = [for (var i = 3; i < pixels.length; i += 4) pixels[i]]
          .any((alpha) => alpha > 0);
      expect(hasInk, ms > 0 && ms < 12000);
      if (renderDirectory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 4);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$renderDirectory/interlude-$ms.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    expect(tester.binding.transientCallbackCount, 0);
  });
}
