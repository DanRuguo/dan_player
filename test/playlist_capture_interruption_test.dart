import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final replaceRequest in [false, true]) {
    testWidgets(
        'scroll during capture preserves the latest view request (replace=$replaceRequest)',
        (tester) async {
      final controller = PlaylistCoverTransitionController();
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(
          home: PlaylistCoverTransitionHost(
              controller: controller,
              child: ListView.builder(
                  controller: scroll,
                  itemExtent: 100,
                  itemCount: 20,
                  itemBuilder: (_, index) => Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(
                          dimension: 80,
                          child: PlaylistCoverTransitionMarker(
                              entryId: index,
                              child: const ColoredBox(color: Colors.red))))))));
      await tester.pumpAndSettle();
      final requests = <String>[];
      await tester.runAsync(() async {
        final pending = controller.transition(() => requests.add('grid'));
        expect(controller.busy, isTrue);
        expect(controller.active, isFalse,
            reason: 'Interrupt while GPU snapshots are still pending');
        scroll.jumpTo(120);
        if (replaceRequest) {
          await controller.transition(() => requests.add('rectangle'));
        }
        await pending;
      });
      await tester.pumpAndSettle();
      expect(requests, [replaceRequest ? 'rectangle' : 'grid']);
      expect(controller.busy, isFalse);
      expect(controller.debugSnapshotCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
