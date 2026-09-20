import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tileKey = ValueKey('moving-tile-content');
const _start = Rect.fromLTWH(0, 0, 80, 80);
const _firstTarget = Rect.fromLTWH(200, 100, 160, 120);

class _Scene {
  Rect rect = _start;
  bool linear = false;
  bool visible = true;
  late StateSetter update;

  Widget build() => MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return TickerMode(
            enabled: visible,
            child: Offstage(
              offstage: !visible,
              child: Stack(children: [
                Positioned.fromRect(
                  rect: rect,
                  child: CategoryTileMotion(
                    rect: rect,
                    linear: linear,
                    child: const SizedBox.expand(key: _tileKey),
                  ),
                ),
              ]),
            ),
          );
        }),
      );

  Future<void> move(WidgetTester tester, Rect target) async {
    update(() => rect = target);
    await tester.pump();
    await tester.pump();
  }
}

Rect _paintedRect(WidgetTester tester) {
  final box =
      tester.renderObject<RenderBox>(find.byKey(_tileKey, skipOffstage: false));
  return Rect.fromPoints(box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)));
}

void _near(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .001));
  expect(actual.top, closeTo(expected.top, .001));
  expect(actual.width, closeTo(expected.width, .001));
  expect(actual.height, closeTo(expected.height, .001));
}

void main() {
  for (final initialLinear in [false, true]) {
    testWidgets(
        'changing fill mode preserves a running ${initialLinear ? 'linear' : 'eased'} tile flight',
        (tester) async {
      final scene = _Scene()..linear = initialLinear;
      await tester.pumpWidget(scene.build());
      await scene.move(tester, _firstTarget);
      await tester.pump(const Duration(milliseconds: 45));
      final before = _paintedRect(tester);
      expect(before.left, greaterThan(_start.left));
      expect(before.left, lessThan(_firstTarget.left));

      scene.update(() => scene.linear = !initialLinear);
      await tester.pump();
      _near(_paintedRect(tester), before);
      await tester.pump(const Duration(milliseconds: 45));
      _near(
          _paintedRect(tester),
          Rect.lerp(_start, _firstTarget,
              initialLinear ? .5 : AppMotion.standardCurve.transform(.5))!);
      await tester.pumpAndSettle();
      _near(_paintedRect(tester), _firstTarget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('retargeting uses the visible frame and the newly selected curve',
      (tester) async {
    final scene = _Scene();
    await tester.pumpWidget(scene.build());
    await scene.move(tester, _firstTarget);
    await tester.pump(const Duration(milliseconds: 45));
    scene.update(() => scene.linear = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final expectedBefore = Rect.lerp(
        _start, _firstTarget, AppMotion.standardCurve.transform(65 / 180))!;
    _near(_paintedRect(tester), expectedBefore);

    const nextTarget = Rect.fromLTWH(400, 260, 90, 160);
    await scene.move(tester, nextTarget);
    _near(_paintedRect(tester), expectedBefore);
    await tester.pump(const Duration(milliseconds: 45));
    _near(_paintedRect(tester), Rect.lerp(expectedBefore, nextTarget, .25)!);
    await tester.pumpAndSettle();
    _near(_paintedRect(tester), nextTarget);
  });

  testWidgets('hiding mid-flight settles before returning to a visible page',
      (tester) async {
    final scene = _Scene();
    await tester.pumpWidget(scene.build());
    await scene.move(tester, _firstTarget);
    await tester.pump(const Duration(milliseconds: 45));
    expect(_paintedRect(tester).left, lessThan(_firstTarget.left));
    scene.update(() => scene.visible = false);
    await tester.pump();
    _near(_paintedRect(tester), _firstTarget);
    // Drain the frame already requested before hiding; no new ticks may follow.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A layout change made while hidden must also be settled immediately.
    const hiddenTarget = Rect.fromLTWH(340, 200, 90, 160);
    await scene.move(tester, hiddenTarget);
    _near(_paintedRect(tester), hiddenTarget);
    await tester.pump(const Duration(seconds: 2));
    scene.update(() => scene.visible = true);
    await tester.pump();
    _near(_paintedRect(tester), hiddenTarget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    _near(_paintedRect(tester), hiddenTarget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
