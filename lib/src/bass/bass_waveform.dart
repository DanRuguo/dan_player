import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'bass.dart' as bass;
import 'bass_diagnostics.dart';

/// Cancellation is cooperative: the worker frees its own decoder and buffer.
/// Killing an isolate during native decoding would skip those finally blocks.
class WaveformCancellation {
  bool cancelled = false;
  void Function()? _onCancel;
  void cancel() {
    cancelled = true;
    _onCancel?.call();
  }
}

class WaveformData {
  WaveformData(this.duration, Iterable<double> peaks)
      : peaks = List<double>.unmodifiable(peaks);
  final double duration;
  final List<double> peaks;
}

/// The player may still report an estimated VBR length. Preserve seconds on
/// the seek axis instead of stretching a precisely scanned envelope to fit.
List<double> waveformPeaksForDuration(
    WaveformData data, double visibleDuration) {
  if (!visibleDuration.isFinite ||
      visibleDuration <= 0 ||
      !data.duration.isFinite ||
      data.duration <= 0 ||
      data.peaks.isEmpty) {
    return const [];
  }
  if ((visibleDuration - data.duration).abs() < .001) return data.peaks;
  final count = data.peaks.length;
  final ratio = visibleDuration / data.duration;
  if (!ratio.isFinite) return const [];
  return List<double>.unmodifiable(List.generate(count, (index) {
    final start = (index * ratio).floor();
    if (start >= count) return 0.0;
    final end = math.max(
        start + 1, math.min(count.toDouble(), (index + 1) * ratio).ceil());
    var peak = 0.0;
    for (var source = start; source < end; source++) {
      peak = math.max(peak, data.peaks[source]);
    }
    return peak;
  }));
}

class WaveformDecodeRequest {
  const WaveformDecodeRequest(this.libraryPath, this.filePath,
      {this.start = 0, this.end});
  final String libraryPath;
  final String filePath;
  final double start;
  final double? end;
}

enum WaveformFailure { online, missing, tooLong, decode, changed, interrupted }

class WaveformUnavailable implements Exception {
  const WaveformUnavailable(this.reason);
  final WaveformFailure reason;
}

/// True amplitude envelope; it is neither an FFT nor LUFS loudness analysis.
/// Frames from all channels enter the same time bucket without downmix phase
/// cancellation. Retains a little peak energy alongside RMS for transients.
class WaveformAccumulator {
  WaveformAccumulator(this.frames, this.channels, {this.bins = 512})
      : _squares = List.filled(bins, 0),
        _peaks = List.filled(bins, 0),
        _counts = List.filled(bins, 0) {
    if (frames <= 0 || channels <= 0 || bins <= 0 || bins > 512) {
      throw ArgumentError('Invalid waveform dimensions');
    }
  }
  final int frames;
  final int channels;
  final int bins;
  final List<double> _squares;
  final List<double> _peaks;
  final List<int> _counts;
  int _samples = 0;
  void add(Iterable<double> samples) {
    for (final raw in samples) {
      final frame = _samples++ ~/ channels;
      if (frame >= frames) break;
      final bin = math.min(bins - 1, frame * bins ~/ frames);
      final value = raw.isFinite ? raw.abs().clamp(0.0, 1.0) : 0.0;
      _squares[bin] += value * value;
      _peaks[bin] = math.max(_peaks[bin], value);
      _counts[bin]++;
    }
  }

  List<double> finish() {
    final energy = List<double>.generate(
        bins,
        (i) => _counts[i] == 0
            ? 0
            : .65 * math.sqrt(_squares[i] / _counts[i]) + .35 * _peaks[i]);
    final max = energy.fold<double>(0, math.max);
    if (max == 0) return energy;
    return energy
        .map((value) => math.pow(value / max, .65).toDouble())
        .toList();
  }
}

Future<WaveformData?> decodeBassWaveform(
    WaveformDecodeRequest request, WaveformCancellation cancellation) async {
  if (cancellation.cancelled) return null;
  final result = Completer<WaveformData?>();
  final receive = ReceivePort();
  SendPort? commands;
  cancellation._onCancel = () => commands?.send('cancel');
  final subscription = receive.listen((message) {
    if (result.isCompleted) return;
    if (message is SendPort) {
      commands = message;
      if (cancellation.cancelled) commands!.send('cancel');
    } else if (message is Map) {
      if (message['failure'] != null) {
        result.completeError(WaveformUnavailable(message['failure'] == 'tooLong'
            ? WaveformFailure.tooLong
            : WaveformFailure.decode));
      } else if (cancellation.cancelled || message['cancelled'] == true) {
        result.complete(null);
      } else {
        result.complete(WaveformData((message['duration'] as num).toDouble(),
            (message['peaks'] as List).cast<double>()));
      }
    } else {
      result.completeError(const WaveformUnavailable(WaveformFailure.decode));
    }
  });
  try {
    await Isolate.spawn(_waveformWorker, (receive.sendPort, request),
        onError: receive.sendPort,
        onExit: receive.sendPort,
        debugName: 'local-waveform');
    return await result.future;
  } finally {
    cancellation._onCancel = null;
    await subscription.cancel();
    receive.close();
  }
}

