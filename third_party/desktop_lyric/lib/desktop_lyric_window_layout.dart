import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

abstract class DesktopLyricWindowAdapter {
  double get pixelRatio;
  Future<Rect> getBounds();
  Future<Rect> workAreaFor(Rect bounds);
  Future<void> setBounds(Rect bounds);
  Future<void> setMinimumSize(Size size);
}

/// Uses the same logical/physical coordinate conversion as window_manager.
/// MONITOR_DEFAULTTONEAREST also recovers saved bounds after monitor removal.
class NativeDesktopLyricWindowAdapter implements DesktopLyricWindowAdapter {
  const NativeDesktopLyricWindowAdapter();
  static const _geometryChannel =
      MethodChannel('dan_player/desktop_lyric_geometry');

  @override
  double get pixelRatio => windowManager.getDevicePixelRatio();
  @override
  Future<Rect> getBounds() => windowManager.getBounds();
  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);
  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<Rect> workAreaFor(Rect bounds) async {
    final scale = pixelRatio;
    final rect = calloc<win32.RECT>();
    final info = calloc<win32.MONITORINFO>();
    try {
      rect.ref
        ..left = (bounds.left * scale).round()
        ..top = (bounds.top * scale).round()
        ..right = (bounds.right * scale).round()
        ..bottom = (bounds.bottom * scale).round();
      info.ref.cbSize = sizeOf<win32.MONITORINFO>();
      final monitor =
          win32.MonitorFromRect(rect, win32.MONITOR_DEFAULTTONEAREST);
      if (monitor == 0 || win32.GetMonitorInfo(monitor, info) == 0) {
        throw StateError('无法读取桌面歌词所在显示器的工作区');
      }
      final area = info.ref.rcWork;
      final monitorArea = info.ref.rcMonitor;
      // rcWork may include an automatically hidden taskbar. Query only the
      // documented per-monitor edge appbars, without private Explorer classes.
      var hiddenInsets = const <int>[0, 0, 0, 0];
      try {
        hiddenInsets = await _geometryChannel.invokeListMethod<int>(
                'autoHideInsets', [
              monitorArea.left,
              monitorArea.top,
              monitorArea.right,
              monitorArea.bottom
            ]).timeout(const Duration(seconds: 2)) ??
            hiddenInsets;
      } on MissingPluginException {
        // Older helper builds retain ordinary work-area placement.
      } on PlatformException {
        // Shell unavailable: keep a recoverable ordinary floating window.
      } on TimeoutException {
        // Geometry must not remain blocked behind an unavailable shell.
      }
      return DesktopLyricGeometry.reserveAutoHideEdges(
        Rect.fromLTRB(area.left / scale, area.top / scale, area.right / scale,
            area.bottom / scale),
        Rect.fromLTRB(monitorArea.left / scale, monitorArea.top / scale,
            monitorArea.right / scale, monitorArea.bottom / scale),
        hiddenInsets.map((value) => value / scale).toList(growable: false),
      );
    } finally {
      calloc.free(rect);
      calloc.free(info);
    }
  }
}

/// Pure geometry policy, shared by real window operations and isolated tests.
abstract final class DesktopLyricGeometry {
  static const horizontalSize = Size(800, 160);
  static const verticalSize = Size(248, 560);
  static const horizontalMinimum = Size(320, 128);
  static const verticalMinimum = Size(200, 320);
  static const paletteSize = Size(640, 440);
  static const paletteMinimum = Size(400, 320);

  static Size defaultSize(bool vertical) =>
      vertical ? verticalSize : horizontalSize;
  static Size minimumSize(bool vertical) =>
      vertical ? verticalMinimum : horizontalMinimum;

  static Rect taskbarBounds(Rect area, {double height = 56, double gap = 8}) {
    if (!_valid(area) || !height.isFinite || !gap.isFinite) {
      throw StateError('桌面歌词停靠区域无效');
    }
    final boundedHeight = height.clamp(1.0, area.height);
    final boundedGap = gap.clamp(0.0, area.height - boundedHeight);
    return Rect.fromLTWH(area.left, area.bottom - boundedGap - boundedHeight,
        area.width, boundedHeight);
  }

  static Rect reserveAutoHideBottom(
          Rect workArea, Rect monitor, double height) =>
      reserveAutoHideEdges(workArea, monitor, [0, 0, 0, height]);

