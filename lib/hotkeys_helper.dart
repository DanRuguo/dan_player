import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/component/app_dialog_title.dart';

export 'package:dan_player/player_shortcut_preferences.dart';

/// One source of truth for dispatch, settings, tooltips and help.
List<PlayerShortcut> get playerShortcuts =>
    AppSettings.instance.shortcuts.value.resolve();

/// App-local and focus-aware. Typing, IME composition and ordinary control
/// actions never go through a global keyboard hook.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({super.key, required this.child, this.onCommand});
  final Widget child;
  final FutureOr<void> Function(PlayerCommand)? onCommand;

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (!HotkeysHelper.enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final focusContext = FocusManager.instance.primaryFocus?.context;
          if (focusContext != null &&
              (focusContext.widget is EditableText ||
                  focusContext.findAncestorStateOfType<EditableTextState>() !=
                      null)) {
            return KeyEventResult.ignored;
          }
          PlayerCommand? command;
          for (final shortcut in playerShortcuts) {
            if (shortcut.activator.accepts(event, HardwareKeyboard.instance)) {
              command = shortcut.command;
              break;
            }
          }
          if (command == null) return KeyEventResult.ignored;
          if (command == PlayerCommand.togglePlayback && focusContext != null) {
            // Buttons expose ActivateIntent below WidgetsApp's default Space
            // binding. Let that ancestor binding run instead of swallowing the
            // key, so a focused button never also toggles playback.
            final activate = Actions.maybeFind<ActivateIntent>(focusContext);
            if (activate?.isEnabled(const ActivateIntent()) == true) {
              return KeyEventResult.ignored;
            }
          }
          final route =
              focusContext == null ? null : ModalRoute.of(focusContext);
          if (route is PopupRoute &&
              command != PlayerCommand.escape &&
              command != PlayerCommand.help) {
            return KeyEventResult.ignored;
          }
          final action = command;
          unawaited(Future<void>.sync(() {
            final handler = onCommand;
            return handler != null
                ? handler(action)
                : HotkeysHelper.runCommand(action);
          }).catchError((Object error, StackTrace trace) {
            LOGGER.w('[keyboard shortcut] $error', stackTrace: trace);
            HotkeysHelper.showError(ui('操作失败：{0}', [error]));
          }));
          return KeyEventResult.handled;
        },
        child: child,
      );
}

class HotkeysHelper {
  static bool enabled = true;
  // Normal and mini modes own separate navigators. A retained offstage dialog
  // must not prevent help in the visible navigator; repeated commands within
  // that same navigator are still deduplicated. Weak keys do not retain routes.
  static final _helpOpen = Expando<bool>('shortcut-help-open');
  static bool _fullScreenBusy = false;

  // Lifecycle compatibility: one widget dispatcher, no repeated native
  // registration when individual text fields gain/lose focus.
  static void registerHotKeys() => enabled = true;
  static Future<void> unregisterAll() async {
    enabled = false;
  }

  static Future<void> onFocusChanges(bool focused) async {}

  static String shortcutLabel(PlayerCommand command) =>
      AppSettings.instance.shortcuts.value.chordFor(command).label;

  static BuildContext? get _activeContext =>
      WindowModeController.instance.isMini
          ? compactNavigatorKey.currentContext
          : ROUTER_KEY.currentContext;

  static void showError(String message) {
    final context = _activeContext;
    showAppNotice(
      message,
      context: context,
      kind: AppNoticeKind.error,
    );
  }

  static Future<void> runCommand(PlayerCommand command) async {
    final mode = WindowModeController.instance;
    switch (command) {
      case PlayerCommand.toggleMini:
        if (!mode.isBusy && !_fullScreenBusy) await mode.toggle();
        return;
      case PlayerCommand.toggleFullScreen:
        if (mode.isBusy || _fullScreenBusy) return;
        _fullScreenBusy = true;
        try {
          final wasMini = mode.isMini;
          if (wasMini) await mode.exit();
          final fullScreen = await windowManager.isFullScreen();
          // F11 acts on the visible mini window, which is not fullscreen.
          // Exiting mini may already have restored a fullscreen snapshot.
          if (!wasMini || !fullScreen) {
            await windowManager.setFullScreen(wasMini || !fullScreen);
          }
        } finally {
          _fullScreenBusy = false;
        }
        return;
      case PlayerCommand.help:
        final context = _activeContext;
        if (context != null) await showShortcuts(context);
        return;
      case PlayerCommand.escape:
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null && ModalRoute.of(focusContext) is PopupRoute) {
          await Navigator.of(focusContext).maybePop();
        } else if (mode.isMini) {
          if (!mode.isBusy) await mode.exit();
        } else if (!mode.isBusy && await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        } else {
          final context = ROUTER_KEY.currentContext;
          if (context != null && context.mounted && context.canPop()) {
            context.pop();
          }
        }
        return;
      default:
        // Early keys and empty libraries must not initialize a native player.
        if (!PlayService.isInitialized) return;
        final playback = PlayService.instance.playbackService;
        if (playback.nowPlaying == null) return;
        switch (command) {
          case PlayerCommand.togglePlayback:
            if (playback.isBuffering.value) return;
            if (playback.playerState == PlayerState.playing) {
              playback.pause();
            } else if (playback.playerState == PlayerState.completed) {
              playback.playAgain();
            } else {
              playback.start();
            }
          case PlayerCommand.previous:
            playback.lastAudio();
          case PlayerCommand.next:
            playback.nextAudio();
          case PlayerCommand.seekBack:
          case PlayerCommand.seekForward:
            if (playback.isBuffering.value || playback.length <= 0) return;
            final change = command == PlayerCommand.seekBack ? -5.0 : 5.0;
            final position = playback.position;
            if (!position.isFinite) return;
            playback.seek((position + change).clamp(0.0, playback.length));
          case PlayerCommand.volumeDown:
          case PlayerCommand.volumeUp:
            final change = command == PlayerCommand.volumeDown ? -0.05 : 0.05;
            playback
                .setVolumeDsp((playback.volumeDsp + change).clamp(0.0, 1.0));
          default:
            break;
        }
    }
  }

  static Future<void> showShortcuts(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_helpOpen[navigator] == true) return;
    _helpOpen[navigator] = true;
    try {
      await showAppDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 650),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                child: AppDialogTitle(
                  ui('快捷键'),
                  style: Theme.of(context).textTheme.titleLarge,
                  trailing: IconButton(
                      tooltip: ui('关闭快捷键说明'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close)),
                ),
              ),
              Flexible(
                  child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ui('在播放器窗口激活时生效。输入文字时不拦截按键；按钮、滑块等控件优先处理自己的按键。')),
                      const SizedBox(height: 12),
                      for (final shortcut in playerShortcuts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 120,
                                    child: Text(shortcut.keys,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                                const SizedBox(width: 12),
                                Expanded(child: Text(ui(shortcut.description))),
                              ]),
                        ),
                      const SizedBox(height: 8),
                      Text(ui('音量快捷键仅改变本播放器音量，不修改 Windows 系统音量。')),
                    ]),
              )),
            ]),
          ),
        ),
      );
    } finally {
      _helpOpen[navigator] = null;
    }
  }
}
