import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum FrameRateMode { display, adaptive, fixed }

@immutable
class FrameRatePreference {
  const FrameRatePreference({this.mode = FrameRateMode.display, this.fps = 60});
  final FrameRateMode mode;
  final int fps;

  factory FrameRatePreference.fromMap(Object? raw) {
    if (raw is! Map) return const FrameRatePreference();
    return FrameRatePreference(
      mode: FrameRateMode.values.firstWhere((v) => v.name == raw['mode'],
          orElse: () => FrameRateMode.display),
      fps: raw['fps'] is int && raw['fps'] >= 15 && raw['fps'] <= 1000
          ? raw['fps'] as int
          : 60,
    );
  }

  Map<String, Object> toMap() => {'mode': mode.name, 'fps': fps};
  double target(double displayHz, {required bool interacting}) =>
      switch (mode) {
        FrameRateMode.display => validDisplayRate(displayHz),
        FrameRateMode.adaptive =>
          math.min(validDisplayRate(displayHz), interacting ? 1000.0 : 60.0),
        FrameRateMode.fixed =>
          math.min(validDisplayRate(displayHz), fps.toDouble()),
      };
  @override
  bool operator ==(Object other) =>
      other is FrameRatePreference && other.mode == mode && other.fps == fps;
  @override
  int get hashCode => Object.hash(mode, fps);
}

double validDisplayRate(double rate) =>
    rate.isFinite && rate >= 15 && rate <= 1000 ? rate : 60;

/// Per-engine preference: the main player persists it and forwards it to helpers.
final frameRatePreference = ValueNotifier(const FrameRatePreference());
final windowDisplayRate = ValueNotifier<double?>(null);
final pauseWindowRendering = ValueNotifier(false);

/// Coalesces requests only; never produces an idle animation or changes audio
/// clocks. Requests still go through Flutter's normal engine/vsync lifecycle.
class FrameRequestPacer {
  FrameRequestPacer({required this.now, required this.emit});
  final Duration Function() now;
  final VoidCallback emit;
  Timer? _pending;
  Duration? _lastRequest;
  bool get pending => _pending != null;

  void request(double? fps) {
    if (_pending != null) return;
    final elapsed = now();
    final delay = fps == null || _lastRequest == null
        ? Duration.zero
        : Duration(microseconds: (1000000 / fps).round()) -
            (elapsed - _lastRequest!);
    if (delay <= Duration.zero) {
      _lastRequest = elapsed;
      emit();
    } else {
      _pending = Timer(delay, () {
        _pending = null;
        _lastRequest = now();
        emit();
      });
    }
  }

  void cancel() {
    _pending?.cancel();
    _pending = null;
  }

  void reset() {
    cancel();
    _lastRequest = null;
  }
}

/// One binding for main, mini, lyric and palette engines. Native resize and
/// forced lifecycle frames retain Flutter's immediate handling. This is an
/// application frame target, not a change to the monitor's hardware refresh.
class FramePacedWidgetsBinding extends WidgetsFlutterBinding {
  final _clock = Stopwatch()..start();
  late final _pacer = FrameRequestPacer(now: () => _clock.elapsed, emit: _emit);
  Duration? _interaction;

  FramePacedWidgetsBinding() {
    frameRatePreference.addListener(_reconfigure);
    pauseWindowRendering.addListener(() {
      _pacer.reset();
      if (!pauseWindowRendering.value) scheduleFrame();
    });
    pointerRouter.addGlobalRoute(_pointer);
    HardwareKeyboard.instance.addHandler(_key);
    const channel = MethodChannel('dan_player/frame_display');
    void update(Object? raw) {
      windowDisplayRate.value =
          raw is num && raw >= 15 && raw <= 1000 ? raw.toDouble() : null;
      _reconfigure();
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') update(call.arguments);
    });
    channel
        .invokeMethod<Object?>('refreshRate')
        .then(update, onError: (Object _) {});
  }

  double get displayRate =>
      windowDisplayRate.value ??
      validDisplayRate(
          platformDispatcher.implicitView?.display.refreshRate ?? 60);

  double? get _target {
    final preference = frameRatePreference.value;
    final hz = displayRate;
    final active = _interaction != null &&
        _clock.elapsed - _interaction! < const Duration(milliseconds: 800);
    final target = preference.target(hz, interacting: active);
    final engineHz = validDisplayRate(
        platformDispatcher.implicitView?.display.refreshRate ?? 60);
    // The Windows engine may retain the primary display's vsync cadence after
    // a cross-screen move. A lower-rate destination still needs a software cap.
    return target >= engineHz ? null : target;
  }

  void _emit() {
    super.scheduleFrame();
  }

  void _reconfigure() {
    final pending = _pacer.pending;
    _pacer.reset();
    if (pending) scheduleFrame();
  }

  void _interact() {
    _interaction = _clock.elapsed;
    if (frameRatePreference.value.mode == FrameRateMode.adaptive) {
      _reconfigure();
    }
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerHoverEvent ||
        event is PointerSignalEvent ||
        event is PointerPanZoomUpdateEvent) {
      _interact();
    }
  }

  bool _key(KeyEvent event) {
    _interact();
    return false;
  }

  @override
  bool get framesEnabled => super.framesEnabled && !pauseWindowRendering.value;

  @override
  void scheduleFrame() {
    if (hasScheduledFrame || !framesEnabled) return;
    _pacer.request(_target);
  }

  @override
  void scheduleForcedFrame() {
    _pacer.reset();
    super.scheduleForcedFrame();
  }

  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    _pacer.reset();
    super.handleAppLifecycleStateChanged(state);
  }

  @override
  void handleMetricsChanged() {
    _pacer.reset();
    super.handleMetricsChanged();
  }
}
