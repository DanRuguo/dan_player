import 'package:dan_player/component/app_motion.dart';
// ignore_for_file: camel_case_types

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/side_nav_layout.dart';
import 'package:dan_player/component/sidebar_resource_placement.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/process_resource_coordinator.dart';
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
  const SideNav(
      {super.key,
      this.desktopWidth,
      this.resizing = false,
      this.resourceCoordinator});
  final ProcessResourceCoordinator? resourceCoordinator;

  /// When provided, renders the persistent continuously-sized desktop
  /// navigation. A null value preserves the overlay drawer/legacy rail used by
  /// direct and narrow-window callers.
  final double? desktopWidth;
  final bool resizing;

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
      // The unified category home keeps the existing saved preference index 1.
      final index = app_paths.START_PAGES.indexOf(desPath);
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
      return _SideNavResourceLayout(
          coordinator: resourceCoordinator,
          child: _ContinuousNavigation(
            width: continuousWidth,
            resizing: resizing,
            selectedIndex: selected,
            onDestinationSelected: onDestinationSelected,
          ));
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
              child: _SideNavResourceLayout(
                  coordinator: resourceCoordinator,
                  width: DrawerTheme.of(context).width ?? 304,
                  child: _CenteredNavigationDrawer(
                    selectedIndex: selected,
                    onDestinationSelected: onDestinationSelected,
                  )),
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
              child: _SideNavResourceLayout(
                  coordinator: resourceCoordinator,
                  width: 80,
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
                  )),
            );
        }
      },
    );
  }
}

/// Resource display uses the unused space without recentering navigation.
class _SideNavResourceLayout extends StatelessWidget {
  const _SideNavResourceLayout(
      {required this.child, this.width, this.coordinator});
  final Widget child;
  final double? width;
  final ProcessResourceCoordinator? coordinator;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: AppSettings.instance.processResources,
      child: child,
      builder: (context, preferences, child) {
        return LayoutBuilder(builder: (context, constraints) {
          final show = preferences.enabled &&
              preferences.showInSidebar &&
              constraints.maxHeight >= 180;
          final compact = show &&
              (child is NavigationRail ||
                  child is _ContinuousNavigation &&
                      (width ?? constraints.maxWidth) <=
                          sideNavCompactThreshold(
                              context,
                              destinations
                                  .map((destination) => destination.label)));
          return SizedBox(
              width: width ??
                  (child is _ContinuousNavigation ? child.width : null),
              child: SidebarResourcePlacement(
                  measurementIdentity: (
                    child.runtimeType,
                    width,
                    MediaQuery.textScalerOf(context),
                    MediaQuery.paddingOf(context),
                    uiLanguage.value,
                    Theme.of(context).textTheme,
                  ),
                  bottomInset:
                      ((constraints.maxHeight - 320) / 4).clamp(0.0, 48.0),
                  widthAffectsNavigationExtent: child is! _ContinuousNavigation,
                  navigation: child!,
                  monitor: show
                      ? CompactProcessResourceMonitor(
                          key: const ValueKey('sidebar-process-resources'),
                          surface: ProcessResourceSurface.sidebar,
                          coordinator: coordinator,
                          compactSidebar: compact)
                      : const SizedBox.shrink()));
        });
      });
}

