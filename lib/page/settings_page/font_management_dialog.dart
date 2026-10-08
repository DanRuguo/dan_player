import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/font/app_font_manager.dart';
import 'package:dan_player/font/font_preferences.dart';
import 'package:dan_player/page/settings_page/font_selector_dialog.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

String fontChoiceName(AppFontChoice choice) =>
    choice.family ??
    switch (choice.id) {
      'source-han-sc' => ui('思源黑体 SC'),
      'source-han-jp' => ui('思源黑体 JP'),
      'google-sans' => 'Google Sans',
      'pretendard' => 'Pretendard',
      _ => ui('思源黑体 SC')
    };

class FontManagementDialog extends StatefulWidget {
  const FontManagementDialog(
      {super.key, this.initial, this.manager, this.persist, this.getFonts});
  final AppFontPreferences? initial;
  final AppFontManager? manager;
  final Future<void> Function()? persist;
  final Future<List<InstalledFont>?> Function()? getFonts;
  @override
  State<FontManagementDialog> createState() => _FontManagementDialogState();
}

class _FontManagementDialogState extends State<FontManagementDialog> {
  late AppFontPreferences _draft =
      widget.initial ?? AppSettings.instance.fontPreferences;
  bool _busy = false;
  bool _saving = false;
  bool _closed = false;
  String? _error;
  AppFontManager get _manager => widget.manager ?? AppFontManager.instance;
  AppFontPolicy get _preview => AppFontPolicy(
      language: uiLanguage.value,
      mixedScripts: _draft.perLanguage && _draft.mixedScripts,
      zh: (_draft.perLanguage ? _draft.zh : _draft.shared).face,
      en: (_draft.perLanguage ? _draft.en : _draft.shared).face,
      ja: (_draft.perLanguage ? _draft.ja : _draft.shared).face,
      ko: (_draft.perLanguage ? _draft.ko : _draft.shared).face);

