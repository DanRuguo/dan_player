import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  final seeks = <double>[];
  double actual = 12;
  bool readActual = false;
  bool rejectSeek = false;
  bool throwOnSeek = false;
  bool roundSeek = false;

  Widget app() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 80,
              child: RectangleProgressIndicator(
                size: const Size(400, 80),
                positionStream: positions.stream,
                lengthProvider: () => 120,
                initialPosition: actual,
                readPosition: readActual ? () => actual : null,
                trackIdentity: ('track', 1),
                onSeek: (target) {
                  if (throwOnSeek) throw StateError('seek rejected');
                  // PlaybackService reports its own error and returns normally.
                  if (rejectSeek) return;
                  actual = roundSeek ? target.roundToDouble() : target;
                  seeks.add(target);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
}

RectangleProgressPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<RectangleProgressPainter>()
    .single;

Future<void> _focus(WidgetTester tester) async {
  tester
      .widget<Focus>(find.byKey(const ValueKey('now-playing-seek')))
      .focusNode!
      .requestFocus();
  await tester.pump();
}

void main() {
  testWidgets('second contact cannot disarm the first pending boundary drag',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
    final first =
        await tester.startGesture(origin + const Offset(40, 30), pointer: 1);
    final second =
        await tester.startGesture(origin + const Offset(200, 60), pointer: 2);
    await first.moveTo(origin + const Offset(300, 30));
    await first.up();
    await second.up();
    expect(fixture.seeks, [90]);
  });

  testWidgets('unrelated touch cancellation preserves an active boundary drag',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
    final first =
        await tester.startGesture(origin + const Offset(40, 30), pointer: 1);
    await first.moveTo(origin + const Offset(300, 30));
    final second =
        await tester.startGesture(origin + const Offset(160, 60), pointer: 2);
    await second.cancel();
    expect(_painter(tester).progress.value, .75);
    await first.up();
    expect(fixture.seeks, [90]);
  });

  testWidgets('second finger on the preview cannot take over the seek handle',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
    final first =
        await tester.startGesture(origin + const Offset(40, 30), pointer: 1);
    await first.moveTo(origin + const Offset(300, 30));
    final second =
        await tester.startGesture(origin + const Offset(300, 60), pointer: 2);
    await second.moveTo(origin + const Offset(100, 60));
    expect(_painter(tester).progress.value, .75);
    await first.up();
    expect(fixture.seeks, [90]);
    await second.up();
    expect(fixture.seeks, [90]);
  });

  testWidgets('internally handled seek failure restores paused actual progress',
      (tester) async {
    final fixture = _Fixture()
      ..readActual = true
      ..rejectSeek = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
    final gesture = await tester.startGesture(origin + const Offset(40, 30));
    await gesture.moveTo(origin + const Offset(300, 30));
    await gesture.up();
    expect(_painter(tester).progress.value, .1);
    expect(fixture.seeks, isEmpty);
  });

  testWidgets('keyboard failure restores the last position without a reader',
      (tester) async {
    final fixture = _Fixture()..throwOnSeek = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    await _focus(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(tester.takeException(), isA<StateError>());
    expect(_painter(tester).progress.value, .1);
  });

  testWidgets('keyboard seeking uses native rounding for the next adjustment',
      (tester) async {
    final fixture = _Fixture()
      ..readActual = true
      ..roundSeek = true
      ..actual = 12.4;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    await _focus(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(_painter(tester).progress.value, 17 / 120);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(fixture.seeks.last, closeTo(22, 1e-9));
  });

  testWidgets(
      'accessibility rejected seek keeps the truthful paused percentage',
      (tester) async {
    final fixture = _Fixture()
      ..readActual = true
      ..rejectSeek = true;
    addTearDown(fixture.positions.close);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(fixture.app());
    final finder = find.byKey(const ValueKey('now-playing-seek-semantics'));
    final node = tester.getSemantics(finder);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(tester.getSemantics(finder).getSemanticsData().value, '10%');
    handle.dispose();
  });
}
