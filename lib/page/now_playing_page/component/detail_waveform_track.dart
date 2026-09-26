import 'dart:math' as math;

import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:flutter/material.dart';

/// A bounded snapshot of decoded peak amplitudes. Oversized input retains the
/// complete timeline by taking the largest peak within each output bucket.
List<double> boundedWaveformPeaks(List<double> input) {
  if (input.isEmpty) return const [];
  final count = math.min(512, input.length);
  return List<double>.unmodifiable(List.generate(count, (index) {
    final start = index * input.length ~/ count;
    final end = (index + 1) * input.length ~/ count;
    var peak = 0.0;
    for (var sample = start; sample < end; sample++) {
      final value = input[sample];
      if (value.isFinite) peak = math.max(peak, value.clamp(0.0, 1.0));
    }
    return peak;
  }));
}

/// Automatic mode preserves physical bar width. Fixed modes preserve the
/// requested count while adapting both bars and gaps to the track width.
({int count, double step, double width}) waveformBarLayout(
    double trackWidth, WaveformBarDensity density) {
  if (!trackWidth.isFinite ||
      trackWidth <= 0 ||
      (density == WaveformBarDensity.automatic && trackWidth < 3)) {
    return (count: 0, step: 0, width: 0);
  }
  final count = switch (density) {
    WaveformBarDensity.automatic =>
      math.min(512, math.max(1, (trackWidth / 3).floor())),
    WaveformBarDensity.sparse => 48,
    WaveformBarDensity.medium => 96,
    WaveformBarDensity.dense => 192,
  };
  final step = trackWidth / count;
  final width = density == WaveformBarDensity.automatic ? 2.25 : step * .65;
  return (count: count, step: step, width: width);
}

/// Keeps one projection for the current physical bar count. Seeking and
/// morphing reuse it; only source data, density or width can require rebucketing.
class WaveformTrackSource {
  WaveformTrackSource(this.peaks, this.density);
  final List<double> peaks;
  final WaveformBarDensity density;
  int _count = -1;
  List<double> _buckets = const [];
  ({
    double width,
    double trackHeight,
    double parentHeight,
    double growth,
    bool rtl
  })? _pathGeometry;
  Path? _path;
  List<double> buckets(int count) {
    if (_count == count) return _buckets;
    _count = count;
    return _buckets = List.generate(count, (bucket) {
      final start = bucket * peaks.length ~/ count;
      final end = math.max(start + 1, (bucket + 1) * peaks.length ~/ count);
      var peak = 0.0;
      for (var index = start; index < end; index++) {
        peak = math.max(peak, peaks[index]);
      }
      return peak;
    });
  }

  /// Interpolate neighboring displayed columns, including coarse max buckets.
  double amplitudeAt(double position, int count) {
    if (count <= 0 || peaks.isEmpty) return 0;
    final values = buckets(count);
    final index =
        (position.clamp(0.0, 1.0) * count - .5).clamp(0.0, count - 1.0);
    final left = index.floor();
    final right = math.min(count - 1, left + 1);
    return values[left] + (values[right] - values[left]) * (index - left);
  }

  /// Position changes only move the active clip and handle. The bar contour
  /// is reused until width, shape growth, density or track emphasis changes.
  Path barPath(
      {required double width,
      required double trackHeight,
      required double parentHeight,
      required double growth,
      required bool rtl}) {
    final geometry = (
      width: width,
      trackHeight: trackHeight,
      parentHeight: parentHeight,
      growth: growth,
      rtl: rtl
    );
    if (_pathGeometry == geometry) return _path!;
    _pathGeometry = geometry;
    final layout = waveformBarLayout(width, density);
    final amplitudes = buckets(layout.count);
    final path = Path();
    for (var index = 0; index < layout.count; index++) {
      final bucket = rtl ? layout.count - index - 1 : index;
      final half = waveformBarHalfHeight(
          trackHeight, parentHeight, amplitudes[bucket], growth);
      path.addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(layout.step * (index + .5), 0),
              width: layout.width,
              height: half * 2),
          Radius.circular(layout.width / 2)));
    }
    return _path = path;
  }
}

