import 'dart:async';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:dan_player/component/ui_layout_options.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'rendering_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// Persistence owner for UI language/layout/rendering; never restarts audio.
class InterfaceSettings extends StatefulWidget {
  const InterfaceSettings({super.key, this.persist});
  final Future<void> Function()? persist;
  @override
  State<InterfaceSettings> createState() => _InterfaceSettingsState();
}

class _InterfaceSettingsState extends State<InterfaceSettings> {
  bool _failed = false;
  int _revision = 0;
  Future<void> _save() async {
    final revision = ++_revision;
    setState(() => _failed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSurface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
              icon: Icons.translate,
              title: ui('界面语言'),
              subtitle: ui('仅切换界面文字，不修改歌曲、歌词或文件。')),
          const SizedBox(height: 12),
          ValueListenableBuilder<UiLanguage>(
              valueListenable: uiLanguage,
              builder: (context, language, _) =>
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final choice in UiLanguage.values)
                      ChoiceChip(
                          key: ValueKey('ui-language-${choice.code}'),
                          label: Text(choice.nativeName),
                          selected: language == choice,
                          onSelected: (selected) {
                            if (!selected || language == choice) return;
                            uiLanguage.value = choice;
                            unawaited(_save());
                          })
                  ])),
        ],
      )),
      const SizedBox(height: 16),
      ValueListenableBuilder<UiLayoutPreferences>(
          valueListenable: AppSettings.instance.uiLayout,
          builder: (context, value, _) => UiLayoutOptions(
              value: value,
              onChanged: (next) {
                AppSettings.instance.uiLayout.value = next;
                unawaited(_save());
              })),
      const SizedBox(height: 16),
      ValueListenableBuilder<RenderingPreferences>(
          valueListenable: AppSettings.instance.rendering,
          builder: (context, value, _) => RenderingSettings(
              value: value,
              onChanged: (next) {
                AppSettings.instance.rendering.value = next;
                unawaited(_save());
              })),
      if (_failed)
        Row(children: [
          Expanded(
              child: Text(ui('保存界面设置失败；本次会话仍然有效。'),
                  style: TextStyle(color: scheme.error))),
          TextButton(onPressed: _save, child: Text(ui('重试')))
        ]),
    ]);
  }
}
