import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final hidden = ValueNotifier(false);
  final seeks = <double>[];
  double actual = 12;

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 80,
              child: RectangleProgressIndicator(
                size: const Size(400, 80),
                positionStream: stream,
                lengthProvider: () => 120,
                readPosition: () => actual,
                initialPosition: actual,
                trackIdentity: ('track', 1),
                hidden: hidden,
                onSeek: (target) {
                  actual = target;
                  seeks.add(target);
                },
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const SizedBox.expand()),
              ),
            ),
          ),
        ),
      );

  Future<void> close() async {
    await positions.close();
    hidden.dispose();
  }
}

double _preview(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<RectangleProgressPainter>()
    .single
    .progress
    .value;

Future<void> _focus(WidgetTester tester) async {
  tester
      .widget<Focus>(find.byKey(const ValueKey('now-playing-seek')))
      .focusNode!
      .requestFocus();
  await tester.pump();
}

Future<void> _adjust(WidgetTester tester, String input) async {
  if (input == 'keyboard') {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
        physicalKey: PhysicalKeyboardKey.arrowRight);
  } else {
    final node = tester
        .getSemantics(find.byKey(const ValueKey('now-playing-seek-semantics')));
    final action = input == 'increase'
        ? SemanticsAction.increase
        : SemanticsAction.decrease;
    expect(node.getSemanticsData().hasAction(action), isTrue);
    node.owner!.performAction(node.id, action);
  }
}

void main() {
  testWidgets('boundary pending touch keeps ownership before drag acceptance',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await tester.pumpWidget(fixture.host());
    await _focus(tester);
    final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
    final gesture = await tester.startGesture(origin + const Offset(40, 30));
    var released = false;
    try {
      await _adjust(tester, 'keyboard');
      expect(fixture.seeks, isEmpty,
          reason: 'An owned boundary press has not yet passed touch slop.');
      await gesture.moveTo(origin + const Offset(240, 30));
      await tester.pump();
      expect(_preview(tester), closeTo(.6, 1e-9));
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(fixture.seeks, [72]);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final input in ['keyboard', 'increase', 'decrease']) {
    testWidgets('boundary held touch retains its preview through $input',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(fixture.host());
      await _focus(tester);
      final origin = tester.getTopLeft(find.byType(RectangleProgressIndicator));
      final gesture = await tester.startGesture(origin + const Offset(40, 30));
      var released = false;
      try {
        await gesture.moveTo(origin + const Offset(240, 30));
        await tester.pump();
        final preview = _preview(tester);
        await _adjust(tester, input);
        await tester.pump();
        expect(fixture.seeks, isEmpty);
        expect(_preview(tester), preview);
        await gesture.moveTo(origin + const Offset(280, 30));
        await tester.pump();
        expect(_preview(tester), closeTo(.7, 1e-9));
        await gesture.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.seeks, [84]);
        await _adjust(tester, input);
        await tester.pumpAndSettle();
        expect(fixture.seeks, hasLength(2),
            reason: 'The same adjustment remains available after release.');
        expect(fixture.actual,
            input == 'decrease' ? lessThan(84) : greaterThan(84));
      } finally {
        if (!released) {
          await gesture.cancel();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });

    testWidgets('hidden boundary rejects a queued $input adjustment',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(fixture.host());
        await _focus(tester);
        fixture.hidden.value = true;
        await _adjust(tester, input);
        await tester.pumpAndSettle();
        expect(fixture.seeks, isEmpty);
        expect(fixture.actual, 12);
        fixture.hidden.value = false;
        await tester.pump();
        await _adjust(tester, input);
        await tester.pumpAndSettle();
        expect(fixture.seeks, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }
}
