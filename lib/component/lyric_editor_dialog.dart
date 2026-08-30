import 'package:dan_player/component/app_presentation.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path_util;
import 'package:desktop_lyric/ui_language.dart';

Future<bool> showLyricEditorDialog(BuildContext context, Audio audio) async {
  if (audio.isOnline) {
    showTextOnSnackBar("联网音乐的歌词为只读，不能修改");
    return false;
  }
  return await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _LyricEditorDialog(audio: audio),
      ) ==
      true;
}

class _LyricEditorDialog extends StatefulWidget {
  const _LyricEditorDialog({required this.audio});
  final Audio audio;

  @override
  State<_LyricEditorDialog> createState() => _LyricEditorDialogState();
}

class _LyricEditorDialogState extends State<_LyricEditorDialog> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  String original = "";
  bool loading = true;
  bool saving = false;
  String? loadError;

  String get sidecarPath => path_util.setExtension(widget.audio.path, ".lrc");
  bool get dirty => controller.text != original;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sidecar = File(sidecarPath);
      String text;
      if (await sidecar.exists()) {
        final bytes = await sidecar.readAsBytes();
        text = decodeLyricText(bytes);
      } else {
        final lyric = await Lrc.fromAudioPath(widget.audio, separator: "┃");
        text = lyric == null ? "" : _serializeLyric(lyric);
      }
      if (!mounted) return;
      original = text;
      controller.text = text;
    } catch (error, trace) {
      LOGGER.e("[lyric editor] load failed: $error", stackTrace: trace);
      loadError = ui("读取歌词失败：{0}", [error]);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _serializeLyric(Lyric lyric) {
    final output = StringBuffer();
    for (final line in lyric.lines) {
      final totalHundredths = line.start.inMilliseconds ~/ 10;
      final minutes = totalHundredths ~/ 6000;
      final seconds = (totalHundredths % 6000) ~/ 100;
      final hundredths = totalHundredths % 100;
      final content = switch (line) {
        UnsyncLyricLine() => line.content,
        SyncLyricLine() => [
            line.content,
            if (line.translation?.trim().isNotEmpty == true) line.translation!,
          ].join("┃"),
        _ => "",
      };
      output.writeln(
        "[${minutes.toString().padLeft(2, "0")}:"
        "${seconds.toString().padLeft(2, "0")}."
        "${hundredths.toString().padLeft(2, "0")}]$content",
      );
    }
    return output.toString().trimRight();
  }

  void _insertCurrentTimestamp() {
    final playback = PlayService.instance.playbackService;
    final position = playback.nowPlaying?.path == widget.audio.path
        ? playback.position
        : 0.0;
    final totalHundredths = (position * 100).floor();
    final minutes = totalHundredths ~/ 6000;
    final seconds = (totalHundredths % 6000) ~/ 100;
    final hundredths = totalHundredths % 100;
    final stamp =
        "[${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}.${hundredths.toString().padLeft(2, "0")}]";
    final selection = controller.selection;
    final offset = selection.isValid ? selection.start : controller.text.length;
    controller.text = controller.text.replaceRange(offset, offset, stamp);
    controller.selection =
        TextSelection.collapsed(offset: offset + stamp.length);
    focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _save() async {
    final text = controller.text.trim();
    if (text.isEmpty) {
      showTextOnSnackBar("歌词不能为空");
      return;
    }
    try {
      if (Lrc.fromLrcText(text, LrcSource.local) == null) {
        showTextOnSnackBar("没有识别到有效的 LRC 时间戳");
        return;
      }
    } on FormatException {
      showTextOnSnackBar("没有识别到有效的 LRC 时间戳");
      return;
    }
    setState(() => saving = true);
    final target = File(sidecarPath);
    final temporary = File("$sidecarPath.tmp");
    final backup = File("$sidecarPath.bak");
    try {
      await temporary.writeAsString(text, encoding: utf8, flush: true);
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      await temporary.rename(target.path);
      original = text;
      LYRIC_SOURCES[widget.audio.path] = LyricSource(LyricSourceType.local);
      await saveLyricSources();
      final playback = PlayService.instance.playbackService;
      if (playback.nowPlaying?.path == widget.audio.path) {
        PlayService.instance.lyricService.useLocalLyric();
      }
      showTextOnSnackBar("歌词已保存到 {0}", arguments: [sidecarPath]);
      if (mounted) Navigator.pop(context, true);
    } catch (error, trace) {
      LOGGER.e("[lyric editor] save failed: $error", stackTrace: trace);
      if (!await target.exists() && await backup.exists()) {
        try {
          await backup.rename(target.path);
        } catch (_) {}
      }
      showTextOnSnackBar("保存歌词失败：{0}", arguments: [error]);
      if (mounted) setState(() => saving = false);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _cancel() async {
    if (!dirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppDialogTitle(ui("放弃歌词修改？")),
        content: Text(ui("尚未保存的内容将丢失。")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ui("继续编辑")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ui("放弃修改")),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PopScope<bool>(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !saving) _cancel();
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogTitle(
                  ui("编辑歌词 · {0}", [widget.audio.displayTitle]),
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  subtitle: Text(
                    ui("保存为同名 .lrc 文件（UTF-8）"),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  leading: const Icon(Symbols.lyrics),
                  trailing: IconButton(
                    tooltip: ui("插入当前播放时间"),
                    onPressed:
                        loading || saving ? null : _insertCurrentTimestamp,
                    icon: const Icon(Symbols.timer),
                  ),
                ),
                const SizedBox(height: 16.0),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : loadError != null
                          ? Center(child: Text(loadError!))
                          : TextField(
                              controller: controller,
                              focusNode: focusNode,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              keyboardType: TextInputType.multiline,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                alignLabelWithHint: true,
                                border: AppShape.inputBorder,
                                hintText: ui("[00:00.00]歌词内容"),
                              ),
                            ),
                ),
                const SizedBox(height: 16.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: saving ? null : _cancel,
                        child: Text(ui("取消"))),
                    const SizedBox(width: 12.0),
                    FilledButton.icon(
                      onPressed:
                          loading || saving || loadError != null ? null : _save,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Symbols.save),
                      label: Text(ui("保存歌词")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
