import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LibraryWatchSettings extends StatelessWidget {
  const LibraryWatchSettings({super.key, this.enabled, this.save});
  final ValueNotifier<bool>? enabled;
  final Future<void> Function()? save;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final value = enabled ?? AppSettings.instance.libraryAutoRefresh;
    return ValueListenableBuilder<bool>(
      valueListenable: value,
      builder: (context, active, _) => SettingsSwitchTile(
        controlKey: const ValueKey('library-auto-refresh'),
        icon: Symbols.sync,
        title: Text(ui('自动更新音乐库')),
        subtitle: Text(ui('监测已添加文件夹的音乐变化，合并后增量刷新。文件夹暂不可用时保留原曲库。')),
        value: active,
        onChanged: (next) async {
          value.value = next;
          try {
            await (save?.call() ??
                AppSettings.instance.saveSettings(throwOnError: true));
          } catch (_) {
            if (context.mounted) {
              showTextOnSnackBar('自动更新设置尚未保存，请重试。',
                  context: context, kind: AppNoticeKind.error);
            }
          }
        },
      ),
    );
  }
}
