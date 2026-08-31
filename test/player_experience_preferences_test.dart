import 'dart:convert';

import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy or absent preferences preserve safe desktop defaults', () {
    for (final old in [null, '', [], 1, <String, Object>{}]) {
      final value = PlayerExperiencePreferences.fromMap(old);
      expect(value, const PlayerExperiencePreferences());
      expect(value.closeToTray, isFalse);
      expect(value.taskbarControls, isTrue);
      expect(value.desktopLyricVertical, isFalse);
      expect(value.exclusiveOutput, isFalse);
      expect(value.playbackRate, 1);
      expect(
          value.sidebarWidth, PlayerExperiencePreferences.defaultSidebarWidth);
      expect(value.sidebarLocked, isFalse);
      expect(value.windowSizeLocked, isFalse);
      expect(value.windowAspectRatioLocked, isFalse);
      expect(value.windowAspectRatio, 0);
      expect(value.roundedWindowCorners, isTrue);
    }
  });

  test('all preferences survive JSON without modifying input', () {
    const value = PlayerExperiencePreferences(
      closeToTray: true,
      taskbarControls: false,
      springLyrics: false,
      desktopLyricVertical: true,
      playbackRate: 1.75,
      exclusiveOutput: true,
      sidebarWidth: 244,
      sidebarLocked: true,
      windowSizeLocked: true,
      windowAspectRatioLocked: true,
      windowAspectRatio: 16 / 9,
      roundedWindowCorners: false,
    );
    final encoded = jsonEncode(value.toMap());
    final source = jsonDecode(encoded);
    final result = PlayerExperiencePreferences.fromMap(source);
    expect(result, value);
    expect(result.hashCode, value.hashCode);
    expect(jsonEncode(source), encoded);
  });

  test('a single preference change preserves every unrelated field', () {
    const value = PlayerExperiencePreferences(
      closeToTray: true,
      taskbarControls: false,
      springLyrics: false,
      desktopLyricVertical: true,
      playbackRate: 1.5,
      exclusiveOutput: true,
      sidebarWidth: 260,
      sidebarLocked: true,
      windowSizeLocked: true,
      windowAspectRatioLocked: true,
      windowAspectRatio: 1.6,
    );
    expect(value.copyWith(), value);
    expect(value.copyWith(roundedWindowCorners: false).toMap(),
        {...value.toMap(), 'roundedWindowCorners': false});
    expect(value.copyWith(playbackRate: .75).toMap(),
        {...value.toMap(), 'playbackRate': .75});
    expect(value.copyWith(closeToTray: false).toMap(),
        {...value.toMap(), 'closeToTray': false});
    expect(value.copyWith(springLyrics: true).toMap(),
        {...value.toMap(), 'springLyrics': true});
    expect(value.copyWith(desktopLyricVertical: false).toMap(),
        {...value.toMap(), 'desktopLyricVertical': false});
    expect(value.copyWith(exclusiveOutput: false).toMap(),
        {...value.toMap(), 'exclusiveOutput': false});
    expect(value.copyWith(sidebarWidth: 180).toMap(),
        {...value.toMap(), 'sidebarWidth': 180.0});
    expect(value.copyWith(sidebarLocked: false).toMap(),
        {...value.toMap(), 'sidebarLocked': false});
    expect(value.copyWith(windowSizeLocked: false).toMap(),
        {...value.toMap(), 'windowSizeLocked': false});
    expect(value.copyWith(windowAspectRatioLocked: false).toMap(),
        {...value.toMap(), 'windowAspectRatioLocked': false});
    expect(value.copyWith(windowAspectRatio: 0).toMap(),
        {...value.toMap(), 'windowAspectRatio': 0.0});
  });

  test('malformed booleans and unknown keys cannot silently enable features',
      () {
    final value = PlayerExperiencePreferences.fromMap(const {
      'closeToTray': 'true',
      'taskbarControls': 0,
      'springLyrics': [],
      'desktopLyricVertical': 1,
      'exclusiveOutput': 'yes',
      'playbackRate': '1.5',
      'sidebarWidth': '240',
      'sidebarLocked': 1,
      'windowSizeLocked': 'yes',
      'windowAspectRatioLocked': 1,
      'windowAspectRatio': '1.777',
      'unknownFutureField': true,
    });
    expect(value, const PlayerExperiencePreferences());
  });

  test('window ratio accepts a capture sentinel and rejects unsafe values', () {
    expect(
        PlayerExperiencePreferences.fromMap(const {'windowAspectRatio': 16 / 9})
            .windowAspectRatio,
        closeTo(16 / 9, .0001));
    expect(
        PlayerExperiencePreferences.fromMap(const {'windowAspectRatio': 0})
            .windowAspectRatio,
        0);
    for (final invalid in [-1, .1, 5, double.nan, double.infinity]) {
      expect(
          PlayerExperiencePreferences.fromMap({'windowAspectRatio': invalid})
              .windowAspectRatio,
          0);
    }
  });

  test('sidebar width is finite and clamped at load and copy boundaries', () {
    expect(
        PlayerExperiencePreferences.fromMap(const {'sidebarWidth': -100})
            .sidebarWidth,
        PlayerExperiencePreferences.minSidebarWidth);
    expect(
        PlayerExperiencePreferences.fromMap(const {'sidebarWidth': 999})
            .sidebarWidth,
        PlayerExperiencePreferences.maxSidebarWidth);
    expect(
        PlayerExperiencePreferences.fromMap(const {'sidebarWidth': double.nan})
            .sidebarWidth,
        PlayerExperiencePreferences.defaultSidebarWidth);
    expect(
        const PlayerExperiencePreferences(sidebarWidth: 240)
            .copyWith(sidebarWidth: double.infinity)
            .sidebarWidth,
        240);
  });

  for (final invalid in [
    double.nan,
    double.infinity,
    double.negativeInfinity
  ]) {
    test('nonfinite speed $invalid is safe at JSON and copy boundaries', () {
      expect(
          PlayerExperiencePreferences.fromMap({'playbackRate': invalid})
              .playbackRate,
          1);
      expect(
          const PlayerExperiencePreferences(playbackRate: 1.5)
              .copyWith(playbackRate: invalid)
              .playbackRate,
          1.5);
      expect(
          jsonEncode(
              PlayerExperiencePreferences(playbackRate: invalid).toMap()),
          contains('"playbackRate":1.0'));
    });
  }

  test('out of range preferences are clamped and validation rejects API misuse',
      () {
    expect(
        PlayerExperiencePreferences.fromMap(const {'playbackRate': -1})
            .playbackRate,
        .5);
    expect(
        PlayerExperiencePreferences.fromMap(const {'playbackRate': 999})
            .playbackRate,
        2);
    for (final rate in [-1.0, .49, 2.01, double.nan, double.infinity]) {
      expect(() => PlaybackRate.validate(rate), throwsArgumentError);
      expect(() => PlaybackRate.tempoPercent(rate), throwsArgumentError);
    }
    expect(PlaybackRate.sanitize(null, fallback: double.nan), 1);
    expect(PlaybackRate.sanitize(null, fallback: 99), 2);
  });

  test('presets have matching BASS tempo percentages and compact labels', () {
    expect(PlaybackRate.presets.map(PlaybackRate.tempoPercent).toList(),
        [-50, -25, 0, 25, 50, 75, 100]);
    expect(PlaybackRate.presets.map(PlaybackRate.label).toList(),
        ['0.5×', '0.75×', '1×', '1.25×', '1.5×', '1.75×', '2×']);
    for (final rate in PlaybackRate.presets) {
      expect(PlaybackRate.validate(rate), rate);
    }
  });
}
