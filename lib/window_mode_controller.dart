import 'dart:async';

import 'package:dan_player/window_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

/// Only window geometry/state is exposed here; playback and routes stay alive.
abstract class WindowModeAdapter {
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool value);
  Future<bool> isAlwaysOnTop();
  Future<void> setAlwaysOnTop(bool value);
  Future<void> setMinimumSize(Size size);
}

class WindowManagerModeAdapter implements WindowModeAdapter {
  const WindowManagerModeAdapter();

  @override
  Future<Rect> getBounds() => windowManager.getBounds();
  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);
  @override
  Future<bool> isMaximized() => windowManager.isMaximized();
  @override
  Future<void> maximize() => windowManager.maximize();
  @override
  Future<void> unmaximize() => windowManager.unmaximize();
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();
  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
  @override
  Future<bool> isAlwaysOnTop() => windowManager.isAlwaysOnTop();
  @override
  Future<void> setAlwaysOnTop(bool value) =>
      windowManager.setAlwaysOnTop(value);
  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);
}

@immutable
class WindowModeSnapshot {
  const WindowModeSnapshot({
    required this.bounds,
    required this.maximized,
    required this.fullScreen,
    required this.alwaysOnTop,
    required this.minimumSize,
  });

  /// Normal, restored geometry, not the work-area/fullscreen rectangle.
  final Rect bounds;
  final bool maximized;
  final bool fullScreen;
  final bool alwaysOnTop;
  final Size minimumSize;

  WindowModeSnapshot copyWith({Rect? bounds, bool? maximized}) =>
      WindowModeSnapshot(
        bounds: bounds ?? this.bounds,
        maximized: maximized ?? this.maximized,
        fullScreen: fullScreen,
        alwaysOnTop: alwaysOnTop,
        minimumSize: minimumSize,
      );
}

class WindowModeException implements Exception {
  WindowModeException(this.operation, this.cause,
      [List<Object> rollbackErrors = const []])
      : rollbackErrors = List.unmodifiable(rollbackErrors);

  final String operation;
  final Object cause;
  final List<Object> rollbackErrors;

  @override
  String toString() => rollbackErrors.isEmpty
      ? '$operation失败，已保留原窗口状态，请重试。'
      : '$operation失败，部分窗口状态未能恢复，请重试还原窗口。';
}

/// Switches the existing HWND into a compact layout without replacing routes.
///
/// All operations, including rapid keyboard toggles, run in order. Settings
/// writers should skip [isBusy] and use [normalWindowSnapshot] while [isMini],
/// so temporary unmaximize/resize events never overwrite the normal size.
class WindowModeController extends ChangeNotifier {
  WindowModeController({
    WindowModeAdapter? adapter,
    this.normalMinimumSize = const Size(
      WindowGeometryPolicy.normalMinimumWidth,
      WindowGeometryPolicy.normalMinimumHeight,
    ),
    this.miniMinimumSize = const Size(440, 280),
    this.miniSize = const Size(520, 300),
  })  : assert(normalMinimumSize.width > 0 && normalMinimumSize.height > 0),
        assert(miniMinimumSize.width > 0 && miniMinimumSize.height > 0),
        assert(miniSize.width >= miniMinimumSize.width),
        assert(miniSize.height >= miniMinimumSize.height),
        _adapter = adapter ?? const WindowManagerModeAdapter();

  static final WindowModeController instance = WindowModeController();

  final WindowModeAdapter _adapter;

  /// window_manager has no minimum-size getter. This must match WindowOptions.
  final Size normalMinimumSize;
  final Size miniMinimumSize;
  final Size miniSize;

  bool _isMini = false;
  bool _isPinned = false;
  bool _disposed = false;
  int _queuedOperations = 0;
  Future<void> _tail = Future<void>.value();
  WindowModeSnapshot? _normalSnapshot;

  bool get isMini => _isMini;
  bool get isBusy => _queuedOperations != 0;
  bool get isPinned => _isPinned;
  WindowModeSnapshot? get normalWindowSnapshot => _normalSnapshot;

