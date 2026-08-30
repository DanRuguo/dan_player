import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

Lyric _lines([String prefix = 'Line']) => _Lyric([
      for (var i = 0; i < 16; i++)
        LrcLine(Duration(seconds: i * 5), '$prefix $i',
            isBlank: false, length: const Duration(seconds: 5)),
    ]);

class _Harness {
  _Harness({this.position = 0}) {
    future = Future.value(_lines());
    textSettings.lyricFontSize = 22;
    textSettings.translationFontSize = 18;
    addTearDown(() async {
      await positions.close();
      spring.dispose();
      textSettings.dispose();
    });
  }
  final positions = StreamController<double>.broadcast();
  final spring = ValueNotifier(true);
  final textSettings = LyricViewController();
  late Future<Lyric?> future;
  double position;
  final seeks = <double>[];
  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Widget app({bool reduced = false, double scale = 1}) => MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          disableAnimations: reduced,
                          textScaler: TextScaler.linear(scale)),
                      child: Center(
                          child: SizedBox(
                        width: 420,
                        height: 480,
                        child: ChangeNotifierProvider.value(
                          value: textSettings,
                          child: ValueListenableBuilder(
                            valueListenable: spring,
                            builder: (context, value, _) =>
                                VerticalLyricContent(
                              lyricFuture: future,
                              positionStream: positions.stream,
                              readPosition: () => position,
                              onSeek: (value) {
                                seeks.add(value);
                                emit(value);
                              },
                              springLyrics: value,
                            ),
                          ),
                        ),
                      )),
                    ))),
      );
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(
        find.byKey(const ValueKey('vertical-lyric-scroll')))
    .controller!;
double _height(WidgetTester tester) =>
    tester.getSize(find.byType(LyricViewTile).first).height;

double _targetForLine(WidgetTester tester, int index) {
  final viewport =
      tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
  final row = tester.getRect(find.byType(LyricViewTile).at(index));
  // The established focus point is a quarter of the available viewport, not
  // zero pixels: a short first row therefore already has a small base offset.
  return _scroll(tester).offset +
      row.top -
      viewport.top -
      (viewport.height - row.height) * .25;
}

Future<void> _startLine(
    WidgetTester tester, _Harness harness, double seconds) async {
  harness.emit(seconds);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  test('spring curve has a real but capped settle and exact endpoints', () {
    for (final distance in [20.0, 200.0, 4000.0]) {
      final curve =
          LyricMotion.scrollCurveFor(spring: true, distance: distance);
      final values = [
        for (var i = 0; i <= 1000; i++) curve.transform(i / 1000)
      ];
      expect(values.first, 0);
      expect(values.last, 1);
      expect(values.reduce(math.max), greaterThan(1));
      expect((values.reduce(math.max) - 1) * distance,
          lessThanOrEqualTo(8.000001));
      expect(values.every((value) => value.isFinite && value >= 0), true);
    }
  });

  testWidgets(
      'enabled spring settles without changing row size or state identity',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final rowHeight = _height(tester);
    final lineState = tester.state(find.byType(LyricLineMotion).at(1));
    final target = _scroll(tester).offset + rowHeight;
    await _startLine(tester, harness, 5.1);
    var peak = 0.0;
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 90));
      peak = math.max(peak, _scroll(tester).offset);
      expect(_height(tester), rowHeight);
      expect(tester.state(find.byType(LyricLineMotion).at(1)), same(lineState));
    }
    expect(peak, greaterThan(target + .05));
    expect(peak - target, lessThanOrEqualTo(8.01));
    expect(_scroll(tester).offset, closeTo(target, .001));
    expect(_scroll(tester).position.isScrollingNotifier.value, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning spring off retains monotonic fast-to-slow scroll',
      (tester) async {
    final harness = _Harness()..spring.value = false;
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final start = _scroll(tester).offset;
    final target = start + _height(tester);
    await _startLine(tester, harness, 5.1);
    var previous = start;
    final changes = <double>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 155));
      final offset = _scroll(tester).offset;
      expect(offset, inInclusiveRange(previous, target + .001));
      changes.add(offset - previous);
      previous = offset;
    }
    expect(changes[0], greaterThan(changes[1]));
    expect(changes[1], greaterThan(changes[2]));
    expect(_scroll(tester).offset, closeTo(target, .001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'large seek cancels an in-flight spring and does not overshoot new line',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final target = _targetForLine(tester, 8);
    await _startLine(tester, harness, 5.1);
    await tester.pump(const Duration(milliseconds: 90));
    final before = _scroll(tester).offset;
    await _startLine(tester, harness, 40);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      expect(_scroll(tester).offset, inInclusiveRange(before, target + .001));
    }
    expect(_scroll(tester).offset, closeTo(target, .001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nonzero first frame jumps to actual line without a stale spring',
      (tester) async {
    final harness = _Harness(position: 25);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(_targetForLine(tester, 5), .001));
    expect(_scroll(tester).position.isScrollingNotifier.value, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'manual wheel keeps four-second protection before spring following resumes',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(PointerScrollEvent(
      position:
          tester.getCenter(find.byKey(const ValueKey('vertical-lyric-scroll'))),
      scrollDelta: const Offset(0, 150),
    ));
    await tester.pump();
    final held = _scroll(tester).offset;
    harness.emit(40);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(_scroll(tester).offset, held);
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(_targetForLine(tester, 8), .001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'disabling spring during settle keeps focus and cancels its old activity',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final target = _targetForLine(tester, 1);
    await _startLine(tester, harness, 5.1);
    await tester.pump(const Duration(milliseconds: 320));
    harness.spring.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(target, .001));
    expect(_scroll(tester).position.isScrollingNotifier.value, false);
    expect(
        tester
            .widgetList<LyricViewTile>(find.byType(LyricViewTile))
            .where((line) => line.distance == 0)
            .length,
        1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'reduced motion overrides enabled spring including an active transition',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _startLine(tester, harness, 5.1);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(harness.app(reduced: true));
    await tester.pump();
    expect(_scroll(tester).offset, closeTo(_targetForLine(tester, 1), .001));
    expect(_scroll(tester).position.isScrollingNotifier.value, false);
    await _startLine(tester, harness, 10.1);
    expect(_scroll(tester).offset, closeTo(_targetForLine(tester, 2), .001));
    expect(_scroll(tester).position.isScrollingNotifier.value, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      '200% text keeps stable full-height rows through elastic transition',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app(scale: 2));
    await tester.pumpAndSettle();
    final height = _height(tester);
    await _startLine(tester, harness, 5.1);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_height(tester), height);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replaced source cancels spring and ignores late previous future',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _startLine(tester, harness, 5.1);
    await tester.pump(const Duration(milliseconds: 90));
    final late = Completer<Lyric?>();
    harness.future = late.future;
    await tester.pumpWidget(harness.app());
    await tester.pump();
    harness.future = Future.value(_lines('New'));
    harness.position = 0;
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    late.complete(_lines('Old'));
    await tester.pumpAndSettle();
    expect(find.text('New 0'), findsOneWidget);
    expect(find.text('Old 0'), findsNothing);
    expect(_scroll(tester).offset, closeTo(_targetForLine(tester, 0), .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
