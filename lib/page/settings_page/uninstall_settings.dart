import 'dart:io';

import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/windows_shell.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class UninstallSettings extends StatefulWidget {
  const UninstallSettings({super.key});

  @override
  State<UninstallSettings> createState() => _UninstallSettingsState();
}

class _UninstallSettingsState extends State<UninstallSettings> {
  late final Future<WindowsInstallation> _installation =
      WindowsShell.instance.installationInfo();
  bool _busy = false;

  Future<void> _open(WindowsInstallation installation) async {
    if (_busy) return;
    if (!installation.canUninstall) {
      try {
        await WindowsShell.instance.openAppFolder();
      } catch (_) {
        showTextOnSnackBar(ui('无法打开程序目录，请稍后重试。'));
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.delete_outline),
        title: Text(ui('卸载 Dan Player')),
        content: Text(ui('播放器将保存状态并退出，然后打开本次安装的卸载向导。您的音乐文件、歌单和设置会保留。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ui('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ui('退出并打开卸载向导'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await WindowsShell.instance.uninstall();
    } catch (error, trace) {
      LOGGER.w('Uninstall handoff: $error', stackTrace: trace);
      showTextOnSnackBar(ui('无法启动卸载向导，请在 Windows“已安装的应用”中卸载 Dan Player。'));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    UiLanguageScope.watch(context);
    return FutureBuilder<WindowsInstallation>(
      future: _installation,
      builder: (context, snapshot) {
        final installation = snapshot.data;
        final subtitle = installation == null
            ? snapshot.hasError
                ? ui('无法读取安装信息，请在 Windows“已安装的应用”中查看。')
                : ui('正在读取安装信息…')
            : installation.canUninstall
                ? ui('卸载程序，保留音乐、歌单和设置。')
                : installation.isPortable
                    ? ui('当前为便携版，无需卸载。退出后可手动删除程序目录；请保留自己的音乐文件。')
                    : ui('此安装的卸载文件不可用，可在 Windows“已安装的应用”中修复或卸载。');
        return SettingsSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SettingsHeader(
                title: ui('应用管理'), icon: Symbols.apps, subtitle: subtitle),
            if (installation != null) ...[
              const SizedBox(height: 12),
              SelectableText(installation.directory,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('uninstall-or-open-folder'),
                onPressed: _busy ? null : () => _open(installation),
                icon: Icon(installation.canUninstall
                    ? Symbols.delete_outline
                    : Symbols.folder_open),
                label: Text(installation.canUninstall
                    ? ui('卸载 Dan Player')
                    : ui('打开程序目录')),
              ),
            ],
          ]),
        );
      },
    );
  }
}
