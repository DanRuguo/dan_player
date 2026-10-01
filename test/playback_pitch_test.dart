import 'dart:convert';

import 'package:dan_player/play_service/playback_pitch.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pitch accepts independent semitones and rejects unsafe native input',
      () {
    for (final value in [-12.0, -4.5, 0.0, .25, 12.0]) {
      expect(PlaybackPitch.validate(value), value);
    }
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -12.001,
      12.001,
    ]) {
      expect(() => PlaybackPitch.validate(value), throwsArgumentError);
    }
  });

  test('invalid stored pitch restores original key without damaging speed', () {
    for (final value in [null, '3', <int>[], double.nan, double.infinity]) {
      final preferences = PlayerExperiencePreferences.fromMap({
        'playbackPitch': value,
        'playbackRate': 1.75,
        'exclusiveOutput': true,
      });
      expect(preferences.playbackPitch, 0);
      expect(preferences.playbackRate, 1.75);
      expect(preferences.exclusiveOutput, isTrue);
    }
    final overflow = jsonDecode('{"playbackPitch":1e999,"playbackRate":0.75}');
    final preferences = PlayerExperiencePreferences.fromMap(overflow);
    expect(preferences.playbackPitch, 0);
    expect(preferences.playbackRate, .75);
  });

  test('pitch bounds and invalid fallbacks stay finite at persistence boundary',
      () {
    expect(PlaybackPitch.sanitize(1e100), 12);
    expect(PlaybackPitch.sanitize(-1e100), -12);
    expect(PlaybackPitch.sanitize(null, fallback: double.nan), 0);
    expect(PlaybackPitch.sanitize(null, fallback: 100), 12);
    expect(PlaybackPitch.sanitize(double.infinity, fallback: -3), -3);
    const invalid = PlayerExperiencePreferences(playbackPitch: double.nan);
    expect(jsonDecode(jsonEncode(invalid.toMap()))['playbackPitch'], 0);
    expect(invalid.copyWith().playbackPitch, 0);
  });

  test('pitch persists with all existing experience preferences unchanged', () {
    const original = PlayerExperiencePreferences(
      playbackRate: .75,
      exclusiveOutput: true,
      closeToTray: true,
      springLyrics: false,
      sidebarWidth: 250,
      windowAspectRatioLocked: true,
      windowAspectRatio: 16 / 9,
    );
    final shifted = original.copyWith(playbackPitch: -4.5);
    expect(shifted.toMap(), {...original.toMap(), 'playbackPitch': -4.5});
    final restored = PlayerExperiencePreferences.fromMap(
        jsonDecode(jsonEncode(shifted.toMap())));
    expect(restored, shifted);
    expect(restored.hashCode, shifted.hashCode);
    expect(restored, isNot(original));
    expect(restored.copyWith(playbackRate: 1.5).playbackPitch, -4.5);
    expect(restored.copyWith(playbackPitch: double.nan).playbackPitch, -4.5);
    expect(restored.copyWith(playbackPitch: 0), original);
  });

  test('legacy preferences start at zero and signed pitch labels retain steps',
      () {
    expect(
        PlayerExperiencePreferences.fromMap(const {'playbackRate': 1.5})
            .playbackPitch,
        0);
    expect(PlaybackPitch.presets.map(PlaybackPitch.label).toList(),
        ['-12', '-7', '-5', '0', '+5', '+7', '+12']);
    expect(PlaybackPitch.label(-0.0), '0');
    expect(PlaybackPitch.label(-.001), '0');
    expect(PlaybackPitch.label(-4.5), '-4.5');
    expect(PlaybackPitch.label(.25), '+0.25');
  });
}
