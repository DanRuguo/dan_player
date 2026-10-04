import 'dart:async';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/component/feature_onboarding.dart';
import 'package:dan_player/component/onboarding_guide_prompt.dart';
import 'package:dan_player/component/player_logo.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_auto_refresh.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/utils.dart' show showAppNotice;
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

class WelcomingPage extends StatefulWidget {
  const WelcomingPage({super.key});

  @override
  State<WelcomingPage> createState() => _WelcomingPageState();
}

class _WelcomingPageState extends State<WelcomingPage> {
  late bool _tutorialCompleted = AppSettings.instance.onboardingCompleted;

  void _completeTutorial({bool offerGuide = false}) {
    if (!mounted || _tutorialCompleted) return;
    final firstUse = !AppSettings.instance.onboardingCompleted;
    final route = ModalRoute.of(context);
    AppSettings.instance.onboardingCompleted = true;
    final saved = AppSettings.instance.saveSettings(captureWindowSize: false);
    setState(() => _tutorialCompleted = true);
    if (firstUse && offerGuide) {
      unawaited(_offerGuideAfterSave(saved, route));
    }
  }

  Future<void> _offerGuideAfterSave(
      Future<void> saved, ModalRoute<dynamic>? route) async {
    await saved;
    if (!mounted || route?.isCurrent == false) return;
    // Let the import page mount before opening a dialog. endOfFrame schedules
    // that one frame even when saving finishes after entrance motion settled.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || route?.isCurrent == false) return;
    await showOnboardingGuidePrompt(context);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: _TitleBar(),
      ),
      body: !_tutorialCompleted
          ? FeatureOnboarding(
              onComplete: () => _completeTutorial(offerGuide: true),
              onRestored: _completeTutorial)
          : LayoutBuilder(builder: (context, viewport) {
              final compact = viewport.maxWidth < 480;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 24, vertical: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: DecoratedBox(
                          key: const ValueKey('welcome-library-card'),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 20 : 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Icon(Icons.library_music_outlined,
                                      size: 32,
                                      color: scheme.onPrimaryContainer),
                                ),
                                const SizedBox(height: 20),
                                AppEntrance(
                                  identity: 'welcome-heading',
                                  child: Column(children: [
                                    Text(ui("你的音乐放在哪些文件夹呢？"),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    Text(
                                      ui("软件会扫描这些文件夹（包括所有子文件夹）下的音乐并建立索引。"),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant),
                                    ),
                                  ]),
                                ),
                                const SizedBox(height: 24),
                                const FolderSelectorView(),
                                const SizedBox(height: 20),
                                Divider(color: scheme.outlineVariant),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => showOnboardingRestore(
                                      context,
                                      onRestored: _completeTutorial),
                                  icon:
                                      const Icon(Icons.settings_backup_restore),
                                  label: Text(ui('从备份恢复')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
    );
  }
}

class FolderSelectorView extends StatefulWidget {
  const FolderSelectorView({super.key});

  @override
  State<FolderSelectorView> createState() => _FolderSelectorViewState();
}

class _FolderSelectorViewState extends State<FolderSelectorView> {
  bool selecting = true;
  final List<String> folders = [];
  final applicationSupportDirectory = getAppDataDir();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
        duration: AppMotion.duration(
            context, MotionKind.transitions, AppMotion.standard),
        child: selecting
            ? folderSelector(scheme)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SizedBox(
                  height: 320,
                  child: FutureBuilder(
                    future: applicationSupportDirectory,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                            child: Text(ui('无法打开播放器数据目录，请检查文件夹权限后重试。')));
                      }
                      if (snapshot.data == null) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return BuildIndexStateView(
                        indexPath: snapshot.data!,
                        folders: folders,
                        whenIndexFailed: (error, _) {
                          if (!mounted) return;
                          setState(() => selecting = true);
                          showAppNotice(ui('扫描未完成，可以调整文件夹后重试。'),
                              context: context);
                        },
                        whenIndexBuilt: () async {
                          await Future.wait([
                            AppSettings.instance.saveSettings(),
                            AudioLibrary.initFromIndex(),
                          ]);
                          await OnlineLibrary.instance.initialize();
                          await Future.wait([
                            readCustomAudioOrder(),
                            readPlaylists(),
                          ]);
                          // Do not rely on MiniNowPlaying's first build to create
                          // BASS. A persisted exclusive-output preference must be
                          // prewarmed before the first song tile can be tapped.
                          PlayService.instance.ensurePlaybackInitialized();
                          LibraryAutoRefresh.instance.start();
                          if (context.mounted) {
                            context.go(app_paths.AUDIOS_PAGE);
                          }
                        },
                      );
                    },
                  ),
                ),
              ));
  }

  Future<void> _addFolder() async {
    final dirPicker = DirectoryPicker()..title = ui("选择文件夹");
    final dir = dirPicker.getDirectory();
    if (dir == null || !mounted) return;
    if (!folders.any((path) => path.toLowerCase() == dir.path.toLowerCase())) {
      setState(() => folders.add(dir.path));
    }
  }

  void _startScan() => setState(() => selecting = false);

  Widget folderSelector(ColorScheme scheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (folders.isNotEmpty) ...[
          Container(
            height: (folders.length * 56.0).clamp(56.0, 224.0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListView.builder(
                itemCount: folders.length,
                itemBuilder: (context, i) => AppEntrance(
                  key: ValueKey((folders[i], i)),
                  identity: ('welcome-folder', folders[i]),
                  order: i,
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined, color: scheme.primary),
                    title: Tooltip(
                      message: folders[i],
                      child: Text(folders[i],
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    trailing: IconButton(
                      tooltip: ui("移除"),
                      onPressed: () => setState(() => folders.removeAt(i)),
                      color: scheme.error,
                      icon: const Icon(Symbols.delete),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        AppEntrance(
          identity: 'welcome-folder-actions',
          order: 1,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (folders.isEmpty)
                FilledButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(ui("添加文件夹")),
                )
              else
                OutlinedButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(ui("添加文件夹")),
                ),
              if (folders.isEmpty)
                TextButton(onPressed: _startScan, child: Text(ui('暂不添加')))
              else
                FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(ui('扫描')),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      return DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: PlayerLogo(),
                    ),
                    if (constraints.maxWidth >= 400)
                      Text(
                        "Dan Player",
                        style: TextStyle(color: scheme.onSurface, fontSize: 16),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              const _WindowControlls(),
            ],
          ),
        ),
      );
    });
  }
}

class _WindowControlls extends StatefulWidget {
  const _WindowControlls();

  @override
  State<_WindowControlls> createState() => __WindowControllsState();
}

class __WindowControllsState extends State<_WindowControlls>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }

  @override
  void onWindowRestore() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Wrap(
      spacing: 8.0,
      children: [
        IconButton(
          tooltip: ui("最小化"),
          onPressed: windowManager.minimize,
          icon: const Icon(Symbols.remove),
        ),
        FutureBuilder(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            final isMaximized = snapshot.data ?? false;
            return IconButton(
              tooltip: isMaximized ? ui("还原") : ui("最大化"),
              onPressed: isMaximized
                  ? windowManager.unmaximize
                  : windowManager.maximize,
              icon: Icon(
                isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
              ),
            );
          },
        ),
        IconButton(
          tooltip: ui("退出"),
          onPressed: windowManager.close,
          icon: const Icon(Symbols.close),
        ),
      ],
    );
  }
}
