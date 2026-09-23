import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;
  bool failSeek = false;

  Widget host({Stream<double>? stream}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: DetailProgressSlider(
                positions: stream ?? this.stream,
                readPosition: () => actual,
                duration: 200,
                trackIdentity: 'track',
                onSeek: (target) {
                  if (failSeek) throw StateError('isolated seek failure');
                  seeks.add(target);
                  actual = target;
                },
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
  await gesture.moveBy(const Offset(70, 0));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('cancelled native pointer capture restores time without seeking',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    final gesture = await _drag(tester);
    expect(_value(tester), greaterThan(100));
    fixture.actual = 24;
    fixture.positions.add(fixture.actual);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(_value(tester), 24);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('failed seek releases preview even while playback stays paused',
      (tester) async {
    final fixture = _Fixture()..failSeek = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    final gesture = await _drag(tester);
    await gesture.up();
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpAndSettle();
    expect(_value(tester), fixture.actual);
    fixture.failSeek = false;
    final retry = await _drag(tester);
    await retry.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, hasLength(1));
    expect(_value(tester), fixture.seeks.single);
  });

  testWidgets('replacing position source invalidates a captured drag',
      (tester) async {
    final fixture = _Fixture();
    final replacement = StreamController<double>.broadcast(sync: true);
    addTearDown(fixture.positions.close);
    addTearDown(replacement.close);
    await tester.pumpWidget(fixture.host());
    final gesture = await _drag(tester);
    fixture.actual = 40;
    await tester.pumpWidget(fixture.host(stream: replacement.stream));
    expect(fixture.positions.hasListener, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(_value(tester), 40);
    replacement.add(44);
    await tester.pumpAndSettle();
    expect(_value(tester), 44);
  });

  testWidgets('rebuilding the same source keeps a live drag until release',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    final gesture = await _drag(tester);
    final preview = _value(tester);
    fixture.actual = 24;
    await tester.pumpWidget(fixture.host());
    expect(_value(tester), preview);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, [preview]);
    expect(_value(tester), preview);
  });

  testWidgets('accessibility seek still completes without a pointer',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(fixture.host());
    final node = tester.getSemantics(find.byType(Slider));
    node.visitChildren((child) {
      if (child.getSemanticsData().hasAction(SemanticsAction.increase)) {
        child.owner!.performAction(child.id, SemanticsAction.increase);
      }
      return true;
    });
    await tester.pumpAndSettle();
    expect(fixture.seeks, hasLength(1));
    expect(fixture.seeks.single, greaterThan(20));
    expect(_value(tester), fixture.seeks.single);
    semantics.dispose();
  });
}
