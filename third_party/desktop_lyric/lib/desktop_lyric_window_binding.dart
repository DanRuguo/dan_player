import 'dart:async';
import 'dart:io';

import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Event-driven synchronization, not a periodic topmost/resize polling loop.
/// The native channel signals display/work-area changes and completed moves.
class DesktopLyricWindowBinding with WidgetsBindingObserver {
  DesktopLyricWindowBinding(this.controller, this.layout);
  final DesktopLyricController controller;
  final DesktopLyricWindowLayout layout;
  static const channel = MethodChannel('dan_player/desktop_lyric_geometry');
  bool _disposed = false;
  bool _fitScheduled = false;

  void attach() {
    if (_disposed) return;
    controller.vertical.addListener(_syncDirection);
    controller.appearance.addListener(_syncAppearance);
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'workAreaChanged') {
        didChangeMetrics();
      }
    });
    _syncDirection();
    _syncAppearance();
  }

  void _run(Future<void> future) =>
      unawaited(future.catchError((Object error, StackTrace stack) {
        stderr.writeln('Desktop lyric geometry: $error\n$stack');
        if (!_disposed) {
          layout.lastError.value = '歌词窗口布局调整失败，请重新切换显示模式。';
        }
      }));
  void _syncDirection() => _run(layout.setVertical(controller.vertical.value));
  void _syncAppearance() {
    final requested = controller.appearance.value;
    unawaited(layout
        .setAppearance(requested)
        .catchError((Object error, StackTrace stack) {
      stderr.writeln('Desktop lyric geometry: $error\n$stack');
      if (_disposed) return;
      // Keep renderer and HWND in the same mode after a native failure. Only
      // roll back this request; a newer user request still owns its snapshot.
      if (controller.appearance.value == requested) {
        final applied = layout.appliedAppearance;
        controller.appearance.update(requested.copyWith(
            taskbarMode: applied.taskbarMode,
            taskbarGap: applied.taskbarGap,
            taskbarHeight: applied.taskbarHeight));
      }
      layout.lastError.value = '歌词窗口布局调整失败，已保留原窗口；请重新切换显示模式重试。';
    }));
  }

  @override
  void didChangeMetrics() {
    if (_disposed || _fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (!_disposed) _run(layout.fitToWorkArea());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.vertical.removeListener(_syncDirection);
    controller.appearance.removeListener(_syncAppearance);
    WidgetsBinding.instance.removeObserver(this);
    channel.setMethodCallHandler(null);
    layout.dispose();
  }
}
