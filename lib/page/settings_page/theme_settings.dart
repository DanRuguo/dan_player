import 'package:dan_player/component/app_presentation.dart';
import 'dart:io';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/services.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/theme_picker_dialog.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';

class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("修改主题"),
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
  const ThemeModeControl({super.key});

  @override
  State<ThemeModeControl> createState() => _ThemeModeControlState();
}

class _ThemeModeControlState extends State<ThemeModeControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("主题模式"),
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
              showTextOnSnackBar(ui('主题模式保存失败，当前选择仅在本次运行生效。'));
            }
          }
        },
      ),
    );
  }
}

class DynamicThemeSwitch extends StatefulWidget {
  const DynamicThemeSwitch({super.key});

  @override
  State<DynamicThemeSwitch> createState() => _DynamicThemeSwitchState();
}

class _DynamicThemeSwitchState extends State<DynamicThemeSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSwitchTile(
      title: Text(ui("专辑封面动态配色")),
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

class SelectFontCombobox extends StatelessWidget {
  const SelectFontCombobox({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("自定义字体"),
      icon: Symbols.text_fields,
      action: FilledButton.icon(
        onPressed: () async {
          final installedFont = await getInstalledFonts();
          if (installedFont == null || installedFont.isEmpty) {
            showTextOnSnackBar("无法获取字体");
            return;
          }

          if (context.mounted) {
            final selectedFont = await showAppDialog<InstalledFont>(
              context: context,
              builder: (context) =>
                  FontSelectorDialog(installedFont: installedFont),
            );
            if (selectedFont == null) return;

            try {
              final fontLoader = FontLoader(selectedFont.fullName);
              fontLoader.addFont(
                File(selectedFont.path).readAsBytes().then((value) {
                  return ByteData.sublistView(value);
                }),
              );
              await fontLoader.load();
              ThemeProvider.instance.changeFontFamily(selectedFont.fullName);

              final settings = AppSettings.instance;
              settings.fontFamily = selectedFont.fullName;
              settings.fontPath = selectedFont.path;
              await settings.saveSettings();
            } catch (err) {
              ThemeProvider.instance.changeFontFamily(null);
              LOGGER.e("[select font] $err");
              if (context.mounted) {
                showTextOnSnackBar(err.toString());
              }
            }
          }
        },
        label: Text(ui("选择字体")),
        icon: const Icon(Symbols.text_fields),
      ),
    );
  }
}

class FontSelectorDialog extends StatelessWidget {
  const FontSelectorDialog({super.key, required this.installedFont});
  final List<InstalledFont> installedFont;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: 350.0,
        height: 400,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: CustomScrollView(
                    key: const ValueKey('font-selector-scroll'),
                    // The header must share the finite scrolling area: long
                    // font names at 200% cannot consume the pinned cancel row.
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: AppDialogTitle(
                                ui("选择字体"),
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(ui("当前字体：{0}",
                                [danFontDisplayName(theme.fontFamily)])),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      SliverList.builder(
                        itemCount: installedFont.length,
                        itemBuilder: (context, i) => ListTile(
                          shape: AppShape.control,
                          title: Text(installedFont[i].fullName),
                          onTap: () => Navigator.pop(context, installedFont[i]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui("取消")),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
