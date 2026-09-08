// ignore_for_file: camel_case_types

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/horizontal_lyric_view.dart';
import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:dan_player/utils.dart' show LOGGER;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Title-bar controls share the window backdrop instead of painting a second
/// material colour or divider over it. Ink and native drag targets still work.
class TitleBarSurface extends StatelessWidget {
  const TitleBarSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Material(type: MaterialType.transparency, child: child);
  }
}

/// The compact song capsule stays vertically centred in the native title-bar
/// row; its lyric content centres short lines within the available width.
/// These are logical pixels on both Windows 10 and Windows 11; Flutter applies
/// the window's DPI scale, so no platform-specific pixel offsets are needed.
class TitleBarSongRegion extends StatelessWidget {
  const TitleBarSongRegion({
    super.key,
    required this.child,
    this.startPadding = 16.0,
    this.endPadding = 16.0,
  })  : assert(startPadding >= 0),
        assert(endPadding >= 0);

  static const double height = 48.0;
  static const double verticalPadding = 8.0;

  final Widget child;
  final double startPadding;
  final double endPadding;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          startPadding,
          verticalPadding,
          endPadding,
          verticalPadding,
        ),
        // A fixed-height title capsule can accommodate 150% body text. Keep
        // larger accessibility scaling elsewhere in the app unchanged.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: child,
          ),
        ),
      ),
    );
  }
}

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    this.songContent = const HorizontalLyricView(),
  });

  /// A content slot keeps window chrome testable without starting playback.
  /// The normal player always uses the live horizontal lyric view.
  final Widget songContent;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final foreground = WindowChromeTheme.foregroundOf(context);
    return TitleBarSurface(
      child: IconTheme(
        data: IconThemeData(
          color: foreground,
          size: 22.0,
        ),
        child: ResponsiveBuilder(
          builder: (context, screenType) {
            switch (screenType) {
              case ScreenType.small:
                return const _TitleBar_Small();
              case ScreenType.medium:
                return _TitleBar_Medium(songContent: songContent);
              case ScreenType.large:
                return _TitleBar_Large(songContent: songContent);
            }
          },
        ),
      ),
    );
  }
}

class _TitleBar_Small extends StatelessWidget {
  const _TitleBar_Small();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final foreground = WindowChromeTheme.foregroundOf(context);

    return SizedBox(
      height: 56.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            const _OpenDrawerBtn(),
            const SizedBox(width: 8.0),
            const NavBackBtn(),
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: AppEntrance(
                    identity: 'title-name',
                    order: 1,
                    child: Text(
                      "Dan Player",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: danCjkTextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const WindowControlls(),
          ],
        ),
      ),
    );
  }
}

class _TitleBar_Medium extends StatelessWidget {
  const _TitleBar_Medium({required this.songContent});

  final Widget songContent;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final foreground = WindowChromeTheme.foregroundOf(context);

