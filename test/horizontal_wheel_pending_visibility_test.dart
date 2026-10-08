import 'package:dan_player/component/app_horizontal_wheel_region.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

const _railKey = ValueKey('pending-wheel-rail');

class _NoIoCovers extends CategoryCoverStore {
  _NoIoCovers()
      : super(dataDirectory: () async {
          throw StateError(
              'The metadata-only wheel fixture cannot access disk');
        });

  @override
  Future<void> load() async {}
}

Widget _host(ScrollController controller, {bool visible = true}) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 260,
              height: 64,
              child: AppHorizontalWheelRegion(
                controller: controller,
                child: SingleChildScrollView(
                  key: _railKey,
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 1600, height: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _startWheel(
    WidgetTester tester, ScrollController controller) async {
  await tester.pumpWidget(_host(controller));
  await tester.pumpAndSettle();
  await tester.sendEventToBinding(PointerScrollEvent(
    position: tester.getCenter(find.byKey(_railKey)),
    scrollDelta: const Offset(0, 120),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 45));
  expect(controller.offset, inExclusiveRange(0, 120));
}

void main() {
  for (final feature in ['reduceMotion', 'disableAnimations']) {
    testWidgets('pending $feature wheel settlement honors same-frame hide',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _startWheel(tester, controller);
      final frozen = controller.offset;

      // Native notification queues the visible terminal position, but the
      // retained rail becomes hidden before that post-frame callback runs.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
              reduceMotion: feature == 'reduceMotion',
              disableAnimations: feature == 'disableAnimations');
      await tester.pumpWidget(_host(controller, visible: false));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(frozen, .0001),
          reason: 'Hiding retires the pending visible jump, preserving the '
              'last rendered scroll position instead of the unvisited target');
      expect(tester.binding.transientCallbackCount, 0);

      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(frozen, .0001),
          reason: 'Restoring visibility must not replay the retired jump');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('visible native reduction commits one pending wheel terminal',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _startWheel(tester, controller);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pumpAndSettle();
    expect(controller.offset, 120);
    expect(tester.binding.transientCallbackCount, 0);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpAndSettle();
    expect(controller.offset, 120);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real category rail retires settlement when desktop is hidden',
      (tester) async {
    await tester.runAsync(loadPlaylistFeatureFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final hidden = ValueNotifier(false);
    final covers = _NoIoCovers();
    addTearDown(hidden.dispose);
    addTearDown(covers.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          useMaterial3: true,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback),
      home: Scaffold(
        body: DesktopVisibilityHost(
          isHidden: hidden,
          child: CategoriesPage(audios: const [], coverStore: covers),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('category-kind-scroll'));
    final position = tester
        .state<ScrollableState>(
            find.descendant(of: rail, matching: find.byType(Scrollable)))
        .position;
    expect(position.maxScrollExtent, greaterThan(120));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(rail),
      scrollDelta: const Offset(0, 120),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    final frozen = position.pixels;
    expect(frozen, inExclusiveRange(0, 120));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    hidden.value = true;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(frozen, .0001));
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = false;
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(frozen, .0001));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
