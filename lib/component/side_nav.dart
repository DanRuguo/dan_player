import 'package:dan_player/component/app_motion.dart';
// ignore_for_file: camel_case_types

import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class DestinationDesc {
  final IconData icon;
  final String _label;
  String get label => ui(_label);
  final String desPath;
  DestinationDesc(this.icon, this._label, this.desPath);
}

const double _drawerDestinationHeight = 64.0;
const double _navVisualTopBias = 36.0;

final destinations = <DestinationDesc>[
  DestinationDesc(Symbols.library_music, "音乐", app_paths.AUDIOS_PAGE),
  DestinationDesc(Symbols.category, "分类", app_paths.CATEGORIES_PAGE),
  DestinationDesc(
    Symbols.collections_bookmark,
    "歌单",
    app_paths.PLAYLISTS_PAGE,
  ),
  DestinationDesc(Symbols.folder, "文件夹", app_paths.FOLDERS_PAGE),
  DestinationDesc(Symbols.search, "搜索", app_paths.SEARCH_PAGE),
  DestinationDesc(Symbols.monitoring, "统计", app_paths.STATISTICS_PAGE),
  DestinationDesc(Symbols.settings, "设置", app_paths.SETTINGS_PAGE),
];

class SideNav extends StatelessWidget {
  const SideNav({super.key, this.desktopWidth});

  /// When provided, renders the persistent continuously-sized desktop
  /// navigation. A null value preserves the overlay drawer/legacy rail used by
  /// direct and narrow-window callers.
  final double? desktopWidth;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final requestedLocation = GoRouterState.of(context).uri.toString();
    // Keep saved pre-unification routes usable without a second destination.
    final location = requestedLocation.startsWith(app_paths.COLLECTIONS_PAGE)
        ? app_paths.PLAYLISTS_PAGE
        : requestedLocation.startsWith(app_paths.ARTISTS_PAGE) ||
                requestedLocation.startsWith(app_paths.ALBUMS_PAGE)
            ? app_paths.CATEGORIES_PAGE
            : requestedLocation;
    int selected = destinations.indexWhere(
      (desc) => location.startsWith(desc.desPath),
    );

    void onDestinationSelected(int value) {
      if (value == selected) return;

      final desPath = destinations[value].desPath;
      // Existing preference index 1 still remains /artists. New categories
      // use that compatible entry rather than shifting any saved indexes.
      final index = app_paths.START_PAGES.indexOf(
          desPath == app_paths.CATEGORIES_PAGE
              ? app_paths.ARTISTS_PAGE
              : desPath);
      if (index != -1) AppPreference.instance.startPage = index;

      // These are peer, top-level destinations. Replacing the location keeps
      // repeated sidebar switches from retaining every previous page (and its
      // listeners) on the Navigator stack. Detail-page links still use push.
      context.go(destinations[value].desPath);

      var scaffold = Scaffold.of(context);
      if (scaffold.hasDrawer) scaffold.closeDrawer();
    }

    final continuousWidth = desktopWidth;
    if (continuousWidth != null) {
      return _ContinuousNavigation(
        width: continuousWidth,
        selectedIndex: selected,
        onDestinationSelected: onDestinationSelected,
      );
    }

