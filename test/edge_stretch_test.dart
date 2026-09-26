import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/app_typography.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/palette_test_bridge.dart';

Widget _host(ScrollController controller,
        {Axis axis = Axis.vertical,
        bool reverse = false,
        bool rtl = false,
        bool visible = true,
        bool reduced = false,
        MotionPreferences motion = const MotionPreferences()}) =>
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      scrollBehavior: const DanPlayerScrollBehavior(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: MotionPreferencesScope(
              preferences: motion,
              child: TickerMode(enabled: visible, child: child!))),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: ListView.builder(
                key: const ValueKey('edge-list'),
                controller: controller,
                scrollDirection: axis,
                reverse: reverse,
                itemExtent: 64,
                itemCount: 20,
                itemBuilder: (_, index) => ColoredBox(
                    color: index.isEven ? Colors.orange : Colors.indigo,
                    child: Center(child: Text('Song $index'))),
              ),
            ),
          ),
        ),
      ),
    );

Future<TestGesture> _pull(
    WidgetTester tester, Finder target, Offset direction) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
  await gesture.down(tester.getCenter(target));
  await gesture.moveBy(direction * 30);
  await tester.pump();
  await gesture.moveBy(direction * 90);
  await tester.pump(const Duration(milliseconds: 32));
  return gesture;
}

