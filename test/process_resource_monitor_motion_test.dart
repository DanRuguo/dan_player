import 'dart:async';

import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

class _MonitorMotionRig {
  final native = ResourceTestRig();
  final preferences = ValueNotifier(const ProcessResourcePreferences());
  final hidden = ValueNotifier(false);
  final layoutMotion = ValueNotifier(true);
  final mediaReduced = ValueNotifier(false);
  final sectionVisible = ValueNotifier(true);
  final tickers = ValueNotifier(true);

  Future<void> mount(WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 800, height: 1100);
    await tester.pumpWidget(listeningStatusHost(Builder(
        builder: (context) => ListenableBuilder(
            listenable: Listenable.merge(
                [layoutMotion, mediaReduced, sectionVisible, tickers]),
            builder: (context, _) => MediaQuery(
                // The static screenshot host disables animations by default.
                // This fixture deliberately exercises the real layout clock.
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: mediaReduced.value),
                child: MotionPreferencesScope(
                    preferences: MotionPreferences(disabled: {
                      if (!layoutMotion.value) MotionKind.layout,
                    }),
                    child: TickerMode(
                        enabled: tickers.value,
                        child: SettingsSectionVisibility(
                            visible: sectionVisible.value,
                            child: SingleChildScrollView(
                                child: ProcessResourceMonitor(
                                    preferences: preferences,
                                    controller: native.service,
                                    isHidden: hidden,
                                    onPreferencesChanged: (value) async =>
                                        preferences.value = value))))))))));
    await tester.pumpAndSettle();
  }

  double height(WidgetTester tester) => tester
      .getSize(find.descendant(
          of: find.byType(ProcessResourceMonitor),
          matching: find.byType(SettingsSurface)))
      .height;

  Finder get resize => find.byKey(const ValueKey('resource-monitor-size'));

  void enable(bool value) =>
      preferences.value = preferences.value.copyWith(enabled: value);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await native.close();
    for (final notifier in [
      preferences,
      hidden,
      layoutMotion,
      mediaReduced,
      sectionVisible,
      tickers
    ]) {
      notifier.dispose();
    }
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'monitor expands and closes progressively while off stops before native ack',
      (tester) async {
    final rig = _MonitorMotionRig();
    await rig.mount(tester);
    final collapsed = rig.height(tester);
    expect(rig.native.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('resource-enabled')));
    await tester.pump();
    expect(rig.height(tester), closeTo(collapsed, .01));
    await tester.pump(const Duration(milliseconds: 70));
    final opening = rig.height(tester);
    expect(opening, greaterThan(collapsed));
    expect(rig.native.service.active, isTrue);
    await tester.pumpAndSettle();
    final expanded = rig.height(tester);
    expect(opening, lessThan(expanded));
    await rig.native.sample();
    await tester.pump();
    final oldSession = rig.native.session;
    final sampleCount = rig.native.service.history.length;
    final stopAck = Completer<void>();
    rig.native.onCall = (call) async {
      if (call.method == 'stop') await stopAck.future;
    };
    await tester.tap(find.byKey(const ValueKey('resource-enabled')));
    // The worker loses ownership synchronously, before any collapse frame.
    expect(rig.native.service.active, isFalse);
    await tester.pump();
    expect(rig.native.calls.last.method, 'stop');
    expect(rig.height(tester), closeTo(expanded, .01));
    await rig.native.sample(session: oldSession);
    expect(rig.native.service.history, hasLength(sampleCount));
    await tester.pump(const Duration(milliseconds: 70));
    expect(rig.height(tester), inExclusiveRange(collapsed, expanded));
    expect(stopAck.isCompleted, isFalse);
    stopAck.complete();
    await rig.native.service.settled;
    await tester.pumpAndSettle();
    expect(rig.height(tester), closeTo(collapsed, .01));
    expect(find.byKey(const ValueKey('resource-interval')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    final calls = rig.native.calls.length;
    await tester.pump(const Duration(seconds: 20));
    expect(rig.native.calls, hasLength(calls));
    expect(tester.takeException(), isNull);
    await rig.close(tester);
  });

  testWidgets('rapid monitor toggles settle only the latest requested size',
      (tester) async {
    final rig = _MonitorMotionRig();
    await rig.mount(tester);
    final collapsed = rig.height(tester);
    rig.enable(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final partial = rig.height(tester);
    expect(partial, greaterThan(collapsed));
    rig.enable(false);
    expect(rig.native.service.active, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    rig.enable(true);
    await tester.pump();
    await tester.pumpAndSettle();
    final expanded = rig.height(tester);
    expect(expanded, greaterThan(partial));
    expect(rig.native.service.active, isTrue);
    expect(find.byKey(const ValueKey('resource-interval')), findsOneWidget);
    expect(find.byType(AppDialogResize), findsOneWidget);
    rig.enable(false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(rig.height(tester), closeTo(collapsed, .01));
    expect(rig.native.service.active, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await rig.close(tester);
  });

  for (final interruption in [
    'layout setting',
    'MediaQuery reduce',
    'native reduce',
    'window hidden',
    'section hidden',
    'TickerMode hidden'
  ]) {
    testWidgets('monitor resize ends immediately on $interruption',
        (tester) async {
      final rig = _MonitorMotionRig();
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await rig.mount(tester);
      final collapsed = rig.height(tester);
      rig.enable(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final partial = rig.height(tester);
      expect(partial, greaterThan(collapsed));
      switch (interruption) {
        case 'layout setting':
          rig.layoutMotion.value = false;
        case 'MediaQuery reduce':
          rig.mediaReduced.value = true;
        case 'native reduce':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'window hidden':
          rig.hidden.value = true;
        case 'section hidden':
          rig.sectionVisible.value = false;
        case 'TickerMode hidden':
          rig.tickers.value = false;
      }
      await tester.pump();
      expect(rig.height(tester), greaterThan(partial));
      expect(
          find.descendant(of: rig.resize, matching: find.byType(AnimatedSize)),
          findsNothing);
      expect(rig.native.service.active, !interruption.endsWith('hidden'));
      rig.enable(false);
      await tester.pump();
      expect(rig.height(tester), closeTo(collapsed, .01));
      expect(rig.native.service.active, isFalse);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.binding.transientCallbackCount, 0);
      final calls = rig.native.calls.length;
      await tester.pump(const Duration(seconds: 20));
      expect(rig.native.calls, hasLength(calls));
      expect(tester.takeException(), isNull);
      await rig.close(tester);
    });
  }
}
