import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:desktop_lyric/component/desktop_lyric_taskbar_options.dart';
import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Uses the same immutable preference and options widget as the lyric window.
/// Opening settings never starts playback or creates another helper process.
class DesktopLyricSettings extends StatefulWidget {
  const DesktopLyricSettings({super.key, this.preferences, this.persist});
  final ValueNotifier<DesktopLyricAppearance>? preferences;
  final Future<void> Function()? persist;
  @override
  State<DesktopLyricSettings> createState() => _DesktopLyricSettingsState();
}

class _DesktopLyricSettingsState extends State<DesktopLyricSettings> {
  Timer? _saveTimer;
  String? _error;
  int _revision = 0;
  ValueNotifier<DesktopLyricAppearance> get _preferences =>
      widget.preferences ?? AppSettings.instance.desktopLyricAppearance;

  void _change(DesktopLyricAppearance next) {
    if (next == _preferences.value) return;
    _preferences.value = next;
    ++_revision;
    setState(() => _error = null);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final revision = _revision;
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(captureWindowSize: false, throwOnError: true))();
      if (mounted && revision == _revision) setState(() => _error = null);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = ui("桌面歌词设置保存失败；本次会话仍然生效。"));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
      child: ValueListenableBuilder(
          valueListenable: _preferences,
          builder: (context, appearance, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsHeader(
                      title: ui("桌面歌词显示"),
                      icon: Icons.subtitles_outlined,
                      subtitle: ui(
                          "对已打开的桌面歌词即时生效；未打开时记住选择，不会自动启动歌词窗口。单行模式停靠当前屏幕工作区底部，不嵌入任务栏；侧边任务栏时仍在屏幕底部显示。")),
                  const SizedBox(height: 16),
                  DesktopLyricAppearanceOptions(
                      appearance: appearance, onChanged: _change),
                  const Divider(height: 32),
                  DesktopLyricTaskbarOptions(
                      appearance: appearance, onChanged: _change),
                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    TextButton.icon(
                        onPressed: () => unawaited(_save()),
                        icon: const Icon(Icons.refresh),
                        label: Text(ui("重试保存"))),
                  ],
                ],
              )),
    );
  }

  @override
  void dispose() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      unawaited(_save());
    }
    super.dispose();
  }
}
