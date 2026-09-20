import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_binding.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:desktop_lyric/message.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

void _send(DesktopLyricController source, Message value) =>
    source.handleMessage(value.buildMessageJson());

FrameRateMessage _policy(
        {bool lyrics = true, bool hidden = true, bool blur = true}) =>
    FrameRateMessage({
      'mode': 'adaptive',
      'fps': 60,
      'animations': {'lyrics': lyrics},
      'pauseWhenHidden': hidden,
      'panelBlur': blur,
    });

void main() {
  late MotionPreferences previousMotion;
  late FrameRatePreference previousFrameRate;
  setUp(() {
    previousMotion = desktopMotionPreferences.value;
    previousFrameRate = frameRatePreference.value;
  });
  tearDown(() {
    desktopMotionPreferences.value = previousMotion;
    frameRatePreference.value = previousFrameRate;
  });

  test('disabled lyric motion stops sampling but seek and playback stay live',
      () {
    fakeAsync((time) {
      final clock =
          PlaybackClock(nowMilliseconds: () => time.elapsed.inMilliseconds);
      final source = DesktopLyricController.detached(clock: clock);
      var notifications = 0;
      clock.addListener(() => notifications++);
      _send(source, const PlaybackTimelineMessage(1, 1000, true));
      time.elapse(const Duration(milliseconds: 330));
      expect(notifications, 11);
      expect(time.periodicTimerCount, 1);
      _send(source, _policy(lyrics: false));
      expect(time.periodicTimerCount, 0);
      final stopped = notifications;
      time.elapse(const Duration(seconds: 2));
      expect(clock.positionMilliseconds, 3330);
      expect(notifications, stopped);
      _send(source,
          const PlaybackTimelineMessage(1, 8000, true, playbackRate: 2));
      expect(notifications, stopped + 1);
      expect(time.periodicTimerCount, 0);
      time.elapse(const Duration(milliseconds: 500));
      expect(clock.positionMilliseconds, 9000);
      _send(source, const PlayerStateChangedMessage(false));
      expect(notifications, stopped + 2);
      time.elapse(const Duration(seconds: 1));
      expect(clock.positionMilliseconds, 9000);
      _send(source, const PlaybackTimelineMessage(1, 3000, false));
      expect(notifications, stopped + 3);
      expect(clock.positionMilliseconds, 3000);
      _send(source, const PlayerStateChangedMessage(true));
      expect(notifications, stopped + 4);
      expect(time.periodicTimerCount, 0);
      _send(source, _policy());
      expect(notifications, stopped + 5); // Current position catches up now.
      expect(time.periodicTimerCount, 1);
      source.dispose();
      expect(time.periodicTimerCount, 0);
    });
  });

  test('hidden preference changes never reanchor time or bypass motion policy',
      () {
    fakeAsync((time) {
      final clock =
          PlaybackClock(nowMilliseconds: () => time.elapsed.inMilliseconds);
      final source = DesktopLyricController.detached(clock: clock);
      var notifications = 0;
      clock.addListener(() => notifications++);
      _send(source, const PlaybackTimelineMessage(1, 0, true));
      source.setWindowLifecycle(AppLifecycleState.inactive);
      time.elapse(const Duration(milliseconds: 330));
      expect(notifications, 11);
      source.setWindowLifecycle(AppLifecycleState.hidden);
      expect(time.periodicTimerCount, 0);
      time.elapse(const Duration(seconds: 3));
      expect(notifications, 11);
      expect(clock.positionMilliseconds, 3330);
      _send(source, _policy(blur: false));
      _send(source, const PlaybackTimelineMessage(1, 5000, true));
      expect(time.periodicTimerCount, 0);
      expect(notifications, 12);
      _send(source, _policy(hidden: false));
      expect(time.periodicTimerCount, 1);
      time.elapse(const Duration(milliseconds: 330));
      expect(clock.positionMilliseconds, 5330);
      _send(source, _policy(hidden: false, lyrics: false));
      expect(time.periodicTimerCount, 0);
      source.setWindowLifecycle(AppLifecycleState.resumed);
      expect(time.periodicTimerCount, 0);
      _send(source, _policy(hidden: false));
      expect(time.periodicTimerCount, 1);
      source.setWindowLifecycle(AppLifecycleState.paused);
      expect(time.periodicTimerCount, 0);
      source.setWindowLifecycle(AppLifecycleState.inactive);
      expect(time.periodicTimerCount, 1);
      source.setWindowLifecycle(AppLifecycleState.detached);
      _send(source, _policy(hidden: false));
      expect(time.periodicTimerCount, 0);
      source.dispose();
    });
  });

  test('old or malformed policy fields retain safe defaults', () {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    _send(source, _policy(blur: false, hidden: false));
    expect(source.renderingPolicy.value.panelBlur, isFalse);
    expect(source.renderingPolicy.value.pauseWhenHidden, isFalse);
    for (final map in <Map<String, Object>>[
      {'mode': 'fixed', 'fps': 30},
      {'panelBlur': 'false', 'pauseWhenHidden': 0},
    ]) {
      _send(source, FrameRateMessage(map));
      expect(source.renderingPolicy.value, const DesktopLyricRenderingPolicy());
    }
  });

  testWidgets('child binding gates only its own lifecycle and accessibility',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final clock = PlaybackClock(
        nowMilliseconds: () =>
            tester.binding.clock.now().millisecondsSinceEpoch);
    final source = DesktopLyricController.detached(clock: clock);
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    final binding = DesktopLyricWindowBinding(source, layout);
    addTearDown(source.dispose);
    addTearDown(binding.dispose);
    var notifications = 0;
    clock.addListener(() => notifications++);
    binding.attach();
    binding.attach(); // Repeated native-ready callback must remain idempotent.
    _send(source, const PlaybackTimelineMessage(1, 1000, true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 330));
    expect(notifications, 11);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final stopped = notifications;
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, stopped);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    _send(source, _policy(hidden: false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, stopped);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 330));
    expect(notifications, stopped);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    expect(notifications, stopped + 1);
    await tester.pump(const Duration(milliseconds: 330));
    expect(notifications, stopped + 11);

    // Rendering policy messages carry preferences, not the main HWND's state.
    // A different controller hiding cannot pause this visible helper clock.
    final other = DesktopLyricController.detached();
    other.setWindowLifecycle(AppLifecycleState.hidden);
    _send(source, _policy());
    final beforeOtherHide = notifications;
    await tester.pump(const Duration(milliseconds: 330));
    expect(notifications, beforeOtherHide + 10);
    other.dispose();
    binding.dispose();
    final disposed = notifications;
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, disposed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel blur follows parent preference while background stays',
      (tester) async {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    addTearDown(source.dispose);
    addTearDown(layout.dispose);
    source.appearance.value =
        DesktopLyricAppearance.defaults.copyWith(backgroundOpacity: .5);
    await tester.pumpWidget(MaterialApp(
        home: Provider<ThemeChangedMessage>.value(
            value: source.theme.value,
            child: DesktopLyricBody(
                controller: source,
                windowLayout: layout,
                sendMessage: (_) {}))));
    await tester.pumpAndSettle();
    Color background() => (tester
            .widget<DecoratedBox>(
                find.byKey(const ValueKey('desktop-lyric-background')))
            .decoration as BoxDecoration)
        .color!;
    final previous = background();
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isTrue);
    _send(source, _policy(blur: false));
    await tester.pumpAndSettle();
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isFalse);
    expect(background(), previous);
    _send(source, _policy());
    await tester.pumpAndSettle();
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isTrue);
    expect(background(), previous);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
