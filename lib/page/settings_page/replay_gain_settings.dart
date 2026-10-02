import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class ReplayGainSettings extends StatefulWidget {
  const ReplayGainSettings({super.key});

  @override
  State<ReplayGainSettings> createState() => _ReplayGainSettingsState();
}

class _ReplayGainSettingsState extends State<ReplayGainSettings> {
  String? _error;
  bool _saveFailed = false;
  int _saveGeneration = 0;

  Future<void> _save() async {
    final generation = ++_saveGeneration;
    try {
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = null;
          _saveFailed = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = ui('当前会话已应用，但设置保存失败：{0}', [error]);
          _saveFailed = true;
        });
      }
    }
  }

  void _change(ReplayGainPreferences Function(ReplayGainPreferences) update) {
    final next = update(AppSettings.instance.replayGain.value);
    if (next == AppSettings.instance.replayGain.value) return;
    ++_saveGeneration;
    if (PlayService.playbackReady.value &&
        !PlayService.instance.playbackService.configureReplayGain(next)) {
      setState(() {
        _error = ui('音量均衡暂时无法应用，原设置已保留。');
        _saveFailed = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _saveFailed = false;
    });
    AppSettings.instance.replayGain.value = next;
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ReplayGainPreferences>(
          valueListenable: AppSettings.instance.replayGain,
          builder: (context, preferences, _) => ReplayGainSettingsPanel(
              preferences: preferences,
              onChanged: _change,
              error: _error,
              onRetrySave: _saveFailed ? () => unawaited(_save()) : null));
}

/// Pure presentation: opening settings does not start a decoder or scan files.
class ReplayGainSettingsPanel extends StatelessWidget {
  const ReplayGainSettingsPanel(
      {super.key,
      required this.preferences,
      required this.onChanged,
      this.error,
      this.onRetrySave});
  final ReplayGainPreferences preferences;
  final void Function(ReplayGainPreferences Function(ReplayGainPreferences))?
      onChanged;
  final String? error;
  final VoidCallback? onRetrySave;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsHeader(
          title: ui('ReplayGain 音量均衡'),
          icon: Icons.graphic_eq,
          subtitle: ui('读取已有响度标签，不修改音乐文件；无标签补偿默认关闭。')),
      const SizedBox(height: 12),
      AppSegmentedControl<ReplayGainMode>(
          key: const ValueKey('replay-gain-mode'),
          semanticLabel: ui('ReplayGain 音量均衡'),
          value: preferences.mode,
          onChanged: onChanged == null
              ? null
              : (mode) => onChanged!((current) => current.copyWith(mode: mode)),
          options: [
            AppSegmentOption(
                value: ReplayGainMode.off,
                label: ui('关闭'),
                icon: Icons.volume_off_outlined),
            AppSegmentOption(
                value: ReplayGainMode.track,
                label: ui('曲目均衡'),
                icon: Icons.music_note_outlined),
            AppSegmentOption(
                value: ReplayGainMode.album,
                label: ui('专辑均衡'),
                icon: Icons.album_outlined),
          ]),
      const SizedBox(height: 8),
      Text(ui('曲目模式平衡歌曲之间的音量；专辑模式保留专辑内部的强弱关系，缺少专辑标签时使用曲目标签。')),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, constraints) {
        final change =
            preferences.mode == ReplayGainMode.off ? null : onChanged;
        final controls = [
          _ReplayGainChoice(
              controlId: 'replay-gain-preamp',
              title: ui('ReplayGain 预增益'),
              value: preferences.preampDb,
              onChanged: change == null
                  ? null
                  : (value) =>
                      change((current) => current.copyWith(preampDb: value))),
          _ReplayGainChoice(
              controlId: 'replay-gain-fallback',
              title: ui('无标签补偿'),
              value: preferences.fallbackGainDb,
              onChanged: change == null
                  ? null
                  : (value) => change(
                      (current) => current.copyWith(fallbackGainDb: value))),
        ];
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return constraints.maxWidth / scale >= 560
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: controls[0]),
                const SizedBox(width: 16),
                Expanded(child: controls[1]),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                controls[0],
                const SizedBox(height: 12),
                controls[1],
              ]);
      }),
      const SizedBox(height: 10),
      Text(ui('预增益叠加标签增益或无标签补偿；补偿只用于没有可用增益标签的歌曲。关闭 ReplayGain 时均不生效。')),
      SettingsSwitchTile(
          surface: false,
          controlKey: const ValueKey('replay-gain-prevent-clipping'),
          contentPadding: SettingsSurface.embeddedRowPadding,
          icon: Icons.multitrack_audio,
          title: Text(ui('依据标签峰值限制增益')),
          subtitle: Text(ui('无峰值标签时不额外放大；此选项不限制均衡器等其他处理产生的峰值。')),
          value: preferences.preventClipping,
          onChanged: onChanged == null || preferences.mode == ReplayGainMode.off
              ? null
              : (value) => onChanged!(
                  (current) => current.copyWith(preventClipping: value))),
      if (error != null) ...[
        Text(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (onRetrySave != null)
          TextButton(onPressed: onRetrySave, child: Text(ui('重试保存'))),
      ],
    ]));
  }
}

