import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const off = ReplayGainPreferences();
  const track = ReplayGainPreferences(mode: ReplayGainMode.track);
  const tags = ReplayGainTags(trackGainDb: 6, trackPeak: .8);
  late List<(String, int, int, double, int)> calls;
  late BassPlaybackVolume volume;
  setUp(() {
    calls = [];
    volume = BassPlaybackVolume(
      setAttribute: (stream, attribute, value) {
        calls.add(('set', stream, attribute, value, 0));
        return true;
      },
      slideAttribute: (stream, attribute, value, milliseconds) {
        calls.add(('slide', stream, attribute, value, milliseconds));
        return true;
      },
    );
  });

  test('new sources receive both factors before playback without a slide', () {
    final base = volume.initialize(11, .4, tags, track);
    expect(base, 1.25);
    expect(calls.map((c) => (c.$1, c.$2, c.$3)),
        [('set', 11, 19), ('set', 11, 2)]);
    expect(base * calls.last.$4, closeTo(tags.volume(.4, track), 1e-12));
  });

  test('drag targets go directly to native output slides and never rewrite DSP',
      () {
    final base = volume.initialize(11, .4, tags, track);
    calls.clear();
    for (final target in [.7, .9, .3, .1, .6]) {
      volume.target(11, target, tags, track, dspBase: base, smooth: true);
    }
    expect(calls, hasLength(5));
    expect(
        calls.every((c) => c.$1 == 'slide' && c.$3 == 2 && c.$5 == 70), isTrue);
    expect(calls.last.$4 * base, closeTo(tags.volume(.6, track), 1e-12));
  });

  test('mute and paused changes cancel the native slide immediately', () {
    volume.target(11, .8, tags, track, dspBase: 1.25, smooth: true);
    volume.target(11, 0, tags, track, dspBase: 1.25, smooth: true);
    expect(calls.last, ('set', 11, 2, 0.0, 0));
    volume.target(11, .2, tags, track, dspBase: 1.25, smooth: false);
    expect(calls.last.$1, 'set');
    expect(calls.last.$3, 2);
    expect(calls.last.$5, 0);
  });

  test('ReplayGain changes preserve the buffered DSP base and total gain', () {
    for (final initial in [off, track]) {
      final base = volume.initialize(11, .4, tags, initial);
      calls.clear();
      for (final preferences in [track, off, track]) {
        for (final user in [0.0, .1, .4, 1.0, 1.5]) {
          volume.target(11, user, tags, preferences,
              dspBase: base, smooth: true);
          expect(calls.last.$3, 2);
          expect(base * calls.last.$4,
              closeTo(tags.volume(user, preferences), 1e-12));
        }
      }
      expect(calls.every((c) => c.$3 != 19), isTrue);
    }
  });

  test('a source switch initializes independently of an old pending ramp', () {
    volume.initialize(11, .6, tags, track);
    volume.target(11, .3, tags, track, dspBase: 1.25, smooth: true);
    calls.clear();
    volume.initialize(12, .3, const ReplayGainTags(trackGainDb: -6), track);
    expect(calls.every((c) => c.$2 == 12 && c.$1 == 'set'), isTrue);
    expect(calls.last.$4, closeTo(.3, 1e-12));
  });

  test('unsupported slides fall back to immediate volume but errors propagate',
      () {
    var setWorks = true;
    final fallback = BassPlaybackVolume(
        setAttribute: (s, a, v) {
          calls.add(('set', s, a, v, 0));
          return setWorks;
        },
        slideAttribute: (s, a, v, t) => false);
    fallback.target(11, .2, const ReplayGainTags(), off,
        dspBase: 1, smooth: true);
    expect(calls.single, ('set', 11, 2, .2, 0));
    setWorks = false;
    expect(
        () => fallback.target(11, .2, const ReplayGainTags(), off,
            dspBase: 1, smooth: true),
        throwsFormatException);
  });
}
