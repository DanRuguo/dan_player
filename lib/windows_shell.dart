import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/services.dart';

/// Bounded startup queue: Shell commands reuse the existing playback instance
/// after the library and saved session finish loading.
class ShellActionQueue {
  ShellActionQueue({required this.dispatch, this.preparePlayback});
  final Future<void> Function(String action) dispatch;
  final Future<void> Function()? preparePlayback;
  final List<String> _pending = [];
  Future<void> _tail = Future.value();
  bool _libraryReady = false;
  Future<void>? _libraryReadyFuture;
  static const actions = {'showMain', 'toggle', 'previous', 'next', 'showMini'};

  Future<void> accept(String action) {
    if (!actions.contains(action)) return Future.value();
    if (!_libraryReady && action != 'showMain' && action != 'showMini') {
      if (_pending.length < 16) _pending.add(action);
      return Future.value();
    }
    final task = _tail.then((_) => dispatch(action));
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> libraryReady() => _libraryReadyFuture ??= _prepareLibrary();

  Future<void> _prepareLibrary() async {
    try {
      await preparePlayback?.call();
    } catch (error, trace) {
      // A failed saved source must still leave window actions and later manual
      // playback usable. Dispatch will show the usual no-track guidance.
      LOGGER.w('Windows task session restoration: $error', stackTrace: trace);
    }
    _libraryReady = true;
    final pending = List<String>.of(_pending);
    _pending.clear();
    // Enqueue the entire batch before waiting: a failed command must not drop
    // the later commands that were accepted during startup.
    await Future.wait([for (final action in pending) accept(action)]);
  }
}

class WindowsInstallation {
  const WindowsInstallation({required this.kind, required this.directory});
  final String kind;
  final String directory;
  bool get canUninstall => kind == 'installed';
  bool get isPortable => kind == 'portable';
}

class WindowsShell {
  WindowsShell._();
  static final instance = WindowsShell._();
  static const _channel = MethodChannel('dan_player/windows_shell');
  late final _actions = ShellActionQueue(
    dispatch: _dispatch,
    preparePlayback: () async {
      if (PlayService.isInitialized) {
        await PlayService.instance.playbackService.restoreLastSessionOnce();
      }
    },
  );
  bool _initialized = false;
  Future<void>? _configuration;

  Future<void> initialize({required bool welcome}) async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        await _actions.accept(call.arguments as String);
      }
    });
    if (welcome) await _actions.libraryReady();
    uiLanguage.addListener(_languageChanged);
    unawaited(_configure());
    try {
      final pending = await _channel.invokeListMethod<String>('ready');
      for (final action in pending ?? const <String>[]) {
        await _actions.accept(action);
      }
    } catch (error, trace) {
      LOGGER.w('Windows task activation: $error', stackTrace: trace);
    }
  }

  void _languageChanged() => unawaited(_configure());

  Future<void> _configure() {
    final language = uiLanguage.value;
    return _configuration ??= _configureTasks().whenComplete(() {
      _configuration = null;
      if (uiLanguage.value != language) unawaited(_configure());
    });
  }

  Future<void> _configureTasks() async {
    if ((Platform.environment['DAN_PLAYER_DATA_DIR'] ?? '').isNotEmpty) return;
    try {
      final available = await _channel.invokeMethod<bool>('configureTasks', {
        'showMain': ui('显示主窗口'),
        'toggle': ui('播放 / 暂停'),
        'previous': ui('上一首'),
        'next': ui('下一首'),
        'showMini': ui('迷你播放器'),
      });
      if (available != true) LOGGER.w('Windows Jump List is unavailable.');
    } catch (error, trace) {
      LOGGER.w('Windows Jump List: $error', stackTrace: trace);
    }
  }

  Future<void> markLibraryReady() => _actions.libraryReady();

  Future<void> _dispatch(String action) async {
    final desktop = DesktopIntegration.instance;
    if (action == 'showMain' || action == 'showMini') {
      await desktop.dispatchAction(action);
      return;
    }
    if (!PlayService.isInitialized ||
        PlayService.instance.playbackService.nowPlaying == null) {
      await desktop.showWindow();
      showTextOnSnackBar('请先选择一首歌曲，再使用播放快捷任务。',
          kind: AppNoticeKind.warning);
      return;
    }
    await desktop.dispatchAction(action);
  }

  Future<WindowsInstallation> installationInfo() async {
    final data =
        await _channel.invokeMapMethod<String, Object?>('installationInfo');
    return WindowsInstallation(
      kind: data?['kind'] as String? ?? 'unavailable',
      directory: data?['directory'] as String? ?? '',
    );
  }

  Future<void> openAppFolder() => _channel.invokeMethod<void>('openAppFolder');

  /// Native code revalidates the registration and holds the selected files
  /// against replacement. Only a successful start permits application shutdown.
  Future<void> uninstall() async {
    await _channel.invokeMethod<void>('launchUninstaller');
    await shutdownAndExit(throwOnError: true);
  }
}
