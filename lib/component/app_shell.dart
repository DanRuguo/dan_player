// ignore_for_file: camel_case_types

import 'package:dan_player/component/mini_now_playing.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) {
    return AutomaticUpdateCheck(
      child: ValueListenableBuilder<WindowBackdropStatus>(
        valueListenable: WindowBackdropService.instance,
        builder: (_, status, child) =>
            AppWindowSurface(status: status, child: child!),
        child: ResponsiveBuilder(
          builder: (context, screenType) {
            switch (screenType) {
              case ScreenType.small:
                return _AppShell_Small(page: page);
              case ScreenType.medium:
              case ScreenType.large:
                return _AppShell_Large(page: page);
            }
          },
        ),
      ),
    );
  }
}

class _AppShell_Small extends StatefulWidget {
  const _AppShell_Small({required this.page});

  final Widget page;

  @override
  State<_AppShell_Small> createState() => _AppShell_SmallState();
}

class _AppShell_SmallState extends State<_AppShell_Small> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return TouchEdgeSwipe(
      onSwipeRight: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.maybePop();
        } else {
          scaffoldKey.currentState?.openDrawer();
        }
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.transparent,
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(48.0),
          child: TitleBar(),
        ),
        drawer: const SideNav(),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AppContentSurface(
            child: Stack(
              fit: StackFit.expand,
              children: [widget.page, const MiniNowPlaying()],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppShell_Large extends StatelessWidget {
  const _AppShell_Large({required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: TitleBar(),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ResizableSideNav(),
          Expanded(
            child: Padding(
              // The song capsule already has an 8px bottom inset inside the
              // title bar. Do not double it with another top margin here.
              padding: const EdgeInsets.fromLTRB(0, 0, 12.0, 12.0),
              child: AppContentSurface(
                child: Stack(
                  fit: StackFit.expand,
                  children: [page, const MiniNowPlaying()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exposes one native desktop backdrop behind title, navigation and margins.
/// The main content frame stays opaque; song/lyric pages own their artwork.
class AppWindowSurface extends StatelessWidget {
  const AppWindowSurface({
    super.key,
    this.status = const WindowBackdropStatus(),
    required this.child,
  });

  final WindowBackdropStatus status;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast =
        status.reason == 'high_contrast' || MediaQuery.highContrastOf(context);
    final fallback = _windowFallbackColor(context, status);
    return Stack(
      fit: StackFit.expand,
      children: [
        AppBackdrop(status: status),
        // The native high-contrast window colour may oppose the app's selected
        // light/dark theme. Pair only the transparent chrome's text with it;
        // opaque content panels retain their own readable colour scheme.
        WindowChromeTheme(
          foreground: highContrast
              ? (fallback.computeLuminance() > 0.1791
                  ? Colors.black
                  : Colors.white)
              : null,
          child: child,
        ),
      ],
    );
  }
}

Color _windowFallbackColor(BuildContext context, WindowBackdropStatus status) {
  return status.fallbackColor ??
      (Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF202020)
          : const Color(0xFFF3F3F3));
}

/// A single neutral veil strengthens the native glass without resetting it.
/// The compositor still supplies live desktop blur; this roughly 70% fill only
/// reduces how strongly its colours show through. It is not a blur-radius
/// control or a Flutter blur filter. Title, navigation and exposed margins all
/// share this layer, independent of album colours; content paints above it.
/// Disabled effects retain an opaque neutral or system high-contrast colour.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, this.status = const WindowBackdropStatus()});

  final WindowBackdropStatus status;

  @override
  Widget build(BuildContext context) => SceneBackground(
        scene: BackgroundScene.main,
        status: status,
      );
}

/// A single clipped frame for every routed page and its mini player.
class AppContentSurface extends StatelessWidget {
  const AppContentSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const radius = AppShape.surfaceRadius;

    return AppContentRegion(
        child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 12.0,
            offset: const Offset(0, 2.0),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(
                alpha: isDark ? 0.34 : 0.40,
              ),
            ),
          ),
          child: ColoredBox(color: scheme.surface, child: child),
        ),
      ),
    ));
  }
}
