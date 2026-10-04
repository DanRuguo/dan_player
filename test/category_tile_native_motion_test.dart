import 'package:dan_player/component/category_tile_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native reduceMotion settles a moving tile and retires its clock',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const tileKey = ValueKey('native-layout-tile');
    const source = Rect.fromLTWH(20, 30, 80, 90);
    const destination = Rect.fromLTWH(300, 150, 160, 120);
    const next = Rect.fromLTWH(120, 280, 120, 160);
    var rect = source;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return Stack(children: [
        Positioned.fromRect(
            rect: rect,
            child: CategoryTileMotion(
                rect: rect,
                child: const ColoredBox(key: tileKey, color: Colors.teal))),
      ]);
    }))));
    Rect painted() {
      final box = tester.renderObject<RenderBox>(find.byKey(tileKey));
      return Rect.fromPoints(box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)));
    }

    void near(Rect expected) {
      final actual = painted();
      expect(actual.left, closeTo(expected.left, .001));
      expect(actual.top, closeTo(expected.top, .001));
      expect(actual.width, closeTo(expected.width, .001));
      expect(actual.height, closeTo(expected.height, .001));
    }

    await tester.pumpAndSettle();
    update(() => rect = destination);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    expect(painted().left, greaterThan(source.left));
    expect(painted().left, lessThan(destination.left));
    expect(tester.binding.transientCallbackCount, 1);
    expect(MediaQuery.disableAnimationsOf(tester.element(find.byKey(tileKey))),
        isFalse);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    near(destination);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    // A subsequent relayout must remain direct while the system flag is set.
    update(() => rect = next);
    await tester.pump();
    near(next);
    expect(tester.binding.transientCallbackCount, 0);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pumpAndSettle();
    near(next);
    expect(tester.binding.transientCallbackCount, 0);
    update(() => rect = source);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    expect(painted().left, greaterThan(source.left));
    expect(painted().left, lessThan(next.left));
    await tester.pumpAndSettle();
    near(source);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
