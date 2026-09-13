import 'dart:async';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/component/feature_onboarding.dart';
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

  void _completeTutorial() {
    AppSettings.instance.onboardingCompleted = true;
    unawaited(AppSettings.instance.saveSettings(captureWindowSize: false));
    setState(() => _tutorialCompleted = true);
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
          ? FeatureOnboarding(onComplete: _completeTutorial)
          : SingleChildScrollView(
              child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppEntrance(
                      identity: 'welcome-heading',
                      child: Column(
                        children: [
                          Text(
                            ui("你的音乐放在哪些文件夹呢？"),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            ui("软件会扫描这些文件夹（包括所有子文件夹）下的音乐并建立索引。"),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => showOnboardingRestore(context,
                          onRestored: _completeTutorial),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: Text(ui('从备份恢复')),
                    ),
                    const FolderSelectorView(),
                  ],
                ),
              ),
            )),
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

    return SizedBox(
      width: 400,
      height: 400,
      child: AnimatedSwitcher(
        duration: AppMotion.standard,
        child: selecting
            ? folderSelector(scheme)
            : FutureBuilder(
                future: applicationSupportDirectory,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(ui('无法打开播放器数据目录，请检查文件夹权限后重试。')));
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ui('扫描未完成，可以调整文件夹后重试。')),
                      ));
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
    );
  }

  Widget folderSelector(ColorScheme scheme) {
    return Column(
      children: [
        AppEntrance(
          identity: 'welcome-folder-actions',
          order: 1,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  // final path = await pickSingleFolder();
                  // if (path == null) return;
                  final dirPicker = DirectoryPicker();
                  dirPicker.title = ui("选择文件夹");

                  final dir = dirPicker.getDirectory();
                  if (dir == null) return;

                  if (!mounted) return;
                  if (!folders.any(
                      (path) => path.toLowerCase() == dir.path.toLowerCase())) {
                    setState(() => folders.add(dir.path));
                  }
                },
                child: Text(ui("添加文件夹")),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    selecting = false;
                  });
                },
                child: Text(ui(folders.isEmpty ? '暂不添加' : '扫描')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),
        Expanded(
          child: ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, i) => AppEntrance(
              key: ValueKey((folders[i], i)),
              identity: ('welcome-folder', folders[i]),
              order: i,
              child: ListTile(
                title: Text(folders[i]),
                trailing: IconButton(
                  tooltip: ui("移除"),
                  onPressed: () {
                    setState(() {
                      folders.removeAt(i);
                    });
                  },
                  color: scheme.error,
                  icon: const Icon(Symbols.delete),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Image.asset("app_icon.ico", width: 24, height: 24),
                  ),
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
