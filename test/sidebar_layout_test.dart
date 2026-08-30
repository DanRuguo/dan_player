import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/page/settings_page/sidebar_layout_settings.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('desktop handle drags directly and persists only on release',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    final router = GoRouter(initialLocation: app_paths.AUDIOS_PAGE, routes: [
      GoRoute(
        path: app_paths.AUDIOS_PAGE,
        builder: (_, __) => Scaffold(
          body: Row(children: [
            ResizableSideNav(
              preferences: preferences,
              persist: () async {
                saves++;
              },
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('resizable-side-nav'))).width,
        300);
    expect(find.byTooltip('音乐'), findsNothing,
        reason: 'inline labels do not need detached hover bubbles');

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('side-nav-resize-handle'))));
    await gesture.moveBy(const Offset(-190, 0));
    await tester.pump();
    expect(saves, 0);
    expect(
        tester.getSize(find.byKey(const ValueKey('resizable-side-nav'))).width,
        closeTo(110, 1));
    expect(find.text('音乐'), findsNothing,
        reason: 'compact mode keeps icons and accessible tooltips only');
    expect(find.byTooltip('音乐'), findsOneWidget,
        reason: 'the true icon-only endpoint remains discoverable');
    final selectedButton =
        find.byKey(const ValueKey('continuous-nav-${app_paths.AUDIOS_PAGE}'));
    final selectedCircle = find.ancestor(
      of: selectedButton,
      matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is CircleBorder),
    );
    expect(selectedCircle, findsOneWidget);
    expect(tester.getSize(selectedCircle), const Size.square(44));
    final selectedIcon = find.descendant(
      of: selectedButton,
      matching: find.byType(Icon),
    );
    expect(selectedIcon, findsOneWidget);
    expect(tester.getCenter(selectedIcon).dx,
        closeTo(tester.getCenter(selectedCircle).dx, .01));
    expect(tester.getCenter(selectedIcon).dy,
        closeTo(tester.getCenter(selectedCircle).dy, .01));
    await gesture.up();
    await tester.pump();
    expect(saves, 1);
    expect(preferences.value.sidebarWidth, closeTo(110, 1));
  });

  testWidgets('locked sidebar ignores drag and remains keyboard discoverable',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ValueNotifier(const PlayerExperiencePreferences(
        sidebarWidth: 240, sidebarLocked: true));
    addTearDown(preferences.dispose);
    var saves = 0;
    final router = GoRouter(initialLocation: app_paths.AUDIOS_PAGE, routes: [
      GoRoute(
        path: app_paths.AUDIOS_PAGE,
        builder: (_, __) => Scaffold(
          body: ResizableSideNav(
            preferences: preferences,
            persist: () async {
              saves++;
            },
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.drag(find.byKey(const ValueKey('side-nav-resize-handle')),
        const Offset(100, 0));
    await tester.pump();
    expect(
        tester.getSize(find.byKey(const ValueKey('resizable-side-nav'))).width,
        240);
    expect(saves, 0);
    expect(find.bySemanticsLabel('侧栏宽度已锁定'), findsOneWidget);
  });

  testWidgets('settings previews continuously, saves on end and can lock',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SidebarLayoutSettings(
          preferences: preferences,
          persist: () async {
            saves++;
          },
        ),
      ),
    ));
    final slider = find.byKey(const ValueKey('sidebar-width-setting'));
    final center = tester.getCenter(slider);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(saves, 0);
    await gesture.up();
    await tester.pump();
    expect(saves, 1);
    await tester.tap(find.byKey(const ValueKey('sidebar-width-lock-setting')));
    await tester.pump();
    expect(preferences.value.sidebarLocked, isTrue);
    expect(saves, 2);

    await tester.tap(find.byKey(const ValueKey('window-size-lock-setting')));
    await tester.pump();
    expect(preferences.value.windowSizeLocked, isTrue);
    expect(saves, 3);

    await tester
        .tap(find.byKey(const ValueKey('window-aspect-ratio-lock-setting')));
    await tester.pump();
    expect(preferences.value.windowAspectRatioLocked, isTrue);
    expect(preferences.value.windowAspectRatio, 0,
        reason: 'the live controller captures the current window ratio');
    expect(saves, 4);
  });

  testWidgets('responsive builder uses allocated main-pane constraints',
      (tester) async {
    ScreenType? measured;
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        const SizedBox(width: 300),
        Expanded(
          child: ResponsiveBuilder(
            builder: (_, type) {
              measured = type;
              return const SizedBox();
            },
          ),
        ),
      ]),
    ));
    expect(measured, ScreenType.small);
  });
}
