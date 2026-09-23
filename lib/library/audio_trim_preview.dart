import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/foundation.dart';

/// Small injectable boundaries keep preview tests independent of native audio.
abstract class AudioTrimPreview extends ChangeNotifier {
  bool get playing;
  bool get loading;
  String? get error;
  Future<void> play(double start, double end);
  Future<void> stop();
}

abstract class TrimMainPlayback extends ChangeNotifier {
  Object? get track;
  bool get playing;
  double get position;
  void pause();
  void resume();
}

abstract interface class TrimPreviewProcess {
  Future<int> get exitCode;
  void kill();
}

typedef TrimPreviewLauncher = Future<TrimPreviewProcess> Function(
    String file, double start, double duration);

class _NativePreviewProcess implements TrimPreviewProcess {
  _NativePreviewProcess(this.process) {
    // Both pipes must be drained even when the decoder reports many errors.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
  }
  final Process process;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  void kill() => process.kill();
}

List<String> trimPreviewArguments(String file, double start, double duration,
        {required double volume}) =>
    [
      '-protocol_whitelist',
      'file,pipe',
      '-volume',
      ((volume.isFinite ? volume : 1) * 100).round().clamp(0, 100).toString(),
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostats',
      '-nodisp',
      '-autoexit',
      '-ss',
      start.toStringAsFixed(6),
      '-t',
      duration.toStringAsFixed(6),
      '-i',
      file,
    ];

Future<TrimPreviewProcess> _launchPreview(
    String file, double start, double duration) async {
  final executable = await audioToolPath('ffplay');
  try {
    return _NativePreviewProcess(await Process.start(
        executable,
        trimPreviewArguments(file, start, duration,
            volume: AppPreference.instance.playbackPref.volumeDsp),
        runInShell: false));
  } on ProcessException {
    FfmpegRuntime.shared.invalidate();
    throw const AudioTrimException('tools', '请先安装或修复裁剪组件');
  }
}

class _ExistingMainPlayback extends TrimMainPlayback {
  _ExistingMainPlayback(this.service) {
    service.addListener(notifyListeners);
    _state = service.playerStateStream.listen((_) => notifyListeners());
    _position = service.positionStream.listen((_) => notifyListeners());
  }
  final PlaybackService service;
  late final StreamSubscription<dynamic> _state;
  late final StreamSubscription<dynamic> _position;
  @override
  Object? get track => service.nowPlaying;
  @override
  bool get playing =>
      service.playerState == PlayerState.playing ||
      service.playerState == PlayerState.stalled;
  @override
  double get position => service.position;
  @override
  void pause() => service.pause();
  @override
  void resume() => service.start();
  @override
  void dispose() {
    service.removeListener(notifyListeners);
    unawaited(_state.cancel());
    unawaited(_position.cancel());
    super.dispose();
  }
}

TrimMainPlayback? _existingMainPlayback() => PlayService.playbackReady.value
    ? _ExistingMainPlayback(PlayService.instance.playbackService)
    : null;

/// FFplay owns only its own process. In particular this never constructs or
/// frees a second BASS engine, whose native resources are process-global.
class ProcessAudioTrimPreview extends AudioTrimPreview {
  ProcessAudioTrimPreview(Audio audio,
      {TrimPreviewLauncher? launch,
      TrimMainPlayback? Function()? mainPlayback,
      this.onCompleted})
      : _file = audio.localFilePath,
        _launch = launch ?? _launchPreview,
        _mainPlayback = mainPlayback ?? _existingMainPlayback;

  final String _file;
  final TrimPreviewLauncher _launch;
  final TrimMainPlayback? Function() _mainPlayback;

  /// Only a successful, current process exit; never a stop or replacement.
  final VoidCallback? onCompleted;
  TrimPreviewProcess? _process;
  Future<TrimPreviewProcess>? _pendingLaunch;
  Future<void>? _stopping;
  TrimMainPlayback? _main;
  Object? _track;
  double _position = 0;
  bool _resumeMain = false;
  bool _changingMain = false;
  bool _disposed = false;
  int _generation = 0;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  @override
  bool get playing => _playing;
  @override
  bool get loading => _loading;
  @override
  String? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> play(double start, double end) async {
    if (_disposed ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start) {
      return;
    }
    final token = ++_generation;
    await _stopResources();
    if (_disposed || token != _generation) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final main = _main = _mainPlayback();
      if (main != null) {
        _track = main.track;
        _resumeMain = main.playing;
        _changingMain = true;
        if (_resumeMain) main.pause();
        _position = main.position;
        _changingMain = false;
        main.addListener(_mainChanged);
        if (main.playing) throw StateError('Main playback did not pause');
      }
      final pending = _pendingLaunch = _launch(_file, start, end - start);
      final process = await pending;
      if (identical(_pendingLaunch, pending)) _pendingLaunch = null;
      if (_disposed || token != _generation) {
        process.kill();
        await process.exitCode;
        return;
      }
      _process = process;
      _loading = false;
      _playing = true;
      _notify();
      unawaited(_waitForExit(process, token));
    } catch (error) {
      if (token != _generation || _disposed) return;
      _pendingLaunch = null;
      _error = error is AudioTrimException
          ? error.message
          : '试听失败，请检查音频输出设备是否被独占，或稍后重试。';
      _loading = false;
      _playing = false;
      _releaseMain();
      _notify();
    }
  }

  bool get _mainUntouched {
    final main = _main;
    return main != null &&
        identical(main.track, _track) &&
        !main.playing &&
        (main.position - _position).abs() <= .15;
  }

  void _mainChanged() {
    if (_changingMain || _mainUntouched) return;
    // A user's play/seek/track action wins, including during process startup.
    _resumeMain = false;
    unawaited(stop());
  }

  void _releaseMain() {
    final main = _main;
    if (main == null) return;
    final resume = _resumeMain && _mainUntouched;
    _main = null;
    _resumeMain = false;
    main.removeListener(_mainChanged);
    if (resume) main.resume();
    main.dispose();
  }

  Future<void> _waitForExit(TrimPreviewProcess process, int token) async {
    final code = await process.exitCode;
    if (_disposed || token != _generation) return;
    _process = null;
    _playing = false;
    if (code != 0) {
      _error = '试听失败，请检查音频输出设备是否被独占，或稍后重试。';
      if (code < 0 || code > 255) {
        FfmpegRuntime.shared.invalidate();
        _error = '请先安装或修复裁剪组件';
      }
    }
    _releaseMain();
    if (code == 0) onCompleted?.call();
    _notify();
  }

  @override
  Future<void> stop() {
    ++_generation;
    return _stopResources();
  }

  Future<void> _stopResources() {
    final existing = _stopping;
    if (existing != null) return existing;
    final work = _stopResourcesImpl();
    _stopping = work;
    return work.whenComplete(() {
      if (identical(_stopping, work)) _stopping = null;
    });
  }

  Future<void> _stopResourcesImpl() async {
    final process = _process;
    final pending = _pendingLaunch;
    _process = null;
    _pendingLaunch = null;
    _playing = false;
    _loading = false;
    process?.kill();
    if (process != null) await process.exitCode;
    // A save/overwrite may only start after even a late process has released
    // its input handle. Killing without reaping would race Windows replacement.
    if (pending != null) {
      try {
        final lateProcess = await pending;
        lateProcess.kill();
        await lateProcess.exitCode;
      } catch (_) {
        // A failed launch owns no audio file handle.
      }
    }
    _releaseMain();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

/// Shares the existing pause/resume guard with isolated lyric preview sessions.
TrimMainPlayback? existingPreviewMainPlayback() => _existingMainPlayback();