double waveformBarHalfHeight(
    double trackHeight, double parentHeight, double amplitude, double growth) {
  final base = math.max(.75, trackHeight / 2);
  final maximum = math.max(base, math.min(12.0, parentHeight / 2 - 4));
  return base + (maximum - base) * amplitude * growth;
}

double waveformHandleHeight(WaveformTrackVisual visual,
    {required double position,
    required double trackWidth,
    required double trackHeight,
    required double parentHeight,
    double emphasis = 0}) {
  var result = 18.0 * visual.lineOpacity;
  for (final layer in visual.layers) {
    final count = waveformBarLayout(trackWidth, layer.source.density).count;
    final height = count == 0
        ? 18.0
        : math.max(
            8.0,
            4 +
                2 *
                    waveformBarHalfHeight(
                        trackHeight,
                        parentHeight,
                        layer.source.amplitudeAt(position, count),
                        layer.growth));
    result += height * layer.opacity;
  }
  return result + 3 * emphasis;
}

class WaveformTrackLayer {
  const WaveformTrackLayer(this.source, this.opacity, this.growth);
  final WaveformTrackSource source;
  final double opacity, growth;
}

/// A captured visual can be retargeted in the middle of a finite transition.
/// Layers are merged by source identity so repeated density toggles stay small.
class WaveformTrackVisual {
  const WaveformTrackVisual(this.lineOpacity, this.layers);
  const WaveformTrackVisual.line()
      : lineOpacity = 1,
        layers = const [];
  factory WaveformTrackVisual.wave(WaveformTrackSource source) =>
      WaveformTrackVisual(0, [WaveformTrackLayer(source, 1, 1)]);
  final double lineOpacity;
  final List<WaveformTrackLayer> layers;
  static WaveformTrackVisual interpolate(
      WaveformTrackVisual from, WaveformTrackVisual to, double mix) {
    if (mix <= 0) return from;
    if (mix >= 1) return to;
    final merged = <WaveformTrackSource, (double, double)>{};
    void add(WaveformTrackSource source, double opacity, double growth) {
      if (opacity < .0001) return;
      final existing = merged[source] ?? (0.0, 0.0);
      merged[source] = (existing.$1 + opacity, existing.$2 + opacity * growth);
    }

    final growing = to.layers.isNotEmpty;
    var startGrowth = 0.0;
    for (final layer in from.layers) {
      startGrowth = math.max(startGrowth, layer.growth);
      add(layer.source, layer.opacity * (1 - mix),
          growing ? layer.growth : layer.growth * (1 - mix));
    }
    for (final layer in to.layers) {
      add(layer.source, layer.opacity * mix,
          startGrowth + (layer.growth - startGrowth) * mix);
    }
    return WaveformTrackVisual(
        from.lineOpacity * (1 - mix) + to.lineOpacity * mix, [
      for (final entry in merged.entries)
        WaveformTrackLayer(
            entry.key, entry.value.$1, entry.value.$2 / entry.value.$1)
    ]);
  }
}

/// Decoded amplitude bars share the stock track's center and seek geometry.
/// There is no ticker or invented waveform; empty data uses the stock line.
class DetailWaveformTrackShape extends RoundedRectSliderTrackShape {
  DetailWaveformTrackShape(
      {required List<double> peaks,
      WaveformBarDensity density = WaveformBarDensity.automatic})
      : visual = peaks.isEmpty
            ? const WaveformTrackVisual.line()
            : WaveformTrackVisual.wave(
                WaveformTrackSource(boundedWaveformPeaks(peaks), density));
  DetailWaveformTrackShape.visual(this.visual);

  final WaveformTrackVisual visual;
  ({
    double position,
    double width,
    double height,
    double parentHeight
  })? _paintedGeometry;

