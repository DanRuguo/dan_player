import 'dart:ffi';
import 'dart:math' as math;

import 'bass.dart';
import 'bass_mix.dart';

/// Output-time policy, independent of a device, timer, or source sample rate.
class BassTransitionTiming {
  const BassTransitionTiming._(this.remainingSeconds, this.fadeSeconds);

  final double remainingSeconds;
  final double fadeSeconds;
  double get delaySeconds => remainingSeconds - fadeSeconds;
  bool get isGapless => fadeSeconds == 0;

  static BassTransitionTiming? resolve(
      {required double remainingSeconds,
      double fadeSeconds = 0,
      double? nextDuration}) {
    if (!remainingSeconds.isFinite || remainingSeconds <= 0) return null;
    final requested =
        fadeSeconds.isFinite && fadeSeconds > 0 ? fadeSeconds : 0.0;
    final nextHalf =
        nextDuration != null && nextDuration.isFinite && nextDuration > 0
            ? nextDuration / 2
            : 0.0;
    return BassTransitionTiming._(remainingSeconds,
        math.min(requested, math.min(remainingSeconds, nextHalf)));
  }
}

class BassTransitionSchedule {
  const BassTransitionSchedule._(
      {required this.mixer,
      required this.current,
      required this.next,
      required this.startByte,
      required this.endByte,
      required this.fadeSeconds,
      required this.previousQueueFlags});

  final int mixer, current, next;
  final int startByte, endByte;
  final double fadeSeconds;
  final int previousQueueFlags;
  bool get isGapless => fadeSeconds == 0;
}

/// One staged successor on a persistent mixer. All coordinates/envelopes are
/// committed under the mixer's native lock; BASSmix advances them per sample.
/// Source creation/freeing, queue intent and audible handoff remain the caller's.
class BassTransitionMixer {
  static const int _positionDecode = 0x10000000;
  static const int _positionError = 0xffffffffffffffff;

  BassTransitionMixer(DynamicLibrary bass, this._mix)
      : _bass = Bass(bass),
        _lock = bass.lookupFunction<Int32 Function(Uint32, Int32),
            int Function(int, int)>('BASS_ChannelLock'),
        _flags = bass.lookupFunction<Uint32 Function(Uint32, Uint32, Uint32),
            int Function(int, int, int)>('BASS_ChannelFlags');

  final Bass _bass;
  final BassMixLibrary _mix;
  final int Function(int, int) _lock;
  final int Function(int, int, int) _flags;
  BassTransitionSchedule? _active;

  BassTransitionSchedule? get active => _active;

  BassTransitionSchedule? schedule(
      {required int mixer,
      required int current,
      required int next,
      required double Function() remainingSeconds,
      double fadeSeconds = 0,
      double? nextDuration}) {
    if (_active != null ||
        mixer == 0 ||
        current == 0 ||
        next == 0 ||
        current == next) {
      return null;
    }
    if (_lock(mixer, 1) == 0) return null;
    var added = false;
    var oldEnvelope = false;
    var queueChanged = false;
    var previous = 0;
    try {
      if (_mix.getChannelMixer(current) != mixer ||
          _mix.getChannelMixer(next) != 0) {
        return null;
      }
      final timing = BassTransitionTiming.resolve(
          remainingSeconds: remainingSeconds(),
          fadeSeconds: fadeSeconds,
          nextDuration: nextDuration);
      if (timing == null) return null;
      // A playable mixer may have buffered audio. ABSOLUTE scheduling follows
      // its decode cursor, rather than its earlier audible/playback cursor.
      final position =
          _bass.BASS_ChannelGetPosition(mixer, BASS_POS_BYTE | _positionDecode);
      final remainingBytes =
          _bass.BASS_ChannelSeconds2Bytes(mixer, timing.remainingSeconds);
      final fadeBytes =
          _bass.BASS_ChannelSeconds2Bytes(mixer, timing.fadeSeconds);
      if (position < 0 ||
          position == _positionError ||
          remainingBytes <= 0 ||
          fadeBytes < 0 ||
          fadeBytes > remainingBytes) {
        return null;
      }
      final gapless = timing.isGapless || fadeBytes == 0;
      final delayBytes = remainingBytes - (gapless ? 0 : fadeBytes);
      previous = _flags(mixer, 0, 0);
      if (previous == BassMixLibrary.errorValue) return null;
      if (_flags(mixer, gapless ? BassMixLibrary.queue : 0,
              BassMixLibrary.queue) ==
          BassMixLibrary.errorValue) {
        return null;
      }
      queueChanged = true;
      added = gapless
          ? _mix.addChannel(mixer, next, paused: false, noRampIn: true)
          : _mix.addChannelEx(mixer, next, startByte: position + delayBytes);
      if (!added) return null;
      if (!gapless) {
        oldEnvelope = _mix.setVolumeEnvelope(current, [
          (0, 1.0),
          if (delayBytes > 0) (delayBytes, 1.0),
          (remainingBytes, 0.0)
        ]);
        if (!oldEnvelope ||
            !_mix.setVolumeEnvelopePosition(current, 0) ||
            !_mix.setVolumeEnvelope(next, [(0, 0.0), (fadeBytes, 1.0)]) ||
            !_mix.setVolumeEnvelopePosition(next, 0)) {
          return null;
        }
      }
      return _active = BassTransitionSchedule._(
          mixer: mixer,
          current: current,
          next: next,
          startByte: position + delayBytes,
          endByte: position + remainingBytes,
          fadeSeconds: gapless ? 0 : timing.fadeSeconds,
          previousQueueFlags: previous & BassMixLibrary.queue);
    } finally {
      if (_active == null) {
        if (added) _mix.removeChannel(next);
        if (oldEnvelope) clearEnvelope(current);
        if (queueChanged) {
          _flags(mixer, previous & BassMixLibrary.queue, BassMixLibrary.queue);
        }
      }
      _lock(mixer, 0);
    }
  }

  bool _matches(int mixer, int current, int next) {
    final owner = _active;
    return owner != null &&
        owner.mixer == mixer &&
        owner.current == current &&
        owner.next == next;
  }

  /// Cancel only the still-owned preparation. Current volume attributes are
  /// untouched, including ReplayGain; removing the envelope restores its gain.
  bool cancel({required int mixer, required int current, required int next}) {
    if (!_matches(mixer, current, next) || _lock(mixer, 1) == 0) return false;
    try {
      final previous = _active!.previousQueueFlags;
      if (_mix.getChannelMixer(next) == mixer) _mix.removeChannel(next);
      if (_mix.getChannelMixer(current) == mixer) {
        clearEnvelope(current);
      }
      _flags(mixer, previous, BassMixLibrary.queue);
      _active = null;
      return true;
    } finally {
      _lock(mixer, 0);
    }
  }

  /// Retire Dart preparation ownership at audible handoff without changing
  /// either native envelope. The caller keeps the fading tail until its EOF.
  bool complete({required int mixer, required int current, required int next}) {
    if (!_matches(mixer, current, next)) return false;
    _active = null;
    return true;
  }

  /// Retire a fade with an already-completed unity envelope. Removing the
  /// envelope altogether makes BASSmix ramp back on the next decode call, even
  /// if NORAMP was briefly set during removal. Unity restores the underlying
  /// gain on the first sample without changing normal attribute ramp flags.
  /// A later fade replaces this single node; freeing the channel releases it.
  bool clearEnvelope(int source) {
    return _mix.setVolumeEnvelope(source, [(0, 1.0)]) &&
        _mix.setVolumeEnvelopePosition(source, 0);
  }
}
