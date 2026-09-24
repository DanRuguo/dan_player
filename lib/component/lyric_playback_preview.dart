import 'package:provider/provider.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'dart:async';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showLyricPlaybackPreview(
        BuildContext context, Audio audio, Lyric lyric,
        {int? line,
        LyricAudioPreview? preview,
        Future<bool> Function()? ensureTools}) =>
    showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LyricPlaybackPreview(
            audio: audio,
            lyric: lyric,
            line: line,
            preview: preview,
            ensureTools: ensureTools));

class LyricPlaybackPreview extends StatefulWidget {
  const LyricPlaybackPreview(
      {super.key,
      required this.audio,
      required this.lyric,
      this.line,
      this.preview,
      this.ensureTools});
  final Audio audio;
  final Lyric lyric;
  final int? line;
  final LyricAudioPreview? preview;
  final Future<bool> Function()? ensureTools;
  @override
  State<LyricPlaybackPreview> createState() => _LyricPlaybackPreviewState();
}

class _LyricPlaybackPreviewState extends State<LyricPlaybackPreview> {
  late final player = widget.preview ?? LyricAudioPreview(widget.audio);
  final _dragging = ValueNotifier<double?>(null);
  int? _dragPointer;
  int _dragGeneration = 0;
  double _dragOrigin = 0;
  bool _dragWasPlaying = false;
  Future<void>? _dragPause;
  bool checking = true, ready = false, closing = false;
  String? setupError;
  ({double start, double end}) get range => widget.line == null
      ? (start: 0.0, end: player.duration)
      : lyricPreviewRange(widget.lyric, widget.line!, player.duration);
  @override
  void initState() {
    super.initState();
    player.addListener(_changed);
    unawaited(_start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    try {
      final ok =
          await (widget.ensureTools ?? () => FfmpegRuntime.shared.ensure())();
      if (ok) await player.prepare();
      if (!mounted || closing) return;
      final playable = ok && player.duration > 0;
      setState(() {
        checking = false;
        ready = playable;
        setupError = ok && !playable ? ui('无法读取歌曲时长，无法试听。') : null;
      });
      if (playable) await player.play(range.start, range.end);
    } catch (_) {
      if (mounted && !closing) {
        setState(() {
          checking = false;
          ready = false;
          setupError = ui('试听失败，请重试。');
        });
      }
    }
  }

  Future<void> _close() async {
    if (closing) return;
    ++_dragGeneration;
    _dragging.value = null;
    setState(() => closing = true);
    if (widget.preview == null) {
      await player.close();
    } else {
      await player.pause();
    }
    if (mounted) Navigator.pop(context);
  }

  void _beginSeek(double value) {
    ++_dragGeneration;
    _dragOrigin = player.position;
    _dragWasPlaying = player.playing || player.loading;
    _dragPause = player.pause();
    _dragging.value = value;
  }

  void _changeSeek(double value) {
    if (_dragging.value != null) _dragging.value = value;
  }

  Future<void> _endSeek(double value) async {
    if (_dragging.value == null) return;
    final generation = _dragGeneration;
    final resume = _dragWasPlaying;
    _dragPointer = null;
    _dragging.value = null;
    await _dragPause;
    if (!mounted || closing || generation != _dragGeneration) return;
    if (resume) {
      final target = value >= range.end ? range.start : value;
      await player.play(target, range.end);
    } else {
      await player.seekPaused(value);
    }
  }

  Future<void> _cancelSeek(int pointer) async {
    if (_dragPointer != pointer) return;
    _dragPointer = null;
    if (_dragging.value == null) return;
    final generation = _dragGeneration;
    final resume = _dragWasPlaying;
    final origin = _dragOrigin;
    _dragging.value = null;
    await _dragPause;
    if (!mounted || closing || generation != _dragGeneration) return;
    if (resume) {
      await player.play(origin, range.end);
    } else {
      await player.seekPaused(origin);
    }
  }

  @override
  void dispose() {
    player.removeListener(_changed);
    if (widget.preview == null) player.dispose();
    _dragging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 500;
    return PopScope(
        canPop: closing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_close());
        },
        child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: AppDialogContent(
                width: 900,
                maxHeight: 780,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppDialogTitle(
                              ui(widget.line == null ? '播放编辑预览' : '逐句试听'),
                              leading:
                                  Icon(Symbols.lyrics, color: scheme.primary),
                              trailing: IconButton(
                                  key: const ValueKey('lyric-preview-close'),
                                  tooltip: ui('关闭'),
                                  onPressed: closing ? null : _close,
                                  icon: const Icon(Symbols.close))),
                          if (!compact) ...[
                            const SizedBox(height: 12),
                            Text(ui('临时试听编辑内容，不改变歌曲的歌词来源。'),
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                          ],
                          if (checking || player.loading)
                            const LinearProgressIndicator(),
                          if (!checking && !ready && setupError == null)
                            Flexible(
                                child: SingleChildScrollView(
                                    child: FfmpegSetupCard(
                                        lyricPreview: true,
                                        onReady: () {
                                          setState(() => checking = true);
                                          unawaited(_start());
                                        })))
                          else if (!checking && ready)
                            Flexible(
                                child: SizedBox(
                                    height: 460,
                                    child: ChangeNotifierProvider(
                                        create: (_) => LyricViewController(),
                                        child: VerticalLyricScrollView(
                                            lyric: widget.lyric,
                                            positionStream:
                                                player.positionStream,
                                            readPosition: () => player.position,
                                            onSeek: (value) => unawaited(
                                                player.play(
                                                    value.clamp(
                                                        range.start, range.end),
                                                    range.end)),
                                            playing: player.playing,
                                            springLyrics: AppSettings
                                                .instance
                                                .experience
                                                .value
                                                .springLyrics)))),
                          if (setupError != null || player.error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(setupError ?? ui(player.error!),
                                    style: TextStyle(color: scheme.error))),
                          StreamBuilder<double>(
                              stream: player.positionStream,
                              initialData: player.position,
                              builder: (context, snapshot) =>
                                  ValueListenableBuilder<double?>(
                                      valueListenable: _dragging,
                                      builder: (context, dragged, _) => Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Listener(
                                                    onPointerDown: (event) =>
                                                        _dragPointer ??=
                                                            event.pointer,
                                                    onPointerUp: (event) {
                                                      if (_dragPointer ==
                                                          event.pointer) {
                                                        _dragPointer = null;
                                                      }
                                                    },
                                                    onPointerCancel: (event) =>
                                                        unawaited(_cancelSeek(
                                                            event.pointer)),
                                                    child: Slider(
                                                        key: const ValueKey(
                                                            'lyric-preview-seek'),
                                                        min: range.start,
                                                        max: range.end >
                                                                range.start
                                                            ? range.end
                                                            : range.start + 1,
                                                        value: (dragged ?? player.position).clamp(
                                                            range.start,
                                                            range.end > range.start
                                                                ? range.end
                                                                : range.start + 1),
                                                        label: lyricStamp(Duration(milliseconds: ((dragged ?? player.position) * 1000).round())),
                                                        onChangeStart: !ready || closing || player.loading ? null : _beginSeek,
                                                        onChanged: !ready || closing || player.loading ? null : _changeSeek,
                                                        onChangeEnd: !ready || closing ? null : (value) => unawaited(_endSeek(value)))),
                                                Text(
                                                    '${lyricStamp(Duration(milliseconds: ((dragged ?? player.position) * 1000).round()))} / ${lyricStamp(Duration(milliseconds: (range.end * 1000).round()))}'),
                                              ]))),
                          const SizedBox(height: 12),
                          Align(
                              alignment: Alignment.center,
                              child: FilledButton.icon(
                                  key: const ValueKey('lyric-preview-play'),
                                  onPressed: !ready || closing || player.loading
                                      ? null
                                      : () => player.playing
                                          ? player.pause()
                                          : player.play(range.start, range.end),
                                  icon: Icon(player.playing
                                      ? Symbols.pause
                                      : Symbols.play_arrow),
                                  label: Text(
                                      ui(player.playing ? '暂停' : '重新试听')))),
                        ])))));
  }
}
