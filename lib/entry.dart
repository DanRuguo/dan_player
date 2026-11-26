import 'dart:async';
import 'package:dan_player/startup_progress.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/multi_selection_lifecycle.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_touch_sound.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_shell.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/component/startup_splash.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/page/album_detail_page.dart';
import 'package:dan_player/page/albums_page.dart';
import 'package:dan_player/page/artist_detail_page.dart';
import 'package:dan_player/page/artists_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/audio_detail_page.dart';
import 'package:dan_player/page/now_playing_audio_detail_page.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/collection_detail_page.dart';
import 'package:dan_player/page/collections_page.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:dan_player/page/playlist_detail_page.dart';
import 'package:dan_player/page/playlists_page.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/page/updating_page.dart';
import 'package:dan_player/page/welcoming_page.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:dan_player/app_paths.dart' as app_paths;

class SlideTransitionPage<T> extends CustomTransitionPage<T> {
  SlideTransitionPage({
    required super.child,
    super.name,
    super.arguments,
    super.restorationId,
    super.key,
    super.maintainState,
  }) : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: _duration,
          reverseTransitionDuration: _duration,
        );

  static Duration get _duration {
    final motion = AppSettings.instance.rendering.value.animations;
    return motion.allows(MotionKind.transitions) ||
            motion.allows(MotionKind.tracking)
        ? AppRouteTransition.enterDuration
        : Duration.zero;
  }

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      AppRouteTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
}

/// The nested pages own their fades and entrances. Keep the shared window
/// chrome fixed instead of adding Material's centred zoom around the shell.
class AppShellPage<T> extends NoTransitionPage<T> {
  const AppShellPage({required super.child, super.key});
}

class Entry extends StatelessWidget {
  Entry({super.key, required this.welcome}) {
    unawaited(LyricViewportBlur.ensureShaderLoaded());
  }
  final bool welcome;