class ResizableSideNav extends StatefulWidget {
  const ResizableSideNav({
    super.key,
    this.preferences,
    this.persist,
    this.resourceCoordinator,
  });

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;
  final ProcessResourceCoordinator? resourceCoordinator;

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
  int? _resizePointer;

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
    if (_preferences.value.sidebarLocked || _resizePointer != null) return;
    _resizePointer = event.pointer;
    _dragStartX = event.position.dx;
    _dragStartWidth = _width;
    setState(() => _dragging = true);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_dragging ||
        event.pointer != _resizePointer ||
        _preferences.value.sidebarLocked) {
      return;
    }
    final next = (_dragStartWidth + event.position.dx - _dragStartX)
        .clamp(
            PlayerExperiencePreferences.minSidebarWidth, _effectiveMax(context))
        .toDouble();
    if (next != _width) setState(() => _width = next);
  }

  void _pointerEnd(int pointer) {
    if (!_dragging || pointer != _resizePointer) return;
    _resizePointer = null;
    setState(() => _dragging = false);
    final current = _preferences.value;
    final next = current.copyWith(sidebarWidth: _width);
    if (next == current) return;
    _preferences.value = next;
    unawaited((widget.persist ??
            () => AppSettings.instance
                .saveSettings(throwOnError: true, captureWindowSize: false))()
        .catchError((Object error, StackTrace trace) {
      LOGGER.e('[sidebar] failed to save width: $error', stackTrace: trace);
      showAppNotice(ui("侧栏宽度保存失败；本次会话仍保留当前宽度"), kind: AppNoticeKind.error);
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
          SideNav(
              desktopWidth: effectiveWidth,
              resizing: _dragging,
              resourceCoordinator: widget.resourceCoordinator),
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
                  onPointerUp: (event) => _pointerEnd(event.pointer),
                  onPointerCancel: (event) => _pointerEnd(event.pointer),
                  child: Center(
                    child: AnimatedContainer(
                      duration: AppMotion.duration(
                          context, MotionKind.feedback, AppMotion.quick),
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

class _ContinuousNavigation extends StatefulWidget {
  const _ContinuousNavigation({
    required this.width,
    required this.resizing,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });
  final double width;
  final bool resizing;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  @override
  State<_ContinuousNavigation> createState() => _ContinuousNavigationState();
}

class _ContinuousNavigationState extends State<_ContinuousNavigation>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _mode = AnimationController(vsync: this);
  late final _label = AnimationController(vsync: this, value: 1);
  late final _visual = Listenable.merge([_mode, _label]);
  bool? _compact;
  double _threshold = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted && _compact != null) setState(_updateTargets);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    UiLanguageScope.watch(context);
    _threshold = sideNavCompactThreshold(
        context, destinations.map((destination) => destination.label));
    _updateTargets();
  }

  @override
  void didUpdateWidget(covariant _ContinuousNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTargets();
  }

  void _updateTargets() {
    final compact = widget.width <= _threshold;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final animate = AppMotion.enabled(context, MotionKind.layout) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (_compact == null || !animate) {
      _mode.value = compact ? 1 : 0;
    } else if (_compact != compact) {
      _mode.animateTo(compact ? 1 : 0,
          duration: AppMotion.emphasized, curve: AppMotion.standardCurve);
    }
    _compact = compact;
    final opacity = widget.resizing && !compact
        ? ((widget.width - _threshold) / 48).clamp(0.0, 1.0)
        : 1.0;
    // Width changes follow the pointer directly; only releasing it starts the
    // recovery clock. The same two finite clocks drive all seven destinations.
    if (widget.resizing || !animate) {
      _label.value = opacity;
    } else if (_label.value != opacity) {
      _label.animateTo(opacity,
          duration: AppMotion.standard, curve: AppMotion.standardCurve);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mode.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = WindowChromeTheme.colorSchemeOf(context);
    final foreground = WindowChromeTheme.foregroundOf(context);
    final compact = _compact!;
    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height;
      final blockHeight = destinations.length * _drawerDestinationHeight;
      final topPadding =
          ((availableHeight - blockHeight) / 2 - _navVisualTopBias)
              .clamp(24.0, 240.0)
              .toDouble();
      return AnimatedBuilder(
        animation: _visual,
        builder: (context, _) => ListView.builder(
          key: const ValueKey('continuous-side-nav-list'),
          padding: EdgeInsets.only(top: topPadding, bottom: 24),
          itemCount: destinations.length,
          itemExtent: _drawerDestinationHeight,
          itemBuilder: (context, index) {
            final destination = destinations[index];
            final selected = index == widget.selectedIndex;
            final mode = _mode.value;
            final surfaceWidth = lerpDouble(widget.width - 32, 44, mode)!;
            final surfaceHeight = lerpDouble(56, 44, mode)!;
            final left = lerpDouble(14, (widget.width - 44) / 2, mode)!;
            final radius = surfaceHeight / 2;
            final iconRight = left + lerpDouble(12, 8, mode)! + 28;
            // Lay out the full label at its final width. Fade it in as the
            // moving icon clears its text area; never squeeze partial glyphs.
            final labelReveal = ((66 - iconRight) / 12).clamp(0.0, 1.0);
            final labelOpacity = _label.value * labelReveal;
            return Tooltip(
              message: compact ? destination.label : '',
              excludeFromSemantics: true,
              waitDuration: const Duration(milliseconds: 350),
              child: Semantics(
                selected: selected,
                button: true,
                label: destination.label,
                child: Stack(children: [
                  PositionedDirectional(
                    start: left,
                    top: (_drawerDestinationHeight - surfaceHeight) / 2,
                    width: surfaceWidth,
                    height: surfaceHeight,
                    child: Material(
                      // Geometry already follows _mode. A second implicit
                      // ShapeBorder tween would leave a circular clip behind
                      // while the icon and label are moving into a wider pill.
                      animationDuration: Duration.zero,
                      color: selected
                          ? scheme.primaryContainer.withValues(
                              alpha: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.68
                                  : 0.78)
                          : Colors.transparent,
                      shape: mode == 1
                          ? const CircleBorder()
                          : RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radius)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('continuous-nav-${destination.desPath}'),
                        onTap: () => widget.onDestinationSelected(index),
                        customBorder: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(radius)),
                        child: Stack(alignment: Alignment.center, children: [
                          PositionedDirectional(
                            start: lerpDouble(12, 8, mode)!,
                            width: 28,
                            top: 0,
                            bottom: 0,
                            child: AppEntrance(
                              identity: ('nav-icon', destination.desPath),
                              order: index,
                              translate: false,
                              child: Icon(destination.icon,
                                  size: 28,
                                  color: selected
                                      ? scheme.onPrimaryContainer
                                      : foreground),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  if (!compact)
                    PositionedDirectional(
                      start: 66,
                      end: 26,
                      top: 4,
                      bottom: 4,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Opacity(
                            key: ValueKey(
                                'nav-label-opacity-${destination.desPath}'),
                            opacity: labelOpacity,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: sideNavLabelStyle(context,
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : foreground,
                                    selected: selected),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            );
          },
        ),
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