class _ReplayGainChoice extends StatefulWidget {
  const _ReplayGainChoice(
      {required this.controlId,
      required this.title,
      required this.value,
      required this.onChanged});
  final String controlId, title;
  final double value;
  final ValueChanged<double>? onChanged;
  @override
  State<_ReplayGainChoice> createState() => _ReplayGainChoiceState();
}

class _ReplayGainChoiceState extends State<_ReplayGainChoice> {
  Future<void> _custom() async {
    final value = await showAppDialog<double>(
        context: context,
        builder: (_) =>
            _ReplayGainNumberDialog(title: widget.title, value: widget.value));
    if (mounted && value != null) widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = ReplayGainPreferences.sanitizeGain(widget.value);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          const SizedBox(height: 6),
          AppMenuAnchor(
              style: const MenuStyle(
                  shape: WidgetStatePropertyAll(AppShape.control)),
              menuChildren: [
                for (final gain
                    in {...ReplayGainPreferences.gainPresets, value}.toList()
                      ..sort())
                  MenuItemButton(
                      key: ValueKey('${widget.controlId}-option-$gain'),
                      onPressed: widget.onChanged == null
                          ? null
                          : () => widget.onChanged?.call(gain),
                      leadingIcon: SizedBox.square(
                          dimension: 20,
                          child: gain == value
                              ? const Icon(Icons.check, size: 20)
                              : null),
                      child: Semantics(
                          selected: gain == value,
                          child: Text(ReplayGainPreferences.gainLabel(gain)))),
                MenuItemButton(
                    key: ValueKey('${widget.controlId}-custom'),
                    onPressed: widget.onChanged == null
                        ? null
                        : () => unawaited(_custom()),
                    leadingIcon: const Icon(Icons.edit_outlined, size: 20),
                    child: Text(ui('自定义增益…'))),
              ],
              builder: (context, controller, _) => OutlinedButton(
                  key: ValueKey(widget.controlId),
                  style: appToolbarControlStyle(context),
                  onPressed: widget.onChanged == null
                      ? null
                      : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                  child: AppToolbarLabel(
                      label: ReplayGainPreferences.gainLabel(value),
                      semanticsLabel:
                          '${widget.title}: ${ReplayGainPreferences.gainLabel(value)}',
                      icon: Icons.volume_up_outlined,
                      trailing: const Icon(Icons.expand_more, size: 18)))),
        ]);
  }
}

class _ReplayGainNumberDialog extends StatefulWidget {
  const _ReplayGainNumberDialog({required this.title, required this.value});
  final String title;
  final double value;
  @override
  State<_ReplayGainNumberDialog> createState() =>
      _ReplayGainNumberDialogState();
}

class _ReplayGainNumberDialogState extends State<_ReplayGainNumberDialog> {
  late final _controller = TextEditingController(
      text: ReplayGainPreferences.sanitizeGain(widget.value).toString());
  String? _error;

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null ||
        !value.isFinite ||
        value < ReplayGainPreferences.minimumGainDb ||
        value > ReplayGainPreferences.maximumGainDb) {
      setState(() => _error = ui('请输入 {0} 到 {1} 之间的增益（dB）', [
            ReplayGainPreferences.minimumGainDb.toInt(),
            ReplayGainPreferences.maximumGainDb.toInt()
          ]));
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
        scrollable: true,
        title: AppDialogTitle(widget.title),
        content: AppDialogResize(
            child: SizedBox(
                width: 360,
                child: Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                        key: const ValueKey('replay-gain-number-input'),
                        controller: _controller,
                        autofocus: true,
                        autocorrect: false,
                        maxLength: 20,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                            labelText: ui('增益（dB）'),
                            helperText:
                                '${ReplayGainPreferences.minimumGainDb.toInt()} – '
                                '${ReplayGainPreferences.maximumGainDb.toInt()}',
                            errorText: _error,
                            errorMaxLines: 3,
                            counterText: ''),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => _submit())))),
        actions: [
          AppDialogActions(children: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
            FilledButton(onPressed: _submit, child: Text(ui('确定'))),
          ])
        ]);
  }
}
