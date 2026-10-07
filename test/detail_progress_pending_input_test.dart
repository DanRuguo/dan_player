import 'dart:async';

import 'package:dan_player/page/now_playing_page/component/detail_playback_layout.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 300,
              child: DetailPlaybackLayout(
                display: const SizedBox.shrink(),
                controls: Column(mainAxisSize: MainAxisSize.min, children: [
                  DetailProgressSlider(
                    positions: stream,
                    readPosition: () => actual,
                    duration: 200,
                    trackIdentity: ('track', 1),
                    onSeek: (value) {
                      seeks.add(value);
                      actual = value;
                    },
                  ),
                  const SizedBox(height: 300),
                ]),
              ),
            ),
          ),
        ),
      );
}

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider));

SemanticsNode _adjustmentNode(WidgetTester tester, SemanticsAction action) {
  SemanticsNode? result;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(action)) {
      result = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return result == null;
    });
  }

  visit(tester.getSemantics(find.byType(Slider)));
  expect(result, isNotNull);
  return result!;
}

Future<void> _adjust(WidgetTester tester, String input) async {
  if (input == 'keyboard') {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
        physicalKey: PhysicalKeyboardKey.arrowRight);
  } else {
    final action = input == 'increase'
        ? SemanticsAction.increase
        : SemanticsAction.decrease;
    final node = _adjustmentNode(tester, action);
    node.owner!.performAction(node.id, action);
  }
}

void main() {
  for (final input in ['keyboard', 'increase', 'decrease']) {
    testWidgets(
        'scrolling detail pending touch retains ownership through $input',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      _slider(tester).focusNode!.requestFocus();
      await tester.pump();
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Slider)));
      var released = false;
      try {
        await tester.pump();
        expect(_slider(tester).value, 20);
        expect(_slider(tester).label, '0:20',
            reason: 'The real scroll arena has not accepted Slider start.');
        await _adjust(tester, input);
        await tester.pump();
        expect(fixture.seeks, isEmpty);
        expect(_slider(tester).value, 20);
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump();
        final preview = _slider(tester).value;
        expect(preview, greaterThan(20),
            reason: 'The pending physical start must still be accepted later.');
        await gesture.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.seeks, [preview]);
        await _adjust(tester, input);
        await tester.pumpAndSettle();
        expect(fixture.seeks, hasLength(2));
      } finally {
        if (!released) {
          await gesture.cancel();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }

  testWidgets('vertical detail scrolling revokes an accepted tap preview',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    var released = false;
    try {
      await tester.pump(const Duration(milliseconds: 120));
      expect(_slider(tester).value, greaterThan(20),
          reason:
              'TapDown fired after its deadline while the arena still waits.');
      await gesture.moveBy(const Offset(0, -80));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.descendant(
          of: find.byKey(const ValueKey('detail-playback-controls-scroll')),
          matching: find.byType(Scrollable)));
      expect(scroll.position.pixels, greaterThan(0),
          reason:
              'The real controls scrollable has consumed the vertical drag.');
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(fixture.seeks, isEmpty,
          reason:
              'Losing the arena to vertical scrolling is not a seek release.');
      expect(_slider(tester).value, 20);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
