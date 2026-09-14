import 'dart:ui' as ui;
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Color> _pixel(WidgetTester tester, GlobalKey key, int x, int y) async {
  late Color result;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (y * image.width + x) * 4;
    result = Color.fromARGB(data.getUint8(offset + 3), data.getUint8(offset),
        data.getUint8(offset + 1), data.getUint8(offset + 2));
    image.dispose();
  });
  return result;
}

Widget _cover(Object id,
        {double size = 60, BorderRadius radius = BorderRadius.zero}) =>
    SizedBox.square(
        dimension: size,
        child: ClipRRect(
            borderRadius: radius,
            child: PlaylistCoverTransitionMarker(
                entryId: id,
                borderRadius: radius,
                child: const ColoredBox(color: Colors.red))));

void main() {
  testWidgets(
      'visible cover travels and changes shape without rebuilding per tick',
      (tester) async {
    final controller = PlaylistCoverTransitionController();
    addTearDown(controller.dispose);
    final image = GlobalKey();
    var changed = false;
    var builds = 0;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 300,
      height: 300,
      child: StatefulBuilder(builder: (context, setState) {
        change = setState;
        builds++;
        return RepaintBoundary(
            key: image,
            child: ColoredBox(
                color: Colors.black,
                child: PlaylistCoverTransitionHost(
                    controller: controller,
                    child: Stack(children: [
                      Positioned(
                          left: changed ? 150 : 20,
                          top: changed ? 150 : 20,
                          child: _cover('song',
                              size: changed ? 100 : 60,
                              radius: changed
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(30))),
                    ]))));
      }),
    )))));
    await tester.pumpAndSettle();
    expect(await _pixel(tester, image, 21, 21), Colors.black);
    await tester.runAsync(
        () => controller.transition(() => change(() => changed = true)));
    await tester.pump();
    await tester.pump();
    expect(controller.active, isTrue);
    expect(controller.debugSnapshotCount, 1);
    final afterLayoutBuilds = builds;
    await tester.pump(const Duration(milliseconds: 110));
    expect(builds, afterLayoutBuilds);
    // Midpoint is (85,85)-(165,165), with a rounded but no longer circular corner.
    expect((await _pixel(tester, image, 125, 125)).toARGB32(),
        Colors.red.toARGB32());
    expect(await _pixel(tester, image, 86, 86), Colors.black);
    await tester.pumpAndSettle();
    expect((await _pixel(tester, image, 151, 151)).toARGB32(),
        Colors.red.toARGB32());
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'quick switch cancels previous flight and leaves the latest layout live',
      (tester) async {
    final controller = PlaylistCoverTransitionController();
    addTearDown(controller.dispose);
    var size = 60.0;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 300,
            height: 300,
            child: StatefulBuilder(builder: (context, setState) {
              change = setState;
              return PlaylistCoverTransitionHost(
                  controller: controller,
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: _cover('song', size: size)));
            }))));
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => controller.transition(() => change(() => size = 90)));
    await tester.pump();
    expect(controller.active, isTrue);
    await controller.transition(() => change(() => size = 120));
    await tester.pumpAndSettle();
    expect(size, 120);
    expect(controller.debugSnapshotCount, 0);
    expect(controller.busy, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses no snapshots or animation', (tester) async {
    final controller = PlaylistCoverTransitionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: PlaylistCoverTransitionHost(
                controller: controller, child: _cover('song')))));
    await tester.pumpAndSettle();
    var updates = 0;
    await controller.transition(() => updates++);
    expect(updates, 1);
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('captures are bounded and scrolling releases the active layer',
      (tester) async {
    final controller = PlaylistCoverTransitionController();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 300,
                height: 300,
                child: PlaylistCoverTransitionHost(
                    controller: controller,
                    child: ListView.builder(
                        controller: scroll,
                        itemExtent: 6,
                        itemCount: 10000,
                        itemBuilder: (_, index) {
                          builds++;
                          return _cover(index, size: 6);
                        }))))));
    await tester.pumpAndSettle();
    expect(builds, lessThan(200));
    await tester.runAsync(() => controller.transition(() {}));
    await tester.pump();
    await tester.pump();
    expect(controller.debugSnapshotCount, greaterThan(0));
    expect(controller.debugSnapshotCount,
        lessThanOrEqualTo(PlaylistCoverTransitionHost.maximumSnapshots));
    scroll.jumpTo(180);
    await tester.pumpAndSettle();
    expect(controller.debugSnapshotCount, 0);
    expect(controller.busy, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during capture and during flight is safe',
      (tester) async {
    final controller = PlaylistCoverTransitionController();
    await tester.pumpWidget(MaterialApp(
        home: PlaylistCoverTransitionHost(
            controller: controller, child: _cover('song'))));
    await tester.pumpAndSettle();
    Future<void>? pending;
    await tester.runAsync(() async {
      pending = controller.transition(() {});
      controller.dispose();
      await pending;
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
