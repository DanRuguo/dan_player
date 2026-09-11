import 'dart:math' as math;
import 'dart:typed_data';

/// The same FFT mapping and smoothing, with geometry reused until sample rate
/// changes. The two visual consumers pay only for the bands they subscribe to.
class SpectrumAnalysis {
  static const fftSize = 4096;
  static const fftValues = fftSize ~/ 2;
  final tones = List<double>.filled(7, 0);
  final frequencies = List<double>.filled(48, 0);
  double? _sampleRate;
  List<({int start, int end})> _bands = const [];
  List<({int start, int end, int pitch})> _notes = const [];

  void update(Float32List fft, double sampleRate,
      {required bool frequencyDemand, required bool toneDemand}) {
    assert(fft.length >= fftValues);
    if (!frequencyDemand && !toneDemand) return;
    if (!sampleRate.isFinite || sampleRate <= 0) sampleRate = 48000;
    if (sampleRate != _sampleRate) {
      _sampleRate = sampleRate;
      _bands = List.generate(frequencies.length, (band) {
        final low = 40 * math.pow(400, band / frequencies.length);
        final high = 40 * math.pow(400, (band + 1) / frequencies.length);
        final start =
            (low * fftSize / sampleRate).floor().clamp(1, fftValues - 1);
        final end =
            (high * fftSize / sampleRate).ceil().clamp(start + 1, fftValues);
        return (start: start, end: end);
      });
      _notes = [
        for (var midi = 33; midi <= 119; midi++)
          if ((440 * math.pow(2, (midi - 69) / 12) * fftSize / sampleRate)
                  .round()
              case final center when center >= 1 && center < fftValues)
            (
              start: math.max(1, center - 2),
              end: math.min(fftValues - 1, center + 2),
              pitch: midi % 12
            ),
      ];
    }
    if (frequencyDemand) _updateFrequencyBands(fft);
    if (toneDemand) _updateTones(fft);
  }

  void _updateTones(Float32List fft) {
    final chroma = List.filled(12, 0.0);
    final counts = List.filled(12, 0);
    for (final note in _notes) {
      var magnitude = 0.0;
      final start = note.start;
      final end = note.end;
      for (var bin = start; bin <= end; bin++) {
        magnitude = math.max(magnitude, fft[bin].toDouble());
      }
      final pitchClass = note.pitch;
      chroma[pitchClass] += math.sqrt(math.max(0.0, magnitude));
      counts[pitchClass]++;
    }
    for (var i = 0; i < chroma.length; i++) {
      if (counts[i] > 0) chroma[i] /= counts[i];
    }

    final targets = <double>[
      chroma[0] + chroma[1] * 0.5,
      chroma[2] + (chroma[1] + chroma[3]) * 0.5,
      chroma[4] + chroma[3] * 0.5,
      chroma[5] + chroma[6] * 0.5,
      chroma[7] + (chroma[6] + chroma[8]) * 0.5,
      chroma[9] + (chroma[8] + chroma[10]) * 0.5,
      chroma[11] + chroma[10] * 0.5,
    ];

    for (var i = 0; i < tones.length; i++) {
      var target = (targets[i] * 3.2).clamp(0.0, 1.0).toDouble();
      if (target < 0.025) target = 0.0;
      final smoothing = target > tones[i] ? 0.58 : 0.14;
      tones[i] += (target - tones[i]) * smoothing;
    }
  }

  void _updateFrequencyBands(Float32List fft) {
    for (var band = 0; band < frequencies.length; band++) {
      final start = _bands[band].start;
      final end = _bands[band].end;
      var peak = 0.0;
      for (var bin = start; bin < end; bin++) {
        peak = math.max(peak, fft[bin].toDouble());
      }
      var target =
          math.pow(peak * 11.0, 0.55).toDouble().clamp(0.0, 1.0).toDouble();
      if (target < 0.018) target = 0.0;
      final current = frequencies[band];
      final smoothing = target > current ? 0.34 : 0.15;
      frequencies[band] += (target - current) * smoothing;
    }
  }
}
