import 'dart:ffi';

import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_transition_mixer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the native envelope node keeps the official QWORD and float ABI', () {
    expect(sizeOf<BassMixerEnvelopeNode>(), 16);
  });

  test('gapless preserves all remaining output time without an overlap', () {
    final timing = BassTransitionTiming.resolve(remainingSeconds: .004)!;
    expect(timing.isGapless, isTrue);
    expect(timing.delaySeconds, .004);
  });

  test('crossfade is bounded by the current remainder and half the next track',
      () {
    final shortNext = BassTransitionTiming.resolve(
        remainingSeconds: 6, fadeSeconds: 12, nextDuration: 4)!;
    expect(shortNext.fadeSeconds, 2);
    expect(shortNext.delaySeconds, 4);
    final shortCurrent = BassTransitionTiming.resolve(
        remainingSeconds: .2, fadeSeconds: 3, nextDuration: 30)!;
    expect(shortCurrent.fadeSeconds, .2);
    expect(shortCurrent.delaySeconds, 0);
  });

  test('unknown or invalid next duration uses FIFO rather than an unsafe fade',
      () {
    for (final duration in [null, 0.0, -1.0, double.nan, double.infinity]) {
      final timing = BassTransitionTiming.resolve(
          remainingSeconds: 5, fadeSeconds: 3, nextDuration: duration)!;
      expect(timing.isGapless, isTrue);
      expect(timing.delaySeconds, 5);
    }
  });

  test('a finished or invalid current remainder cannot acquire a successor',
      () {
    for (final remaining in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
          BassTransitionTiming.resolve(
              remainingSeconds: remaining, fadeSeconds: 3, nextDuration: 10),
          isNull);
    }
  });

  test('invalid or disabled fade falls back to gapless without negative delay',
      () {
    for (final fade in [0.0, -1.0, double.nan, double.infinity]) {
      final timing = BassTransitionTiming.resolve(
          remainingSeconds: 5, fadeSeconds: fade, nextDuration: 10)!;
      expect(timing.isGapless, isTrue);
      expect(timing.delaySeconds, 5);
    }
  });
}
