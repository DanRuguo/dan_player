import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:flutter/foundation.dart';

({double start, double end}) lyricPreviewRange(
    Lyric lyric, int index, double duration) {
  if (lyric is PlainLyric) return (start: 0, end: duration);
  final line = lyric.lines[index];
  final start = (line.start.inMicroseconds / 1e6).clamp(0.0, duration);
  var end = duration;
  if (line is SyncLyricLine && line.length > Duration.zero) {
    end = (line.start + line.length).inMicroseconds / 1e6;
    for (final word in line.words) {
      final wordEnd = (word.start + word.length).inMicroseconds / 1e6;
      if (wordEnd > end) end = wordEnd;
    }
  } else {
    for (final following in lyric.lines.skip(index + 1)) {
      if (following.start > line.start) {
        end = following.start.inMicroseconds / 1e6;
        break;
      }
    }
  }
  return (start: start, end: end.clamp(start, duration));
}

/// FFplay reports the audio master clock. Never derive lyric time from launch
/// wall time: codec startup, device buffers and seeking have variable latency.
class LyricPreviewClockParser {
  LyricPreviewClockParser(this.onPosition);
  final ValueChanged<double> onPosition;
  String _pending = '';
  void add(String chunk) {
    final rows = ('$_pending$chunk').split(RegExp(r'[\r\n]'));
    _pending = rows.removeLast();
    if (_pending.length > 4096) _pending = '';
    for (final row in rows) {
      final match =
          RegExp(r'^\s*([0-9]+\.[0-9]+)\s+(?:M-A|A-V|M-V):').firstMatch(row);
      final value = match == null ? null : double.tryParse(match[1]!);
      if (value != null && value.isFinite) onPosition(value);
    }
  }
}

class _LyricPreviewProcess implements TrimPreviewProcess {
  _LyricPreviewProcess(this.process, ValueChanged<double> onPosition) {
    final parser = LyricPreviewClockParser(onPosition);
    unawaited(process.stdout.drain<void>());
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(parser.add);
  }
  final Process process;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  void kill() => process.kill();
}

typedef LyricPreviewLauncher = Future<TrimPreviewProcess> Function(String file,
    double start, double duration, ValueChanged<double> onPosition);
Future<TrimPreviewProcess> launchLyricPreview(
    String file, double start, double duration, ValueChanged<double> onPosition,
    {double rate = 1}) async {
  if (![.25, .5, .75, 1.0].contains(rate)) {
    throw ArgumentError.value(rate, 'rate');
  }
  final executable = await audioToolPath('ffplay');
  final args = trimPreviewArguments(file, start, duration,
      volume: AppPreference.instance.playbackPref.volumeDsp);
  args[args.indexOf('-nostats')] = '-stats';
  args[args.indexOf('-loglevel') + 1] = 'info';
  if (rate != 1) {
    args.insertAll(args.indexOf('-i'), [
      '-af',
      '${rate == .25 ? 'atempo=0.5,atempo=0.5' : 'atempo=$rate'},asetpts=N/SR/TB'
    ]);
  }
  final process = await Process.start(executable, args, runInShell: false);
  await process.stdin.close();
  return _LyricPreviewProcess(process,
      rate == 1 ? onPosition : (time) => onPosition(start + time * rate));
}

/// Preview owns a decoder process, not a playlist entry or a lyric source. The
/// normal player is resumed only if the user has not changed it meanwhile.
typedef LyricPreviewDurationProbe = Future<double?> Function(Audio audio);

Future<double?> _probeLyricPreviewDuration(Audio audio) async {
  final executable = await audioToolPath('ffprobe');
  final output = await probeFfmpeg(executable, [
    '-v',
    'error',
    '-protocol_whitelist',
    'file,pipe',
    '-show_entries',
    'format=duration',
    '-of',
    'default=noprint_wrappers=1:nokey=1',
    audio.localFilePath
  ]);
  return double.tryParse(output.trim());
}

