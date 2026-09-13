import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/data/backup_selection.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class BackupDialogChoice {
  const BackupDialogChoice(this.selection, this.password);
  final BackupSelection selection;
  final String? password;
}

enum _BackupScope { all, music, data, custom }

String backupComponentLabel(BackupComponent value) => ui(switch (value) {
      BackupComponent.library => '曲库索引与播放状态',
      BackupComponent.playlists => '歌单与个人整理',
      BackupComponent.statistics => '播放统计',
      BackupComponent.settings => '播放器设置',
      BackupComponent.resources => '封面、歌词与其他缓存',
    });

IconData _componentIcon(BackupComponent value) => switch (value) {
      BackupComponent.library => Symbols.library_music,
      BackupComponent.playlists => Symbols.queue_music,
      BackupComponent.statistics => Symbols.bar_chart,
      BackupComponent.settings => Symbols.settings,
      BackupComponent.resources => Symbols.photo_library,
    };

String backupByteLabel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  if (bytes >= 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

/// The same selection surface is used for export and restoration. A backup's
/// available contents constrain the choices rather than implicitly restoring
/// everything that happened to be in its archive.
class BackupSelectionDialog extends StatefulWidget {
  const BackupSelectionDialog(
      {super.key,
      required this.contents,
      this.restoring = false,
      this.firstUse = false});
  final BackupContents contents;
  final bool restoring;
  final bool firstUse;
  @override
  State<BackupSelectionDialog> createState() => _BackupSelectionDialogState();
}

class _BackupSelectionDialogState extends State<BackupSelectionDialog> {
  late Set<BackupComponent> _components;
  final Set<String> _folders = {};
  _BackupScope get _scope {
    final allData = _components.length == widget.contents.components.length;
    final allMusic = widget.contents.musicFolders.isNotEmpty &&
        _folders.length == widget.contents.musicFolders.length;
    if (allData && allMusic) return _BackupScope.all;
    if (_components.isEmpty && allMusic) return _BackupScope.music;
    if (allData && _folders.isEmpty) return _BackupScope.data;
    return _BackupScope.custom;
  }

  bool _encrypted = false, _showPassword = false;
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _components = {...widget.contents.components};
    if (_components.isEmpty) _selectScope(_BackupScope.music);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _selectScope(_BackupScope value) {
    if (value == _BackupScope.custom) return;
    _components =
        value == _BackupScope.music ? {} : {...widget.contents.components};
    _folders.clear();
    if (value != _BackupScope.data)
      _folders.addAll(widget.contents.musicFolders.map((value) => value.id));
  }

  void _submit() {
    if (_encrypted && !widget.restoring) {
      if (_password.text.isEmpty || _password.text != _confirmation.text) {
        setState(() => _passwordError =
            ui(_password.text.isEmpty ? '请输入备份密码' : '两次输入的密码不一致'));
        return;
      }
    }
    Navigator.pop(
        context,
        BackupDialogChoice(
            BackupSelection(
                components: _components,
                includeMusic: _folders.isNotEmpty,
                musicFolders: _folders),
            _encrypted ? _password.text : null));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final selectedBytes = widget.contents.musicFolders
        .where((folder) => _folders.contains(folder.id))
        .fold(0, (sum, folder) => sum + folder.bytes);
    return AlertDialog(
      scrollable: true,
      constraints: BoxConstraints.tightFor(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0, 688)),
      title: AppDialogTitle(ui(widget.restoring ? '选择恢复内容' : '创建播放器备份'),
          leading: Icon(widget.restoring
              ? Symbols.settings_backup_restore
              : Symbols.backup)),
      content: SizedBox(
          width: 640,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ui(widget.restoring
                    ? '只恢复勾选的内容，其余当前数据保留。歌曲存入目标位置的新文件夹，不覆盖原音乐。'
                    : '音乐与播放器数据可分别选择，压缩保存为一个 .bak 文件。')),
                const SizedBox(height: 16),
                if (widget.restoring) ...[
                  if (widget.firstUse)
                    Text(ui('首次迁移建议选择包含音乐和播放器资料的完整备份，并恢复全部内容；也可以按需选择。')),
                  if (_folders.isEmpty ||
                      _folders.length < widget.contents.musicFolders.length)
                    Text(ui(
                        '未恢复全部音乐：索引不会包含音频本身。原路径不可用的歌曲无法播放，之后可导入音乐或修复路径；已有封面缓存仍可显示。')),
                  if (!_components.contains(BackupComponent.resources))
                    Text(ui('未选择完整缓存资源：随其他资料附带的封面仍可恢复；缺少的封面和歌词需要重新读取或获取。')),
                  const SizedBox(height: 12),
                ],
                AppSegmentedControl<_BackupScope>(
                    value: _scope,
                    semanticLabel: ui('快速选择'),
                    options: [
                      AppSegmentOption(
                          value: _BackupScope.all,
                          label: ui('全部内容'),
                          icon: Symbols.select_all),
                      AppSegmentOption(
                          value: _BackupScope.music,
                          label: ui('全部歌曲'),
                          icon: Symbols.library_music),
                      AppSegmentOption(
                          value: _BackupScope.data,
                          label: ui('全部缓存'),
                          icon: Symbols.database),
                      AppSegmentOption(
                          value: _BackupScope.custom,
                          label: ui('自定义'),
                          icon: Symbols.tune),
                    ],
                    onChanged: (value) => setState(() => _selectScope(value))),
                const SizedBox(height: 16),
                SettingsSurface(
                    padding: EdgeInsets.zero,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final value in BackupComponent.values)
                        if (widget.contents.components.contains(value))
                          CheckboxListTile(
                              key: ValueKey('backup-component-${value.name}'),
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              secondary: Icon(_componentIcon(value),
                                  color: scheme.primary),
                              title: Text(backupComponentLabel(value)),
                              value: _components.contains(value),
                              onChanged: (checked) => setState(() {
                                    if (checked == true) {
                                      _components.add(value);
                                    } else {
                                      _components.remove(value);
                                    }
                                  })),
                      if (widget.contents.components.isEmpty)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(ui('此备份不含播放器缓存'))),
                    ])),
                const SizedBox(height: 16),
                SettingsSurface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      SettingsHeader(
                          title: ui('本地音乐文件夹'),
                          icon: Symbols.folder_copy,
                          subtitle: ui('{0} 个文件夹 · {1} 个源文件 · {2}', [
                            widget.contents.musicFolders.length,
                            widget.contents.musicCount,
                            backupByteLabel(widget.contents.musicBytes)
                          ])),
                      const SizedBox(height: 8),
                      if (widget.contents.musicFolders.isEmpty)
                        Text(ui(
                            widget.restoring ? '此备份不含音乐文件' : '曲库中没有可读取的本地音乐文件'))
                      else ...[
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          TextButton(
                              onPressed: () => setState(() => _folders.addAll(
                                  widget.contents.musicFolders
                                      .map((folder) => folder.id))),
                              child: Text(ui('全选歌曲'))),
                          TextButton(
                              onPressed: () => setState(_folders.clear),
                              child: Text(ui('清除歌曲选择'))),
                        ]),
                        SizedBox(
                            height: (widget.contents.musicFolders.length *
                                    80 *
                                    MediaQuery.textScalerOf(context).scale(1))
                                .clamp(100, 240),
                            child: ListView.builder(
                                primary: false,
                                itemCount: widget.contents.musicFolders.length,
                                itemBuilder: (context, index) {
                                  final folder =
                                      widget.contents.musicFolders[index];
                                  return CheckboxListTile(
                                      key: ValueKey(
                                          'backup-folder-${folder.id}'),
                                      contentPadding: EdgeInsets.zero,
                                      title: Tooltip(
                                          message: folder.name,
                                          child: Text(folder.name,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis)),
                                      subtitle: Text(ui('{0} 个源文件 · {1}', [
                                        folder.songCount,
                                        backupByteLabel(folder.bytes)
                                      ])),
                                      value: _folders.contains(folder.id),
                                      onChanged: (checked) => setState(() {
                                            if (checked == true) {
                                              _folders.add(folder.id);
                                            } else {
                                              _folders.remove(folder.id);
                                            }
                                          }));
                                })),
                      ],
                    ])),
                const SizedBox(height: 12),
                Text(
                    ui('已选 {0} 项缓存 · {1} 个音乐文件夹 · {2}', [
                      _components.length,
                      _folders.length,
                      backupByteLabel(selectedBytes)
                    ]),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.primary)),
                const SizedBox(height: 8),
                Text(ui('所选数据引用的封面和字体会一并保留。音乐文件已压缩的部分通常无法明显缩小；需要足够的临时磁盘空间。'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                if (!widget.restoring) ...[
                  const SizedBox(height: 16),
                  SettingsSwitchTile(
                      surface: false,
                      contentPadding: EdgeInsets.zero,
                      icon: Symbols.lock,
                      title: Text(ui('密码加密')),
                      subtitle: Text(ui('密码区分大小写，支持中文、空格和符号；不保存密码，遗失后无法恢复。')),
                      value: _encrypted,
                      onChanged: (value) => setState(() => _encrypted = value)),
                  if (_encrypted) ...[
                    const SizedBox(height: 8),
                    Text(ui('加密备份的压缩后大小须小于 64 GiB；更大的曲库可按文件夹分批备份。'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    TextField(
                        key: const ValueKey('backup-password'),
                        controller: _password,
                        obscureText: !_showPassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                            labelText: ui('备份密码'),
                            suffixIcon: IconButton(
                                tooltip: ui(_showPassword ? '隐藏密码' : '显示密码'),
                                icon: Icon(_showPassword
                                    ? Symbols.visibility_off
                                    : Symbols.visibility),
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword)))),
                    const SizedBox(height: 12),
                    TextField(
                        key: const ValueKey('backup-password-confirm'),
                        controller: _confirmation,
                        obscureText: !_showPassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                            labelText: ui('再次输入密码'),
                            errorText: _passwordError)),
                  ],
                ],
                if (widget.restoring) ...[
                  const SizedBox(height: 12),
                  Text(ui('恢复在下次启动时生效。只恢复歌曲时会保留当前曲库索引，可随后扫描恢复的音乐文件夹。'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
        FilledButton.icon(
            key: const ValueKey('backup-selection-confirm'),
            onPressed: _components.isEmpty && _folders.isEmpty ? null : _submit,
            icon: Icon(widget.restoring
                ? Symbols.settings_backup_restore
                : Symbols.backup),
            label: Text(ui(widget.restoring ? '恢复所选内容' : '备份所选内容'))),
      ],
    );
  }
}