Future<void> _waveformWorker((SendPort, WaveformDecodeRequest) input) async {
  final (reply, request) = input;
  final commands = ReceivePort();
  var cancelled = false;
  final listener = commands.listen((_) => cancelled = true);
  reply.send(commands.sendPort);
  DynamicLibrary? library;
  Pointer<Void>? name;
  Pointer<Float>? buffer;
  Pointer<BassChannelInfo>? info;
  bass.Bass? api;
  var handle = 0;
  Map<String, Object> outcome = {'failure': 'decode'};
  final watch = Stopwatch()..start();
  try {
    library = DynamicLibrary.open(request.libraryPath);
    api = bass.Bass(library);
    // Device zero is BASS's no-output decoder device. Thread-local selection
    // does not switch the player's output. Never call BASS_Free here: BASS
    // state/plugins belong to the shared process, only this handle is ours.
    final setDevice =
        library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'BASS_SetDevice');
    if (setDevice(0) == 0) {
      if (api.BASS_Init(0, 44100, 0, nullptr, nullptr) == 0 &&
          api.BASS_ErrorGetCode() != bass.BASS_ERROR_ALREADY) {
        throw const WaveformUnavailable(WaveformFailure.decode);
      }
      if (setDevice(0) == 0) {
        throw const WaveformUnavailable(WaveformFailure.decode);
      }
    }
    name = request.filePath.toNativeUtf16().cast<Void>();
    // Exact MPEG length/seeks keep CUE boundaries on the source time axis.
    // PRESCAN is local to this decoder; no shared BASS config is changed.
    const streamPrescan = 0x20000;
    handle = api.BASS_StreamCreateFile(
        bass.FALSE,
        name,
        0,
        0,
        bass.BASS_UNICODE |
            bass.BASS_STREAM_DECODE |
            bass.BASS_SAMPLE_FLOAT |
            streamPrescan);
    if (handle == 0) throw const WaveformUnavailable(WaveformFailure.decode);
    final getInfo = library.lookupFunction<
        Int32 Function(Uint32, Pointer<BassChannelInfo>),
        int Function(int, Pointer<BassChannelInfo>)>('BASS_ChannelGetInfo');
    info = calloc<BassChannelInfo>();
    if (getInfo(handle, info) == 0 ||
        info.ref.channels < 1 ||
        info.ref.channels > 32 ||
        info.ref.frequency < 1) {
      throw const WaveformUnavailable(WaveformFailure.decode);
    }
    final bytes = api.BASS_ChannelGetLength(handle, bass.BASS_POS_BYTE);
    if (bytes <= 0 || bytes > (1 << 62)) {
      throw const WaveformUnavailable(WaveformFailure.decode);
    }
    final length = api.BASS_ChannelBytes2Seconds(handle, bytes);
    final end = request.end ?? length;
    if (!length.isFinite ||
        !request.start.isFinite ||
        !end.isFinite ||
        request.start < 0 ||
        end <= request.start ||
        end > length + 1 / 75) {
      throw const WaveformUnavailable(WaveformFailure.decode);
    }
    final duration = math.min(end, length) - request.start;
    if (duration > 7200) {
      throw const WaveformUnavailable(WaveformFailure.tooLong);
    }
    final channels = info.ref.channels;
    final startByte = api.BASS_ChannelSeconds2Bytes(handle, request.start);
    final endByte =
        api.BASS_ChannelSeconds2Bytes(handle, math.min(end, length));
    if (api.BASS_ChannelSetPosition(handle, startByte, bass.BASS_POS_BYTE) ==
        0) {
      throw const WaveformUnavailable(WaveformFailure.decode);
    }
    final frameBytes = channels * sizeOf<Float>();
    var remaining = (endByte - startByte) ~/ frameBytes * frameBytes;
    final accumulator = WaveformAccumulator(remaining ~/ frameBytes, channels);
    const samples = 32768;
    buffer = calloc<Float>(samples);
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    while (remaining > 0) {
      // Give cancellation a turn between bounded reads; no full PCM is retained.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (cancelled) {
        outcome = {'cancelled': true};
        return;
      }
      if (watch.elapsed > const Duration(seconds: 120)) {
        throw const WaveformUnavailable(WaveformFailure.tooLong);
      }
      final wanted = math.min(remaining, samples * sizeOf<Float>()) ~/
          frameBytes *
          frameBytes;
      final read = getData(handle, buffer.cast<Void>(), wanted);
      if (read <= 0 ||
          read == 0xffffffff ||
          read > wanted ||
          read % frameBytes != 0) {
        // An incomplete decode is never cached as a convincing full waveform.
        throw const WaveformUnavailable(WaveformFailure.decode);
      }
      accumulator.add(buffer.asTypedList(read ~/ sizeOf<Float>()));
      remaining -= read;
    }
    outcome = {'duration': duration, 'peaks': accumulator.finish()};
  } catch (error) {
    outcome = {
      'failure': error is WaveformUnavailable &&
              error.reason == WaveformFailure.tooLong
          ? 'tooLong'
          : 'decode'
    };
  } finally {
    if (handle != 0) api?.BASS_StreamFree(handle);
    if (name != null) malloc.free(name);
    if (buffer != null) calloc.free(buffer);
    if (info != null) calloc.free(info);
    library?.close();
    await listener.cancel();
    commands.close();
    reply.send(outcome);
  }
}
