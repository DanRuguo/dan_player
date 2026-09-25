import 'dart:async';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PerformanceSnapshot baseline() => PerformanceSnapshot.capture(
      const RenderingPreferences(
          animations: MotionPreferences(disabled: {MotionKind.tracking}),
          frameRate: FrameRatePreference(mode: FrameRateMode.fixed, fps: 90)),
      const BackgroundPreferences(
          main: BackgroundAppearance(
              source: BackgroundSource.customImage,
              customImageId:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png',
              motion: true)),
      const PlayerExperiencePreferences(
          springLyrics: false, trayMenuBlurRadius: 12),
      false);

  test('backup is committed before applying and survives mode switch/restart',
      () async {
    final original = baseline();
    var live = original;
    final commits = <Map<String, Object>>[];
    late PerformancePresetController controller;
    controller = PerformancePresetController(
        capture: () => live,
        apply: (v) => live = v,
        persist: () async {
          if (commits.isEmpty) expect(live, same(original));
          commits.add(controller.value.toMap());
        });
    await controller.select(PerformanceMode.economy);
    expect(commits.length, 2);
    expect(live.rendering.compactSpectrum, false);
    expect(live.rendering.animations.allDisabled, true);
    expect(live.rendering.surfaceBlur, false);
    expect(live.rendering.frameRate.target(144, interacting: true), 30);
    expect(live.backgrounds.main.source, BackgroundSource.solid);
    expect(live.backgrounds.retainedImageIds,
        original.backgrounds.retainedImageIds);
    await controller.select(PerformanceMode.performance);
    expect(controller.value.before!.toMap(), original.toMap());
    expect(live.rendering.lyricSpectrum, true);
    expect(live.rendering.animations.allEnabled, true);
    expect(live.rendering.frameRate.mode, FrameRateMode.display);
    expect(live.backgrounds.main.source, BackgroundSource.customImage);
    controller.value = PerformancePresetState.fromMap(commits.last);
    await controller.select(PerformanceMode.custom);
    expect(live.toMap(), original.toMap());
    expect(controller.value.before, isNull);
    controller.dispose();
  });

  test('checkpoint failure never applies preset; apply save failure rolls back',
      () async {
    for (final failAt in [1, 2]) {
      final original = baseline();
      var live = original;
      var writes = 0;
      final controller = PerformancePresetController(
          capture: () => live,
          apply: (v) => live = v,
          persist: () async {
            if (++writes == failAt) throw StateError('disk full');
          });
      await expectLater(
          controller.select(PerformanceMode.economy), throwsStateError);
      expect(live.toMap(), original.toMap());
      expect(controller.value.mode, PerformanceMode.custom);
      controller.dispose();
    }
  });

  test('restore failure retains active mode and recovery snapshot', () async {
    var live = baseline();
    var fail = false;
    final controller = PerformancePresetController(
        capture: () => live,
        apply: (v) => live = v,
        persist: () async {
          if (fail) throw StateError('disk full');
        });
    await controller.select(PerformanceMode.economy);
    final active = live;
    fail = true;
    await expectLater(
        controller.select(PerformanceMode.custom), throwsStateError);
    expect(live.toMap(), active.toMap());
    expect(controller.value.mode, PerformanceMode.economy);
    expect(controller.value.before, isNotNull);
    controller.dispose();
  });

  test('superseded override commit also repairs the persisted state', () async {
    final original = baseline();
    var live = original;
    var writes = 0;
    Map<String, Object>? disk;
    late PerformancePresetController controller;
    controller = PerformancePresetController(
      capture: () => live,
      apply: (value) => live = value,
      persist: () async {
        disk = {'preset': controller.value.toMap(), 'live': live.toMap()};
        // A concurrent regular writer persisted the shared override while
        // this stricter commit was superseded.
        if (++writes == 2) throw StateError('superseded');
      },
    );
    await expectLater(
        controller.select(PerformanceMode.economy), throwsStateError);
    expect(writes, 3);
    expect(disk!['preset'], {'mode': 'custom'});
    expect(disk!['live'], original.toMap());
    expect(live.toMap(), original.toMap());
    controller.dispose();
  });

  test('duplicate requests cannot replace original snapshot mid-save',
      () async {
    var live = baseline();
    final gate = Completer<void>();
    final controller = PerformancePresetController(
        capture: () => live,
        apply: (v) => live = v,
        persist: () => gate.future);
    final first = controller.select(PerformanceMode.economy);
    await controller.select(PerformanceMode.performance);
    gate.complete();
    await first;
    expect(controller.value.mode, PerformanceMode.economy);
    controller.dispose();
  });

  test('manual edit during checkpoint becomes the recoverable original',
      () async {
    final original = baseline();
    var live = original;
    final firstStarted = Completer<void>();
    final firstCommit = Completer<void>();
    var writes = 0;
    final controller = PerformancePresetController(
        capture: () => live,
        apply: (value) => live = value,
        persist: () {
          writes++;
          if (writes == 1) {
            firstStarted.complete();
            return firstCommit.future;
          }
          return Future.value();
        });
    final selection = controller.select(PerformanceMode.economy);
    await firstStarted.future;
    final edited = PerformanceSnapshot(
        rendering: live.rendering.copyWith(surfaceBlur: false),
        backgrounds: live.backgrounds,
        dynamicTheme: live.dynamicTheme,
        springLyrics: live.springLyrics,
        taskbarSongPreview: live.taskbarSongPreview,
        taskbarPlaybackProgress: live.taskbarPlaybackProgress,
        trayBlur: live.trayBlur);
    live = edited;
    firstCommit.complete();
    await selection;
    expect(writes, 3);
    expect(controller.value.before!.samePreferencesAs(edited), isTrue);
    await controller.select(PerformanceMode.custom);
    expect(live.samePreferencesAs(edited), isTrue);
    controller.dispose();
  });

  test('continuous edits cancel selection without overwriting the latest edit',
      () async {
    var live = baseline();
    var writes = 0;
    late PerformancePresetController controller;
    controller = PerformancePresetController(
        capture: () => live,
        apply: (value) => live = value,
        persist: () async {
          writes++;
          if (writes <= 3) {
            live = PerformanceSnapshot(
                rendering: live.rendering
                    .copyWith(surfaceBlur: !live.rendering.surfaceBlur),
                backgrounds: live.backgrounds,
                dynamicTheme: live.dynamicTheme,
                springLyrics: live.springLyrics,
                taskbarSongPreview: live.taskbarSongPreview,
                taskbarPlaybackProgress: live.taskbarPlaybackProgress,
                trayBlur: live.trayBlur);
          }
        });
    await controller.select(PerformanceMode.economy);
    expect(writes, 4);
    expect(controller.value.mode, PerformanceMode.custom);
    expect(live.rendering.surfaceBlur, isFalse);
    controller.dispose();
  });

  test('failed final save does not roll back a concurrent manual edit',
      () async {
    var live = baseline();
    final finalStarted = Completer<void>();
    final finalCommit = Completer<void>();
    var writes = 0;
    final controller = PerformancePresetController(
        capture: () => live,
        apply: (value) => live = value,
        persist: () {
          writes++;
          if (writes == 2) {
            finalStarted.complete();
            return finalCommit.future;
          }
          return Future.value();
        });
    final selection = controller.select(PerformanceMode.economy);
    await finalStarted.future;
    live = PerformanceSnapshot(
        rendering: live.rendering.copyWith(surfaceBlur: true),
        backgrounds: live.backgrounds,
        dynamicTheme: live.dynamicTheme,
        springLyrics: live.springLyrics,
        taskbarSongPreview: live.taskbarSongPreview,
        taskbarPlaybackProgress: live.taskbarPlaybackProgress,
        trayBlur: live.trayBlur);
    finalCommit.completeError(StateError('superseded'));
    await selection;
    expect(writes, 3);
    expect(controller.value.mode, PerformanceMode.economy);
    expect(live.rendering.surfaceBlur, isTrue);
    controller.dispose();
  });

  test('a failed capture does not permanently lock mode selection', () async {
    var fail = true;
    var live = baseline();
    final controller = PerformancePresetController(
        capture: () {
          if (fail) throw StateError('capture');
          return live;
        },
        apply: (value) => live = value,
        persist: () async {});
    await expectLater(
        controller.select(PerformanceMode.economy), throwsStateError);
    fail = false;
    await controller.select(PerformanceMode.economy);
    expect(controller.value.mode, PerformanceMode.economy);
    controller.dispose();
  });

  test('invalid recovery records cannot enable a mode without original values',
      () {
    for (final data in [
      null,
      {'mode': 'economy'},
      {'mode': 'economy', 'before': {}},
      {'before': 7}
    ]) {
      expect(PerformancePresetState.fromMap(data).mode, PerformanceMode.custom);
    }
  });
}
