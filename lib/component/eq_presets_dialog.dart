import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_action_list_tile.dart';
import 'dart:convert';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/play_service/eq_preset_store.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

Future<void> showEqPresets(BuildContext context, PlaybackService service) =>
    showAppDialog<void>(
        context: context, builder: (_) => EqPresetsDialog(service: service));

class EqPresetsDialog extends StatefulWidget {
  const EqPresetsDialog({super.key, required this.service, this.store});
  final EqPresetStore? store;
  final PlaybackService service;
  @override
  State<EqPresetsDialog> createState() => _EqPresetsDialogState();
}

class _EqPresetsDialogState extends State<EqPresetsDialog> {
  final _name = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await (widget.store ?? await EqPresetStore.instance).list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function(EqPresetStore) work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work(widget.store ?? await EqPresetStore.instance);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final file = (OpenFilePicker()
          ..title = ui('导入 EQ 预设')
          ..filterSpecification = {'JSON': '*.json'})
        .getFile();
    if (file == null) return;
    try {
      final preset = await EqPresetStore.readExchange(file);
      if (!mounted) return;
      final yes = await showAppDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(preset['name'] as String,
                      textAlign: TextAlign.center),
                  content: Text(
                      '${preset['frequencies']} Hz\n${preset['gains']} dB\n${ui("同名预设将创建副本。")}'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: Text(ui('取消'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(ui('导入')))
                  ]));
      if (yes == true && mounted)
        await _run((s) => s.add(
            preset['name'] as String,
            (preset['gains'] as List)
                .map((g) => (g as num).toDouble())
                .toList()));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: AppDialogTitle(ui('用户 EQ 预设')),
          content: AppDialogContent(
              width: 620,
              maxHeight: 440,
              child: ListView(shrinkWrap: true, children: [
                TextField(
                    controller: _name,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: ui('预设名称'))),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _run((s) => s.add(
                              _name.text, List.of(widget.service.eqGains))),
                      child: Text(ui('保存当前调节'))),
                  OutlinedButton(
                      onPressed: _busy ? null : _import,
                      child: Text(ui('导入 JSON')))
                ]),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
                for (final preset in _items)
                  AppActionListTile(
                      title: preset['name'] as String,
                      subtitle: ui('10 频段 · {0} 至 {1} dB', [
                        (preset['gains'] as List)
                            .cast<num>()
                            .reduce((a, b) => a < b ? a : b)
                            .toStringAsFixed(1),
                        (preset['gains'] as List)
                            .cast<num>()
                            .reduce((a, b) => a > b ? a : b)
                            .toStringAsFixed(1)
                      ]),
                      onTap: _busy
                          ? null
                          : () {
                              if (!widget.service.setEqEnabled(true)) {
                                setState(() => _error = ui('当前输出模式不支持均衡器'));
                                return;
                              }
                              widget.service.applyEqGains(
                                  (preset['gains'] as List)
                                      .map((g) => (g as num).toDouble())
                                      .toList());
                              Navigator.pop(context);
                            },
                      actions: [
                        IconButton(
                            tooltip: ui('重命名为输入名称'),
                            onPressed: _busy
                                ? null
                                : () => _run((s) => s.rename(
                                    preset['id'] as String, _name.text)),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: ui('导出 JSON'),
                            onPressed: _busy
                                ? null
                                : () => _run((_) async {
                                      final f = (SaveFilePicker()
                                            ..title = ui('导出 EQ 预设')
                                            ..fileName = 'eq-preset.json'
                                            ..defaultExtension = 'json'
                                            ..filterSpecification = {
                                              'JSON': '*.json'
                                            })
                                          .getFile();
                                      if (f != null)
                                        await f.writeAsString(
                                            jsonEncode(preset),
                                            flush: true);
                                    }),
                            icon: const Icon(Icons.file_upload_outlined)),
                        IconButton(
                            tooltip: ui('删除'),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    (s) => s.remove(preset['id'] as String)),
                            icon: const Icon(Icons.delete_outline)),
                      ])
              ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(ui('关闭')))
          ]);
}
