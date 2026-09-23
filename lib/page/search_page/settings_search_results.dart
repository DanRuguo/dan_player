import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class SettingsSearchResultsView extends StatelessWidget {
  const SettingsSearchResultsView({super.key, required this.query, this.open});
  final String query;
  final ValueChanged<SettingsSearchEntry>? open;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final entries = searchSettings(query);
    return AppContentScrollbar(
        builder: (context, controller) => ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 100),
            itemCount: entries.isEmpty ? 1 : entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (entries.isEmpty) {
                return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(ui('没有匹配设置项'), textAlign: TextAlign.center));
              }
              final entry = entries[index];
              return SettingsSurface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                      key: ValueKey('settings-result-${entry.id}'),
                      leading: const Icon(Symbols.settings),
                      title: Text(ui(entry.title)),
                      subtitle: Text(ui(entry.sectionTitle)),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => open != null
                          ? open!(entry)
                          : context.push(entry.location)));
            }));
  }
}