    return ResponsiveBuilder(
      builder: (context, screenType) {
        // A narrow drawer overlays app content, not the native desktop. Its
        // foreground must remain paired with its own themed surface.
        final scheme = screenType == ScreenType.small
            ? Theme.of(context).colorScheme
            : WindowChromeTheme.colorSchemeOf(context);
        final unselectedForeground = screenType == ScreenType.small
            ? scheme.onSurface
            : WindowChromeTheme.foregroundOf(context);
        final labelTheme = NavigationDrawerThemeData(
          tileHeight: _drawerDestinationHeight,
          indicatorSize: const Size(272.0, 56.0),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return danCjkTextStyle(
              color:
                  selected ? scheme.onPrimaryContainer : unselectedForeground,
              fontSize: 16.0,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color:
                  selected ? scheme.onPrimaryContainer : unselectedForeground,
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
            final navigation = NavigationDrawerTheme(
              data: labelTheme,
              child: _CenteredNavigationDrawer(
                selectedIndex: selected,
                onDestinationSelected: onDestinationSelected,
              ),
            );
            // Desktop navigation and the exposed bottom/right margins share
            // the Windows compositor's desktop backdrop. A separate
            // sidebar tint/filter creates a visible seam at its bottom edge.
            return screenType == ScreenType.small
                ? _FrostedDrawer(child: navigation)
                : navigation;
          case ScreenType.medium:
            return NavigationRailTheme(
              data: NavigationRailThemeData(
                elevation: 0,
                labelType: NavigationRailLabelType.all,
                selectedLabelTextStyle: danCjkTextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelTextStyle: danCjkTextStyle(
                  color: unselectedForeground,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                selectedIconTheme: IconThemeData(
                  color: scheme.onPrimaryContainer,
                  size: 27.0,
                ),
                unselectedIconTheme: IconThemeData(
                  color: unselectedForeground,
                  size: 27.0,
                ),
                indicatorColor: scheme.primaryContainer.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.68
                      : 0.78,
                ),
              ),
              child: NavigationRail(
                groupAlignment: -0.14,
                // All destinations must remain reachable at the normal
                // window's minimum height and with large accessibility text.
                scrollable: true,
                backgroundColor: Colors.transparent,
                selectedIndex: selected < 0 ? null : selected,
                onDestinationSelected: onDestinationSelected,
                destinations: List.generate(
                  destinations.length,
                  (i) => NavigationRailDestination(
                    icon: AppEntrance(
                      identity: ('nav-icon', destinations[i].desPath),
                      order: i,
                      child: Icon(destinations[i].icon, size: 27.0),
                    ),
                    label: AppEntrance(
                      identity: ('nav-label', destinations[i].desPath),
                      order: i,
                      child: Text(destinations[i].label),
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

class ResizableSideNav extends StatefulWidget {
  const ResizableSideNav({
    super.key,
    this.preferences,
    this.persist,
  });

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<ResizableSideNav> createState() => _ResizableSideNavState();
}

class _ResizableSideNavState extends State<ResizableSideNav> {
  late ValueNotifier<PlayerExperiencePreferences> _preferences;
  late double _width;
  bool _dragging = false;
  bool _hovering = false;
  double _dragStartX = 0;
  double _dragStartWidth = 0;

  @override
  void initState() {
    super.initState();
    _attachPreferences();
  }

  void _attachPreferences() {
    _preferences = widget.preferences ?? AppSettings.instance.experience;
    _width = PlayerExperiencePreferences.safeSidebarWidth(
        _preferences.value.sidebarWidth);
    _preferences.addListener(_preferenceChanged);
  }

  void _preferenceChanged() {
    if (!mounted || _dragging) return;
    final next = PlayerExperiencePreferences.safeSidebarWidth(
        _preferences.value.sidebarWidth);
    if (next != _width) setState(() => _width = next);
  }

  @override
  void didUpdateWidget(covariant ResizableSideNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.preferences ?? AppSettings.instance.experience;
    if (!identical(next, _preferences)) {
      _preferences.removeListener(_preferenceChanged);
      _attachPreferences();
    }
  }

  double _effectiveMax(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 480.0;
    return available
        .clamp(PlayerExperiencePreferences.minSidebarWidth,
            PlayerExperiencePreferences.maxSidebarWidth)
        .toDouble();
  }

  void _pointerDown(PointerDownEvent event) {
    if (_preferences.value.sidebarLocked) return;
    _dragStartX = event.position.dx;
    _dragStartWidth = _width;
    setState(() => _dragging = true);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_dragging || _preferences.value.sidebarLocked) return;
    final next = (_dragStartWidth + event.position.dx - _dragStartX)
        .clamp(
            PlayerExperiencePreferences.minSidebarWidth, _effectiveMax(context))
        .toDouble();
    if (next != _width) setState(() => _width = next);
  }

  void _pointerEnd() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    final current = _preferences.value;
    final next = current.copyWith(sidebarWidth: _width);
    if (next == current) return;
    _preferences.value = next;
    unawaited((widget.persist ??
            () => AppSettings.instance.saveSettings(throwOnError: true))()
        .catchError((Object error, StackTrace trace) {
      LOGGER.e('[sidebar] failed to save width: $error', stackTrace: trace);
      showTextOnSnackBar("侧栏宽度保存失败；本次会话仍保留当前宽度");
    }));
  }

  @override
  void dispose() {
    _preferences.removeListener(_preferenceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final locked = _preferences.value.sidebarLocked;
    final effectiveWidth = _width.clamp(
      PlayerExperiencePreferences.minSidebarWidth,
      _effectiveMax(context),
    );
    final scheme = WindowChromeTheme.colorSchemeOf(context);
    return SizedBox(
      key: const ValueKey('resizable-side-nav'),
      width: effectiveWidth,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SideNav(desktopWidth: effectiveWidth),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: 10,
            child: Semantics(
              label: locked ? ui("侧栏宽度已锁定") : ui("拖动调整侧栏宽度"),
              child: MouseRegion(
                cursor: locked
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.resizeLeftRight,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: Listener(
                  key: const ValueKey('side-nav-resize-handle'),
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: (_) => _pointerEnd(),
                  onPointerCancel: (_) => _pointerEnd(),
                  child: Center(
                    child: AnimatedContainer(
                      duration: AppMotion.quick,
                      width: _dragging || _hovering ? 3 : 1,
                      height: _dragging || _hovering ? 56 : 28,
                      decoration: BoxDecoration(
                        color: locked
                            ? scheme.outlineVariant.withValues(alpha: 0.35)
                            : scheme.primary.withValues(
                                alpha: _dragging
                                    ? 0.82
                                    : _hovering
                                        ? 0.52
                                        : 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinuousNavigation extends StatelessWidget {
  const _ContinuousNavigation({
    required this.width,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final double width;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = WindowChromeTheme.colorSchemeOf(context);
    final foreground = WindowChromeTheme.foregroundOf(context);
    final labelProgress =
        ((width - PlayerExperiencePreferences.compactSidebarThreshold) / 72.0)
            .clamp(0.0, 1.0);
    final compact = labelProgress == 0;
    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height;
      final blockHeight = destinations.length * _drawerDestinationHeight;
      final topPadding =
          ((availableHeight - blockHeight) / 2 - _navVisualTopBias)
              .clamp(24.0, 240.0)
              .toDouble();
      return ListView.builder(
        key: const ValueKey('continuous-side-nav-list'),
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 14,
          topPadding,
          compact ? 8 : 18,
          24,
        ),
        itemCount: destinations.length,
        itemExtent: _drawerDestinationHeight,
        itemBuilder: (context, index) {
          final destination = destinations[index];
          final selected = index == selectedIndex;
          final destinationSurface = Material(
            color: selected
                ? scheme.primaryContainer.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.68
                        : 0.78)
                : Colors.transparent,
            shape: compact ? const CircleBorder() : const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('continuous-nav-${destination.desPath}'),
              onTap: () => onDestinationSelected(index),
              customBorder:
                  compact ? const CircleBorder() : const StadiumBorder(),
              child: compact
                  ? Center(
                      child: AppEntrance(
                        identity: ('nav-icon', destination.desPath),
                        order: index,
                        translate: false,
                        child: Icon(
                          destination.icon,
                          size: 28,
                          color:
                              selected ? scheme.onPrimaryContainer : foreground,
                        ),
                      ),
                    )
                  : Row(children: [
                      SizedBox(
                        width: 52,
                        child: Center(
                          child: AppEntrance(
                            identity: ('nav-icon', destination.desPath),
                            order: index,
                            child: Icon(
                              destination.icon,
                              size: 28,
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : foreground,
                            ),
                          ),
                        ),
                      ),
                      if (labelProgress > 0)
                        Expanded(
                          child: ClipRect(
                            child: Opacity(
                              opacity: labelProgress,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: AppEntrance(
                                  identity: ('nav-label', destination.desPath),
                                  order: index,
                                  child: Text(
                                    destination.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: danCjkTextStyle(
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : foreground,
                                      fontSize: 16,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
            ),
          );
          final destinationButton = Semantics(
            selected: selected,
            button: true,
            label: destination.label,
            child: compact
                ? Center(
                    child: SizedBox.square(
                      dimension: 44,
                      child: destinationSurface,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: destinationSurface,
                  ),
          );
          // Expanded and transitioning layouts already have an inline label.
          // Tooltip help is reserved for the true icon-only endpoint.
          return compact
              ? Tooltip(
                  message: destination.label,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 52,
                      child: destinationButton,
                    ),
                  ),
                )
              : destinationButton;
        },
      );
    });
  }
}

class _CenteredNavigationDrawer extends StatelessWidget {
  const _CenteredNavigationDrawer({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final destinationBlockHeight =
            destinations.length * _drawerDestinationHeight;
        final topPadding =
            ((availableHeight - destinationBlockHeight) / 2 - _navVisualTopBias)
                .clamp(24.0, 240.0);

        return NavigationDrawer(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          tilePadding: const EdgeInsetsDirectional.only(
            start: 12.0,
            end: 18.0,
          ),
          children: [
            SizedBox(height: topPadding),
            ...List.generate(
              destinations.length,
              (i) => NavigationDrawerDestination(
                // Keep the destination itself a direct drawer child: Flutter
                // assigns its selection index and touch target by widget type.
                icon: AppEntrance(
                  identity: ('nav-icon', destinations[i].desPath),
                  order: i,
                  child: Icon(destinations[i].icon, size: 28.0),
                ),
                label: AppEntrance(
                  identity: ('nav-label', destinations[i].desPath),
                  order: i,
                  child: Text(destinations[i].label),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FrostedDrawer extends StatelessWidget {
  const _FrostedDrawer({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context) ||
        context
                .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
                ?.foreground !=
            null;
    if (highContrast) {
      // Native setting notifications can arrive before MediaQuery updates.
      // The chrome override also signals that an opaque drawer is required.
      return ColoredBox(color: scheme.surface, child: child);
    }
    // Only the narrow-window overlay drawer needs to blur the page beneath it.
    // Persistent desktop navigation stays transparent to the native backdrop.
    return FrostedSurface(
      borderRadius: BorderRadius.zero,
      blur: 34.0,
      tintColor: scheme.surface.withValues(alpha: isDark ? 0.10 : 0.08),
      showBorder: false,
      boxShadow: const [],
      child: child,
    );
  }
}
