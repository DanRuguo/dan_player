import 'package:dan_player/component/touch_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edge slider drag seeks without also navigating', (tester) async {
    var value = 0.0;
    var completed = 0;
    var returns = 0;
    await tester.pumpWidget(MaterialApp(
        home: Material(
      child: TouchEdgeSwipe(
          onSwipeRight: () => returns++,
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 320,
                  height: 80,
                  child: StatefulBuilder(
                      builder: (context, update) => Slider(
                          value: value,
                          onChanged: (next) => update(() => value = next),
                          onChangeEnd: (_) => completed++))))),
    )));
    final finger = await tester.startGesture(const Offset(24, 40));
    await finger.moveTo(const Offset(160, 40));
    await finger.up();
    await tester.pumpAndSettle();
    expect(value, greaterThan(.3));
    expect(completed, 1);
    expect(returns, 0);
  });

  testWidgets('an accepted button long press cannot turn into edge navigation',
      (tester) async {
    var held = 0;
    var returns = 0;
    await tester.pumpWidget(MaterialApp(
        home: Material(
      child: TouchEdgeSwipe(
          onSwipeRight: () => returns++,
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 250,
                  height: 80,
                  child: TextButton(
                      onPressed: () {},
                      onLongPress: () => held++,
                      child: const Text('Hold'))))),
    )));
    final finger = await tester.startGesture(const Offset(24, 40));
    await tester.pump(const Duration(milliseconds: 650));
    expect(held, 1);
    await finger.moveTo(const Offset(160, 40));
    await finger.up();
    await tester.pumpAndSettle();
    expect(returns, 0);
  });

  testWidgets('two fingers cancel track switching until the sequence ends',
      (tester) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(MaterialApp(
        home: TouchTrackSwipe(
      onPrevious: () => previous++,
      onNext: () => next++,
      child: const SizedBox.expand(),
    )));
    final first = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final second =
        await tester.startGesture(const Offset(350, 200), pointer: 2);
    await first.moveTo(const Offset(320, 200));
    await first.up();
    await second.cancel();
    expect((previous, next), (0, 0));
    final single =
        await tester.startGesture(const Offset(300, 200), pointer: 3);
    await single.moveTo(const Offset(180, 200));
    await single.up();
    expect((previous, next), (0, 1));
  });

  testWidgets('nested edge and cover swipes commit a single action',
      (tester) async {
    var returns = 0;
    var previous = 0;
    await tester.pumpWidget(MaterialApp(
        home: TouchEdgeSwipe(
      onSwipeRight: () => returns++,
      child: TouchTrackSwipe(
          onPrevious: () => previous++,
          onNext: () {},
          child: const SizedBox.expand()),
    )));
    final finger = await tester.startGesture(const Offset(12, 200));
    await finger.moveTo(const Offset(132, 200));
    await finger.up();
    expect((returns, previous), (0, 1));
  });

  testWidgets(
      'vertical edge movement scrolls the child and stylus can navigate',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var returns = 0;
    await tester.pumpWidget(MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        home: TouchEdgeSwipe(
            onSwipeRight: () => returns++,
            child: ListView.builder(
                controller: scroll,
                itemExtent: 100,
                itemCount: 30,
                itemBuilder: (_, i) => Text('Line $i')))));
    final finger = await tester.startGesture(const Offset(12, 300));
    await finger.moveBy(const Offset(0, -120));
    await tester.pump();
    await finger.moveBy(const Offset(0, -80));
    await finger.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(60));
    expect(returns, 0);
    final pen = await tester.startGesture(const Offset(12, 300),
        kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(110, 0));
    await pen.up();
    expect(returns, 1);
  });

  testWidgets(
      'edge reversal stays inert and foreign mouse does not cancel touch',
      (tester) async {
    var returns = 0;
    await tester.pumpWidget(MaterialApp(
        home: TouchEdgeSwipe(
            onSwipeRight: () => returns++, child: const SizedBox.expand())));
    final reverse =
        await tester.startGesture(const Offset(12, 200), pointer: 1);
    await reverse.moveBy(const Offset(25, 0));
    await reverse.moveBy(const Offset(-160, 0));
    await reverse.up();
    expect(returns, 0);
    final finger = await tester.startGesture(const Offset(12, 200), pointer: 2);
    final mouse = await tester.startGesture(const Offset(100, 200),
        pointer: 3, kind: PointerDeviceKind.mouse);
    await mouse.up();
    await finger.moveBy(const Offset(110, 0));
    await finger.up();
    expect(returns, 1);
  });
}
