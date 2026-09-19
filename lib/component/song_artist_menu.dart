import 'package:dan_player/component/readable_ellipsis_text.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Shares the regular song menu's typography and native hover/keyboard submenu
/// behavior. Original names are kept for existing library lookup keys.
class SongArtistMenu extends StatelessWidget {
  const SongArtistMenu({
    super.key,
    required this.artists,
    required this.onSelected,
  });

  final Iterable<String> artists;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final names = <String, String>{};
    for (final original in artists) {
      final label = original.trim();
      if (label.isNotEmpty) names.putIfAbsent(label, () => original);
    }
    final availableWidth =
        (MediaQuery.sizeOf(context).width - 96).clamp(64.0, 336.0);
    Widget item(MapEntry<String, String> name) => MenuItemButton(
          onPressed: () => onSelected(name.value),
          leadingIcon: const Icon(Symbols.artist),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: availableWidth),
            child: ReadableEllipsisText(name.key),
          ),
        );
    if (names.isEmpty) return const SizedBox.shrink();
    if (names.length == 1) return item(names.entries.single);
    return SubmenuButton(
      leadingIcon: const Icon(Symbols.artist),
      menuStyle: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(420, double.infinity)),
      ),
      menuChildren: [for (final name in names.entries) item(name)],
      child: Text(ui('艺术家')),
    );
  }
}
