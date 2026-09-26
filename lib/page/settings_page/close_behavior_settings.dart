import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// The existing closeToTray preference also controls × and Alt+F4. Opening this
/// surface does not initialize playback or interact with the native tray.
class CloseBehaviorSettings extends StatefulWidget {
  const CloseBehaviorSettings({super.key, this.preferences, this.persist});

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<CloseBehaviorSettings> createState() => _CloseBehaviorSettingsState();
}

class _CloseBehaviorSettingsState extends State<CloseBehaviorSettings> {
  int _saveRevision = 0;
  bool _saveFailed = false;

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;

  Future<void> _save() async {
    final preferences = _preferences;
    final revision = ++_saveRevision;
    setState(() => _saveFailed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted &&
          revision == _saveRevision &&
          identical(preferences, _preferences)) {
        setState(() => _saveFailed = true);
      }
    }
  }

  void _change(bool? closeToTray) {
    if (closeToTray == null || closeToTray == _preferences.value.closeToTray) {
      return;
    }
    _preferences.value = _preferences.value.copyWith(closeToTray: closeToTray);
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<PlayerExperiencePreferences>(
      valueListenable: _preferences,
      builder: (context, preferences, _) => SettingsSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SettingsTile(
            surface: false,
            description: ui('退出后操作'),
            icon: Icons.exit_to_app,
            subtitle: ui('点击窗口关闭按钮（×）或按 Alt+F4 时执行所选操作；托盘不可用时直接退出程序。'),
            action: _actionMenu(context, preferences.closeToTray),
          ),
          if (_saveFailed)
            SettingsSaveFeedback(onRetry: () => unawaited(_save())),
        ]),
      ),
    );
  }

  Widget _actionMenu(BuildContext context, bool closeToTray) {
    final width =
        math.max(44.0, math.min(320.0, MediaQuery.sizeOf(context).width - 64));
    final selected = ui(closeToTray ? '缩小到任务栏托盘' : '直接退出程序');
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: AppMenuAnchor(
        crossAxisUnconstrained: false,
        style: MenuStyle(
          shape: const WidgetStatePropertyAll(AppShape.control),
          maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
        ),
        menuChildren: [
          for (final option in [
            (false, '直接退出程序', 0, 'close-behavior-exit'),
            (true, '缩小到任务栏托盘', 1, 'close-behavior-tray'),
          ])
            MenuItemButton(
              key: ValueKey(option.$4),
              autofocus: option.$1 == closeToTray,
              // One glyph keeps visible area and stroke weight matched. The
              // tray choice points down into the same window-shaped outline.
              leadingIcon: SizedBox.square(
                dimension: 20,
                child: RotatedBox(
                  quarterTurns: option.$3,
                  child: const Icon(Icons.exit_to_app, size: 20),
                ),
              ),
              trailingIcon: SizedBox.square(
                  dimension: 20,
                  child: option.$1 == closeToTray
                      ? const Icon(Icons.check, size: 20)
                      : null),
              onPressed: () => _change(option.$1),
              child: Semantics(
                  selected: option.$1 == closeToTray,
                  child: Text(ui(option.$2))),
            ),
        ],
        builder: (context, controller, _) => Semantics(
          label: ui('退出后操作'),
          child: OutlinedButton(
            key: const ValueKey('close-to-tray-setting'),
            // Retain shared control metrics, but let long labels grow at 200%.
            style: appToolbarControlStyle(context)
                .copyWith(fixedSize: const WidgetStatePropertyAll<Size?>(null)),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(selected, textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
