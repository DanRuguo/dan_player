import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path_util;
import 'package:desktop_lyric/ui_language.dart';

typedef OnlineLyricEditorSearch = Future<LyricSearchResponse> Function(
  Audio audio,
);
typedef OnlineLyricEditorCandidateLoader = Future<Lyric?> Function(
  SongSearchResult candidate,
);
typedef OnlineLyricEditorCustomCandidateLoader = Future<Lyric?> Function(
  Audio audio,
  CustomLyricSourceChoice choice,
);
typedef LocalLyricEditorLoader = Future<String> Function(Audio audio);
typedef LyricEditorSourcePersistCallback = Future<void> Function(
  String audioPath,
  LyricSource source,
);

/// Replaces the sidecar and its source association as one recoverable unit.
/// The lyric-source helper owns index atomicity; this layer restores the LRC
/// when that second half fails so the file and association cannot diverge.
Future<void> persistEditedLyric({
  required String audioPath,
  required String sidecarPath,
  required String text,
  LyricEditorSourcePersistCallback? persistSource,
}) async {
  final target = File(sidecarPath);
  final temporary = File('$sidecarPath.tmp');
  final backup = File('$sidecarPath.bak');
  final hadPreviousSource = LYRIC_SOURCES.containsKey(audioPath);
  final previousSource = LYRIC_SOURCES[audioPath];
  final localSource = LyricSource(LyricSourceType.local);
  var movedTarget = false;
  var installedTarget = false;

  try {
    await temporary.writeAsString(text, encoding: utf8, flush: true);
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      movedTarget = true;
    }
    await temporary.rename(target.path);
    installedTarget = true;
    await (persistSource ??
        (audioPath, source) => persistLyricSource(audioPath, source))(
      audioPath,
      localSource,
    );
  } catch (error, trace) {
    // persistLyricSource already restores its own mutation. The identity guard
    // also makes injected implementations recoverable without overwriting a
    // different source that may have been selected concurrently.
    if (identical(LYRIC_SOURCES[audioPath], localSource)) {
      if (hadPreviousSource) {
        LYRIC_SOURCES[audioPath] = previousSource!;
      } else {
        LYRIC_SOURCES.remove(audioPath);
      }
    }

    Object? rollbackFailure;
    StackTrace? rollbackTrace;
    if (installedTarget && await target.exists()) {
      try {
        await target.delete();
      } catch (rollbackError, rollbackStack) {
        rollbackFailure = rollbackError;
        rollbackTrace = rollbackStack;
      }
    }
    if (movedTarget && await backup.exists()) {
      try {
        if (await target.exists()) await target.delete();
        await backup.rename(target.path);
      } catch (rollbackError, rollbackStack) {
        rollbackFailure ??= rollbackError;
        rollbackTrace ??= rollbackStack;
      }
    }
    if (rollbackFailure != null) {
      LOGGER.e(
        '[lyric editor] rollback failed after $error: $rollbackFailure',
        stackTrace: rollbackTrace ?? trace,
      );
      throw StateError('无法恢复保存前的歌词文件：$rollbackFailure');
    }
    rethrow;
  } finally {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {}
    }
  }
}

Future<bool> showLyricEditorDialog(
  BuildContext context,
  Audio audio, {
  OnlineLyricEditorSearch? onlineLyricSearch,
  OnlineLyricEditorCandidateLoader? onlineLyricCandidateLoader,
  List<CustomLyricSourceChoice>? customLyricChoices,
  OnlineLyricEditorCustomCandidateLoader? customLyricCandidateLoader,
}) async {
  if (audio.isOnline) {
    showTextOnSnackBar("联网音乐的歌词为只读，不能修改");
    return false;
  }
  return await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => LyricEditorDialog(
          audio: audio,
          onlineLyricSearch: onlineLyricSearch,
          onlineLyricCandidateLoader: onlineLyricCandidateLoader,
          customLyricChoices: customLyricChoices,
          customLyricCandidateLoader: customLyricCandidateLoader,
        ),
      ) ==
      true;
}