    return Row(
      children: [
        const SizedBox(
          width: 80,
          child: Center(child: NavBackBtn()),
        ),
        Expanded(
          child: DragToMoveArea(
            child: Row(
              children: [
                AppEntrance(
                  identity: 'title-name',
                  order: 1,
                  child: Text(
                    "Dan Player",
                    style: danCjkTextStyle(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: TitleBarSongRegion(
                    child: AppEntrance(
                      identity: 'title-song',
                      order: 2,
                      child: songContent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const WindowControlls(),
        const SizedBox(width: 8.0),
      ],
    );
  }
}

class _TitleBar_Large extends StatelessWidget {
  const _TitleBar_Large({required this.songContent});

  final Widget songContent;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final foreground = WindowChromeTheme.foregroundOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          const NavBackBtn(),
          const SizedBox(width: 8.0),
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  SizedBox(
                    width: 248,
                    child: AppEntrance(
                      identity: 'title-name',
                      order: 1,
                      child: Row(
                        children: [
                          Image.asset("app_icon.ico", width: 24, height: 24),
                          const SizedBox(width: 8.0),
                          Text(
                            "Dan Player",
                            style: danCjkTextStyle(
                              color: foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TitleBarSongRegion(
                      startPadding: 0,
                      child: AppEntrance(
                        identity: 'title-song',
                        order: 2,
                        child: songContent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const WindowControlls(),
        ],
      ),
    );
  }
}

class _OpenDrawerBtn extends StatelessWidget {
  const _OpenDrawerBtn();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return IconButton(
      tooltip: ui("打开导航栏"),
      color: WindowChromeTheme.foregroundOf(context),
      onPressed: Scaffold.of(context).openDrawer,
      icon: const AppEntrance(
        identity: 'title-drawer',
        child: Icon(Symbols.menu),
      ),
    );
  }
}

class NavBackBtn extends StatelessWidget {
  const NavBackBtn({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return IconButton(
      tooltip: ui("返回"),
      color: WindowChromeTheme.foregroundOf(context),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        }
      },
      icon: const AppEntrance(
        identity: 'title-back',
        child: Icon(Symbols.navigate_before),
      ),
    );
  }
}

class WindowControlls extends StatefulWidget {
  const WindowControlls({super.key});

  @override
  State<WindowControlls> createState() => _WindowControllsState();
}

class _WindowControllsState extends State<WindowControlls> with WindowListener {
  bool _isFullScreen = false;
  bool _isMaximized = false;
  bool _isProcessing = false;
  int _windowStateRevision = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _updateWindowStates();
  }

  Future<void> _updateWindowStates() async {
    final revision = ++_windowStateRevision;
    try {
      final states = await Future.wait([
        windowManager.isFullScreen(),
        windowManager.isMaximized(),
      ]).timeout(const Duration(seconds: 2));
      if (mounted && revision == _windowStateRevision) {
        setState(() {
          _isFullScreen = states[0];
          _isMaximized = states[1];
        });
      }
    } catch (error, trace) {
      // A failed native status read must not disable all window controls or
      // escape an unawaited WindowListener callback. Keep the last known state.
      LOGGER.w('读取窗口状态失败：$error', stackTrace: trace);
    }
  }

  Future<void> _toggleFullScreen() async {
    if (_isProcessing || WindowModeController.instance.isBusy) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await HotkeysHelper.runCommand(PlayerCommand.toggleFullScreen);
    } catch (error) {
      HotkeysHelper.showError(ui("切换全屏失败：{0}", [error]));
    } finally {
      await _finishWindowOperation();
    }
  }

  Future<void> _toggleMaximized() async {
    if (_isProcessing ||
        WindowModeController.instance.isBusy ||
        AppSettings.instance.experience.value.windowSizeLocked) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_isMaximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (error) {
      HotkeysHelper.showError(ui("切换窗口大小失败：{0}", [error]));
    } finally {
      await _finishWindowOperation();
    }
  }

  Future<void> _finishWindowOperation() async {
    try {
      if (mounted) await _updateWindowStates();
    } finally {
      // Only the operation owner releases this guard. Native resize events
      // may refresh state while the operation is still in flight.
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    _updateWindowStates();
    // Maximize/restore notifications can arrive while Windows is still
    // animating the frame. Persist only the state here; the stable restored
    // size is sampled from onWindowResized (WM_EXITSIZEMOVE) or at shutdown.
    AppSettings.instance.saveSettings(captureWindowSize: false);
  }

  @override
  void onWindowUnmaximize() {
    _updateWindowStates();
    AppSettings.instance.saveSettings(captureWindowSize: false);
  }

  @override
  void onWindowRestore() {
    _updateWindowStates();
    AppSettings.instance.saveSettings(captureWindowSize: false);
  }

  @override
  void onWindowResized() {
    _updateWindowStates();
    // window_manager emits this after the interactive resize loop finishes on
    // Windows, so it is safe to replace the cached normal-window size.
    AppSettings.instance.saveSettings();
  }

  @override
  void onWindowEnterFullScreen() {
    super.onWindowEnterFullScreen();
    _updateWindowStates();
    AppSettings.instance.saveSettings(captureWindowSize: false);
  }

  @override
  void onWindowLeaveFullScreen() {
    super.onWindowLeaveFullScreen();
    _updateWindowStates();
    AppSettings.instance.saveSettings(captureWindowSize: false);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final foreground = WindowChromeTheme.foregroundOf(context);
    final controlStyle = IconButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: foreground.withValues(alpha: .38),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([
        WindowModeController.instance,
        AppSettings.instance.shortcuts,
        AppSettings.instance.experience,
      ]),
      builder: (context, _) {
        final sizeLocked =
            AppSettings.instance.experience.value.windowSizeLocked;
        return Wrap(
          spacing: 8.0,
          children: [
            IconButton(
              tooltip: ui("最小化"),
              style: controlStyle,
              onPressed: windowManager.minimize,
              icon: const AppEntrance(
                identity: 'title-minimize',
                order: 3,
                child: Icon(Symbols.remove),
              ),
            ),
            IconButton(
              key: const ValueKey('title-mini-control'),
              tooltip: ui("迷你播放器（{0}）",
                  [HotkeysHelper.shortcutLabel(PlayerCommand.toggleMini)]),
              onPressed: _isProcessing || WindowModeController.instance.isBusy
                  ? null
                  : () async {
                      try {
                        await HotkeysHelper.runCommand(
                            PlayerCommand.toggleMini);
                      } catch (error) {
                        HotkeysHelper.showError('$error');
                      }
                    },
              style: controlStyle,
              icon: const AppEntrance(
                identity: 'title-mini',
                order: 4,
                child: Icon(Symbols.picture_in_picture_alt),
              ),
            ),
            IconButton(
              key: const ValueKey('title-fullscreen-control'),
              tooltip: _isFullScreen ? ui("退出全屏") : ui("全屏"),
              onPressed: _isProcessing || WindowModeController.instance.isBusy
                  ? null
                  : _toggleFullScreen,
              style: controlStyle,
              icon: AppEntrance(
                identity: 'title-fullscreen',
                order: 5,
                child: Icon(
                  _isFullScreen
                      ? Symbols.close_fullscreen
                      : Symbols.open_in_full,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('title-maximize-control'),
              tooltip: sizeLocked
                  ? ui("窗口大小已锁定")
                  : _isFullScreen
                      ? ui("全屏模式下不可用")
                      : (_isMaximized ? ui("还原") : ui("最大化")),
              onPressed: sizeLocked ||
                      _isFullScreen ||
                      _isProcessing ||
                      WindowModeController.instance.isBusy
                  ? null
                  : _toggleMaximized,
              style: controlStyle,
              icon: AppEntrance(
                identity: 'title-maximize',
                order: 6,
                child: Icon(
                  _isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
                ),
              ),
            ),
            IconButton(
              tooltip: ui("退出"),
              onPressed: requestAppClose,
              style: controlStyle,
              icon: const AppEntrance(
                identity: 'title-close',
                order: 7,
                child: Icon(Symbols.close),
              ),
            ),
          ],
        );
      },
    );
  }
}