class LyricAudioPreview extends ChangeNotifier {
  LyricAudioPreview(this.audio,
      {LyricPreviewLauncher? launch,
      LyricPreviewDurationProbe? probeDuration,
      TrimMainPlayback? Function()? mainPlayback})
      : _launch = launch ?? launchLyricPreview,
        _durationProbe = probeDuration ?? _probeLyricPreviewDuration,
        _mainFactory = mainPlayback ?? existingPreviewMainPlayback {
    _decoder = ProcessAudioTrimPreview(audio,
        mainPlayback: () => null,
        onCompleted: () {
          if (_disposed || _closing != null) return;
          // Stats are periodic and need not include the final audio sample.
          // Seal this generation so buffered stderr cannot rewind the endpoint.
          ++_generation;
          _position = _rangeEnd;
          _positions.add(_position);
        },
        launch: (file, start, duration) {
          final token = _generation;
          return _launch(file, start, duration, (time) {
            if (_disposed || token != _generation) return;
            if (!time.isFinite) return;
            _clockReady = true;
            // Device-clock corrections must not move recorded media time back.
            _position = (time - _cueStart).clamp(_position, _rangeEnd);
            _positions.add(_position);
          });
        });
    _decoder.addListener(_changed);
  }
  final Audio audio;
  final LyricPreviewLauncher _launch;
  final LyricPreviewDurationProbe _durationProbe;
  final TrimMainPlayback? Function() _mainFactory;
  late final ProcessAudioTrimPreview _decoder;
  final _positions = StreamController<double>.broadcast(sync: true);
  Stream<double> get positionStream => _positions.stream;
  double _position = 0, _rangeStart = 0, _rangeEnd = 0;
  double get position => _position;
  bool _clockReady = false;
  bool get clockReady => _clockReady;
  double? _fileDuration;
  Future<void>? _prepareTask;
  double get duration => audio.cueTrack?.endSeconds != null
      ? audio.cueTrack!.endSeconds! - _cueStart
      : _fileDuration == null
          ? audio.duration.toDouble()
          : (_fileDuration! - _cueStart).clamp(0.0, double.infinity);
  double get _cueStart => audio.cueTrack?.startSeconds ?? 0;
  bool get playing => _decoder.playing;
  bool get loading => _decoder.loading;
  String? get error => _decoder.error;
  bool _disposed = false, _changingMain = false, _resumeMain = false;
  int _generation = 0;
  TrimMainPlayback? _main;
  Object? _mainTrack;
  double _mainPosition = 0;
  Future<void>? _closing;
  bool get _mainUntouched =>
      _main != null &&
      identical(_main!.track, _mainTrack) &&
      !_main!.playing &&
      (_main!.position - _mainPosition).abs() <= .15;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _mainChanged() {
    if (_changingMain || _mainUntouched) return;
    _resumeMain = false;
    unawaited(pause());
  }

  void _acquireMain() {
    if (_main != null) return;
    final main = _main = _mainFactory();
    if (main == null) return;
    _mainTrack = main.track;
    _resumeMain = main.playing;
    _changingMain = true;
    if (_resumeMain) main.pause();
    _mainPosition = main.position;
    _changingMain = false;
    main.addListener(_mainChanged);
  }

  Future<void> prepare() => _prepareTask ??= _probe().whenComplete(() {
        if (_fileDuration == null) _prepareTask = null;
      });

  Future<void> _probe() async {
    try {
      final value = await _durationProbe(audio);
      if (!_disposed && value != null && value.isFinite && value > 0) {
        _fileDuration = value;
      }
    } catch (_) {
      /* Playback still reports a useful decoder error, or uses library duration. */
    }
  }

  Future<void> play(double start, double end) async {
    if (_disposed ||
        _closing != null ||
        !start.isFinite ||
        !end.isFinite ||
        duration <= 0) {
      return;
    }
    _rangeStart = start.clamp(0.0, duration);
    _rangeEnd = end.clamp(_rangeStart, duration);
    if (_rangeEnd <= _rangeStart) return;
    ++_generation;
    _acquireMain();
    // A user play action during startup wins over this temporary decoder.
    if (_main?.playing == true) return;
    _position = _rangeStart;
    _clockReady = false;
    _positions.add(_position);
    await _decoder.play(_rangeStart + _cueStart, _rangeEnd + _cueStart);
  }

  Future<void> pause() async {
    ++_generation;
    await _decoder.stop();
  }

  Future<void> seekPaused(double value) async {
    if (_disposed || !value.isFinite) return;
    await pause();
    if (_disposed) return;
    _position = value.clamp(0.0, duration);
    _rangeStart = _position;
    _rangeEnd = duration;
    _positions.add(_position);
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    ++_generation;
    await _decoder.stop();
    final main = _main;
    final resume = _resumeMain && _mainUntouched;
    _main = null;
    _resumeMain = false;
    main?.removeListener(_mainChanged);
    if (resume) main!.resume();
    main?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _decoder.removeListener(_changed);
    unawaited(close().whenComplete(() {
      _decoder.dispose();
      _positions.close();
    }));
    super.dispose();
  }
}
