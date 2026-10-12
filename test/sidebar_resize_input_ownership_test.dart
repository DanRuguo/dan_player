import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _SidebarRig {
  final original = ValueNotifier(const PlayerExperiencePreferences());
  final replacement =
      ValueNotifier(const PlayerExperiencePreferences(sidebarWidth: 260));
  late ValueNotifier<PlayerExperiencePreferences> active = original;
  late StateSetter rebuild;
  late GoRouter router;
  var direction = TextDirection.ltr;
  var tickers = true;
  var reduced = false;
  var saves = 0;

  Future<void> mount(WidgetTester tester,
      {TextDirection direction = TextDirection.ltr}) async {
    this.direction = direction;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
      GoRoute(
        path: paths.AUDIOS_PAGE,
        builder: (_, __) => Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return TickerMode(
              enabled: tickers,
              child: MediaQuery(
                data:
                    MediaQuery.of(context).copyWith(disableAnimations: reduced),
                child: Directionality(
                  textDirection: this.direction,
                  child: Row(children: [
                    ResizableSideNav(
                      preferences: active,
                      persist: () async {
                        saves++;
                      },
                    ),
                    const Expanded(child: SizedBox()),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      original.dispose();
      replacement.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Finder get nav => find.byKey(const ValueKey('resizable-side-nav'));
  Finder get handle => find.byKey(const ValueKey('side-nav-resize-handle'));
  double width(WidgetTester tester) => tester.getSize(nav).width;

  Future<TestGesture> drag(WidgetTester tester,
          {int pointer = 1,
          PointerDeviceKind kind = PointerDeviceKind.touch}) =>
      tester.startGesture(tester.getCenter(handle),
          pointer: pointer, kind: kind);
}

void main() {
  testWidgets('locking during a sidebar drag retires the unsaved pointer draft',
      (tester) async {
    final rig = _SidebarRig();
    await rig.mount(tester);
    final primary = await rig.drag(tester);
    await primary.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(rig.width(tester), 220);
    expect(rig.saves, 0);

    rig.original.value = rig.original.value.copyWith(sidebarLocked: true);
    await tester.pump();
    expect(rig.width(tester), 300,
        reason: 'The explicit lock restores the saved width, not the draft');
    expect(find.bySemanticsLabel('侧栏宽度已锁定'), findsOneWidget);
    await primary.moveBy(const Offset(40, 0));
    await primary.up();
    await tester.pumpAndSettle();
    expect(rig.original.value.sidebarWidth, 300);
    expect(rig.saves, 0,
        reason: 'A late release cannot save the revoked drag under a lock');
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocking before an old sidebar pointer ends does not revive it',
      (tester) async {
    final rig = _SidebarRig();
    await rig.mount(tester);
    final primary = await rig.drag(tester);
    await primary.moveBy(const Offset(-80, 0));
    await tester.pump();
    rig.original.value = rig.original.value.copyWith(sidebarLocked: true);
    await tester.pump();
    rig.original.value = rig.original.value.copyWith(sidebarLocked: false);
    await tester.pump();
    await primary.moveBy(const Offset(40, 0));
    await primary.up();
    await tester.pumpAndSettle();
    expect(rig.width(tester), 300);
    expect(rig.original.value.sidebarWidth, 300);
    expect(rig.saves, 0);

    final fresh = await rig.drag(tester, pointer: 2);
    await fresh.moveBy(const Offset(-40, 0));
    await fresh.up();
    await tester.pumpAndSettle();
    expect(rig.original.value.sidebarWidth, 260);
    expect(rig.saves, 1,
        reason: 'Fresh input retains normal resizing and persistence');
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing sidebar preferences revokes the old physical sequence',
      (tester) async {
    final rig = _SidebarRig();
    await rig.mount(tester);
    final primary = await rig.drag(tester);
    await primary.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(rig.width(tester), 220);

    rig.rebuild(() => rig.active = rig.replacement);
    await tester.pump();
    expect(rig.width(tester), 260);
    await primary.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(rig.width(tester), 260,
        reason: 'The old start width and pointer cannot edit the new owner');
    await primary.up();
    await tester.pumpAndSettle();
    expect(rig.original.value.sidebarWidth, 300);
    expect(rig.replacement.value.sidebarWidth, 260);
    expect(rig.saves, 0);

    final fresh = await rig.drag(tester, pointer: 2);
    await fresh.moveBy(const Offset(40, 0));
    await fresh.up();
    await tester.pumpAndSettle();
    expect(rig.replacement.value.sidebarWidth, 300);
    expect(rig.original.value.sidebarWidth, 300);
    expect(rig.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated preference changes preserve the primary sidebar drag',
      (tester) async {
    final rig = _SidebarRig();
    await rig.mount(tester);
    final primary = await rig.drag(tester);
    await primary.moveBy(const Offset(-60, 0));
    await tester.pump();
    rig.original.value = rig.original.value.copyWith(windowSizeLocked: true);
    await tester.pump();
    expect(rig.width(tester), 240);
    final secondary = await rig.drag(tester, pointer: 2);
    await secondary.moveBy(const Offset(60, 0));
    await secondary.cancel();
    await tester.pump();
    expect(rig.width(tester), 240);
    expect(rig.saves, 0);
    await primary.moveBy(const Offset(-20, 0));
    await primary.up();
    await tester.pumpAndSettle();
    expect(rig.original.value.sidebarWidth, 220);
    expect(rig.original.value.windowSizeLocked, isTrue);
    expect(rig.saves, 1);
    expect(tester.takeException(), isNull);
  });

  for (final interruption in [
    'direction',
    'TickerMode',
    'reduced motion',
    'native reduced motion'
  ]) {
    testWidgets(
        '$interruption revokes a held sidebar draft without reviving it',
        (tester) async {
      final rig = _SidebarRig();
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await rig.mount(tester);
      final primary = await rig.drag(tester);
      await primary.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(rig.width(tester), 220);
      rig.rebuild(() {
        switch (interruption) {
          case 'direction':
            rig.direction = TextDirection.rtl;
          case 'TickerMode':
            rig.tickers = false;
          case 'reduced motion':
            rig.reduced = true;
          case 'native reduced motion':
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(reduceMotion: true);
        }
      });
      await tester.pump();
      expect(rig.width(tester), 300,
          reason: 'The changed input surface restores the persisted width');
      rig.rebuild(() {
        rig.direction = TextDirection.ltr;
        rig.tickers = true;
        rig.reduced = interruption == 'reduced motion';
      });
      await tester.pump();
      await primary.moveBy(const Offset(-20, 0));
      await primary.up();
      await tester.pumpAndSettle();
      expect(rig.original.value.sidebarWidth, 300);
      expect(rig.saves, 0);
      final fresh = await rig.drag(tester, pointer: 2);
      await fresh.moveBy(const Offset(-40, 0));
      await fresh.up();
      await tester.pumpAndSettle();
      expect(rig.original.value.sidebarWidth, 260);
      expect(rig.saves, 1);
      // Fresh input works even while the selected reduced-motion policy stays
      // active; accessibility changes retire ownership, not the control.
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
        'the ${direction.name} body-facing resize edge follows its drag',
        (tester) async {
      final rig = _SidebarRig();
      await rig.mount(tester, direction: direction);
      final initial = tester.getRect(rig.nav);
      final handle = tester.getCenter(rig.handle);
      expect(
          handle.dx,
          direction == TextDirection.ltr
              ? greaterThan(initial.center.dx)
              : lessThan(initial.center.dx));
      final primary = await rig.drag(tester,
          kind: direction == TextDirection.ltr
              ? PointerDeviceKind.touch
              : PointerDeviceKind.mouse);
      await primary
          .moveBy(Offset(direction == TextDirection.ltr ? 60 : -60, 0));
      await tester.pump();
      expect(rig.width(tester), 360,
          reason: 'Dragging the body-facing edge into the body expands it');
      expect(rig.saves, 0);
      await primary.up();
      await tester.pumpAndSettle();
      expect(rig.original.value.sidebarWidth, 360);
      expect(rig.saves, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
