import 'dart:async';

import 'package:dan_player/component/compact_player.dart';
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

  void seek(double target) {
    actual = target;
    seeks.add(target);
  }

  Widget host({required bool detail, ValueNotifier<bool>? hidden}) =>
      MaterialApp(
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
                      hidden: hidden,
                      onSeek: seek,
                    )
                  : CompactPlayerView(
                      position: actual,
                      positions: stream,
                      readPosition: () => actual,
                      duration: 200,
                      trackIdentity: ('track', 1),
                      hidden: hidden,
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
  expect(result, isNotNull, reason: 'Use the real Slider adjustment action.');
  return result!;
}

void main() {
  for (final detail in [true, false]) {
    final name = detail ? 'detail' : 'compact';
    for (final action in [SemanticsAction.increase, SemanticsAction.decrease]) {
      testWidgets('$name held touch retains ownership through ${action.name}',
          (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.positions.close);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(fixture.host(detail: detail));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
            tester.getRect(find.byType(Slider)).center,
            pointer: 1);
        var released = false;
        try {
          await gesture.moveBy(const Offset(60, 0));
          await tester.pump();
          final preview = _preview(tester);
          final node = _adjustmentNode(tester, action);
          node.owner!.performAction(node.id, action);
          await tester.pump();
          expect(fixture.seeks, isEmpty,
              reason: 'A semantics cycle cannot commit a held touch.');
          expect(_preview(tester), preview);
          await gesture.moveBy(const Offset(20, 0));
          await tester.pump();
          final moved = _preview(tester);
          expect(moved, greaterThan(preview),
              reason: 'The primary touch must continue updating its preview.');
          await gesture.up();
          released = true;
          await tester.pumpAndSettle();
          expect(fixture.seeks, [moved]);

          final idle = _adjustmentNode(tester, action);
          idle.owner!.performAction(idle.id, action);
          await tester.pumpAndSettle();
          expect(fixture.seeks, hasLength(2),
              reason:
                  'Idle semantics seeking remains available after release.');
          expect(
              fixture.actual,
              action == SemanticsAction.increase
                  ? greaterThan(moved)
                  : lessThan(moved));
        } finally {
          if (!released) {
            await gesture.cancel();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      });
    }
    testWidgets('$name held touch retains seek ownership through arrow input',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      await tester.pumpAndSettle();
      final focus = tester.widget<FocusableActionDetector>(find.descendant(
          of: find.byType(Slider),
          matching: find.byType(FocusableActionDetector)));
      focus.focusNode!.requestFocus();
      await tester.pump();
      final gesture = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 1);
      var released = false;
      try {
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        final preview = _preview(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(fixture.seeks, isEmpty,
            reason: 'A stock Slider shortcut cannot commit the held touch.');
        expect(_preview(tester), preview);
        await gesture.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.seeks, [preview]);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(fixture.seeks, hasLength(2),
            reason: 'Keyboard seeking remains available after touch release.');
        expect(fixture.actual, greaterThan(preview));
      } finally {
        if (!released) {
          await gesture.cancel();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('$name cancelled mixed-input drag commits no preview',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(detail: detail));
      await tester.pumpAndSettle();
      final focus = tester.widget<FocusableActionDetector>(find.descendant(
          of: find.byType(Slider),
          matching: find.byType(FocusableActionDetector)));
      focus.focusNode!.requestFocus();
      await tester.pump();
      final gesture = await tester
          .startGesture(tester.getRect(find.byType(Slider)).center, pointer: 1);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft);
      fixture.actual = 24;
      fixture.positions.add(fixture.actual);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(fixture.seeks, isEmpty);
      expect(_preview(tester), 24);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$name hidden focused slider rejects a queued arrow seek',
        (tester) async {
      final fixture = _Fixture();
      final hidden = ValueNotifier(false);
      addTearDown(fixture.positions.close);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(fixture.host(detail: detail, hidden: hidden));
      await tester.pumpAndSettle();
      final focus = tester.widget<FocusableActionDetector>(find.descendant(
          of: find.byType(Slider),
          matching: find.byType(FocusableActionDetector)));
      focus.focusNode!.requestFocus();
      await tester.pump();
      hidden.value = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fixture.seeks, isEmpty,
          reason: 'A queued key cannot seek a now hidden playback surface.');
      expect(fixture.actual, 20);
      hidden.value = false;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fixture.seeks, hasLength(1));
      expect(fixture.actual, greaterThan(20));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
