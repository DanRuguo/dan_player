import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/play_service/waveform_service.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'detail_progress_slider.dart';

/// Analysis belongs to the visible lyrics timeline, not playback startup or
/// library scanning. The existing slider still owns seeking and motion.
class WaveformProgress extends StatefulWidget {
  const WaveformProgress(
      {super.key,
      required this.audio,
      required this.waveformEnabled,
      this.waveformDensity = WaveformBarDensity.automatic,
      required this.positions,
      required this.readPosition,
      required this.duration,
      required this.trackIdentity,
      required this.onSeek,
      this.enabled = true,
      this.hidden,
      this.service});
  final Audio? audio;
  final bool waveformEnabled;
  final WaveformBarDensity waveformDensity;
  final Stream<double> positions;
  final double Function() readPosition;
  final double duration;
  final Object? trackIdentity;
  final ValueChanged<double> onSeek;
  final bool enabled;
  final ValueListenable<bool>? hidden;
  final WaveformService? service;

  @override
  State<WaveformProgress> createState() => _WaveformProgressState();
}

class _WaveformProgressState extends State<WaveformProgress>
    with WidgetsBindingObserver {
  WaveformCancellation? _cancellation;
  WaveformData? _data;
  WaveformData? _projectedData;
  double? _projectedDuration;
  List<double>? _projectedPeaks;
  WaveformFailure? _failure;
  Object? _key;
  int _generation = 0;
  bool _visible = false;
  bool _pending = false;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_hiddenChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(WaveformProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_hiddenChanged);
      widget.hidden?.addListener(_hiddenChanged);
    }
    _sync();
  }

  bool get _active =>
      _visible &&
      widget.hidden?.value != true &&
      (_lifecycle == null ||
          _lifecycle == AppLifecycleState.resumed ||
          _lifecycle == AppLifecycleState.inactive);

  void _sync() {
    final audio = widget.audio;
    final key = (
      audio?.path,
      audio?.localFilePath,
      audio?.cueTrack?.startFrame,
      audio?.cueTrack?.endFrame,
      widget.waveformEnabled,
      _active,
      widget.enabled,
      audio?.modified,
      audio?.modifiedNanos,
      audio?.fileSizeBytes,
      widget.service
    );
    if (_key == key) return;
    _key = key;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _data = null;
    _failure = null;
    _pending = false;
    if (!widget.waveformEnabled ||
        !_active ||
        !widget.enabled ||
        audio == null) {
      return;
    }
    if (audio.isOnline) {
      _failure = WaveformFailure.online;
      return;
    }
    _pending = true;
    final cancellation = _cancellation = WaveformCancellation();
    final generation = _generation;
    unawaited((() async {
      try {
        final data = await (widget.service ?? WaveformService.shared)
            .load(audio, cancellation);
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _data = cancellation.cancelled ? null : data;
          if (_data == null) _failure = WaveformFailure.interrupted;
          _pending = false;
        });
      } catch (error) {
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _failure = cancellation.cancelled
              ? WaveformFailure.interrupted
              : error is WaveformUnavailable
                  ? error.reason
                  : WaveformFailure.decode;
          _pending = false;
        });
      }
    })());
  }

  void _hiddenChanged() {
    if (mounted) setState(_sync);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (mounted) setState(_sync);
  }

  @override
  void dispose() {
    _generation++;
    _cancellation?.cancel();
    widget.hidden?.removeListener(_hiddenChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    if (!identical(_projectedData, _data) ||
        _projectedDuration != widget.duration) {
      _projectedData = _data;
      _projectedDuration = widget.duration;
      _projectedPeaks = _data == null
          ? null
          : waveformPeaksForDuration(_data!, widget.duration);
    }
    final message = _pending
        ? ui('正在分析音频波形，进度仍可调节。')
        : switch (_failure) {
            WaveformFailure.online => ui('联网歌曲使用默认进度条。'),
            WaveformFailure.missing => ui('文件不可用，显示默认进度条。'),
            WaveformFailure.tooLong => ui('音频过长或分析超时，显示默认进度条。'),
            WaveformFailure.changed => ui('分析期间文件已变化，显示默认进度条。'),
            WaveformFailure.interrupted => ui('分析已取消，显示默认进度条。'),
            WaveformFailure.decode => ui('无法读取音频波形，显示默认进度条。'),
            null => _data != null ? ui('音频波形显示振幅强弱；点击或拖动调整进度。') : null,
          };
    return DetailProgressSlider(
      positions: widget.positions,
      readPosition: widget.readPosition,
      duration: widget.duration,
      trackIdentity: widget.trackIdentity,
      onSeek: widget.onSeek,
      enabled: widget.enabled,
      hidden: widget.hidden,
      waveform: _projectedPeaks,
      waveformDensity: widget.waveformDensity,
      waveformTooltip: message,
    );
  }
}
