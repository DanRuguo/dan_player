import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A theme-colored pill rail, retaining native TabBar keyboard navigation and
/// horizontal scrolling when labels grow or the content window becomes narrow.
class SearchCategoryTabs extends StatelessWidget {
  const SearchCategoryTabs({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    const categories = [
      ('所有', Symbols.manage_search),
      ('总乐库', Symbols.library_music),
      ('联网', Symbols.language),
      ('艺术家', Symbols.person),
      ('专辑', Symbols.album),
    ];
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        key: const ValueKey('search-category-rail'),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 2),
          indicator: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          splashBorderRadius: BorderRadius.circular(24),
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          labelColor: scheme.onPrimaryContainer,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          unselectedLabelStyle: Theme.of(context).textTheme.labelLarge,
          tabs: [
            for (final category in categories)
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(category.$2, size: 19),
                  const SizedBox(width: 7),
                  Text(ui(category.$1)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
