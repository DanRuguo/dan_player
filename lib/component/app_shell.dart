// ignore_for_file: camel_case_types

import 'package:dan_player/component/mini_now_playing.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.small:
            return _AppShell_Small(page: page);
          case ScreenType.medium:
          case ScreenType.large:
            return _AppShell_Large(page: page);
        }
      },
    );
  }
}

class _AppShell_Small extends StatelessWidget {
  const _AppShell_Small({required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: TitleBar(),
      ),
      drawer: const SideNav(),
      body: Stack(children: [
        const _AppBackdrop(),
        page,
        const MiniNowPlaying(),
      ]),
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
      body: Stack(
        children: [
          const _AppBackdrop(),
          Row(
            children: [
              const SideNav(),
              Expanded(
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8.0),
                    ),
                    child: page,
                  ),
                  const MiniNowPlaying()
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: isDark ? 0.20 : 0.32),
              scheme.surface,
              scheme.tertiaryContainer.withValues(alpha: isDark ? 0.16 : 0.26),
            ],
            stops: const [0.0, 0.48, 1.0],
          ),
        ),
      ),
    );
  }
}
