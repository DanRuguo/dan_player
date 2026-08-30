import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_window_mode_adapter.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key, this.onMount});
  final VoidCallback? onMount;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final AnimationController clock;
  final focus = FocusNode();
  int ticks = 0;
  bool disposed = false;
  @override
  void initState() {
    super.initState();
    widget.onMount?.call();
    clock = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..addListener(() => ticks++)
      ..repeat();
  }

  @override
  Widget build(BuildContext context) => Focus(
      focusNode: focus,
      child: const SizedBox(height: 48, child: Text('Existing visual')));
  @override
  void dispose() {
    disposed = true;
    clock.dispose();
    focus.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
      'native-hidden parent gate follows preference but still blocks input',
      (tester) async {
    final preferences = ValueNotifier(const RenderingPreferences());
    final hidden = ValueNotifier(false);
    final key = GlobalKey<_ProbeState>();
    addTearDown(preferences.dispose);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(RenderingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
          home:
              DesktopVisibilityHost(isHidden: hidden, child: _Probe(key: key))),
    ));
    final state = key.currentState!;
    await tester.pump(const Duration(milliseconds: 100));
    hidden.value = true;
    await tester.pump();
    final stopped = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, stopped);
    expect(TickerMode.valuesOf(key.currentContext!).enabled, isFalse);
    preferences.value = const RenderingPreferences(pauseWhenHidden: false);
    await tester.pump();
    final resumed = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, greaterThan(resumed));
    expect(TickerMode.valuesOf(key.currentContext!).enabled, isTrue);
    expect(state.focus.canRequestFocus, isFalse);
    expect(
        tester
            .widget<IgnorePointer>(find
                .descendant(
                  of: find.byType(DesktopVisibilityHost),
                  matching: find.byType(IgnorePointer),
                )
                .first)
            .ignoring,
        isTrue);
    expect(key.currentState, same(state));
    preferences.value = const RenderingPreferences();
    await tester.pump();
    final stoppedAgain = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, stoppedAgain);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mini retains normal tickers when opted out without prebuilding mini',
      (tester) async {
    final preferences =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    final controller = WindowModeController(adapter: FakeWindowModeAdapter());
    final key = GlobalKey<_ProbeState>();
    addTearDown(preferences.dispose);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var miniBuilds = 0;
    await tester.pumpWidget(RenderingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
          builder: (context, child) => AppWindowModeHost(
                controller: controller,
                navigatorKey: GlobalKey<NavigatorState>(),
                compactBuilder: (_) {
                  miniBuilds++;
                  return const Text('Mini');
                },
                child: child!,
              ),
          home: Scaffold(body: _Probe(key: key))),
    ));
    final state = key.currentState!;
    expect(miniBuilds, 0);
    await controller.enter();
    tester.view.physicalSize = const Size(520, 200);
    await tester.pump();
    expect(miniBuilds, greaterThan(0));
    expect(TickerMode.valuesOf(key.currentContext!).enabled, isTrue);
    expect(state.focus.canRequestFocus, isFalse);
    final before = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, greaterThan(before));
    expect(key.currentState, same(state));
    expect(find.text('Existing visual'), findsNothing);
    preferences.value = const RenderingPreferences();
    await tester.pump();
    final stopped = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, stopped);
    expect(TickerMode.valuesOf(key.currentContext!).enabled, isFalse);
    await controller.exit();
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, greaterThan(stopped));
    expect(key.currentState, same(state));
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'visited settings honor opt-out while unseen sections stay unmounted',
      (tester) async {
    final preferences =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    final first = GlobalKey<_ProbeState>();
    var secondMounts = 0;
    var thirdMounts = 0;
    addTearDown(preferences.dispose);
    await tester.pumpWidget(RenderingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
          home: Scaffold(
              body: AppEntranceScope(
        child: GroupedSettings(sections: [
          SettingsSection(
              id: 'one',
              title: 'First',
              icon: Icons.looks_one,
              children: [_Probe(key: first)]),
          SettingsSection(
              id: 'two',
              title: 'Second',
              icon: Icons.looks_two,
              children: [_Probe(onMount: () => secondMounts++)]),
          SettingsSection(
              id: 'three',
              title: 'Never opened',
              icon: Icons.looks_3,
              children: [_Probe(onMount: () => thirdMounts++)]),
        ]),
      ))),
    ));
    final state = first.currentState!;
    expect(secondMounts, 0);
    expect(thirdMounts, 0);
    await tester.tap(find.byKey(const ValueKey('settings-category-two')));
    await tester.pump();
    expect(secondMounts, 1);
    expect(thirdMounts, 0);
    expect(TickerMode.valuesOf(first.currentContext!).enabled, isTrue);
    expect(state.focus.canRequestFocus, isFalse);
    final before = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, greaterThan(before));
    preferences.value = const RenderingPreferences();
    await tester.pump();
    final stopped = state.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, stopped);
    expect(first.currentState, same(state));
    expect(thirdMounts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
