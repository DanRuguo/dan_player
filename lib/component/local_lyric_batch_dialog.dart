import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_shape.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class LocalLyricChoice {
  LocalLyricChoice(this.audio, this.identity, this.revision, this.candidates,
      this.protected);
  final Audio audio;
  final String identity;
  final int revision;
  final List<File> candidates;
  final bool protected;
  File? selected;
  Lyric? lyric;
  String? hash, error;
  bool saved = false;
  Future<void> choose(File file) async {
    if (await file.length() > 1024 * 1024)
      throw const FormatException('歌词超过 1 MiB');
    final bytes = await file.readAsBytes();
    final text = decodeLyricText(bytes);
    if (text.trim().isEmpty) throw const FormatException('歌词为空');
    lyric = Lrc.fromLrcText(text, LrcSource.local, separator: '┃') ??
        PlainLyric(text);
    hash = sha256.convert(bytes).toString();
    selected = file;
    error = null;
  }
}

Future<void> showLocalLyricBatch(
    BuildContext context, List<Audio> audios) async {
  final directory = (DirectoryPicker()..title = ui('选择本地歌词目录')).getDirectory();
  if (directory == null || !context.mounted) return;
  await showAppDialog<void>(
      context: context,
      builder: (_) => LocalLyricBatchDialog(
          audios: List.unmodifiable(audios), directory: directory));
}

class LocalLyricBatchDialog extends StatefulWidget {
  const LocalLyricBatchDialog(
      {super.key, required this.audios, required this.directory});
  final List<Audio> audios;
  final Directory directory;
  @override
  State<LocalLyricBatchDialog> createState() => _LocalLyricBatchDialogState();
}

class _LocalLyricBatchDialogState extends State<LocalLyricBatchDialog> {
  final _store = LyricDocumentStore.instance;
  final _choices = <LocalLyricChoice>[];
  bool _busy = true, _cancel = false, _keepOffset = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _store.load();
      final files = <String, List<File>>{};
      var count = 0;
      await for (final file
          in widget.directory.list(recursive: true, followLinks: false)) {
        if (!mounted || _cancel) return;
        if (++count > 20000) throw StateError('目录超过 20000 项，请选择更小的目录');
        if (file is File &&
            ['.lrc', '.txt'].contains(p.extension(file.path).toLowerCase()))
          (files[p.basenameWithoutExtension(file.path).toLowerCase()] ??= [])
              .add(file);
      }
      final seen = <String>{};
      for (final audio in widget.audios) {
        if (!seen.add(audio.stableTrackId)) continue;
        final doc = _store.forAudio(audio);
        final candidates = files[p
                .basenameWithoutExtension(audio.localFilePath)
                .toLowerCase()] ??
            [];
        final choice = LocalLyricChoice(
            audio,
            audio.stableTrackId,
            _store.revisionFor(audio),
            candidates,
            audio.isOnline ||
                audio.isCueTrack ||
                doc?.locked == true ||
                doc?.edited != null ||
                doc?.noLyrics == true);
        _choices.add(choice);
        if (!choice.protected && candidates.length == 1) {
          try {
            await choice.choose(candidates.single);
          } catch (e) {
            choice.error = '$e';
          }
        }
        if (!mounted || _cancel) return;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _cancel = false;
      _error = null;
    });
    final selected = _choices
        .where((c) =>
            !c.protected && !c.saved && c.selected != null && c.lyric != null)
        .toList();
    try {
      for (var i = 0; i < selected.length && !_cancel; i += 16) {
        final group = selected.sublist(i, (i + 16).clamp(0, selected.length));
        final valid = <LocalLyricChoice>[];
        for (final c in group) {
          try {
            if (c.audio.stableTrackId != c.identity ||
                await c.selected!.length() > 1024 * 1024 ||
                sha256.convert(await c.selected!.readAsBytes()).toString() !=
                    c.hash) throw StateError('源文件或曲目身份已改变，请重新预览');
            valid.add(c);
          } catch (e) {
            c.error = '$e';
          }
        }
        if (_cancel) break;
        final conflicts = await _store.selectLocalBatch([
          for (final c in valid)
            (audio: c.audio, lyric: c.lyric!, revision: c.revision)
        ], keepOffset: _keepOffset);
        for (final c in valid) {
          if (conflicts.contains(c.identity)) {
            c.error = ui('修订冲突或歌词已受保护，未覆盖');
          } else {
            c.saved = true;
            c.error = null;
          }
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      _error = '${ui("保存失败，未提交项可重试")}: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: AppDialogTitle(ui('批量关联本地歌词')),
          content: AppDialogContent(
              width: 760,
              maxHeight: 520,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ui('按文件同基名匹配；保留受保护歌词，保存为应用内副本并锁定。')),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(ui('保留原歌曲偏移')),
                    value: _keepOffset,
                    onChanged:
                        _busy ? null : (v) => setState(() => _keepOffset = v)),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final c in _choices)
                    Card.outlined(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(c.audio.displayTitle),
                                  Text(c.protected
                                      ? ui('已跳过：受保护歌词或不支持的来源／CUE')
                                      : c.saved
                                          ? ui('已保存并锁定')
                                          : c.candidates.isEmpty
                                              ? ui('无同基名候选')
                                              : c.lyric is PlainLyric
                                                  ? ui('纯文本，无时间轴')
                                                  : ui('LRC 时间轴')),
                                  if (c.error != null)
                                    Text(c.error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  if (!c.protected && c.candidates.isNotEmpty)
                                    DropdownButtonFormField<File>(
                                        borderRadius: AppShape.controlRadius,
                                        elevation: 3,
                                        dropdownColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        isExpanded: true,
                                        initialValue: c.selected,
                                        items: [
                                          for (final f in c.candidates)
                                            DropdownMenuItem(
                                                value: f,
                                                child: Text(f.path,
                                                    overflow:
                                                        TextOverflow.ellipsis))
                                        ],
                                        onChanged: _busy || c.saved
                                            ? null
                                            : (f) async {
                                                try {
                                                  await c.choose(f!);
                                                } catch (e) {
                                                  c.selected = null;
                                                  c.lyric = null;
                                                  c.error = '$e';
                                                }
                                                if (mounted) setState(() {});
                                              })
                                ])))
                ])),
              ])),
          actions: [
            if (_busy)
              TextButton(
                  onPressed: () => setState(() => _cancel = true),
                  child: Text(ui('停止后续提交'))),
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(ui('关闭'))),
            FilledButton(
                onPressed: _busy ? null : _save, child: Text(ui('确认关联')))
          ]);
}
