import 'dart:async';

import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;
  int session = 1;
  bool failSeek = false;
  Future<Lyric?> lyrics = Future.value(null);

  void seek(double value) {
    if (failSeek) throw StateError('seek rejected');
    seeks.add(value);
    actual = value;
  }

  Widget app({bool detail = false, bool enabled = true}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 300,
              child: detail
                  ? DetailProgressSlider(
                      positions: stream,
                      readPosition: () => actual,
                      duration: 200,
                      trackIdentity: ('same-track', session),
                      enabled: enabled,
                      onSeek: seek,
                    )
                  : CompactPlayerView(
                      position: actual,
                      positions: stream,
                      readPosition: () => actual,
                      duration: 200,
                      trackIdentity: ('same-track', session),
                      lyricFuture: lyrics,
                      isBuffering: !enabled,
                      onSeek: seek,
                    ),
            ),
          ),
        ),
      );
}

double _value(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

Future<TestGesture> _drag(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(Slider));
  final gesture = await tester.startGesture(rect.center);
  await gesture.moveBy(const Offset(60, 0));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('compact pointer cancellation cannot seek or retain preview',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final gesture = await _drag(tester);
    fixture.actual = 24;
    fixture.positions.add(fixture.actual);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(_value(tester), 24);
  });

  testWidgets('compact failing callback releases slider for a real next drag',
      (tester) async {
    final fixture = _Fixture()..failSeek = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final gesture = await _drag(tester);
    await gesture.up();
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpAndSettle();
    expect(_value(tester), 20);
    fixture.failSeek = false;
    final retry = await _drag(tester);
    await retry.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, hasLength(1));
    expect(_value(tester), fixture.actual);
  });

  testWidgets('compact paused seek reads actual position before the next tick',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final gesture = await _drag(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.actual, greaterThan(100));
    expect(_value(tester), fixture.actual);
  });

  testWidgets('replacing compact lyrics preserves the same playback drag',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final gesture = await _drag(tester);
    final preview = _value(tester);
    fixture.lyrics = Future.value(null);
    await tester.pumpWidget(fixture.app());
    expect(_value(tester), preview);
    await gesture.up();
    expect(fixture.seeks, [preview]);
  });

  testWidgets('detail reopening the same path invalidates its previous session',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app(detail: true));
    final gesture = await _drag(tester);
    fixture.session++;
    fixture.actual = 0;
    await tester.pumpWidget(fixture.app(detail: true));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(_value(tester), 0);
  });

  for (final detail in [false, true]) {
    testWidgets('local source opening cancels captured seek: detail=$detail',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app(detail: detail));
      final gesture = await _drag(tester);
      await tester.pumpWidget(fixture.app(detail: detail, enabled: false));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(fixture.seeks, isEmpty);
    });
  }
}