  static Rect reserveAutoHideEdges(
      Rect workArea, Rect monitor, List<double> insets) {
    if (insets.length != 4) return workArea;
    double inset(int index, double extent) {
      final value = insets[index];
      return value.isFinite && value > 0 && value < extent / 2 ? value : 0;
    }

    final safe = Rect.fromLTRB(
      math.max(workArea.left, monitor.left + inset(0, monitor.width)),
      math.max(workArea.top, monitor.top + inset(1, monitor.height)),
      math.min(workArea.right, monitor.right - inset(2, monitor.width)),
      math.min(workArea.bottom, monitor.bottom - inset(3, monitor.height)),
    );
    return _valid(safe) ? safe : workArea;
  }

  static Rect fit(Rect requested, Rect workArea, Size minimum) {
    if (!_valid(requested) || !_valid(workArea)) {
      throw StateError('桌面歌词窗口尺寸无效');
    }
    final width = requested.width
        .clamp(math.min(minimum.width, workArea.width), workArea.width)
        .toDouble();
    final height = requested.height
        .clamp(math.min(minimum.height, workArea.height), workArea.height)
        .toDouble();
    return Rect.fromLTWH(
      requested.left.clamp(workArea.left, workArea.right - width),
      requested.top.clamp(workArea.top, workArea.bottom - height),
      width,
      height,
    );
  }

  static bool _valid(Rect value) =>
      value.left.isFinite &&
      value.top.isFinite &&
      value.width.isFinite &&
      value.height.isFinite &&
      value.width > 0 &&
      value.height > 0;
}

class _RememberedBounds {
  _RememberedBounds(Rect bounds, double ratio)
      : physical = Rect.fromLTWH(bounds.left * ratio, bounds.top * ratio,
            bounds.width * ratio, bounds.height * ratio);

  final Rect physical;

  Rect atRatio(double ratio) => Rect.fromLTWH(physical.left / ratio,
      physical.top / ratio, physical.width / ratio, physical.height / ratio);
}

/// The lyric surface stays at its original screen position while the same HWND
/// temporarily grows to host a palette. It is not a frozen lyric bitmap.
class DesktopLyricPalettePresentation {
  const DesktopLyricPalettePresentation(
      {this.contentBounds, this.viewportBounds});
  final Rect? contentBounds;
  final Rect? viewportBounds;

  Rect? contentFrame(Size viewportSize) {
    final content = contentBounds;
    final viewport = viewportBounds;
    if (content == null || viewport == null) return null;
    // The notifier can be delivered before the native resize's metrics frame.
    // In that frame the original HWND still owns the original local origin.
    final originalSize = (viewportSize.width - content.width).abs() < .5 &&
        (viewportSize.height - content.height).abs() < .5;
    return Rect.fromLTWH(
        originalSize ? 0 : content.left - viewport.left,
        originalSize ? 0 : content.top - viewport.top,
        content.width,
        content.height);
  }
}

/// Serializes rotation, font-size constraints and the temporary palette.
/// Horizontal/vertical geometry is remembered separately within the process;
/// a palette never overwrites either snapshot. No music/settings files exist
/// here and constructing the controller does not call native APIs.
class DesktopLyricWindowLayout {
  DesktopLyricWindowLayout({required DesktopLyricWindowAdapter adapter})
      : _adapter = adapter;

  static final instance = DesktopLyricWindowLayout(
    adapter: const NativeDesktopLyricWindowAdapter(),
  );

  final DesktopLyricWindowAdapter _adapter;
  final Map<bool, _RememberedBounds> _remembered = {};
  final Map<bool, Size> _contentMinimum = {};
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _vertical = false;
  bool _paletteOpen = false;
  bool _fitPending = false;
  bool _fitAgain = false;
  bool _disposed = false;
  Size _appliedMinimum = Size.zero;
  DesktopLyricAppearance _appearance = DesktopLyricAppearance.defaults;
  final lastError = ValueNotifier<String?>(null);
  final palettePresentation =
      ValueNotifier<DesktopLyricPalettePresentation?>(null);
  bool? paletteExitHover;
  double _taskbarContentHeight = 44;

  bool get vertical => _vertical;
  bool get paletteOpen => _paletteOpen;
  bool get taskbarMode => _appearance.taskbarMode;
  DesktopLyricAppearance get appliedAppearance => _appearance;

  /// Hover latch only for the independently owned palette. No HWND mutation.
  void beginPalettePresentation() {
    if (!_disposed && palettePresentation.value == null) {
      paletteExitHover = null;
      palettePresentation.value = const DesktopLyricPalettePresentation();
    }
  }

  /// Native close supplies the real cursor position before releasing hover.
  void endPalettePresentation({bool? ownerHover}) {
    if (ownerHover != null) paletteExitHover = ownerHover;
    palettePresentation.value = null;
  }