  Future<void> enter() => _enqueue(_enter);
  Future<void> exit() => _enqueue(_exit);
  Future<void> toggle() => _enqueue(() => _isMini ? _exit() : _enter());
  Future<void> togglePinned() => _enqueue(_togglePinned);

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_disposed) {
      return Future<void>.error(StateError('WindowModeController is disposed'));
    }
    _queuedOperations++;
    final task = _tail.then((_) async {
      try {
        if (_disposed) throw StateError('WindowModeController is disposed');
        await operation();
      } finally {
        _queuedOperations--;
        if (!_disposed) notifyListeners();
      }
    });
    // A rejected command must not poison subsequent recovery/toggle commands.
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    // Publish only after reserving our queue slot. A listener may synchronously
    // enqueue another command, which must run after this one, not before it.
    if (_queuedOperations == 1) notifyListeners();
    return task;
  }

  Future<WindowModeSnapshot> _readSnapshot(Size minimumSize) async {
    final fullScreen = await _adapter.isFullScreen();
    final maximized = await _adapter.isMaximized();
    final alwaysOnTop = await _adapter.isAlwaysOnTop();
    final bounds = await _adapter.getBounds();
    _checkBounds(bounds);
    return WindowModeSnapshot(
      bounds: bounds,
      maximized: maximized,
      fullScreen: fullScreen,
      alwaysOnTop: alwaysOnTop,
      minimumSize: minimumSize,
    );
  }

  static void _checkBounds(Rect bounds) {
    if (!bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      throw StateError('Invalid native window bounds: $bounds');
    }
  }

  Future<void> _enter() async {
    if (_isMini) return;
    WindowModeSnapshot? before;
    var mutated = false;
    var hasNormalBounds = false;
    try {
      before = await _readSnapshot(normalMinimumSize);
      hasNormalBounds = !before.fullScreen && !before.maximized;
      if (before.fullScreen) {
        mutated = true;
        await _adapter.setFullScreen(false);
        // Fullscreen may have been entered from a maximized window. Let the
        // plugin restore that state before recording the underlying geometry.
        before = before.copyWith(maximized: await _adapter.isMaximized());
      }
      if (before.maximized) {
        mutated = true;
        await _adapter.unmaximize();
      }
      final bounds = await _adapter.getBounds();
      _checkBounds(bounds);
      before = before.copyWith(bounds: bounds);
      hasNormalBounds = true;
      _normalSnapshot = before;

      mutated = true;
      await _adapter.setMinimumSize(miniMinimumSize);
      await _adapter.setBounds(Rect.fromLTWH(
        bounds.left,
        bounds.top,
        miniSize.width,
        miniSize.height,
      ));
      // Do not make a user's window topmost simply for entering mini mode.
      _isPinned = before.alwaysOnTop;
      _isMini = true;
    } catch (error) {
      final rollbackErrors = mutated && before != null
          ? await _rollback(before, restoreBounds: hasNormalBounds)
          : <Object>[];
      // If rollback itself fails after compact sizing began, keep the normal
      // snapshot and the visible Restore action available for a later retry.
      final needsRecovery =
          rollbackErrors.isNotEmpty && hasNormalBounds && before != null;
      _normalSnapshot = needsRecovery ? before : null;
      _isMini = needsRecovery;
      if (before != null) _isPinned = before.alwaysOnTop;
      throw WindowModeException('进入迷你播放器', error, rollbackErrors);
    }
  }

  Future<void> _exit() async {
    if (!_isMini) return;
    final normal = _normalSnapshot!;
    WindowModeSnapshot? before;
    var mutated = false;
    var hasNormalBounds = false;
    try {
      before = await _readSnapshot(miniMinimumSize);
      hasNormalBounds = !before.fullScreen && !before.maximized;
      if (before.fullScreen) {
        mutated = true;
        await _adapter.setFullScreen(false);
        before = before.copyWith(maximized: await _adapter.isMaximized());
      }
      if (before.maximized) {
        mutated = true;
        await _adapter.unmaximize();
      }
      final miniBounds = await _adapter.getBounds();
      _checkBounds(miniBounds);
      before = before.copyWith(bounds: miniBounds);
      hasNormalBounds = true;

      mutated = true;
      await _adapter.setMinimumSize(normal.minimumSize);
      await _adapter.setBounds(normal.bounds);
      if (normal.maximized) await _adapter.maximize();
      if (normal.fullScreen) await _adapter.setFullScreen(true);
      await _adapter.setAlwaysOnTop(normal.alwaysOnTop);

      _isMini = false;
      _isPinned = normal.alwaysOnTop;
      _normalSnapshot = null;
    } catch (error) {
      final rollbackErrors = mutated && before != null
          ? await _rollback(before, restoreBounds: hasNormalBounds)
          : <Object>[];
      if (before != null) _isPinned = before.alwaysOnTop;
      throw WindowModeException('还原完整播放器', error, rollbackErrors);
    }
  }

  Future<void> _togglePinned() async {
    if (!_isMini) return;
    bool? previous;
    try {
      previous = await _adapter.isAlwaysOnTop();
      await _adapter.setAlwaysOnTop(!previous);
      _isPinned = !previous;
    } catch (error) {
      final rollbackErrors = <Object>[];
      if (previous != null) {
        try {
          await _adapter.setAlwaysOnTop(previous);
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
        _isPinned = previous;
      }
      throw WindowModeException('切换窗口置顶', error, rollbackErrors);
    }
  }

  /// Every restoration step is attempted, even if another step is rejected.
  /// Never write a maximized/fullscreen rectangle into the saved normal bounds
  /// when a failure happened before their genuine restored value was readable.
  Future<List<Object>> _rollback(WindowModeSnapshot snapshot,
      {required bool restoreBounds}) async {
    final failures = <Object>[];
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failures.add(error);
      }
    }

    await attempt(() async {
      if (await _adapter.isFullScreen()) await _adapter.setFullScreen(false);
    });
    await attempt(() async {
      if (await _adapter.isMaximized()) await _adapter.unmaximize();
    });
    await attempt(() => _adapter.setMinimumSize(snapshot.minimumSize));
    if (restoreBounds) {
      await attempt(() => _adapter.setBounds(snapshot.bounds));
    }
    if (snapshot.maximized) await attempt(_adapter.maximize);
    if (snapshot.fullScreen) {
      await attempt(() => _adapter.setFullScreen(true));
    }
    await attempt(() => _adapter.setAlwaysOnTop(snapshot.alwaysOnTop));
    return failures;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
