import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/page/settings_page/rendering_settings.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lyric helper receives the same frame policy without touching playback',
      () {
    final controller = DesktopLyricController.detached();
    final previous = frameRatePreference.value;
    addTearDown(() {
      frameRatePreference.value = previous;
      controller.dispose();
    });
    const preference = FrameRatePreference(mode: FrameRateMode.fixed, fps: 30);
    controller
        .handleMessage(FrameRateMessage(preference.toMap()).buildMessageJson());
    expect(frameRatePreference.value, preference);
    expect(controller.isPlaying.value, false);
  });

  test('preferences migrate, persist and clamp targets to the window display',
      () {
    expect(RenderingPreferences.fromMap(const {}).frameRate.mode,
        FrameRateMode.display);
    for (final mode in FrameRateMode.values) {
      final pref = FrameRatePreference(mode: mode, fps: 144);
      final settings = RenderingPreferences(frameRate: pref);
      expect(RenderingPreferences.fromMap(settings.toMap()), settings);
      expect(pref.target(59, interacting: true), 59);
      expect(pref.target(double.nan, interacting: false),
          mode == FrameRateMode.adaptive ? 48 : 60);
    }
    expect(FrameRatePreference.fromMap(const {'mode': 'bad', 'fps': -1}),
        const FrameRatePreference());
    const adaptive = FrameRatePreference(mode: FrameRateMode.adaptive);
    expect(adaptive.target(144, interacting: true), 144);
    expect(adaptive.target(144, interacting: false), 48);
    expect(adaptive.target(60, interacting: false), 48);
    expect(adaptive.target(30, interacting: false), 30);
  });

  test('coalesces bursts, emits at the target and has no idle timers', () {
    fakeAsync((time) {
      final emitted = <Duration>[];
      final pacer = FrameRequestPacer(
          now: () => time.elapsed, emit: () => emitted.add(time.elapsed));
      pacer.request(30);
      for (var i = 0; i < 100; i++) {
        pacer.request(30);
      }
      expect(emitted, [Duration.zero]);
      expect(time.nonPeriodicTimerCount, 1);
      time.elapse(const Duration(milliseconds: 33));
      expect(emitted.length, 1);
      time.elapse(const Duration(milliseconds: 1));
      expect(emitted.length, 2);
      time.elapse(const Duration(seconds: 10));
      expect(emitted.length, 2);
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  test('changing policy or hiding cancels pending frames; restore is immediate',
      () {
    fakeAsync((time) {
      var frames = 0;
      final pacer =
          FrameRequestPacer(now: () => time.elapsed, emit: () => frames++);
      pacer.request(30);
      pacer.request(30);
      pacer.reset();
      time.elapse(const Duration(seconds: 1));
      expect(frames, 1);
      pacer.request(60);
      expect(frames, 2);
      pacer.request(null);
      expect(frames, 3);
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  testWidgets('fixed choices follow monitor limit and keep stored preference',
      (tester) async {
    windowDisplayRate.value = 144;
    addTearDown(() => windowDisplayRate.value = null);
    var value = const RenderingPreferences(
        frameRate: FrameRatePreference(mode: FrameRateMode.fixed, fps: 144));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
                    builder: (context, setState) => RenderingSettings(
                        value: value,
                        onChanged: (next) => setState(() => value = next)))))));
    expect(
        tester
            .widget<AppSegmentedControl<int>>(
                find.byKey(const ValueKey('frame-rate-fps')))
            .options
            .map((v) => v.value),
        contains(144));
    windowDisplayRate.value = 60;
    await tester.pump();
    expect(
        tester
            .widget<AppSegmentedControl<int>>(
                find.byKey(const ValueKey('frame-rate-fps')))
            .options
            .map((v) => v.value),
        isNot(contains(144)));
    expect(
        tester
            .widget<AppSegmentedControl<int>>(
                find.byKey(const ValueKey('frame-rate-fps')))
            .value,
        60);
    expect(value.frameRate.fps, 144);
    windowDisplayRate.value = 144;
    await tester.pump();
    expect(
        tester
            .widget<AppSegmentedControl<int>>(
                find.byKey(const ValueKey('frame-rate-fps')))
            .value,
        144);
    expect(tester.takeException(), isNull);
  });
}
