import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'resizing during cover flight releases the old viewport snapshots',
      (tester) async {
    final controller = PlaylistCoverTransitionController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    var size = const Size(400, 400);
    var moved = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Center(child: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return SizedBox.fromSize(
          size: size,
          child: PlaylistCoverTransitionHost(
              controller: controller,
              child: Align(
                  alignment: moved ? Alignment.bottomRight : Alignment.topLeft,
                  child: const SizedBox.square(
                      dimension: 100,
                      child: PlaylistCoverTransitionMarker(
                          entryId: 'song',
                          child: ColoredBox(color: Colors.red))))));
    }))));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => controller.transition(() => update(() => moved = true)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.active, isTrue);
    final beforeResize = notifications;
    update(() => size = const Size(500, 450));
    await tester.pump();
    expect(controller.active, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(notifications, greaterThan(beforeResize));
    final opacity = tester.widget<FadeTransition>(find.descendant(
        of: find.byType(PlaylistCoverTransitionMarker),
        matching: find.byType(FadeTransition)));
    expect(opacity.opacity.value, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
