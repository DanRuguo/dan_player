import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dan_player/play_service/silence_skip_preferences.dart';
import 'package:ffi/ffi.dart';

import 'bass.dart';
import 'bass_diagnostics.dart';

/// Absolute source coordinates; the public song length and seek range remain
/// the original file's. No silence inside this interval is removed.
class BassSilenceBounds {
  const BassSilenceBounds(this.start, this.end, this.duration);
  final double start, end, duration;
}

/// Analyses an uncommitted decoding stream. Its caller retains native ownership
/// until [result] completes, including cancellation. Cancellation is cooperative
/// between bounded reads; a blocked native read is never freed underneath it.
class BassSilenceScan {
  BassSilenceScan(
      String libraryPath, int handle, SilenceSkipPreferences settings,
      {Duration timeout = const Duration(seconds: 2)}) {
    _subscription = _events.listen((message) {
      if (message is SendPort) {
        _commands = message;
        if (_cancelled) message.send(null);
      } else if (message is List && message.length == 3) {
        _finish(_cancelled
            ? null
            : BassSilenceBounds(message[0] as double, message[1] as double,
                message[2] as double));
      } else {
        _finish(null);
      }
    });
    _timer = Timer(timeout, cancel);
    unawaited(() async {
      try {
        // Never force-kill a worker that may still be using the native stream.
        await Isolate.spawn(
            _scan,
            (
              _events.sendPort,
              libraryPath,
              handle,
              settings,
              timeout.inMilliseconds
            ),
            onError: _events.sendPort,
            onExit: _events.sendPort,
            errorsAreFatal: true,
            debugName: 'bass-edge-silence');
      } catch (_) {
        _finish(null);
      }
    }());
  }

  final _events = ReceivePort();
  final _completion = Completer<BassSilenceBounds?>();
  late final StreamSubscription<dynamic> _subscription;
  Timer? _timer;
  SendPort? _commands;
  bool _cancelled = false;
  Future<BassSilenceBounds?> get result => _completion.future;

  void cancel() {
    _cancelled = true;
    _commands?.send(null);
  }

  void _finish(BassSilenceBounds? bounds) {
    if (_completion.isCompleted) return;
    _timer?.cancel();
    _events.close();
    unawaited(_subscription.cancel());
    _completion.complete(bounds);
  }
}

Future<void> _scan(
    (SendPort, String, int, SilenceSkipPreferences, int) request) async {
  final (reply, libraryPath, handle, settings, timeoutMs) = request;
  final commands = ReceivePort();
  var cancelled = false;
  final subscription = commands.listen((_) => cancelled = true);
  reply.send(commands.sendPort);
  final clock = Stopwatch()..start();
  DynamicLibrary? library;
  Pointer<Float>? buffer;
  BassSilenceBounds? bounds;
  try {
    library = DynamicLibrary.open(libraryPath);
    final api = Bass(library);
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    final format = readBassChannelFormat(library, handle);
    if (format == null ||
        format.channels < 1 ||
        format.channels > 8 ||
        format.sampleRate <= 0 ||
        format.sampleRate > 384000) return;
    // This optional local-file path never requests a whole-file PRESCAN.
    // BASS's ordinary MPEG seek and length can be approximate even when the
    // reported position matches the request. Do not infer trim coordinates
    // from those streams or scan the unbounded middle to build a seek table.
    if (const {0x10003, 0x10004, 0x10005}.contains(format.decoderType)) return;
    final duration = api.BASS_ChannelBytes2Seconds(
        handle, api.BASS_ChannelGetLength(handle, BASS_POS_BYTE));
    if (!duration.isFinite || duration < 1 || duration > 86400) return;
    final rate = format.sampleRate;
    final channels = format.channels;
    const chunkFrames = 4096;
    buffer = calloc<Float>(chunkFrames * channels);
    final threshold = math.pow(
        10, SilenceSkipPreferences.safeThreshold(settings.thresholdDb) / 20);
    final windowFrames = math.max(1, (rate * .005).round());
    final maximum =
        SilenceSkipPreferences.safeScanSeconds(settings.scanSeconds);
    bool active() => !cancelled && clock.elapsedMilliseconds < timeoutMs;

    Future<({double? first, double? last})?> readEdge(
        double start, double seconds,
        {required bool stopAtFirst}) async {
      if (!active() ||
          api.BASS_ChannelSetPosition(
                  handle,
                  api.BASS_ChannelSeconds2Bytes(handle, start),
                  BASS_POS_BYTE) ==
              0) return null;
      final actualBytes = api.BASS_ChannelGetPosition(handle, BASS_POS_BYTE);
      if (actualBytes < 0) return null;
      final actualStart = api.BASS_ChannelBytes2Seconds(handle, actualBytes);
      if (!actualStart.isFinite || (actualStart - start).abs() > 1.1 / rate) {
        return null;
      }
      final requested =
          ((math.min(duration, start + seconds) - actualStart) * rate).floor();
      var offset = 0, inWindow = 0, consecutive = 0;
      var peak = 0.0;
      double? first, last;
      while (offset < requested && active()) {
        final frames = math.min(chunkFrames, requested - offset);
        final bytes =
            getData(handle, buffer!.cast<Void>(), frames * channels * 4);
        if (bytes <= 0 || bytes == 0xffffffff) return null;
        final readFrames = bytes ~/ (channels * 4);
        if (readFrames <= 0 || readFrames > frames) return null;
        for (var frame = 0; frame < readFrames; frame++) {
          for (var channel = 0; channel < channels; channel++) {
            final value = buffer[frame * channels + channel].abs();
            if (!value.isFinite) return null;
            peak = math.max(peak, value);
          }
          inWindow++;
          if (inWindow == windowFrames) {
            consecutive = peak >= threshold ? consecutive + 1 : 0;
            if (consecutive >= 2) {
              final windowEnd = actualStart + (offset + frame + 1) / rate;
              first ??= windowEnd - 2 * windowFrames / rate;
              last = windowEnd;
              if (stopAtFirst) return (first: first, last: last);
            }
            inWindow = 0;
            peak = 0;
          }
        }
        offset += readFrames;
        // Deliver cancellation messages without blocking Flutter's isolate.
        await Future<void>.delayed(Duration.zero);
      }
      return active() ? (first: first, last: last) : null;
    }

    final head =
        await readEdge(0, math.min(duration, maximum), stopAtFirst: true);
    if (head == null || !active()) return;
    final tailStart = math.max(0.0, duration - maximum);
    final tail =
        await readEdge(tailStart, duration - tailStart, stopAtFirst: false);
    if (tail == null || !active()) return;
    // If an edge contains no confirmed sound, leave that edge intact rather
    // than guessing that an unscanned region or an entirely silent file is safe.
    var start = head.first == null ? 0.0 : math.max(0.0, head.first! - .020);
    var end =
        tail.last == null ? duration : math.min(duration, tail.last! + .020);
    if (start < .03) start = 0;
    if (duration - end < .03) end = duration;
    if (end - start < .5 || (start == 0 && end == duration)) return;
    bounds = BassSilenceBounds(start, end, duration);
  } catch (_) {
    // Optional analysis must leave normal source loading available.
  } finally {
    if (buffer != null) calloc.free(buffer);
    library?.close();
    commands.close();
    await subscription.cancel();
    reply.send(
        bounds == null ? null : [bounds.start, bounds.end, bounds.duration]);
  }
}
