import 'package:dan_player/src/bass/bass_equalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('44.1k peaking keeps the actual 16k band; DX8 cannot represent it', () {
    expect(BassEqualizer.supportFor(44100, peakingAvailable: true),
        List.filled(10, true));
    expect(BassEqualizer.supportFor(44100, peakingAvailable: false),
        [...List.filled(9, true), false]);
  });
  test('Nyquist is an exclusive limit, including the exact 32k boundary', () {
    expect(BassEqualizer.supportFor(32000, peakingAvailable: true).last, false);
    expect(BassEqualizer.supportFor(32001, peakingAvailable: true).last, true);
    expect(BassEqualizer.supportFor(16000, peakingAvailable: true),
        [...List.filled(7, true), false, false, false]);
  });
  test('DX8 supports its exact sampleRate/3 limit without shifting centres',
      () {
    expect(BassEqualizer.supportFor(48000, peakingAvailable: false).last, true);
    expect(
        BassEqualizer.supportFor(47999, peakingAvailable: false).last, false);
    expect(BassEqualizer.supportFor(8000, peakingAvailable: false),
        [...List.filled(6, true), false, false, false, false]);
  });
  test('low sample rates disable only the unrepresentable upper bands', () {
    expect(BassEqualizer.supportFor(22050, peakingAvailable: true),
        [...List.filled(8, true), false, false]);
    expect(BassEqualizer.supportFor(8000, peakingAvailable: true),
        [...List.filled(6, true), false, false, false, false]);
  });
  test('unknown/invalid source format never guesses native capability', () {
    for (final sampleRate in [null, 0, -44100]) {
      for (final peaking in [false, true]) {
        expect(BassEqualizer.supportFor(sampleRate, peakingAvailable: peaking),
            List.filled(10, false));
      }
    }
  });
  test('cached band masks and original fixed frequencies are immutable', () {
    final mask = BassEqualizer.supportFor(8000, peakingAvailable: true);
    expect(() => mask[9] = true, throwsUnsupportedError);
    expect(BassEqualizer.centers.last, 16000);
    expect(BassEqualizer.centers.length, 10);
  });
}