  ThemeData fromSchemeAndFontFamily({
    required ColorScheme colorScheme,
    String? fontFamily,
  }) {
    final bool isDark = colorScheme.brightness == Brightness.dark;

    // For surfaces that use primary color in light themes and surface color in dark
    final Color primarySurfaceColor =
        isDark ? colorScheme.surface : colorScheme.primary;
    final Color onPrimarySurfaceColor =
        isDark ? colorScheme.onSurface : colorScheme.onPrimary;

    return applyAppControlTheme(ThemeData(
      fontFamily: fontFamily ?? danEmbeddedFontFamily,
      fontFamilyFallback: danFontFamilyFallback,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      primaryColor: primarySurfaceColor,
      canvasColor: colorScheme.surface,
      scaffoldBackgroundColor: colorScheme.surface,
      cardColor: colorScheme.surface,
      dividerColor: colorScheme.onSurface.withValues(alpha: 0.12),
      tabBarTheme: TabBarThemeData(indicatorColor: onPrimarySurfaceColor),
      applyElevationOverlayColor: isDark,
      useMaterial3: true,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.13);
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primary.withValues(alpha: 0.09);
            }
            return null;
          }),
          shape: const WidgetStatePropertyAll(AppShape.pill),
        ),
      ),
      // Desktop Flutter's default tooltip is an opaque black rectangle. Use
      // the generated Material palette instead, so icon-only help remains
      // readable without looking detached from the current artwork theme.
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .98),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: .56),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: .16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(AppShape.pill)),
      ),
      elevatedButtonTheme: const ElevatedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(AppShape.pill)),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(AppShape.pill)),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(AppShape.pill)),
      ),
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(AppShape.pill)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: AppShape.card,
        elevation: 3,
      ),
      listTileTheme: const ListTileThemeData(shape: AppShape.control),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShape.surfaceRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .48),
          ),
        ),
        elevation: 6,
        shadowColor: colorScheme.shadow.withValues(alpha: .22),
        surfaceTintColor: Colors.transparent,
        color: colorScheme.surfaceContainerLow,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppShape.cardRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: isDark ? .34 : .42),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? colorScheme.surfaceContainerLow : colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: isDark ? .44 : .20),
        barrierColor: Colors.black.withValues(alpha: isDark ? .56 : .40),
        shape: RoundedRectangleBorder(
          borderRadius: AppShape.dialogRadius,
          side: BorderSide(
            color:
                colorScheme.outlineVariant.withValues(alpha: isDark ? .38 : .46),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(6),
          shadowColor: WidgetStatePropertyAll(
            colorScheme.shadow.withValues(alpha: .22),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor:
              WidgetStatePropertyAll(colorScheme.surfaceContainerLow),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          ),
          side: WidgetStatePropertyAll(BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: .52))),
          shape: const WidgetStatePropertyAll(AppShape.surface),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return UiLanguageScope(
        child: ValueListenableBuilder<UiLanguage>(
            valueListenable: uiLanguage,
            builder: (context, language, _) => ChangeNotifierProvider.value(
                  value: ThemeProvider.instance,
                  builder: (context, _) {
                    final theme = Provider.of<ThemeProvider>(context);
                    return ValueListenableBuilder<RenderingPreferences>(
                        valueListenable: AppSettings.instance.rendering,
                        builder: (context, rendering, _) => MaterialApp.router(
                            themeAnimationDuration:
                                rendering.animations.allows(MotionKind.theme)
                                    ? AppMotion.standard
                                    : Duration.zero,
                            themeAnimationCurve: AppMotion.standardCurve,
                            title: "Dan Player",
                            scaffoldMessengerKey: SCAFFOLD_MESSAGER,
                            debugShowCheckedModeBanner: false,
                            theme: fromSchemeAndFontFamily(
                              fontFamily: theme.fontFamily,
                              colorScheme: theme.lightScheme,
                            ),
                            darkTheme: fromSchemeAndFontFamily(
                              fontFamily: theme.fontFamily,
                              colorScheme: theme.darkScheme,
                            ),
                            themeMode: theme.themeMode,
                            localizationsDelegates:
                                GlobalMaterialLocalizations.delegates,
                            supportedLocales: supportedLocales,
                            locale: language.locale,
                            scrollBehavior: const DanPlayerScrollBehavior(),
                            routerConfig: config,
                            builder: (context, child) => AppFontScope(
                                  policy: theme.fontPolicy,
                                  child: RenderingPreferencesScope(
                                    preferences: AppSettings.instance.rendering,
                                    child: UiLanguageTransition(
                                        child: ValueListenableBuilder<
                                                UiLayoutPreferences>(
                                            valueListenable:
                                                AppSettings.instance.uiLayout,
                                            builder: (context, layout, _) =>
                                                UiLayoutScope(
                                                    preferences: layout,
                                                    child:
                                                        WindowBackdropThemeSync(
                                                      child: PlayerShortcuts(
                                                        child:
                                                            DesktopVisibilityHost(
                                                          child: StartupSplash(
                                                            progress:
                                                                StartupProgress
                                                                    .instance,
                                                            showProgress: layout
                                                                    .startupFooter ==
                                                                StartupFooter
                                                                    .progress,
                                                            child:
                                                                AppTouchSoundScope(
                                                              child:
                                                                  AppPresentationHost(
                                                                child:
                                                                    AppWindowModeHost(
                                                                  child: child ??
                                                                      const SizedBox
                                                                          .shrink(),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    )))),
                                  ),
                                )));
                  },
                )));
  }

  late final GoRouter config = GoRouter(
    navigatorKey: ROUTER_KEY,
    observers: [MultiSelectionRouteObserver()],
    initialLocation:
        welcome ? app_paths.WELCOMING_PAGE : app_paths.UPDATING_DIALOG,
    routes: [
      ShellRoute(
        observers: [MultiSelectionRouteObserver()],
        pageBuilder: (context, state, page) => AppShellPage(
          key: state.pageKey,
          child: AppShell(page: page),
        ),
        routes: [
          /// audios page
          GoRoute(
            path: app_paths.AUDIOS_PAGE,
            pageBuilder: (context, state) {
              if (state.extra != null) {
                return SlideTransitionPage(
                    key: state.pageKey,
                    child: AudiosPage(locateTo: state.extra as Audio));
              }
              return SlideTransitionPage(
                  key: state.pageKey, child: const AudiosPage());
            },
            routes: [
              GoRoute(
                path: "detail",
                pageBuilder: (context, state) => SlideTransitionPage(
                  key: state.pageKey,
                  child: AudioDetailPage(audio: state.extra as Audio),
                ),
              ),
            ],
          ),

          GoRoute(
            path: app_paths.CATEGORIES_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: CategoriesPage(
                initialCategory:
                    MusicCategoryKind.fromName(state.uri.queryParameters['by']),
              ),
            ),
            routes: [
              GoRoute(
                path: 'detail',
                pageBuilder: (context, state) {
                  final kind = MusicCategoryKind.fromName(
                      state.uri.queryParameters['by']);
                  final group = state.extra is MusicCategoryGroup
                      ? state.extra as MusicCategoryGroup
                      : null;
                  final groupId =
                      state.uri.queryParameters['group'] ?? group?.id ?? '';
                  final child = switch (kind) {
                    MusicCategoryKind.artist => ArtistDetailPage.group(
                        groupId: groupId,
                        initialGroup: group?.kind == MusicCategoryKind.artist
                            ? group
                            : null,
                      ),
                    MusicCategoryKind.album => AlbumDetailPage.group(
                        groupId: groupId,
                        initialGroup: group?.kind == MusicCategoryKind.album
                            ? group
                            : null,
                      ),
                    _ => CategoryDetailPage(
                        kind: kind,
                        groupId: groupId,
                        initialGroup: group,
                      ),
                  };
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: child,
                  );
                },
              ),
            ],
          ),

          /// Legacy artist routes and their saved startup index remain valid.
          GoRoute(
            path: app_paths.ARTISTS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const ArtistsPage(),
            ),
            routes: [
              GoRoute(
                path: "detail",
                pageBuilder: (context, state) {
                  final extra = state.extra;
                  final child = extra is Artist
                      ? ArtistDetailPage(artist: extra)
                      : extra is MusicCategoryGroup &&
                              extra.kind == MusicCategoryKind.artist
                          ? ArtistDetailPage.group(
                              groupId: extra.id, initialGroup: extra)
                          : const CategoriesPage(
                              initialCategory: MusicCategoryKind.artist);
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: child,
                  );
                },
              ),
            ],
          ),

          /// albums page
          GoRoute(
            path: app_paths.COLLECTIONS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const CollectionsPage(),
            ),
            routes: [
              GoRoute(
                path: "detail",
                pageBuilder: (context, state) {
                  final collection = state.extra as UserCollection;
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: CollectionDetailPage(collection: collection),
                  );
                },
              ),
            ],
          ),

          /// albums page
          GoRoute(
            path: app_paths.ALBUMS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const AlbumsPage(),
            ),
            routes: [
              GoRoute(
                path: "detail",
                pageBuilder: (context, state) {
                  final extra = state.extra;
                  final child = extra is Album
                      ? AlbumDetailPage(album: extra)
                      : extra is MusicCategoryGroup &&
                              extra.kind == MusicCategoryKind.album
                          ? AlbumDetailPage.group(
                              groupId: extra.id, initialGroup: extra)
                          : const CategoriesPage(
                              initialCategory: MusicCategoryKind.album);
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: child,
                  );
                },
              ),
            ],
          ),

          /// folders page
          GoRoute(
            path: app_paths.FOLDERS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: FoldersPage(
                initialFolderPath: state.uri.queryParameters['folder'],
              ),
            ),
            routes: [
              // Old folder links now open the same in-place tree.
              GoRoute(
                path: "detail",
                redirect: (context, state) {
                  final extra = state.extra;
                  final folderPath = extra is AudioFolder
                      ? extra.path
                      : state.uri.queryParameters['folder'];
                  return Uri(
                    path: app_paths.FOLDERS_PAGE,
                    queryParameters:
                        folderPath == null ? null : {'folder': folderPath},
                  ).toString();
                },
              ),
            ],
          ),

          /// playlists page
          GoRoute(
            path: app_paths.PLAYLISTS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const PlaylistsPage(),
            ),
            routes: [
              GoRoute(
                path: "detail",
                pageBuilder: (context, state) {
                  final playlist = state.extra as Playlist;
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: PlaylistDetailPage(playlist: playlist),
                  );
                },
              ),
            ],
          ),

          /// search page
          GoRoute(
            path: app_paths.SEARCH_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const SearchPage(),
            ),
            routes: [
              GoRoute(
                path: "result",
                pageBuilder: (context, state) {
                  final result = state.extra as UnionSearchResult;
                  return SlideTransitionPage(
                    key: state.pageKey,
                    child: SearchResultPage(searchResult: result),
                  );
                },
              ),
            ],
          ),

          GoRoute(
            path: app_paths.STATISTICS_PAGE,
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: StatisticsPage(
                  initialStorageSection: state.uri.queryParameters['section'],
                  initialStorageFolder: state.uri.queryParameters['folder']),
            ),
          ),

          /// settings page
          GoRoute(
              path: app_paths.SETTINGS_PAGE,
              pageBuilder: (context, state) => SlideTransitionPage(
                    key: state.pageKey,
                    child: SettingsPage(
                        initialSection: state.uri.queryParameters['section'],
                        initialSetting: state.uri.queryParameters['setting'],
                        openIssueDialogOnMount:
                            state.uri.queryParameters['openIssue'] == '1'),
                  ),
              routes: [
                GoRoute(
                  path: "issue",
                  redirect: (context, state) => Uri(
                    path: app_paths.SETTINGS_PAGE,
                    queryParameters: const {
                      'section': 'about',
                      'setting': 'issues',
                      'openIssue': '1',
                    },
                  ).toString(),
                )
              ]),
        ],
      ),

      /// now playing page
      GoRoute(
        path: app_paths.NOW_PLAYING_PAGE,
        pageBuilder: (context, state) => SlideTransitionPage(
          key: state.pageKey,
          maintainState: false,
          child: const NowPlayingPage(),
        ),
        routes: [
          GoRoute(
            path: 'detail',
            pageBuilder: (context, state) => SlideTransitionPage(
              key: state.pageKey,
              child: NowPlayingAudioDetailPage(audio: state.extra as Audio),
            ),
          ),
        ],
      ),

      /// welcoming page
      GoRoute(
        path: app_paths.WELCOMING_PAGE,
        pageBuilder: (context, state) => SlideTransitionPage(
          key: state.pageKey,
          child: const WelcomingPage(),
        ),
      ),

      /// updating dialog
      GoRoute(
        path: app_paths.UPDATING_DIALOG,
        pageBuilder: (context, state) => SlideTransitionPage(
          key: state.pageKey,
          child: const UpdatingPage(),
        ),
      ),
    ],
  );

  final supportedLocales = const [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko')
  ];
}
