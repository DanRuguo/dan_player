import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class ShortcutSettings extends StatefulWidget {
  const ShortcutSettings({super.key, this.persist});

  /// Production uses the atomic app-settings writer. Tests can inject the same
  /// asynchronous contract without creating a native window or touching disk.
  final Future<void> Function()? persist;

  @override
  State<ShortcutSettings> createState() => _ShortcutSettingsState();
}

class _ShortcutSettingsState extends State<ShortcutSettings> {
  bool _saving = false;
  String? _error;

  Future<void> _apply(ShortcutPreferences next) async {
    if (_saving) return;
    final notifier = AppSettings.instance.shortcuts;
    final previous = notifier.value;
    if (next == previous) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    notifier.value = next;
    try {
      final persist = widget.persist;
      if (persist == null) {
        await AppSettings.instance.saveSettings(throwOnError: true);
      } else {
        await persist();
      }
    } catch (error) {
      notifier.value = previous;
      if (mounted) {
        setState(() => _error = ui("快捷键保存失败，已恢复原设置：{0}", [error]));
        showAppNotice(
          ui("快捷键保存失败，已恢复原设置"),
          context: context,
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _record(
    PlayerShortcutDefinition definition,
    ShortcutPreferences preferences,
  ) async {
    if (_saving) return;
    final chord = await showAppDialog<ShortcutChord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShortcutRecorderDialog(
        definition: definition,
        preferences: preferences,
      ),
    );
    if (chord == null || !mounted) return;
    await _apply(preferences.withBinding(definition.command, chord));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: AppSettings.instance.shortcuts,
      builder: (context, preferences, _) => SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = SettingsHeader(
                    title: ui("应用内快捷键"), icon: Icons.keyboard_outlined);
                final reset = TextButton.icon(
                  key: const ValueKey('restore-default-shortcuts'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: _saving
                      ? null
                      : () => unawaited(
                            _apply(ShortcutPreferences.defaults()),
                          ),
                  icon: const Icon(Symbols.restart_alt),
                  label: Text(ui("恢复默认")),
                );
                if (constraints.maxWidth < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      Align(alignment: Alignment.centerRight, child: reset),
                    ],
                  );
                }
                return Row(children: [Expanded(child: title), reset]);
              },
            ),
            const SizedBox(height: 4),
            Text(
              ui("仅在播放器窗口内生效；输入文字、编辑标签或录制按键时不会触发播放操作。"),
            ),
            const SizedBox(height: 12),
            for (final definition in playerShortcutDefinitions)
              _ShortcutBindingRow(
                definition: definition,
                chord: preferences.chordFor(definition.command),
                onPressed: _saving
                    ? null
                    : () => unawaited(
                          _record(definition, preferences),
                        ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('shortcut-save-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShortcutBindingRow extends StatelessWidget {
  const _ShortcutBindingRow({
    required this.definition,
    required this.chord,
    required this.onPressed,
  });

  final PlayerShortcutDefinition definition;
  final ShortcutChord chord;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(builder: (context, constraints) {
        final button = OutlinedButton(
          key: ValueKey('shortcut-${definition.command.name}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          onPressed: onPressed,
          child: Text(chord.label),
        );
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ui(definition.description)),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }
        return Row(children: [
          Expanded(child: Text(ui(definition.description))),
          const SizedBox(width: 12),
          button,
        ]);
      }),
    );
  }
}

class ShortcutRecorderDialog extends StatefulWidget {
  const ShortcutRecorderDialog({
    super.key,
    required this.definition,
    required this.preferences,
  });

  final PlayerShortcutDefinition definition;
  final ShortcutPreferences preferences;

  @override
  State<ShortcutRecorderDialog> createState() => _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<ShortcutRecorderDialog> {
  final FocusNode _focus = FocusNode(debugLabel: 'shortcut-recorder');
  ShortcutChord? _candidate;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  PlayerCommand? get _conflict => _candidate == null
      ? null
      : widget.preferences.conflictingCommand(
          widget.definition.command,
          _candidate!,
        );

  String _description(PlayerCommand command) => playerShortcutDefinitions
      .firstWhere((definition) => definition.command == command)
      .description;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent || event is KeyUpEvent) {
      return KeyEventResult.handled;
    }
    final chord = shortcutChordFromEvent(event, HardwareKeyboard.instance);
    if (chord == null) return KeyEventResult.handled;
    setState(() => _candidate = chord);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final conflict = _conflict;
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(ui("修改“{0}”", [ui(widget.definition.description)])),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('shortcut-recorder'),
            width: 360,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: AppShape.controlRadius,
              border: Border.all(
                color: _focus.hasFocus
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.keyboard, size: 32),
                const SizedBox(height: 12),
                Text(
                  _candidate?.label ?? ui("请按下新的组合键"),
                  key: const ValueKey('shortcut-candidate'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (conflict != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    ui("与“{0}”冲突", [_description(conflict)]),
                    key: const ValueKey('shortcut-conflict'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-shortcut-recording'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ui("取消")),
        ),
        FilledButton(
          key: const ValueKey('save-shortcut-recording'),
          onPressed: _candidate == null || conflict != null
              ? null
              : () => Navigator.of(context).pop(_candidate),
          child: Text(ui("保存")),
        ),
      ],
    );
  }
}
