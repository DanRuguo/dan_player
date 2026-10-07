import 'dart:ui' as drawing;

import 'package:dan_player/component/category_cover_flight.dart';
import 'package:dan_player/component/cover_route_landing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<drawing.Image> _image(Color color) async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(40, 40);
  } finally {
    picture.dispose();
  }
}

class _Destination extends StatefulWidget {
  const _Destination({super.key, required this.image});
  final drawing.Image image;
  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination>
    with TickerProviderStateMixin {
  late final spinner = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300))
    ..repeat();
  late final fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));
  bool ready = false;

  void showImage() {
    spinner.stop();
    setState(() => ready = true);
    fade.forward(from: 0);
  }

  @override
  void dispose() {
    spinner.dispose();
    fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
      child: ready
          ? FadeTransition(
              opacity: fade,
              child: RawImage(image: widget.image, fit: BoxFit.cover))
          : RotationTransition(
              turns: spinner,
              child: const Icon(Icons.sync, color: Colors.green)));
}

const _landingImage = ValueKey('test-route-landing-image');

void main() {
  testWidgets('queued landing releases its source without mounting or a frame',
      (tester) async {
    final image = (await tester.runAsync(() => _image(Colors.red)))!;
    addTearDown(image.dispose);
    final controller = CoverRouteLandingController(canRetain: () => true);
    addTearDown(controller.dispose);
    controller.acceptSource(image);
    expect(image.debugGetOpenHandleStackTraces()!.length, 2);
    controller.retire();
    expect(image.debugGetOpenHandleStackTraces()!.length, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('covered placeholder pauses while a real image fade can finish',
      (tester) async {
    final source = (await tester.runAsync(() => _image(Colors.red)))!;
    final target = (await tester.runAsync(() => _image(Colors.blue)))!;
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    final controller = CoverRouteLandingController(canRetain: () => true);
    addTearDown(controller.dispose);
    final destination = GlobalKey<_DestinationState>();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox.square(
                dimension: 100,
                child: CoverRouteLanding(
                    identity: 'cover',
                    controller: controller,
                    borderRadius: BorderRadius.circular(50),
                    imageKey: _landingImage,
                    child: _Destination(key: destination, image: target))))));
    controller.acceptSource(source);
    await tester.pump();
    await tester.pump();
    final retained = tester.widget<RawImage>(find.byKey(_landingImage)).image!;
    final spinner = destination.currentState!.spinner.value;
    await tester.pump(const Duration(seconds: 1));
    expect(destination.currentState!.spinner.value, spinner);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'a fully covered spinner does not keep scheduling frames');
    destination.currentState!.showImage();
    await tester.pump();
    await tester.pump();
    expect(TickerMode.valuesOf(destination.currentContext!).enabled, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(destination.currentState!.fade.value, inExclusiveRange(0, 1));
    expect(find.byKey(_landingImage), findsOneWidget,
        reason:
            'presence restores the fade before strict readiness retires it');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(_landingImage), findsNothing);
    expect(retained.debugDisposed, isTrue);
    expect(destination.currentState!.fade.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.debugGetOpenHandleStackTraces()!.length, 1);
  });

  for (final policy in ['ticker', 'native', 'hidden']) {
    testWidgets('$policy retires a landing without reviving it on restore',
        (tester) async {
      final source = (await tester.runAsync(() => _image(Colors.red)))!;
      addTearDown(source.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      var enabled = true;
      late StateSetter change;
      late BuildContext policyContext;
      final controller = CoverRouteLandingController(
          canRetain: () => coverFlightMotionAllowed(policyContext));
      addTearDown(controller.dispose);
      await tester
          .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
        change = setState;
        return TickerMode(
            enabled: enabled,
            child: Builder(builder: (context) {
              policyContext = context;
              return Center(
                  child: SizedBox.square(
                      dimension: 100,
                      child: CoverRouteLanding(
                          identity: 'cover',
                          controller: controller,
                          borderRadius: BorderRadius.zero,
                          imageKey: _landingImage,
                          child: const ColoredBox(color: Colors.green))));
            }));
      })));
      controller.acceptSource(source);
      await tester.pump();
      await tester.pump();
      final retained =
          tester.widget<RawImage>(find.byKey(_landingImage)).image!;
      switch (policy) {
        case 'ticker':
          change(() => enabled = false);
          await tester.pump();
          change(() => enabled = true);
        case 'native':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
          expect(retained.debugDisposed, isTrue,
              reason: 'retire the owned handle before waiting for a frame');
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures();
        case 'hidden':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          expect(retained.debugDisposed, isTrue);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_landingImage), findsNothing);
      expect(retained.debugDisposed, isTrue);
      expect(source.debugGetOpenHandleStackTraces()!.length, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('identity update cancels pending landing before its first frame',
      (tester) async {
    final source = (await tester.runAsync(() => _image(Colors.red)))!;
    addTearDown(source.dispose);
    final controller = CoverRouteLandingController(canRetain: () => true);
    addTearDown(controller.dispose);
    var identity = 'first';
    var acceptDuringBuild = false;
    late StateSetter change;
    await tester
        .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
      change = setState;
      if (acceptDuringBuild) {
        acceptDuringBuild = false;
        controller.acceptSource(source);
        expect(source.debugGetOpenHandleStackTraces()!.length, 2);
      }
      return Center(
          child: SizedBox.square(
              dimension: 100,
              child: CoverRouteLanding(
                  identity: identity,
                  controller: controller,
                  borderRadius: BorderRadius.zero,
                  imageKey: _landingImage,
                  child: const ColoredBox(color: Colors.green))));
    })));
    change(() {
      acceptDuringBuild = true;
      identity = 'second';
    });
    await tester.pumpAndSettle();
    expect(find.byKey(_landingImage), findsNothing);
    expect(source.debugGetOpenHandleStackTraces()!.length, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a missing destination expires after the bounded handoff timeout',
      (tester) async {
    final source = (await tester.runAsync(() => _image(Colors.red)))!;
    addTearDown(source.dispose);
    final controller = CoverRouteLandingController(canRetain: () => true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: SizedBox.square(
            dimension: 100,
            child: CoverRouteLanding(
                identity: 'missing',
                controller: controller,
                borderRadius: BorderRadius.zero,
                imageKey: _landingImage,
                child: const ColoredBox(color: Colors.green)))));
    controller.acceptSource(source);
    await tester.pump();
    await tester.pump();
    final retained = tester.widget<RawImage>(find.byKey(_landingImage)).image!;
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.byKey(_landingImage), findsNothing);
    expect(retained.debugDisposed, isTrue);
    expect(source.debugGetOpenHandleStackTraces()!.length, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