Future<void> _wheel(WidgetTester tester, Finder target, Offset delta,
    {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  tester.binding.handlePointerEvent(PointerScrollEvent(
      position: tester.getCenter(target), kind: kind, scrollDelta: delta));
  await tester.pump(const Duration(milliseconds: 32));
}

Future<void> _render(
    WidgetTester tester, GlobalKey boundaryKey, String name) async {
  const directory = String.fromEnvironment('DAN_EDGE_WHEEL_RENDER');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes =
          (await image.toByteData(format: raster.ImageByteFormat.png))!
              .buffer
              .asUint8List();
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', DesktopLyricTypography.fontFamily]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
      await loader.load();
    }
  });
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.trackpad]) {
    for (final scenario in [
      (Axis.vertical, false, false, const Offset(0, -120)),
      (Axis.vertical, true, false, const Offset(0, 120)),
      (Axis.horizontal, false, false, const Offset(-120, 0)),
      (Axis.horizontal, false, true, const Offset(120, 0)),
    ]) {
      testWidgets(
          '${kind.name} signal ${scenario.$1.name} reverse=${scenario.$2} rtl=${scenario.$3} stretches both edges',
          (tester) async {
        final controller = ScrollController();
        final boundary = GlobalKey();
        addTearDown(controller.dispose);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: _host(controller,
                axis: scenario.$1, reverse: scenario.$2, rtl: scenario.$3)));
        final list = find.byKey(const ValueKey('edge-list'));
        await _render(tester, boundary,
            '${kind.name}-${scenario.$1.name}-${scenario.$2}-${scenario.$3}-idle');
        await _wheel(tester, list, scenario.$4, kind: kind);
        final leading = tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength;
        expect(leading.abs(), greaterThan(0));
        expect(controller.offset, controller.position.minScrollExtent);
        await _render(tester, boundary,
            '${kind.name}-${scenario.$1.name}-${scenario.$2}-${scenario.$3}-leading');
        await tester.pumpAndSettle();
        await _wheel(tester, list, -scenario.$4 / 2, kind: kind);
        expect(controller.offset, greaterThan(0),
            reason: 'normal wheel movement must still scroll content');
        expect(
            tester
                .widget<StretchEffect>(find.byType(StretchEffect))
                .stretchStrength,
            0);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await _wheel(tester, list, -scenario.$4, kind: kind);
        final trailing = tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength;
        expect(trailing.abs(), greaterThan(0));
        expect(leading.sign, -trailing.sign);
        expect(controller.offset, controller.position.maxScrollExtent);
        await _render(tester, boundary,
            '${kind.name}-${scenario.$1.name}-${scenario.$2}-${scenario.$3}-trailing');
        // Rapid real signals must remain finite and never create two effects.
        for (var i = 0; i < 12; i++) {
          await _wheel(tester, list, -scenario.$4, kind: kind);
        }
        expect(find.byType(StretchEffect), findsOneWidget);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<StretchEffect>(find.byType(StretchEffect))
                .stretchStrength,
            0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Shift mouse wheel uses the horizontal axis', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, axis: Axis.horizontal));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _wheel(
        tester, find.byKey(const ValueKey('edge-list')), const Offset(0, -120));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength
            .abs(),
        greaterThan(0));
    expect(controller.offset, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  });

  testWidgets('trackpad pan zoom still uses the native drag spring',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    final location = tester.getCenter(find.byKey(const ValueKey('edge-list')));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(location);
    await gesture.panZoomUpdate(location, pan: const Offset(0, 40));
    await tester.pump();
    await gesture.panZoomUpdate(location, pan: const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 32));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength
            .abs(),
        greaterThan(0));
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('wheel visual notifications respect opt out and do not escape',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var movements = 0;
    await tester.pumpWidget(NotificationListener<ScrollNotification>(
        onNotification: (_) {
          movements++;
          return false;
        },
        child: NotificationListener<OverscrollIndicatorNotification>(
            onNotification: (notification) {
              notification.disallowIndicator();
              return false;
            },
            child: _host(controller))));
    await _wheel(
        tester, find.byKey(const ValueKey('edge-list')), const Offset(0, -120));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength,
        0);
    expect(movements, 0);
    await _wheel(
        tester, find.byKey(const ValueKey('edge-list')), const Offset(0, 120));
    expect(controller.offset, 120);
    expect(movements, greaterThan(0));
  });

  testWidgets('nested same-axis wheel hands the edge to a movable parent',
      (tester) async {
    final outer = ScrollController(), inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const DanPlayerScrollBehavior(),
        home: Scaffold(
            body: ListView(controller: outer, children: [
          const SizedBox(height: 100),
          SizedBox(
              height: 200,
              child: ListView.builder(
                  key: const ValueKey('nested-wheel'),
                  controller: inner,
                  itemExtent: 50,
                  itemCount: 20,
                  itemBuilder: (_, i) => Text('Inner $i'))),
          const SizedBox(height: 1500),
        ]))));
    outer.jumpTo(80);
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('nested-wheel'));
    await _wheel(tester, list, const Offset(0, -60));
    expect(inner.offset, 0);
    expect(outer.offset, 20,
        reason: 'an inner edge must not take a wheel that can move its parent');
    expect(
        tester
            .widgetList<StretchEffect>(find.byType(StretchEffect))
            .every((effect) => effect.stretchStrength == 0),
        isTrue);
    outer.jumpTo(0);
    await tester.pumpAndSettle();
    await _wheel(tester, list, const Offset(0, -60));
    expect(
        tester
            .widgetList<StretchEffect>(find.byType(StretchEffect))
            .where((effect) => effect.stretchStrength != 0)
            .length,
        1);
    expect(outer.offset, 0);
    await tester.pumpAndSettle();
    await _wheel(tester, list, const Offset(0, 60));
    expect(inner.offset, 60);
    expect(outer.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel gates reset active stretch and keep ordinary scrolling',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    for (final mode in ['feedback', 'all', 'media', 'platform', 'hidden']) {
      await tester.pumpWidget(_host(controller));
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('edge-list'));
      await _wheel(tester, list, const Offset(0, -120));
      expect(
          tester
              .widget<StretchEffect>(find.byType(StretchEffect))
              .stretchStrength
              .abs(),
          greaterThan(0));
      switch (mode) {
        case 'feedback':
          await tester.pumpWidget(_host(controller,
              motion: const MotionPreferences()
                  .withKind(MotionKind.feedback, false)));
        case 'all':
          await tester.pumpWidget(
              _host(controller, motion: const MotionPreferences().all(false)));
        case 'media':
          await tester.pumpWidget(_host(controller, reduced: true));
        case 'platform':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'hidden':
          await tester.pumpWidget(_host(controller, visible: false));
      }
      await tester.pump();
      expect(find.byType(StretchEffect), findsNothing);
      await _wheel(tester, list, const Offset(0, -120));
      expect(find.byType(StretchEffect), findsNothing);
      await _wheel(tester, list, const Offset(0, 80));
      expect(controller.offset, 80);
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('nested horizontal signals preserve vertical parent wheels',
      (tester) async {
    final outer = ScrollController(), inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        home: Scaffold(
            body: ListView(controller: outer, children: [
          SizedBox(
              height: 200,
              child: ListView.builder(
                  key: const ValueKey('horizontal-wheel'),
                  controller: inner,
                  scrollDirection: Axis.horizontal,
                  itemExtent: 100,
                  itemCount: 20,
                  itemBuilder: (_, i) => Center(child: Text('Album $i')))),
          const SizedBox(height: 1500),
        ]))));
    final list = find.byKey(const ValueKey('horizontal-wheel'));
    await _wheel(tester, list, const Offset(-100, 0));
    expect(
        tester
            .widgetList<StretchEffect>(find.byType(StretchEffect))
            .where((effect) => effect.stretchStrength != 0)
            .length,
        1);
    expect(outer.offset, 0);
    await tester.pumpAndSettle();
    await _wheel(tester, list, const Offset(0, 100));
    expect(outer.offset, 100);
    expect(inner.offset, 0);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit horizontal AlwaysScrollable content can stretch once',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        home: Scaffold(
            body: SingleChildScrollView(
                key: const ValueKey('fit-wheel'),
                controller: controller,
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics()),
                child: const SizedBox(width: 200, height: 200)))));
    expect(controller.position.maxScrollExtent, 0);
    await _wheel(
        tester, find.byKey(const ValueKey('fit-wheel')), const Offset(-80, 0));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength
            .abs(),
        greaterThan(0));
    expect(controller.offset, 0);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('real desktop appearance window shares wheel and hidden policy',
      (tester) async {
    final original = desktopMotionPreferences.value;
    final client = DesktopLyricPaletteClient(
        channel: PaletteLoopbackChannel('test/edge_wheel_palette'));
    final boundary = GlobalKey();
    addTearDown(() {
      client.dispose();
      desktopMotionPreferences.value = original;
    });
    Map<String, Object?> snapshot(int revision, Map<String, bool> animations) =>
        {
          'session': 1,
          'revision': revision,
          'editAck': 0,
          'darkMode': false,
          'primary': 0xff008577,
          'surfaceContainer': 0xfff0f4f2,
          'onSurface': 0xff17211e,
          'language': 'en',
          'appearance': DesktopLyricAppearance.defaults.toJson(),
          'animations': animations,
        };
    expect(client.applySnapshot(snapshot(1, const MotionPreferences().toMap())),
        isTrue);
    tester.view.physicalSize = const Size(520, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: boundary, child: DesktopLyricAppearanceApp(client: client)));
    await tester.pumpAndSettle();
    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);
    await _render(tester, boundary, 'desktop-palette-idle');
    await _wheel(tester, scroll, const Offset(0, -120));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength
            .abs(),
        greaterThan(0));
    await _render(tester, boundary, 'desktop-palette-wheel-midframe');
    expect(client.applySnapshot(snapshot(2, {'feedback': false})), isTrue);
    await tester.pump();
    expect(find.byType(StretchEffect), findsNothing);
    expect(client.applySnapshot(snapshot(3, const MotionPreferences().toMap())),
        isTrue);
    await tester.pumpAndSettle();
    await _wheel(tester, scroll, const Offset(0, -120));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength
            .abs(),
        greaterThan(0));
    client.suspend();
    await tester.pump();
    expect(find.byType(StretchEffect), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real mouse wheel at the edge stretches then becomes idle',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await _wheel(
        tester, find.byKey(const ValueKey('edge-list')), const Offset(0, -120));
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength,
        greaterThan(0));
    expect(controller.offset, 0);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<StretchEffect>(find.byType(StretchEffect))
            .stretchStrength,
        0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final scenario in [
    (Axis.vertical, false, false, AxisDirection.down, const Offset(0, 1)),
    (Axis.vertical, true, false, AxisDirection.up, const Offset(0, -1)),
    (Axis.horizontal, false, false, AxisDirection.right, const Offset(1, 0)),
    (Axis.horizontal, false, true, AxisDirection.left, const Offset(-1, 0)),
  ]) {
    testWidgets('native stretch ${scenario.$4.name} clamps and returns to idle',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller,
          axis: scenario.$1, reverse: scenario.$2, rtl: scenario.$3));
      expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
      expect(find.byType(GlowingOverscrollIndicator), findsNothing);
      expect(
          tester
              .widget<StretchingOverscrollIndicator>(
                  find.byType(StretchingOverscrollIndicator))
              .axisDirection,
          scenario.$4);
      final gesture = await _pull(
          tester, find.byKey(const ValueKey('edge-list')), scenario.$5);
      expect(
          tester
              .widget<StretchEffect>(find.byType(StretchEffect))
              .stretchStrength
              .abs(),
          greaterThan(0));
      expect(controller.offset, controller.position.minScrollExtent);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<StretchEffect>(find.byType(StretchEffect))
              .stretchStrength,
          0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'live feedback, total, reduced motion and visibility stop stretch',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    for (final mode in ['feedback', 'all', 'media', 'platform', 'hidden']) {
      await tester.pumpWidget(_host(controller));
      final gesture = await _pull(
          tester, find.byKey(const ValueKey('edge-list')), const Offset(0, 1));
      expect(
          tester
              .widget<StretchEffect>(find.byType(StretchEffect))
              .stretchStrength
              .abs(),
          greaterThan(0));
      switch (mode) {
        case 'feedback':
          await tester.pumpWidget(_host(controller,
              motion: const MotionPreferences()
                  .withKind(MotionKind.feedback, false)));
        case 'all':
          await tester.pumpWidget(
              _host(controller, motion: const MotionPreferences().all(false)));
        case 'media':
          await tester.pumpWidget(_host(controller, reduced: true));
        case 'platform':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'hidden':
          await tester.pumpWidget(_host(controller, visible: false));
      }
      await tester.pump();
      expect(find.byType(StretchingOverscrollIndicator), findsNothing,
          reason: '$mode must reset the active native transform immediately');
      expect(controller.offset, 0);
      await gesture.cancel();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets(
      'nested axes stretch independently and keep parent touch scrolling',
      (tester) async {
    final outer = ScrollController(), inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        home: Scaffold(
            body: ListView(controller: outer, children: [
          SizedBox(
              height: 200,
              child: ListView.builder(
                  key: const ValueKey('inner-edge'),
                  controller: inner,
                  scrollDirection: Axis.horizontal,
                  itemExtent: 100,
                  itemCount: 20,
                  itemBuilder: (_, index) =>
                      Center(child: Text('Inner $index')))),
          const SizedBox(height: 1500),
        ]))));
    expect(find.byType(StretchingOverscrollIndicator), findsNWidgets(2));
    final gesture = await _pull(
        tester, find.byKey(const ValueKey('inner-edge')), const Offset(1, 0));
    final effects =
        tester.widgetList<StretchEffect>(find.byType(StretchEffect));
    expect(effects.where((effect) => effect.stretchStrength != 0).length, 1);
    expect(outer.offset, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('inner-edge')), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(outer.offset, greaterThan(0));
    expect(inner.offset, 0);
    expect(tester.takeException(), isNull);
  });

  test('desktop IPC keeps old messages compatible and shares live edge policy',
      () {
    final original = desktopMotionPreferences.value;
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false), sendMessage: (_) {});
    addTearDown(() {
      controller.dispose();
      desktopMotionPreferences.value = original;
    });
    controller.handleMessage(const FrameRateMessage({
      'animations': {'feedback': false}
    }).buildMessageJson());
    expect(desktopMotionPreferences.value.allows(MotionKind.feedback), isFalse);
    controller.handleMessage(const FrameRateMessage({}).buildMessageJson());
    expect(desktopMotionPreferences.value.allows(MotionKind.feedback), isTrue);
  });
}
