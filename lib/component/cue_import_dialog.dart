import 'dart:async';
import 'dart:io';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

Future<PlaylistImportDetails?> importCuePlaylist(BuildContext context,
    {required List<Audio> library,
    FutureOr<String?> Function()? pickFile,
    Future<CueDocument> Function(File)? readFile,
    Future<List<Audio>> Function(CueDocument, List<Audio>)?
        resolveEntries}) async {
  String? location;
  try {
    location = await (pickFile ??
        () => (OpenFilePicker()
              ..title = ui('导入 CUE 分轨')
              ..filterSpecification = {'CUE': '*.cue'})
            .getFile()
            ?.path)();
  } catch (_) {
    if (context.mounted) {
      showTextOnSnackBar(ui('无法打开文件选择器，请稍后重试。'), context: context);
    }
    return null;
  }
  if (location == null || !context.mounted) return null;
  return showAppDialog<PlaylistImportDetails>(
      context: context,
      builder: (_) => CueImportDialog(
          file: File(location!),
          library: library,
          readFile: readFile,
          resolveEntries: resolveEntries));
}

class CueImportDialog extends StatefulWidget {
  const CueImportDialog(
      {super.key,
      required this.file,
      required this.library,
      this.readFile,
      this.resolveEntries});
  final File file;
  final List<Audio> library;
  final Future<CueDocument> Function(File)? readFile;
  final Future<List<Audio>> Function(CueDocument, List<Audio>)? resolveEntries;
  @override
  State<CueImportDialog> createState() => _CueImportDialogState();
}

class _CueImportDialogState extends State<CueImportDialog> {
  late final _name = TextEditingController(
      text: p.windows.basenameWithoutExtension(widget.file.path));
  List<Audio>? _audios;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final document = await (widget.readFile ?? readCueFile)(widget.file);
      final audios = await (widget.resolveEntries ?? resolveCueEntries)(
          document, widget.library);
      if (mounted) {
        setState(() {
          _audios = audios;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? ui(error.message.toString())
            : ui('无法读取 CUE 或其音频文件，请检查位置与访问权限。'));
      }
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120 || _audios?.isNotEmpty != true) {
      return;
    }
    Navigator.of(context).pop(PlaylistImportDetails(name, _audios!));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(ui('导入 CUE 分轨')),
      content: SizedBox(
          width: 420,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                        controller: _name,
                        maxLength: 120,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                            labelText: ui('歌单名称'),
                            border: AppShape.inputBorder))),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                else if (_audios == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Text(ui('将导入 {0} 首 CUE 分轨，每首有独立的播放进度。', [_audios!.length])),
                  const SizedBox(height: 8),
                  Text(ui('只保存分轨引用，不拆分或修改音频文件；保留 CUE 和源文件以便重新导入。')),
                  const SizedBox(height: 8),
                  SizedBox(
                      height: (_audios!.length * 66.0).clamp(66, 230),
                      child: ListView.builder(
                          itemCount: _audios!.length,
                          itemBuilder: (_, i) {
                            final audio = _audios![i];
                            return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Symbols.album),
                                title: Text(audio.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    ui('第 {0} 轨 · {1}',
                                        [audio.track, audio.artist]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis));
                          })),
                ],
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ui('取消'))),
        FilledButton(
            onPressed: _audios?.isNotEmpty == true &&
                    _name.text.trim().isNotEmpty &&
                    _name.text.trim().length <= 120
                ? _submit
                : null,
            child: Text(ui('新建歌单')))
      ],
    );
  }
}
