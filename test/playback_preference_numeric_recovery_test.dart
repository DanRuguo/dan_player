import 'dart:convert';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/play_service/playback_modes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final stored in ['1e400', '-1e400', '-0.5', '"0.5"', 'false', 'null']) {
    test('invalid stored volume $stored recovers and can be persisted again',
        () {
      final raw = jsonDecode('''{
        "playMode":"singleLoop", "shuffle":false, "eqEnabled":true,
        "volumeDsp":$stored, "eqGains":[-2.5,4]
      }''') as Map;
      final restored = PlaybackPreference.fromMap(raw);
      expect(restored.volumeDsp, 1.0);
      expect(restored.playMode, PlayMode.singleLoop);
      expect(restored.shuffle, isFalse);
      expect(restored.eqEnabled, isTrue);
      expect(restored.eqGains, [-2.5, 4.0]);
      final persisted = jsonEncode(restored.toMap());
      expect(PlaybackPreference.fromMap(jsonDecode(persisted)).volumeDsp, 1.0);
    });
  }

  test('overflowing stored EQ bands recover individually without losing gain',
      () {
    final raw = jsonDecode('''{
      "volumeDsp":1.75, "eqGains":[-4,1e400,3,-1e400,"2",null,0.5]
    }''') as Map;
    final restored = PlaybackPreference.fromMap(raw);
    expect(restored.eqGains, [-4.0, 0.0, 3.0, 0.0, 0.0, 0.0, .5]);
    expect(restored.volumeDsp, 1.75);
    expect(
        PlaybackPreference.fromMap(jsonDecode(jsonEncode(restored.toMap())))
            .eqGains,
        restored.eqGains);
  });

  test('missing legacy volume and EQ retain playback defaults', () {
    final legacy = PlaybackPreference.fromMap({});
    expect(legacy.volumeDsp, 1.0);
    expect(legacy.eqGains, List<double>.filled(10, 0));
    expect(legacy.shuffle, isNull);
    expect(legacy.toMap().containsKey('shuffle'), isFalse);
  });

  test('finite mute and boosts survive JSON without a new volume clamp', () {
    for (final volume in [0.0, .5, 1.75, 4.0]) {
      final pref = PlaybackPreference(PlayMode.forward, volume);
      final restored =
          PlaybackPreference.fromMap(jsonDecode(jsonEncode(pref.toMap())));
      expect(restored.volumeDsp, volume);
    }
  });

  test('non-finite values from a direct preference map recover safely', () {
    for (final volume in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      final pref = PlaybackPreference.fromMap({
        'volumeDsp': volume,
        'eqGains': [double.nan, double.infinity, double.negativeInfinity],
      });
      expect(pref.volumeDsp, 1);
      expect(pref.eqGains, [0.0, 0.0, 0.0]);
      expect(() => jsonEncode(pref.toMap()), returnsNormally);
    }
  });
}