  Size _minimum(bool vertical) {
    final base = DesktopLyricGeometry.minimumSize(vertical);
    final content = _contentMinimum[vertical] ?? Size.zero;
    return Size(math.max(base.width, content.width),
        math.max(base.height, content.height));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _tail.then((_) async {
      if (!_disposed) await operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> initialize(
          {required bool vertical,
          DesktopLyricAppearance appearance =
              DesktopLyricAppearance.defaults}) =>
      _enqueue(() async {
        if (_initialized) return;
        final current = await _adapter.getBounds();
        if (appearance.taskbarMode) {
          _remembered[vertical] =
              _RememberedBounds(current, _adapter.pixelRatio);
          await _applyTaskbar(current, appearance);
        } else {
          await _apply(current, _minimum(vertical));
        }
        _appearance = appearance;
        _vertical = vertical;
        _initialized = true;
      });

  Future<void> setVertical(bool value) => _enqueue(() async {
        if (_initialized && value == _vertical) return;
        final current = await _adapter.getBounds();
        if (_initialized && !_paletteOpen && !taskbarMode) {
          _remembered[_vertical] =
              _RememberedBounds(current, _adapter.pixelRatio);
        }
        final target = _remembered[value]?.atRatio(_adapter.pixelRatio) ??
            Rect.fromCenter(
                center: current.center,
                width: DesktopLyricGeometry.defaultSize(value).width,
                height: DesktopLyricGeometry.defaultSize(value).height);
        if (_paletteOpen || taskbarMode) {
          _remembered[value] = _RememberedBounds(target, _adapter.pixelRatio);
        } else {
          await _apply(target, _minimum(value));
        }
        _vertical = value;
        _initialized = true;
      });

  Future<void> setPaletteOpen(bool value) => _enqueue(() async {
        if (!_initialized || value == _paletteOpen) return;
        final current = await _adapter.getBounds();
        if (value) {
          if (palettePresentation.value != null) {
            palettePresentation.value = DesktopLyricPalettePresentation(
                contentBounds: current, viewportBounds: current);
          }
          if (!taskbarMode) {
            _remembered[_vertical] =
                _RememberedBounds(current, _adapter.pixelRatio);
          }
          await _apply(
              Rect.fromCenter(
                  center: current.center,
                  width: math.max(
                      current.width, DesktopLyricGeometry.paletteSize.width),
                  height: math.max(
                      current.height, DesktopLyricGeometry.paletteSize.height)),
              DesktopLyricGeometry.paletteMinimum);
        } else {
          if (taskbarMode) {
            await _applyTaskbar(current, _appearance);
          } else {
            await _apply(_floatingTarget(current), _minimum(_vertical));
          }
        }
        _paletteOpen = value;
      });

  Rect _floatingTarget(Rect current) =>
      _remembered[_vertical]?.atRatio(_adapter.pixelRatio) ??
      Rect.fromCenter(
          center: current.center,
          width: DesktopLyricGeometry.defaultSize(_vertical).width,
          height: DesktopLyricGeometry.defaultSize(_vertical).height);

  Future<void> setAppearance(DesktopLyricAppearance value) =>
      _enqueue(() async {
        final previous = _appearance;
        if ((value.taskbarMode, value.taskbarGap, value.taskbarHeight) ==
            (
              previous.taskbarMode,
              previous.taskbarGap,
              previous.taskbarHeight
            )) {
          return;
        }
        if (_initialized && !_paletteOpen) {
          final current = await _adapter.getBounds();
          if (value.taskbarMode) {
            if (!taskbarMode) {
              _remembered[_vertical] =
                  _RememberedBounds(current, _adapter.pixelRatio);
            }
            await _applyTaskbar(current, value);
          } else if (taskbarMode) {
            await _apply(_floatingTarget(current), _minimum(_vertical));
          }
        }
        // Commit only after successful native calls so identical requests can retry.
        _appearance = value;
        lastError.value = null;
      });

  Future<void> ensureTaskbarMinimumHeight(double height) => _enqueue(() async {
        if (!height.isFinite ||
            height <= 0 ||
            height == _taskbarContentHeight) {
          return;
        }
        final previous = _taskbarContentHeight;
        _taskbarContentHeight = height;
        try {
          if (_initialized && taskbarMode && !_paletteOpen) {
            await _applyTaskbar(await _adapter.getBounds(), _appearance);
          }
        } catch (_) {
          _taskbarContentHeight = previous;
          rethrow;
        }
      });

  Future<void> _applyTaskbar(Rect current, DesktopLyricAppearance appearance,
      [int retries = 0]) async {
    if (_disposed) return;
    final ratio = _adapter.pixelRatio;
    final area = await _adapter.workAreaFor(current);
    if (_disposed) return;
    if (ratio != _adapter.pixelRatio) {
      if (retries >= 3) throw StateError('显示器缩放正在变化，请重试布局');
      return _applyTaskbar(await _adapter.getBounds(), appearance, retries + 1);
    }
    final target = DesktopLyricGeometry.taskbarBounds(area,
        height: math.max(appearance.taskbarHeight, _taskbarContentHeight),
        gap: appearance.taskbarGap);
    await _apply(target, Size(math.min(320, area.width), target.height));
  }

  Future<void> ensureContentMinimum(Size minimum, {required bool vertical}) =>
      _enqueue(() async {
        if (minimum.width <= 0 ||
            minimum.height <= 0 ||
            !minimum.width.isFinite ||
            !minimum.height.isFinite) {
          return;
        }
        if (_contentMinimum[vertical] == minimum) return;
        final previous = _contentMinimum[vertical];
        _contentMinimum[vertical] = minimum;
        if (!_initialized ||
            _paletteOpen ||
            taskbarMode ||
            vertical != _vertical) {
          return;
        }
        try {
          await _apply(await _adapter.getBounds(), _minimum(vertical));
        } catch (_) {
          if (previous == null) {
            _contentMinimum.remove(vertical);
          } else {
            _contentMinimum[vertical] = previous;
          }
          rethrow;
        }
      });

  Future<void> fitToWorkArea() {
    if (_disposed || !_initialized) return _tail;
    _fitAgain = true;
    if (_fitPending) return _tail;
    _fitPending = true;
    return _enqueue(() async {
      try {
        do {
          _fitAgain = false;
          if (taskbarMode && !_paletteOpen) {
            await _applyTaskbar(await _adapter.getBounds(), _appearance);
          } else {
            await _apply(
                await _adapter.getBounds(),
                _paletteOpen
                    ? DesktopLyricGeometry.paletteMinimum
                    : _minimum(_vertical));
          }
        } while (_fitAgain && !_disposed);
      } finally {
        _fitPending = false;
      }
    });
  }

  /// Stops queued native work during owner shutdown. In-flight reads may finish
  /// but are checked again before changing the HWND.
  void dispose() {
    _disposed = true;
    _fitAgain = false;
  }

  Future<void> _apply(Rect requested, Size minimum, [int retries = 0]) async {
    if (_disposed) return;
    final ratio = _adapter.pixelRatio;
    final area = await _adapter.workAreaFor(requested);
    final fitted = DesktopLyricGeometry.fit(requested, area, minimum);
    final boundedMinimum = Size(math.min(minimum.width, area.width),
        math.min(minimum.height, area.height));
    final before = await _adapter.getBounds();
    if (_disposed) return;
    if (ratio != _adapter.pixelRatio) {
      if (retries >= 3) throw StateError('显示器缩放正在变化，请重试布局');
      final factor = ratio / _adapter.pixelRatio;
      return _apply(
          Rect.fromLTWH(requested.left * factor, requested.top * factor,
              requested.width * factor, requested.height * factor),
          minimum,
          retries + 1);
    }
    if (before == fitted && boundedMinimum == _appliedMinimum) return;
    final previousMinimum = _appliedMinimum;
    // Clear the old orientation's constraints before applying the new bounds.
    // Even on a tiny display, minimum <= work area, never a forced offscreen UI.
    try {
      final presentation = palettePresentation.value;
      if (presentation != null) {
        palettePresentation.value = DesktopLyricPalettePresentation(
            contentBounds: presentation.contentBounds, viewportBounds: fitted);
      }
      await _adapter.setMinimumSize(Size.zero);
      if (_disposed) return;
      if (before != fitted) await _adapter.setBounds(fitted);
      if (_disposed) return;
      await _adapter.setMinimumSize(boundedMinimum);
      _appliedMinimum = boundedMinimum;
    } catch (_) {
      // A native failure must not leave a half-rotated window or permanently
      // remove its constraints. Recovery is best effort; the error stays visible
      // and the queue remains available for another user request.
      if (_disposed) return;
      try {
        final presentation = palettePresentation.value;
        if (presentation != null) {
          palettePresentation.value = DesktopLyricPalettePresentation(
              contentBounds: presentation.contentBounds,
              viewportBounds: before);
        }
        await _adapter.setMinimumSize(Size.zero);
        await _adapter.setBounds(before);
        await _adapter.setMinimumSize(previousMinimum);
      } catch (_) {}
      rethrow;
    }
  }
}
