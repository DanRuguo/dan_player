// ignore_for_file: camel_case_types

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class DestinationDesc {
  final IconData icon;
  final String label;
  final String desPath;
  DestinationDesc(this.icon, this.label, this.desPath);
}

final destinations = <DestinationDesc>[
  DestinationDesc(Symbols.library_music, "音乐", app_paths.AUDIOS_PAGE),
  DestinationDesc(Symbols.artist, "艺术家", app_paths.ARTISTS_PAGE),
  DestinationDesc(
    Symbols.collections_bookmark,
    "合集",
    app_paths.COLLECTIONS_PAGE,
  ),
  DestinationDesc(Symbols.folder, "文件夹", app_paths.FOLDERS_PAGE),
  DestinationDesc(Symbols.search, "搜索", app_paths.SEARCH_PAGE),
  DestinationDesc(Symbols.settings, "设置", app_paths.SETTINGS_PAGE),
];

class SideNav extends StatelessWidget {
  const SideNav({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int selected = destinations.indexWhere(
      (desc) => location.startsWith(desc.desPath),
    );

    void onDestinationSelected(int value) {
      if (value == selected) return;

      final index = app_paths.START_PAGES.indexOf(destinations[value].desPath);
      if (index != -1) AppPreference.instance.startPage = index;

      context.push(destinations[value].desPath);

      var scaffold = Scaffold.of(context);
      if (scaffold.hasDrawer) scaffold.closeDrawer();
    }

    return ResponsiveBuilder(
      builder: (context, screenType) {
        final scheme = Theme.of(context).colorScheme;
        final labelTheme = NavigationDrawerThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return danCjkTextStyle(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              fontSize: 16.0,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              size: 28.0,
            );
          }),
          indicatorColor: scheme.primaryContainer.withValues(
            alpha:
                Theme.of(context).brightness == Brightness.dark ? 0.68 : 0.78,
          ),
        );
        switch (screenType) {
          case ScreenType.small:
          case ScreenType.large:
            return _FrostedSideNav(
              screenType: screenType,
              child: NavigationDrawerTheme(
                data: labelTheme,
                child: NavigationDrawer(
                  backgroundColor: Colors.transparent,
                  selectedIndex: selected,
                  onDestinationSelected: onDestinationSelected,
                  children: List.generate(
                    destinations.length,
                    (i) => NavigationDrawerDestination(
                      icon: Icon(destinations[i].icon, size: 28.0),
                      selectedIcon: Icon(destinations[i].icon, size: 28.0),
                      label: Text(destinations[i].label),
                    ),
                  ),
                ),
              ),
            );
          case ScreenType.medium:
            return _FrostedSideNav(
              screenType: screenType,
              child: NavigationRailTheme(
                data: NavigationRailThemeData(
                  labelType: NavigationRailLabelType.all,
                  selectedLabelTextStyle: danCjkTextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelTextStyle: danCjkTextStyle(
                    color: scheme.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  selectedIconTheme: IconThemeData(
                    color: scheme.onPrimaryContainer,
                    size: 27.0,
                  ),
                  unselectedIconTheme: IconThemeData(
                    color: scheme.onSurface,
                    size: 27.0,
                  ),
                  indicatorColor: scheme.primaryContainer.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.68
                        : 0.78,
                  ),
                ),
                child: NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: selected,
                  onDestinationSelected: onDestinationSelected,
                  destinations: List.generate(
                    destinations.length,
                    (i) => NavigationRailDestination(
                      icon: Icon(destinations[i].icon, size: 27.0),
                      selectedIcon: Icon(destinations[i].icon, size: 27.0),
                      label: Text(destinations[i].label),
                    ),
                  ),
                ),
              ),
            );
        }
      },
    );
  }
}

class _FrostedSideNav extends StatelessWidget {
  const _FrostedSideNav({
    required this.screenType,
    required this.child,
  });

  final ScreenType screenType;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = screenType == ScreenType.small
        ? BorderRadius.zero
        : const BorderRadius.only(
            topRight: Radius.circular(18.0),
            bottomRight: Radius.circular(18.0),
          );

    return FrostedSurface(
      borderRadius: radius,
      blur: 34.0,
      tintColor: scheme.surface.withValues(alpha: isDark ? 0.30 : 0.36),
      borderColor: scheme.outlineVariant.withValues(
        alpha: isDark ? 0.42 : 0.62,
      ),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.30 : 0.12),
          blurRadius: 30.0,
          offset: const Offset(8.0, 0.0),
        ),
      ],
      child: child,
    );
  }
}
