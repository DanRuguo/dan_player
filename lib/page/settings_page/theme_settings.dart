import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/page/settings_page/font_selector_dialog.dart';
export 'package:dan_player/page/settings_page/font_selector_dialog.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/theme_picker_dialog.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Related appearance controls share one surface and keep their own save logic.
class ThemeAppearanceSettings extends StatelessWidget {
  const ThemeAppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) => const SettingsSurface(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ThemeModeControl(surface: false),
          Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1)),
          DynamicThemeSwitch(surface: false),
          Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1)),
          ThemeSelector(surface: false),
        ]),
      );
}

class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key, this.surface = true});
  final bool surface;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      surface: surface,
      description: ui("修改主题"),
      subtitle: ui("选择喜欢的主色，按钮与高亮会统一使用；关闭动态配色后持续使用此颜色。"),
      icon: Symbols.palette,
      action: FilledButton.icon(
        onPressed: () async {
          final seedColor = await showAppDialog<Color>(
            context: context,
            builder: (context) => const ThemePickerDialog(),
          );
          if (seedColor == null) return;

          ThemeProvider.instance.applyTheme(seedColor: seedColor);
          AppSettings.instance.defaultTheme = seedColor.toARGB32();
          await AppSettings.instance.saveSettings();
        },
        label: Text(ui("主题选择器")),
        icon: const Icon(Symbols.palette),
      ),
    );
  }
}

class ThemeModeControl extends StatefulWidget {
  const ThemeModeControl({super.key, this.surface = true});
  final bool surface;

  @override
  State<ThemeModeControl> createState() => _ThemeModeControlState();
}

class _ThemeModeControlState extends State<ThemeModeControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      surface: widget.surface,
      description: ui("主题模式"),
      subtitle: ui("选择浅色、深色，或随系统外观自动切换。"),
      icon: Symbols.contrast,
      action: AppSegmentedControl<ThemeMode>(
        value: settings.themeMode,
        semanticLabel: ui('主题模式'),
        options: [
          AppSegmentOption<ThemeMode>(
            value: ThemeMode.system,
            icon: Symbols.brightness_auto,
            label: ui('跟随系统'),
          ),
          AppSegmentOption<ThemeMode>(
            value: ThemeMode.light,
            icon: Symbols.light_mode,
            label: ui('明亮'),
          ),
          AppSegmentOption<ThemeMode>(
            value: ThemeMode.dark,
            icon: Symbols.dark_mode,
            label: ui('深色'),
          ),
        ],
        onChanged: (newSelection) async {
          if (newSelection == settings.themeMode) return;

          setState(() {
            settings.themeMode = newSelection;
          });
          ThemeProvider.instance.applyThemeMode(settings.themeMode);
          try {
            await settings.saveSettings(
                captureWindowSize: false, throwOnError: true);
          } catch (_) {
            if (mounted) {
              showAppNotice(ui('主题模式保存失败，当前选择仅在本次运行生效。'),
                  context: this.context, kind: AppNoticeKind.error);
            }
          }
        },
      ),
    );
  }
}

class DynamicThemeSwitch extends StatefulWidget {
  const DynamicThemeSwitch({super.key, this.surface = true});
  final bool surface;

  @override
  State<DynamicThemeSwitch> createState() => _DynamicThemeSwitchState();
}

class _DynamicThemeSwitchState extends State<DynamicThemeSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSwitchTile(
      surface: widget.surface,
      contentPadding:
          widget.surface ? SettingsSurface.rowPadding : EdgeInsets.zero,
      title: Text(ui("专辑封面动态配色")),
      subtitle: Text(ui("随当前歌曲封面平滑调整界面颜色；背景图片仍由背景设置决定。")),
      icon: Symbols.auto_awesome,
      value: settings.dynamicTheme,
      onChanged: (_) async {
        setState(() {
          settings.dynamicTheme = !settings.dynamicTheme;
        });
        ThemeProvider.instance.syncDynamicThemeSetting();
        await settings.saveSettings();
      },
    );
  }
}

class WindowBackdropInfo extends StatelessWidget {
  const WindowBackdropInfo({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return const BackgroundSettingsPanel();
  }
}

class SelectFontCombobox extends StatefulWidget {
  const SelectFontCombobox({super.key});

  @override
  State<SelectFontCombobox> createState() => _SelectFontComboboxState();
}

class _SelectFontComboboxState extends State<SelectFontCombobox> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("自定义字体"),
      subtitle: ui("使用电脑上已安装的字体显示界面文字，歌曲标签和文件不受影响。"),
      icon: Symbols.text_fields,
      action: FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  final installedFont = await getInstalledFonts();
                  if (installedFont == null || installedFont.isEmpty) {
                    showAppNotice(ui("无法获取字体"), kind: AppNoticeKind.error);
                    return;
                  }

                  if (context.mounted) {
                    final selectedFont = await showAppDialog<InstalledFont>(
                      context: context,
                      dialogBottomInset: 0,
                      builder: (context) =>
                          FontSelectorDialog(installedFont: installedFont),
                    );
                    if (selectedFont == null) return;

                    final settings = AppSettings.instance;
                    final previousFamily = settings.fontFamily;
                    final previousPath = settings.fontPath;
                    final preview = FontPreviewLoader.instance
                        .acquire(selectedFont, explicit: true);
                    try {
                      if (await preview.family == null) {
                        throw StateError('Selected font is unavailable');
                      }
                      settings.fontFamily = selectedFont.fullName;
                      settings.fontPath = selectedFont.path;
                      await settings.saveSettings(
                          captureWindowSize: false,
                          throwOnError: true,
                          requireCommit: true);
                      ThemeProvider.instance
                          .changeFontFamily(selectedFont.fullName);
                    } catch (err) {
                      settings.fontFamily = previousFamily;
                      settings.fontPath = previousPath;
                      LOGGER.e("[select font] $err");
                      if (context.mounted) {
                        showAppNotice(ui('字体应用失败，已保留原字体。'),
                            context: context, kind: AppNoticeKind.error);
                      }
                    } finally {
                      preview.release();
                    }
                  }
                } catch (err) {
                  LOGGER.e('[installed fonts] $err');
                  if (context.mounted) {
                    showAppNotice(ui('无法获取字体'),
                        context: context, kind: AppNoticeKind.error);
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        label: Text(ui("选择字体")),
        icon: const Icon(Symbols.text_fields),
      ),
    );
  }
}
