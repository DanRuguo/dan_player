import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart';

/// Short visual interpolation of real FFT snapshots. It never changes the
/// audio clock or requests FFT samples; a settled or hidden surface stops.
class SpectrumLevelMotion extends ValueNotifier<List<double>> {
  SpectrumLevelMotion({required TickerProvider vsync}) : super(const []) {
    _controller = AnimationController(vsync: vsync)..addListener(_tick);
  }
  late final AnimationController _controller;
  List<double> _from = const [];
  List<double> _target = const [];
  bool _animate = false;

  set animate(bool enabled) {
    if (_animate == enabled) return;
    _animate = enabled;
    if (!enabled) {
      _controller.stop();
      _publish(_target);
    }
  }

  void update(List<double> samples) {
    double safe(double v) => v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
    if (samples.length == _target.length) {
      var same = true;
      for (var i = 0; i < samples.length; i++) {
        if (safe(samples[i]) != _target[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    final target = List<double>.unmodifiable(samples.map(safe));
    _target = target;
    if (!_animate) {
      _controller.stop();
      _publish(target);
      return;
    }
    _from = value;
    _controller.duration =
        target.every((v) => v == 0) ? AppMotion.quick : AppMotion.followSample;
    _controller.forward(from: 0);
  }

  static double _sample(List<double> values, int index, int count) {
    if (values.isEmpty) return 0;
    if (values.length == count) return values[index];
    final at = count <= 1 ? 0.0 : index / (count - 1) * (values.length - 1);
    final left = at.floor();
    final right = math.min(left + 1, values.length - 1);
    return values[left] + (values[right] - values[left]) * (at - left);
  }

  void _tick() {
    if (_controller.value == 1) {
      _publish(_target);
      return;
    }
    final t = AppMotion.standardCurve.transform(_controller.value);
    final count = math.max(_from.length, _target.length);
    _publish(List<double>.generate(count, (index) {
      final start = _sample(_from, index, count);
      return start + (_sample(_target, index, count) - start) * t;
    }, growable: false));
  }

  void _publish(List<double> next) {
    if (!listEquals(value, next)) value = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
