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
        BuildContext context, Audio audio, Lyric lyric, {int? line}) =>
    showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            LyricPlaybackPreview(audio: audio, lyric: lyric, line: line));

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
  double? dragging;
  bool checking = true, ready = false, closing = false;
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
    final ok =
        await (widget.ensureTools ?? () => FfmpegRuntime.shared.ensure())();
    if (ok && widget.preview == null) await player.prepare();
    if (!mounted || closing) return;
    setState(() {
      checking = false;
      ready = ok;
    });
    if (ok) await player.play(range.start, range.end);
  }

  Future<void> _close() async {
    if (closing) return;
    setState(() => closing = true);
    await player.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    player.removeListener(_changed);
    player.dispose();
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
                          if (!checking && !ready)
                            Flexible(
                                child: SingleChildScrollView(
                                    child: FfmpegSetupCard(
                                        lyricPreview: true,
                                        onReady: () {
                                          setState(() => ready = true);
                                          unawaited(player.play(
                                              range.start, range.end));
                                        })))
                          else if (!checking)
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
                          if (player.error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(ui(player.error!),
                                    style: TextStyle(color: scheme.error))),
                          StreamBuilder<double>(
                              stream: player.positionStream,
                              initialData: player.position,
                              builder: (context, snapshot) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Slider(
                                            key: const ValueKey(
                                                'lyric-preview-seek'),
                                            min: range.start,
                                            max: range.end > range.start
                                                ? range.end
                                                : range.start + 1,
                                            value: (dragging ?? player.position)
                                                .clamp(
                                                    range.start,
                                                    range.end > range.start
                                                        ? range.end
                                                        : range.start + 1),
                                            onChanged: !ready || closing
                                                ? null
                                                : (value) => setState(
                                                    () => dragging = value),
                                            onChangeEnd: !ready || closing
                                                ? null
                                                : (value) {
                                                    setState(
                                                        () => dragging = null);
                                                    unawaited(player.play(
                                                        value, range.end));
                                                  }),
                                        Text(
                                            '${lyricStamp(Duration(milliseconds: (player.position * 1000).round()))} / ${lyricStamp(Duration(milliseconds: (range.end * 1000).round()))}'),
                                      ])),
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