  /// Track painting precedes thumb painting. Share its exact preferred rect,
  /// thumb center and RTL mapping rather than estimating width during layout.
  double? handleHeight(double emphasis) {
    final geometry = _paintedGeometry;
    if (geometry == null) return null;
    return waveformHandleHeight(visual,
        position: geometry.position,
        trackWidth: geometry.width,
        trackHeight: geometry.height,
        parentHeight: geometry.parentHeight,
        emphasis: emphasis);
  }

  List<double> get peaks => visual.layers.lastOrNull?.source.peaks ?? const [];
  WaveformBarDensity get density =>
      visual.layers.lastOrNull?.source.density ?? WaveformBarDensity.automatic;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    void line(double opacity) {
      Color? fade(Color? color) => color?.withValues(alpha: color.a * opacity);
      super.paint(context, offset,
          parentBox: parentBox,
          sliderTheme: opacity == 1
              ? sliderTheme
              : sliderTheme.copyWith(
                  activeTrackColor: fade(sliderTheme.activeTrackColor),
                  inactiveTrackColor: fade(sliderTheme.inactiveTrackColor),
                  disabledActiveTrackColor:
                      fade(sliderTheme.disabledActiveTrackColor),
                  disabledInactiveTrackColor:
                      fade(sliderTheme.disabledInactiveTrackColor)),
          enableAnimation: enableAnimation,
          textDirection: textDirection,
          thumbCenter: thumbCenter,
          secondaryOffset: secondaryOffset,
          isDiscrete: isDiscrete,
          isEnabled: isEnabled,
          additionalActiveTrackHeight: additionalActiveTrackHeight);
    }

    if (visual.lineOpacity > 0) line(visual.lineOpacity);
    if (visual.layers.isEmpty) return;
    if ((sliderTheme.trackHeight ?? 0) <= 0) return;
    final track = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete);
    if (track.width <= 0) return;
    final physical =
        ((thumbCenter.dx - track.left) / track.width).clamp(0.0, 1.0);
    _paintedGeometry = (
      position: textDirection == TextDirection.rtl ? 1 - physical : physical,
      width: track.width,
      height: track.height,
      parentHeight: parentBox.size.height
    );
    for (final layer in visual.layers) {
      final layout = waveformBarLayout(track.width, layer.source.density);
      if (layout.count == 0) {
        line(layer.opacity);
        continue;
      }
      final base = math.max(.75, track.height / 2);
      final maximum =
          math.max(base, math.min(12.0, parentBox.size.height / 2 - 4));
      final rtl = textDirection == TextDirection.rtl;
      final bars = layer.source.barPath(
          width: track.width,
          trackHeight: track.height,
          parentHeight: parentBox.size.height,
          growth: layer.growth,
          rtl: rtl);
      final inactive = Color.lerp(sliderTheme.disabledInactiveTrackColor,
          sliderTheme.inactiveTrackColor, enableAnimation.value)!;
      final active = Color.lerp(sliderTheme.disabledActiveTrackColor,
          sliderTheme.activeTrackColor, enableAnimation.value)!;
      final canvas = context.canvas;
      final paint = Paint()
        ..color = inactive.withValues(alpha: inactive.a * layer.opacity);
      canvas.save();
      canvas.translate(track.left, track.center.dy);
      canvas.drawPath(bars, paint);
      // Clip at the real thumb location, so an in-progress bar does not color
      // ahead of playback and RTL seeks use the same time direction as Slider.
      final progress =
          thumbCenter.dx.clamp(track.left, track.right) - track.left;
      canvas.clipRect(Rect.fromLTRB(
          rtl ? progress : 0, -maximum, rtl ? track.width : progress, maximum));
      paint.color = active.withValues(alpha: active.a * layer.opacity);
      canvas.drawPath(bars, paint);
      canvas.restore();
    }
  }
}
