import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SliderFixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;

  void seek(double target) {
    actual = target;
    seeks.add(target);
  }

  Widget host({required bool detail}) => MaterialApp(
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
                      trackIdentity: ('track', 1),
                      onSeek: seek,
                    )
                  : CompactPlayerView(
                      position: actual,
                      positions: stream,
                      readPosition: () => actual,
                      duration: 200,
                      trackIdentity: ('track', 1),
                      lyricFuture: Future.value(null),
                      onSeek: seek,
                    ),
            ),
          ),
        ),
      );
}

double _preview(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

Future<TestGesture> _primary(WidgetTester tester,
    {int pointer = 1, PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final bounds = tester.getRect(find.byType(Slider));
  final primary =
      await tester.startGesture(bounds.center, pointer: pointer, kind: kind);
  await primary.moveBy(const Offset(60, 0));
  await tester.pump();
  return primary;
}

void main() {
  for (final detail in [true, false]) {
    final name = detail ? 'detail' : 'compact';
    testWidgets('$name secondary finger cannot move the active seek preview',
        (tester) async {
      final fixture = _SliderFixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      final first = await _primary(tester);
      final preview = _preview(tester);
      final second = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 2);
      await second.moveBy(const Offset(-90, 0));
      await tester.pump();
      expect(_preview(tester), preview);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(fixture.seeks, [preview]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$name primary release commits before a held secondary contact',
        (tester) async {
      final fixture = _SliderFixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      final first = await _primary(tester);
      final preview = _preview(tester);
      final second = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 2);
      await first.up();
      await tester.pump();
      expect(fixture.seeks, [preview]);
      await second.moveBy(const Offset(-90, 0));
      await second.up();
      await tester.pumpAndSettle();
      expect(fixture.seeks, [preview]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$name primary cancel revokes seek with a secondary still down',
        (tester) async {
      final fixture = _SliderFixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      final first = await _primary(tester);
      final second = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 2);
      fixture.actual = 24;
      fixture.positions.add(fixture.actual);
      await first.cancel();
      await second.moveBy(const Offset(-90, 0));
      await second.up();
      await tester.pumpAndSettle();
      expect(fixture.seeks, isEmpty);
      expect(_preview(tester), fixture.actual);
      final retry = await _primary(tester);
      await retry.up();
      await tester.pumpAndSettle();
      expect(fixture.seeks, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$name new drag owns seek while an ignored contact stays down',
        (tester) async {
      final fixture = _SliderFixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      final first = await _primary(tester,
          kind: detail ? PointerDeviceKind.touch : PointerDeviceKind.mouse);
      final second = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 2);
      await first.cancel();
      await tester.pump();
      expect(fixture.seeks, isEmpty);

      // The canceled first drag has ended. A fresh contact starts a new drag;
      // the held, previously ignored second contact cannot acquire ownership.
      final third = await _primary(tester, pointer: 3);
      final preview = _preview(tester);
      await second.moveBy(const Offset(-90, 0));
      await second.up();
      await tester.pump();
      expect(_preview(tester), preview);
      expect(fixture.seeks, isEmpty);
      await third.up();
      await tester.pumpAndSettle();
      expect(fixture.seeks, [preview]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
