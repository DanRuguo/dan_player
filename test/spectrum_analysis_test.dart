import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dan_player/src/bass/spectrum_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached spectrum preserves original output across rates and frames', () {
    final actual = SpectrumAnalysis();
    final original = _OriginalAnalysis();
    final random = math.Random(482);
    for (final rate in [48000.0, 44100.0, 96000.0, 8000.0, 48000.0]) {
      for (var frame = 0; frame < 80; frame++) {
        final fft = Float32List.fromList(List.generate(
            2048, (_) => frame % 7 == 0 ? 0 : random.nextDouble() * .1));
        original.update(fft, rate);
        actual.update(fft, rate, frequencyDemand: true, toneDemand: true);
        expect(actual.frequencies,
            orderedEquals(original._frequencySpectrumLevels));
        expect(actual.tones, orderedEquals(original._spectrumLevels));
      }
    }
  });
  test('unsubscribed visualization does no smoothing or calculation', () {
    final actual = SpectrumAnalysis();
    final fft = Float32List.fromList(List.filled(2048, .05));
    actual.update(fft, 48000, frequencyDemand: true, toneDemand: false);
    expect(actual.tones, everyElement(0));
    expect(actual.frequencies.any((v) => v > 0), true);
    final previous = List.of(actual.frequencies);
    actual.update(fft, 44100, frequencyDemand: false, toneDemand: true);
    expect(actual.frequencies, previous);
    expect(actual.tones.any((v) => v > 0), true);
  });
}

// Frozen original formulas verify that caching does not alter visual amplitudes.
class _OriginalAnalysis {
  static const _fftSize = 4096, _fftValueCount = 2048;
  final _spectrumLevels = List<double>.filled(7, 0);
  final _frequencySpectrumLevels = List<double>.filled(48, 0);
  void update(Float32List fft, double sampleRate) {
    _updateFrequencyBands(fft, sampleRate);
    final chroma = List.filled(12, 0.0);
    final counts = List.filled(12, 0);
    for (var midi = 33; midi <= 119; midi++) {
      final frequency = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
      final center = (frequency * _fftSize / sampleRate).round();
      if (center < 1 || center >= _fftValueCount) continue;

      var magnitude = 0.0;
      final start = math.max(1, center - 2);
      final end = math.min(_fftValueCount - 1, center + 2);
      for (var bin = start; bin <= end; bin++) {
        magnitude = math.max(magnitude, fft[bin].toDouble());
      }
      final pitchClass = midi % 12;
      chroma[pitchClass] += math.sqrt(math.max(0.0, magnitude));
      counts[pitchClass]++;
    }
    for (var i = 0; i < chroma.length; i++) {
      if (counts[i] > 0) chroma[i] /= counts[i];
    }

    final tones = <double>[
      chroma[0] + chroma[1] * 0.5,
      chroma[2] + (chroma[1] + chroma[3]) * 0.5,
      chroma[4] + chroma[3] * 0.5,
      chroma[5] + chroma[6] * 0.5,
      chroma[7] + (chroma[6] + chroma[8]) * 0.5,
      chroma[9] + (chroma[8] + chroma[10]) * 0.5,
      chroma[11] + chroma[10] * 0.5,
    ];

    for (var i = 0; i < _spectrumLevels.length; i++) {
      var target = (tones[i] * 3.2).clamp(0.0, 1.0).toDouble();
      if (target < 0.025) target = 0.0;
      final smoothing = target > _spectrumLevels[i] ? 0.58 : 0.14;
      _spectrumLevels[i] += (target - _spectrumLevels[i]) * smoothing;
    }
  }

  void _updateFrequencyBands(Float32List fft, double sampleRate) {
    const minimumFrequency = 40.0;
    const maximumFrequency = 16000.0;
    const ratio = maximumFrequency / minimumFrequency;
    for (var band = 0; band < _frequencySpectrumLevels.length; band++) {
      final low = minimumFrequency *
          math.pow(ratio, band / _frequencySpectrumLevels.length);
      final high = minimumFrequency *
          math.pow(ratio, (band + 1) / _frequencySpectrumLevels.length);
      final start = (low * _fftSize / sampleRate)
          .floor()
          .clamp(1, _fftValueCount - 1)
          .toInt();
      final end = (high * _fftSize / sampleRate)
          .ceil()
          .clamp(start + 1, _fftValueCount)
          .toInt();
      var peak = 0.0;
      for (var bin = start; bin < end; bin++) {
        peak = math.max(peak, fft[bin].toDouble());
      }
      var target =
          math.pow(peak * 11.0, 0.55).toDouble().clamp(0.0, 1.0).toDouble();
      if (target < 0.018) target = 0.0;
      final current = _frequencySpectrumLevels[band];
      final smoothing = target > current ? 0.34 : 0.15;
      _frequencySpectrumLevels[band] += (target - current) * smoothing;
    }
  }
}