class LyricEditorDialog extends StatefulWidget {
  const LyricEditorDialog({
    super.key,
    required this.audio,
    this.onlineLyricSearch,
    this.onlineLyricCandidateLoader,
    this.customLyricChoices,
    this.customLyricCandidateLoader,
    this.localLyricLoader,
  });

  final Audio audio;
  final OnlineLyricEditorSearch? onlineLyricSearch;
  final OnlineLyricEditorCandidateLoader? onlineLyricCandidateLoader;
  final List<CustomLyricSourceChoice>? customLyricChoices;
  final OnlineLyricEditorCustomCandidateLoader? customLyricCandidateLoader;
  final LocalLyricEditorLoader? localLyricLoader;

  @override
  State<LyricEditorDialog> createState() => _LyricEditorDialogState();
}

class _LyricEditorDialogState extends State<LyricEditorDialog> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  String original = "";
  bool loading = true;
  bool saving = false;
  bool loadingOnline = false;
  String? loadError;
  String? onlineError;
  int _onlineLoadGeneration = 0;

  String get sidecarPath => path_util.setExtension(widget.audio.path, ".lrc");
  bool get dirty => controller.text != original;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      String text;
      final injectedLoader = widget.localLyricLoader;
      if (injectedLoader != null) {
        text = await injectedLoader(widget.audio);
      } else {
        final sidecar = File(sidecarPath);
        if (await sidecar.exists()) {
          final bytes = await sidecar.readAsBytes();
          text = decodeLyricText(bytes);
        } else {
          final lyric = await Lrc.fromAudioPath(widget.audio, separator: "┃");
          text = lyric == null ? "" : _serializeLyric(lyric);
        }
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
      final timestamp = "[${minutes.toString().padLeft(2, "0")}:"
          "${seconds.toString().padLeft(2, "0")}."
          "${hundredths.toString().padLeft(2, "0")}]";
      // Plain/custom providers can return one multiline lyric item. Give every
      // displayed line a valid editable LRC prefix without inventing playback
      // timing; the user can adjust timestamps before explicitly saving.
      for (final contentLine in content.replaceAll('\r\n', '\n').split('\n')) {
        output.writeln('$timestamp$contentLine');
      }
    }
    return output.toString().trimRight();
  }

  Future<void> _fillOnlineLyric() async {
    if (loading || saving || loadingOnline) return;
    final generation = ++_onlineLoadGeneration;
    setState(() {
      loadingOnline = true;
      onlineError = null;
    });

    final lyric = await showAppDialog<Lyric>(
      context: context,
      builder: (_) => _OnlineLyricCandidateDialog(
        audio: widget.audio,
        search: widget.onlineLyricSearch ?? searchLyricCandidates,
        loadCandidate:
            widget.onlineLyricCandidateLoader ?? getLyricForCandidate,
        customChoices: widget.customLyricChoices ??
            customLyricSourceChoicesFor(widget.audio),
        loadCustomCandidate:
            widget.customLyricCandidateLoader ?? getLyricForCustomSourceChoice,
      ),
    );

    if (!mounted || generation != _onlineLoadGeneration) return;
    if (lyric == null) {
      setState(() => loadingOnline = false);
      return;
    }
    final text = _serializeLyric(lyric).trim();
    final failure = text.isEmpty ? ui("该候选没有返回可用歌词，可选择其他候选或重试。") : null;
    setState(() {
      loadingOnline = false;
      onlineError = failure;
      if (failure == null) {
        loadError = null;
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
    if (failure == null) focusNode.requestFocus();
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
    try {
      await persistEditedLyric(
        audioPath: widget.audio.path,
        sidecarPath: sidecarPath,
        text: text,
      );
    } catch (error, trace) {
      LOGGER.e("[lyric editor] save failed: $error", stackTrace: trace);
      showTextOnSnackBar("保存歌词失败：{0}", arguments: [error]);
      if (mounted) setState(() => saving = false);
      return;
    }

    original = text;
    try {
      final playback = PlayService.instance.playbackService;
      if (playback.nowPlaying?.path == widget.audio.path) {
        PlayService.instance.lyricService.useLocalLyric();
      }
    } catch (error, trace) {
      // The file and source index are already durable. A playback refresh is
      // best-effort and must not turn a committed save into a false failure.
      LOGGER.w("[lyric editor] refresh after save failed: $error",
          stackTrace: trace);
    }
    showTextOnSnackBar("歌词已保存到 {0}", arguments: [sidecarPath]);
    if (mounted) Navigator.pop(context, true);
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
    _onlineLoadGeneration++;
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Widget _editorSurface(ThemeData theme, ColorScheme scheme) => loading
      ? const Center(child: CircularProgressIndicator())
      : loadError != null
          ? Center(
              child: Text(
                loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                TextField(
                  key: const ValueKey('lyric-editor-field'),
                  controller: controller,
                  focusNode: focusNode,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  readOnly: saving || loadingOnline,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => setState(() {}),
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                  decoration: InputDecoration(
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    border: AppShape.inputBorder,
                    contentPadding: const EdgeInsets.all(16),
                    hintText: ui("[00:00.00]歌词内容"),
                  ),
                ),
                if (loadingOnline)
                  const Positioned(
                    key: ValueKey('lyric-editor-online-progress'),
                    top: 1,
                    left: 12,
                    right: 12,
                    child: LinearProgressIndicator(),
                  ),
              ],
            );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height - 48).clamp(300, 760).toDouble();
    return PopScope<bool>(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !saving) _cancel();
      },
      child: Dialog(
        child: SizedBox(
          width: 900,
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final compact = constraints.maxHeight < 480 || textScale > 1.7;
                final editor = _editorSurface(theme, scheme);
                final column = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogTitle(
                      ui("编辑歌词 · {0}", [widget.audio.displayTitle]),
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      subtitle: Text(
                        '${widget.audio.artist} · ${widget.audio.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      leading: Icon(Symbols.lyrics, color: scheme.primary),
                      trailing: IconButton(
                        key: const ValueKey('lyric-editor-close'),
                        tooltip: ui("关闭"),
                        onPressed: saving ? null : _cancel,
                        icon: const Icon(Symbols.close),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppShape.controlRadius,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .72),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final summary = Text(
                            ui("保存为同名 .lrc 文件（UTF-8）"),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          );
                          final actions = Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('lyric-editor-fill-online'),
                                onPressed: loading || saving || loadingOnline
                                    ? null
                                    : _fillOnlineLyric,
                                icon: loadingOnline
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Symbols.cloud_download),
                                label: Text(loadingOnline
                                    ? ui("正在加载歌词")
                                    : ui("填入联网歌词")),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('lyric-editor-insert-time'),
                                onPressed: loading ||
                                        saving ||
                                        loadingOnline ||
                                        loadError != null
                                    ? null
                                    : _insertCurrentTimestamp,
                                icon: const Icon(Symbols.timer),
                                label: Text(ui("插入当前播放时间")),
                              ),
                            ],
                          );
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          if (constraints.maxWidth < 620 * textScale) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                summary,
                                const SizedBox(height: 10),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: actions,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: summary),
                              const SizedBox(width: 16),
                              actions,
                            ],
                          );
                        },
                      ),
                    ),
                    if (onlineError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          key: const ValueKey('lyric-editor-online-error'),
                          padding: const EdgeInsetsDirectional.only(
                            start: 12,
                            top: 6,
                            bottom: 6,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: AppShape.controlRadius,
                          ),
                          child: Row(
                            children: [
                              Icon(Symbols.cloud_off,
                                  color: scheme.onErrorContainer),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  onlineError!,
                                  style:
                                      TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                              IconButton(
                                tooltip: ui("关闭"),
                                onPressed: () =>
                                    setState(() => onlineError = null),
                                icon: const Icon(Symbols.close),
                                color: scheme.onErrorContainer,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12.0),
                    if (compact)
                      SizedBox(
                        height: (constraints.maxHeight * .65)
                            .clamp(180, 360)
                            .toDouble(),
                        child: editor,
                      )
                    else
                      Expanded(child: editor),
                    const SizedBox(height: 16.0),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 12,
                      overflowSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: saving ? null : _cancel,
                          icon: const Icon(Symbols.close),
                          label: Text(ui("取消")),
                        ),
                        FilledButton.icon(
                          onPressed: loading ||
                                  saving ||
                                  loadingOnline ||
                                  loadError != null
                              ? null
                              : _save,
                          icon: saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Symbols.save),
                          label: Text(ui("保存歌词")),
                        ),
                      ],
                    ),
                  ],
                );
                if (!compact) return column;
                return SingleChildScrollView(
                  key: const ValueKey('lyric-editor-compact-scroll'),
                  child: column,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlineLyricCandidateDialog extends StatefulWidget {
  const _OnlineLyricCandidateDialog({
    required this.audio,
    required this.search,
    required this.loadCandidate,
    required this.customChoices,
    required this.loadCustomCandidate,
  });

  final Audio audio;
  final OnlineLyricEditorSearch search;
  final OnlineLyricEditorCandidateLoader loadCandidate;
  final List<CustomLyricSourceChoice> customChoices;
  final OnlineLyricEditorCustomCandidateLoader loadCustomCandidate;

  @override
  State<_OnlineLyricCandidateDialog> createState() =>
      _OnlineLyricCandidateDialogState();
}

class _OnlineLyricCandidateDialogState
    extends State<_OnlineLyricCandidateDialog> {
  LyricSearchResponse? _response;
  String? _searchError;
  String? _loadingIdentity;
  final Map<String, String> _candidateErrors = <String, String>{};
  int _searchGeneration = 0;
  int _loadGeneration = 0;
  bool _searching = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    if (_searching || _closing) return;
    final generation = ++_searchGeneration;
    _loadGeneration++;
    setState(() {
      _searching = true;
      _searchError = null;
      _response = null;
      _loadingIdentity = null;
      _candidateErrors.clear();
    });
    try {
      final response = await widget.search(widget.audio);
      if (!mounted || _closing || generation != _searchGeneration) return;
      setState(() {
        _response = response;
        _searching = false;
      });
    } catch (error, trace) {
      LOGGER.e('[lyric editor] candidate search failed: $error',
          stackTrace: trace);
      if (!mounted || _closing || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _searchError = ui("搜索歌词候选失败，请检查网络后重试。");
      });
    }
  }

  Future<void> _choose(SongSearchResult candidate) async {
    if (_loadingIdentity != null || _closing) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingIdentity = candidate.identity;
      _candidateErrors.remove(candidate.identity);
    });
    try {
      final lyric = await widget.loadCandidate(candidate);
      if (!mounted || _closing || generation != _loadGeneration) return;
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() {
          _candidateErrors[candidate.identity] = ui(
            "{0}未返回可用歌词，可选择其他候选或重试。",
            [ui(candidate.sourceLabel)],
          );
        });
        return;
      }
      _complete(lyric);
    } catch (error, trace) {
      LOGGER.e('[lyric editor] candidate load failed: $error',
          stackTrace: trace);
      if (!mounted || _closing || generation != _loadGeneration) return;
      setState(() {
        _candidateErrors[candidate.identity] = ui("获取歌词失败，可选择其他候选或重试。");
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingIdentity = null);
      }
    }
  }

  Future<void> _chooseCustom(CustomLyricSourceChoice choice) async {
    if (_loadingIdentity != null || _closing) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingIdentity = choice.identity;
      _candidateErrors.remove(choice.identity);
    });
    try {
      final lyric = await widget.loadCustomCandidate(widget.audio, choice);
      if (!mounted || _closing || generation != _loadGeneration) return;
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() {
          _candidateErrors[choice.identity] = ui(
            "{0}未返回可用歌词，可选择其他候选或重试。",
            [choice.profile.name],
          );
        });
        return;
      }
      _complete(lyric);
    } catch (error, trace) {
      LOGGER.e(
        '[lyric editor] custom candidate load failed: $error',
        stackTrace: trace,
      );
      if (!mounted || _closing || generation != _loadGeneration) return;
      setState(() {
        _candidateErrors[choice.identity] = ui("获取歌词失败，可选择其他候选或重试。");
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingIdentity = null);
      }
    }
  }

  void _invalidatePending() {
    if (_closing) return;
    _closing = true;
    _searchGeneration++;
    _loadGeneration++;
  }

  void _close() {
    if (_closing) return;
    _invalidatePending();
    Navigator.of(context).pop();
  }

  void _complete(Lyric lyric) {
    if (_closing) return;
    _invalidatePending();
    Navigator.of(context).pop(lyric);
  }

  @override
  void dispose() {
    _invalidatePending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height - 64).clamp(360, 680).toDouble();
    return PopScope<Lyric>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _invalidatePending();
      },
      child: Dialog(
        child: SizedBox(
          width: 660,
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final compact = constraints.maxHeight < 480 || textScale > 1.7;
                final candidateContent = DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: AppShape.surfaceRadius,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: AppShape.surfaceRadius,
                    child: _buildContent(context),
                  ),
                );
                final column = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogTitle(
                      ui("填入联网歌词"),
                      style: theme.textTheme.titleLarge,
                      leading:
                          Icon(Symbols.cloud_download, color: scheme.primary),
                      trailing: IconButton(
                        key: const ValueKey('online-lyric-candidate-close'),
                        tooltip: ui("取消"),
                        onPressed: _close,
                        icon: const Icon(Symbols.close),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.audio.displayTitle} · ${widget.audio.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ui("选择一条候选歌词填入编辑器；填入后仍需手动保存。"),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (compact)
                      SizedBox(
                        height: (constraints.maxHeight * .68)
                            .clamp(210, 380)
                            .toDouble(),
                        child: candidateContent,
                      )
                    else
                      Expanded(child: candidateContent),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        key: const ValueKey('online-lyric-candidate-cancel'),
                        onPressed: _close,
                        icon: const Icon(Symbols.close),
                        label: Text(ui("取消")),
                      ),
                    ),
                  ],
                );
                if (!compact) return column;
                return SingleChildScrollView(
                  key: const ValueKey('online-lyric-candidate-compact-scroll'),
                  child: column,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.customChoices.isNotEmpty) {
      return _buildContentWithCustomChoices();
    }
    if (_searching) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-loading'),
        icon: const SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        message: ui("正在加载歌词"),
      );
    }
    if (_searchError != null) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-search-error'),
        icon: const Icon(Symbols.cloud_off),
        message: _searchError!,
        onRetry: _search,
      );
    }
    final response = _response;
    if (response == null) {
      return _OnlineCandidateState(
        icon: const Icon(Symbols.error),
        message: ui("候选状态不可用，请重试。"),
        onRetry: _search,
      );
    }
    if (response.sourcesDisabled) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-sources-disabled'),
        icon: const Icon(Symbols.cloud_off),
        message: ui("当前没有可用的联网歌词来源，请检查歌词与歌源设置。"),
      );
    }

    final failureText = response.failures.entries
        .map((entry) => '${ui(entry.key.sourceLabel)}：${ui(entry.value)}')
        .join('\n');
    if (response.candidates.isEmpty) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-empty'),
        icon: const Icon(Symbols.search_off),
        message: failureText.isEmpty
            ? ui("没有找到相关歌词候选，可检查歌曲标签后重试。")
            : ui("可用来源没有返回候选。"),
        details: failureText.isEmpty ? null : failureText,
        onRetry: _search,
      );
    }

    return Scrollbar(
      child: ListView.separated(
        key: const ValueKey('online-lyric-candidates'),
        padding: const EdgeInsets.all(10),
        itemCount: response.candidates.length + (failureText.isEmpty ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (failureText.isNotEmpty && index == 0) {
            return _OnlineCandidateNotice(
              message: failureText,
              onRetry: _search,
            );
          }
          final candidateIndex = index - (failureText.isEmpty ? 0 : 1);
          return _candidateTile(response.candidates[candidateIndex]);
        },
      ),
    );
  }

  Widget _buildContentWithCustomChoices() {
    final response = _response;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 2),
        child: Text(
          ui("自定义歌源"),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      for (final choice in widget.customChoices)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
          child: _customCandidateTile(choice),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(height: 1),
      ),
    ];

    if (_searching) {
      children.add(
        ListTile(
          key: const ValueKey('online-lyric-candidate-loading'),
          leading: const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(ui("正在加载歌词")),
        ),
      );
    } else if (_searchError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(10),
          child: _OnlineCandidateNotice(
            message: _searchError!,
            onRetry: _search,
          ),
        ),
      );
    } else if (response == null) {
      children.add(
        ListTile(
          leading: const Icon(Symbols.error),
          title: Text(ui("候选状态不可用，请重试。")),
        ),
      );
    } else if (response.sourcesDisabled) {
      children.add(
        ListTile(
          key: const ValueKey('online-lyric-candidate-sources-disabled'),
          leading: const Icon(Symbols.cloud_off),
          title: Text(ui("内置歌词来源不可用；仍可选择上方的自定义歌源。")),
        ),
      );
    } else {
      final failureText = response.failures.entries
          .map((entry) => '${ui(entry.key.sourceLabel)}：${ui(entry.value)}')
          .join('\n');
      if (failureText.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.all(10),
            child: _OnlineCandidateNotice(
              message: failureText,
              onRetry: _search,
            ),
          ),
        );
      }
      if (response.candidates.isEmpty) {
        children.add(
          ListTile(
            key: const ValueKey('online-lyric-candidate-empty'),
            leading: const Icon(Symbols.search_off),
            title: Text(ui(failureText.isEmpty
                ? "没有找到相关歌词候选，可检查歌曲标签后重试。"
                : "可用来源没有返回候选。")),
          ),
        );
      } else {
        for (final candidate in response.candidates) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: _candidateTile(candidate),
            ),
          );
        }
      }
    }

    return Scrollbar(
      child: ListView(
        key: const ValueKey('online-lyric-candidates'),
        children: children,
      ),
    );
  }

  Widget _candidateTile(SongSearchResult candidate) {
    final scheme = Theme.of(context).colorScheme;
    final loading = _loadingIdentity == candidate.identity;
    final error = _candidateErrors[candidate.identity];
    final details = [
      if (candidate.artists.trim().isNotEmpty) candidate.artists.trim(),
      if (candidate.album.trim().isNotEmpty) candidate.album.trim(),
    ].join(' · ');
    return Material(
      color: loading
          ? scheme.secondaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerLow,
      shape: AppShape.control,
      child: ListTile(
        key: ValueKey('online-lyric-candidate-${candidate.identity}'),
        enabled: _loadingIdentity == null,
        shape: AppShape.control,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(switch (candidate.source) {
            ResultSource.qq => 'QQ',
            ResultSource.netease => ui("网"),
            ResultSource.kugou => ui("酷"),
            ResultSource.lrclib => 'LR',
          }),
        ),
        title: Text(
          candidate.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(ui("来源：{0} · 匹配 {1}%", [
              ui(candidate.sourceLabel),
              (candidate.score * 100).round(),
            ])),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Symbols.chevron_right),
        onTap: loading ? null : () => _choose(candidate),
      ),
    );
  }

  Widget _customCandidateTile(CustomLyricSourceChoice choice) {
    final scheme = Theme.of(context).colorScheme;
    final loading = _loadingIdentity == choice.identity;
    final error = _candidateErrors[choice.identity];
    return Material(
      color: loading
          ? scheme.secondaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerLow,
      shape: AppShape.control,
      child: ListTile(
        key: ValueKey('online-lyric-custom-${choice.profile.id}'),
        enabled: _loadingIdentity == null,
        shape: AppShape.control,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(Symbols.api, size: 20),
        ),
        title: Text(
          choice.profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ui("来源：{0}", [ui("自定义歌源")])),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Symbols.chevron_right),
        onTap: loading ? null : () => _chooseCustom(choice),
      ),
    );
  }
}

class _OnlineCandidateState extends StatelessWidget {
  const _OnlineCandidateState({
    super.key,
    required this.icon,
    required this.message,
    this.details,
    this.onRetry,
  });

  final Widget icon;
  final String message;
  final String? details;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: icon,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (details?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  details!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Symbols.refresh),
                  label: Text(ui("重试")),
                ),
              ],
            ],
          ),
        ),
      );
}

class _OnlineCandidateNotice extends StatelessWidget {
  const _OnlineCandidateNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppShape.controlRadius,
      ),
      child: Row(
        children: [
          Icon(Symbols.warning, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh),
            label: Text(ui("重试")),
          ),
        ],
      ),
    );
  }
}
