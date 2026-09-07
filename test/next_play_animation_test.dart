import 'package:dan_player/component/next_play_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  tearDown(NextPlayAnimation.cancel);

  test('flight path is a real curve with exact endpoints', () {
    const source = Rect.fromLTWH(0, 180, 48, 48);
    const target = Rect.fromLTWH(420, 180, 44, 44);
    expect(nextPlayFlightPosition(source, target, 0), source.center);
    expect(nextPlayFlightPosition(source, target, 1), target.center);
    final midpoint = nextPlayFlightPosition(source, target, .5);
    expect(midpoint.dy, lessThan(source.center.dy - 20));

    const nearTitleBar = Rect.fromLTWH(8, 0, 32, 32);
    for (var step = 0; step <= 20; step++) {
      expect(
        nextPlayFlightPosition(nearTitleBar, target, step / 20).dy,
        greaterThanOrEqualTo(0),
      );
    }
  });

  test('original launch blends into gentle arrival even with a queue far below',
      () {
    const source = Rect.fromLTWH(16, 28, 48, 48);
    for (final target in [
      const Rect.fromLTWH(580, 520, 44, 44),
      const Rect.fromLTWH(420, 30, 44, 44),
      const Rect.fromLTWH(24, 520, 44, 44),
    ]) {
      final path = NextPlayFlightPath(source, target);
      Offset point(double time) =>
          path.positionAt(nextPlayFlightProgress(time));
      expect(point(0), source.center);
      expect(point(1), target.center);
      final approaching = (point(.80) - point(.75)).distance;
      final arriving = (point(.95) - point(.90)).distance;
      expect(approaching / arriving, inInclusiveRange(1.1, 1.8));
      expect(
          nextPlayFlightProgress(.1), Curves.easeInCubic.transform(52 / 430));
      var previous = 0.0;
      for (var step = 1; step <= 100; step++) {
        final progress = nextPlayFlightProgress(step / 100);
        expect(progress, greaterThan(previous));
        previous = progress;
      }
    }
  });

  testWidgets('root flight finishes and a later pointer cancels immediately',
      (tester) async {
    final sourceKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 24,
            top: 180,
            child: SizedBox.square(
              key: sourceKey,
              dimension: 48,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: SizedBox.square(
              key: NextPlayAnimation.targetKey,
              dimension: 44,
            ),
          ),
        ]),
      ),
    ));

    final context = tester.element(find.byKey(sourceKey));
    final started = NextPlayAnimation.fly(
      context: context,
      sourceContext: context,
      audio: CategoryTestAudio('Flight'),
    );
    expect(started, isTrue);
    // An inserted OverlayEntry is not `mounted` until its first build. A
    // same-frame cancellation must still remove it before disposal.
    NextPlayAnimation.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const ValueKey('next-play-flight-surface')), findsNothing);

    expect(
        NextPlayAnimation.fly(
          context: context,
          sourceContext: context,
          audio: CategoryTestAudio('Replaced'),
        ),
        isTrue);
    expect(
        NextPlayAnimation.fly(
          context: context,
          sourceContext: context,
          audio: CategoryTestAudio('Cancel'),
        ),
        isTrue);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('next-play-flight-surface')), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('next-play-flight-surface')), findsNothing);

    expect(
        NextPlayAnimation.fly(
          context: context,
          sourceContext: context,
          audio: CategoryTestAudio('Finish'),
        ),
        isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 530));
    expect(
        find.byKey(const ValueKey('next-play-flight-surface')), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(context.mounted, isFalse);
    expect(
      NextPlayAnimation.fly(
        context: context,
        sourceContext: context,
        audio: CategoryTestAudio('Unmounted'),
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
