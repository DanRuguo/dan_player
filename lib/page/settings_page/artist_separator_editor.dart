import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class ArtistSeparatorEditor extends StatelessWidget {
  const ArtistSeparatorEditor({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("自定义艺术家分隔符"),
      icon: Symbols.artist,
      action: FilledButton.icon(
        icon: const Icon(Symbols.edit),
        label: Text(ui("管理艺术家分隔符")),
        onPressed: () {
          showAppDialog(
            context: context,
            dialogBottomInset: 0,
            builder: (context) => const _ArtistSeparatorEditDialog(),
          );
        },
      ),
    );
  }
}

class _ArtistSeparatorEditDialog extends StatefulWidget {
  const _ArtistSeparatorEditDialog();

  @override
  State<_ArtistSeparatorEditDialog> createState() =>
      __ArtistSeparatorEditDialogState();
}

class __ArtistSeparatorEditDialogState
    extends State<_ArtistSeparatorEditDialog> {
  final appSettings = AppSettings.instance;
  late List<String> separators = List.from(appSettings.artistSeparator);
  final currEditController = TextEditingController();
  bool editing = false;

  Widget _separatorTile(String separator) => ListTile(
        title: Text(separator),
        trailing: IconButton(
          tooltip: ui("删除"),
          onPressed: () {
            setState(() => separators.remove(separator));
          },
          icon: const Icon(Symbols.remove),
        ),
      );

  void _addArtistSeparator() {
    final separator = currEditController.text;
    if (separator.isEmpty) return;
    setState(() {
      if (!separators.contains(separator)) separators.add(separator);
      currEditController.clear();
      editing = false;
    });
  }

  @override
  void dispose() {
    currEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: 350.0,
        height: 350.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: AppDialogTitle(
                  ui("管理艺术家分隔符"),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final separator in separators)
                      _separatorTile(separator),
                    if (editing)
                      ListTile(
                        title: Focus(
                          onFocusChange: HotkeysHelper.onFocusChanges,
                          child: TextField(
                            controller: currEditController,
                            autofocus: true,
                            decoration: InputDecoration(
                              suffixIcon: IconButton(
                                tooltip: ui("添加"),
                                onPressed: _addArtistSeparator,
                                icon: const Icon(Symbols.done),
                              ),
                            ),
                            onSubmitted: (_) => _addArtistSeparator(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: editing
                        ? null
                        : () {
                            setState(() => editing = true);
                          },
                    child: Text(ui("新增")),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui("取消")),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: editing
                        ? null
                        : () async {
                            appSettings.artistSeparator = List.of(separators);
                            appSettings.artistSplitPattern =
                                appSettings.artistSeparator.join("|");
                            await appSettings.saveSettings();
                            await AudioLibrary.initFromIndex();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                    child: Text(ui("确定")),
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
