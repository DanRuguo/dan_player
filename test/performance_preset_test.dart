import 'dart:async';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PerformanceSnapshot baseline() => PerformanceSnapshot.capture(
      const RenderingPreferences(
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
    expect(live.rendering.surfaceBlur, false);
    expect(live.rendering.frameRate.target(144, interacting: true), 30);
    expect(live.backgrounds.main.source, BackgroundSource.solid);
    expect(live.backgrounds.retainedImageIds,
        original.backgrounds.retainedImageIds);
    await controller.select(PerformanceMode.performance);
    expect(controller.value.before!.toMap(), original.toMap());
    expect(live.rendering.lyricSpectrum, true);
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
