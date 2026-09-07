import 'package:dan_player/app_settings.dart' show getAppDataDir;
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart'
    show customAudioOrderStorageWarning;
import 'package:dan_player/library/library_data_migration.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

class LibraryHealthSettings extends StatelessWidget {
  const LibraryHealthSettings({super.key});
  @override
  Widget build(BuildContext context) => SettingsSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SettingsHeader(
            title: ui('曲库健康与搬迁'),
            icon: Icons.library_add_check_outlined,
            subtitle: ui('查看来源状态，或重新关联已经搬好的音乐目录。')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(ui('检查曲库')),
              onPressed: () => showAppDialog(
                  context: context, builder: (_) => const _HealthDialog())),
          OutlinedButton.icon(
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(ui('重定位目录')),
              onPressed: () => showAppDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const _RelocationDialog())),
          TextButton(
              onPressed: () async {
                final confirmed = await showAppDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                            title: Text(ui('恢复迁移前的资料？')),
                            content: Text(ui(
                                '这会成组恢复最近一次目录迁移前的索引、歌单、统计和歌词等资料，撤销迁移后的相关更改。迁移后新增的资料文件会移入该批次的 displaced 目录保留。音乐文件不会移动。保存恢复任务后将退出，下次启动生效。')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: Text(ui('取消'))),
                              FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: Text(ui('恢复并退出')))
                            ]));
                if (confirmed != true || !context.mounted) return;
                try {
                  final migration = LibraryDataMigration(await getAppDataDir());
                  await LibraryMutationGate.shared
                      .run(migration.scheduleRestore);
                  await shutdownAndExit(throwOnError: true);
                } catch (error) {
                  if (context.mounted) {
                    showAppNotice('$error',
                        context: context, kind: AppNoticeKind.error);
                  }
                }
              },
              child: Text(ui('恢复迁移快照'))),
        ]),
      ]));
}

class _HealthDialog extends StatefulWidget {
  const _HealthDialog();
  @override
  State<_HealthDialog> createState() => _HealthDialogState();
}

class _HealthDialogState extends State<_HealthDialog> {
  LibraryHealthReport? _report;
  String? _error;
  int _checked = 0;
  @override
  void initState() {
    super.initState();
    _inspect();
  }

  Future<void> _inspect() async {
    try {
      final service = LibraryHealthService(await getAppDataDir());
      final report = await service.inspect(AudioLibrary.instance,
          files: true,
          cancelled: () => !mounted,
          onProgress: (value) {
            if (mounted) setState(() => _checked = value);
          });
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AlertDialog(
        scrollable: true,
        title: Text(ui('曲库健康')),
        content: SizedBox(
            width: 520,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (customAudioOrderStorageWarning != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(ui(customAudioOrderStorageWarning!),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_error != null) Text(_error!),
                  if (report == null && _error == null) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(ui('已检查 {0} 首；关闭窗口会停止后续检查。', [_checked])),
                  ],
                  if (report != null) ...[
                    for (final source in report.sources)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(source.availability ==
                                  LibraryAvailability.available
                              ? Icons.check_circle_outline
                              : Icons.cloud_off_outlined),
                          title: Text(source.root, softWrap: true),
                          subtitle: Text(
                              '${ui(source.label)} · ${ui('最近成功扫描')}：${source.lastSuccess?.toLocal().toString().split('.').first ?? ui('尚无记录')}')),
                    const Divider(),
                    Text(ui('确认缺失 {0} · 访问受限 {1} · 未能确认 {2}',
                        [report.missing, report.denied, report.unverified])),
                    const SizedBox(height: 8),
                    Text(ui('元数据待补 {0} · 近期未读取到封面 {1}',
                        [report.pendingMetadata, report.withoutCover])),
                    const SizedBox(height: 8),
                    Text(ui('离线来源保留原记录；封面仅统计近期实际读取失败，不代表全库封面检查。')),
                    for (final value in report.examples)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText(value)),
                  ],
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('关闭')))
        ]);
  }
}

class _RelocationDialog extends StatefulWidget {
  const _RelocationDialog();
  @override
  State<_RelocationDialog> createState() => _RelocationDialogState();
}

class _RelocationDialogState extends State<_RelocationDialog> {
  late final _old = TextEditingController(
      text: AudioLibrary.instance.scanRoots.firstOrNull ?? '');
  final _new = TextEditingController();
  LibraryRelocationPreview? _preview;
  bool _busy = false;
  bool _applying = false, _cancelled = false;
  String? _error;
  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _run({bool apply = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _applying = apply;
      _cancelled = false;
      _error = null;
    });
    try {
      final migration = LibraryDataMigration(await getAppDataDir());
      final mapping = LibraryPathMapping(_old.text, _new.text);
      if (apply) {
        await LibraryMutationGate.shared.run(() => migration.schedule(mapping));
        await shutdownAndExit(throwOnError: true);
      } else {
        final result = await migration.preview(mapping,
            cancelled: () => _cancelled || !mounted);
        if (mounted) setState(() => _preview = result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
        scrollable: true,
        title: Text(ui('重定位音乐目录')),
        content: SizedBox(
            width: 560,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ui(
                      '将旧目录按相对路径关联到新目录。音乐应已搬好；本操作不搬动文件。确认后退出，下次启动成组备份并应用，同时保留歌单顺序、统计与歌词成果。')),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _old,
                      enabled: !_busy,
                      onChanged: (_) => setState(() => _preview = null),
                      decoration: InputDecoration(
                          labelText: ui('旧目录（可填写离线路径）'),
                          border: const OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _new,
                      enabled: !_busy,
                      onChanged: (_) => setState(() => _preview = null),
                      decoration: InputDecoration(
                          labelText: ui('新目录'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                              tooltip: ui('选择文件夹'),
                              icon: const Icon(Icons.folder_open),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final picked = (DirectoryPicker()
                                            ..title = ui('选择搬迁后的音乐目录'))
                                          .getDirectory();
                                      if (picked != null) {
                                        setState(() {
                                          _new.text = picked.path;
                                          _preview = null;
                                        });
                                      }
                                    }))),
                  const SizedBox(height: 12),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (preview != null) ...[
                    Text(ui('映射 {0} 首 · 新位置缺失 {1} 首 · 冲突 {2} 项', [
                      preview.matches,
                      preview.missing,
                      preview.conflicts.length
                    ])),
                    for (final item in preview.examples)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText('${item.$1}\n→ ${item.$2}')),
                    for (final error in preview.conflicts.take(5)) Text(error),
                  ],
                ])),
        actions: [
          TextButton(
              onPressed: _busy && _applying
                  ? null
                  : () {
                      _cancelled = true;
                      Navigator.pop(context);
                    },
              child: Text(ui('取消'))),
          OutlinedButton(
              onPressed: _busy ? null : () => _run(), child: Text(ui('预览映射'))),
          FilledButton(
              onPressed: !_busy && preview?.canApply == true
                  ? () => _run(apply: true)
                  : null,
              child: Text(ui('确认并退出')))
        ]);
  }
}