  Future<void> _installed(UiLanguage? slot) async {
    if (_busy || _closed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fonts = await (widget.getFonts ?? getInstalledFonts)();
      if (!mounted || _closed) return;
      if (fonts == null || fonts.isEmpty) {
        setState(() => _error = ui('无法获取字体'));
        return;
      }
      final current = slot == null ? _draft.shared : _draft.choiceFor(slot);
      final selected = await showAppDialog<InstalledFont>(
          context: context,
          dialogBottomInset: 0,
          builder: (_) => FontSelectorDialog(
              installedFont: fonts,
              currentFont: current.face.family,
              stageSelection: true));
      if (selected != null && mounted && !_closed) {
        setState(() => _draft = _draft.withChoice(
            slot,
            AppFontChoice.custom(
                family: selected.fullName, path: selected.path)));
      }
    } catch (_) {
      if (mounted) setState(() => _error = ui('无法获取字体'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_busy || _closed) return;
    setState(() {
      _busy = true;
      _saving = true;
      _error = null;
    });
    try {
      await _manager.commit(_draft, persist: widget.persist);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = ui('字体应用失败，已保留原字体。'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  Widget _slot(UiLanguage? language) {
    final choice =
        language == null ? _draft.shared : _draft.choiceFor(language);
    final menuWidth =
        math.max(44.0, math.min(360.0, MediaQuery.sizeOf(context).width - 32));
    Widget menuLabel(String label) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.max(1.0, menuWidth - 64)),
        child: Text(label, softWrap: true));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(language?.nativeName ?? ui('所有语言'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 5),
          MenuAnchor(
              style: MenuStyle(
                  shape: const WidgetStatePropertyAll(AppShape.control),
                  maximumSize:
                      WidgetStatePropertyAll(Size(menuWidth, double.infinity))),
              menuChildren: [
                for (final font in appBundledFonts)
                  MenuItemButton(
                      key: ValueKey(
                          'font-choice-${language?.code ?? 'all'}-${font.id}'),
                      leadingIcon: Icon(choice.id == font.id
                          ? Icons.check
                          : Icons.text_fields),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _draft = _draft.withChoice(
                              language, AppFontChoice.bundled(font.id))),
                      child: menuLabel(
                          fontChoiceName(AppFontChoice.bundled(font.id)))),
                const Divider(),
                MenuItemButton(
                    leadingIcon: const Icon(Icons.folder_open),
                    onPressed: _busy ? null : () => _installed(language),
                    child: menuLabel(ui('选择已安装字体'))),
              ],
              builder: (_, controller, child) => OutlinedButton(
                  key: ValueKey('font-slot-${language?.code ?? 'all'}'),
                  onPressed: _busy
                      ? null
                      : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(children: [
                        Expanded(
                            child: Text(fontChoiceName(choice),
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        const Icon(Icons.expand_more)
                      ])))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
        canPop: !_saving,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _closed = true;
        },
        child: Dialog(
            child: AppDialogContent(
                width: 680,
                maxHeight: 740,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: SingleChildScrollView(
                              key: const ValueKey('font-management-scroll'),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AppDialogTitle(ui('字体管理'),
                                        leading: Icon(Icons.text_fields,
                                            color: scheme.primary)),
                                    const SizedBox(height: 12),
                                    Text(ui('主界面、桌面歌词和任务栏共用字体设置；歌曲标签和文件不受影响。')),
                                    const SizedBox(height: 16),
                                    AppSegmentedControl<bool>(
                                        wrapCompactLabel: true,
                                        value: _draft.perLanguage,
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(() => _draft =
                                                _draft.copyWith(
                                                    perLanguage: value)),
                                        options: [
                                          AppSegmentOption(
                                              value: false,
                                              label: ui('统一字体'),
                                              icon: Icons.text_fields,
                                              key: const ValueKey(
                                                  'font-mode-unified')),
                                          AppSegmentOption(
                                              value: true,
                                              label: ui('按语言选择'),
                                              icon: Icons.translate,
                                              key: const ValueKey(
                                                  'font-mode-language'))
                                        ]),
                                    const SizedBox(height: 10),
                                    if (_draft.perLanguage) ...[
                                      SwitchListTile(
                                          key: const ValueKey(
                                              'font-mixed-scripts'),
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(ui('混合文字按语种使用字体')),
                                          subtitle: Text(ui(
                                              '英文、假名与韩文分别使用所选字体；共用汉字结合上下文和界面语言判断，缺字自动回退。')),
                                          value: _draft.mixedScripts,
                                          onChanged: _busy
                                              ? null
                                              : (value) => setState(() =>
                                                  _draft = _draft.copyWith(
                                                      mixedScripts: value))),
                                      LayoutBuilder(builder: (_, constraints) {
                                        final width = constraints.maxWidth >=
                                                480
                                            ? (constraints.maxWidth - 16) / 2
                                            : constraints.maxWidth;
                                        return Wrap(spacing: 16, children: [
                                          for (final language
                                              in UiLanguage.values)
                                            SizedBox(
                                                width: width,
                                                child: _slot(language))
                                        ]);
                                      }),
                                    ] else
                                      _slot(null),
                                    const SizedBox(height: 14),
                                    Container(
                                        key: const ValueKey(
                                            'font-management-preview'),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                            color: scheme.surfaceContainerLow,
                                            borderRadius:
                                                AppShape.controlRadius,
                                            border: Border.all(
                                                color: scheme.outlineVariant)),
                                        child: AppFontScope(
                                            policy: _preview,
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(ui('预览'),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelLarge),
                                                  const SizedBox(height: 8),
                                                  const AppFontText(
                                                      '音乐，让每一句都清晰。\nMusic, clear in every line.\n音楽を、ひとつひとつ鮮やかに。\n음악, 한 줄 한 줄 또렷하게.',
                                                      style: TextStyle(
                                                          fontSize: 20,
                                                          height: 1.5)),
                                                ]))),
                                    const SizedBox(height: 8),
                                    Text(ui('内置字体采用开放许可。自定义字体使用电脑中的原文件，不复制进播放器；删除或移动后会回退。'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color:
                                                    scheme.onSurfaceVariant)),
                                    ValueListenableBuilder<List<AppFontChoice>>(
                                        valueListenable:
                                            _manager.missingCustomFonts,
                                        builder: (_, missing, child) => missing
                                                .isEmpty
                                            ? const SizedBox.shrink()
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Text(
                                                    ui(
                                                        '部分自定义字体不可用，正在使用内置回退；原选择已保留。'),
                                                    style: TextStyle(
                                                        color: scheme.error)))),
                                    if (_error != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(_error!,
                                              key: const ValueKey(
                                                  'font-management-error'),
                                              style: TextStyle(
                                                  color: scheme.error))),
                                  ]))),
                      const SizedBox(height: 14),
                      AppDialogActions(children: [
                        TextButton(
                            key: const ValueKey('font-management-reset'),
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _draft = const AppFontPreferences()),
                            child: Text(ui('恢复推荐字体'))),
                        TextButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            child: Text(ui('取消'))),
                        FilledButton.icon(
                            key: const ValueKey('font-management-apply'),
                            onPressed: _busy ? null : _apply,
                            icon: const Icon(Icons.check),
                            label: Text(ui('应用'))),
                      ]),
                    ])))));
  }
}
