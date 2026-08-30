import 'dart:async';

import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/services.dart';

/// No native methods, UI, audio or filesystem access. Also backs the mocked
/// window_manager channel when an integration path uses its singleton.
class FakeWindowModeAdapter implements WindowModeAdapter {
  FakeWindowModeAdapter({
    Rect normalBounds = const Rect.fromLTWH(100, 80, 900, 700),
    this.maximized = false,
    this.fullScreen = false,
    this.alwaysOnTop = false,
  })  : restoredBounds = normalBounds,
        bounds = fullScreen
            ? const Rect.fromLTWH(0, 0, 1920, 1080)
            : maximized
                ? const Rect.fromLTWH(0, 0, 1920, 1040)
                : normalBounds,
        _beforeFullScreenMaximized = maximized;

  Rect bounds;
  Rect restoredBounds;
  bool maximized;
  bool fullScreen;
  bool alwaysOnTop;
  bool _beforeFullScreenMaximized;
  Size minimumSize = const Size(507, 320);
  final calls = <String>[];
  FutureOr<void> Function(String method)? beforeCall;

  Future<T> _call<T>(String method, T Function() body) async {
    calls.add(method);
    await beforeCall?.call(method);
    return body();
  }

  @override
  Future<Rect> getBounds() => _call('getBounds', () => bounds);
  @override
  Future<bool> isMaximized() => _call('isMaximized', () => maximized);
  @override
  Future<bool> isFullScreen() => _call('isFullScreen', () => fullScreen);
  @override
  Future<bool> isAlwaysOnTop() => _call('isAlwaysOnTop', () => alwaysOnTop);
  @override
  Future<void> setMinimumSize(Size size) =>
      _call('setMinimumSize', () => minimumSize = size);
  @override
  Future<void> setAlwaysOnTop(bool value) =>
      _call('setAlwaysOnTop', () => alwaysOnTop = value);
  @override
  Future<void> setBounds(Rect value) => _call('setBounds', () {
        bounds = value;
        if (!maximized && !fullScreen) restoredBounds = value;
      });
  @override
  Future<void> maximize() => _call('maximize', () {
        if (!maximized && !fullScreen) restoredBounds = bounds;
        maximized = true;
        bounds = const Rect.fromLTWH(0, 0, 1920, 1040);
      });
  @override
  Future<void> unmaximize() => _call('unmaximize', () {
        maximized = false;
        bounds = restoredBounds;
      });
  @override
  Future<void> setFullScreen(bool value) => _call('setFullScreen', () {
        if (value && !fullScreen) {
          _beforeFullScreenMaximized = maximized;
          if (!maximized) restoredBounds = bounds;
          fullScreen = true;
          bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
        } else if (!value && fullScreen) {
          fullScreen = false;
          maximized = _beforeFullScreenMaximized;
          bounds = maximized
              ? const Rect.fromLTWH(0, 0, 1920, 1040)
              : restoredBounds;
        }
      });

  Future<Object?> handleMethodCall(MethodCall call) async {
    final arguments = call.arguments as Map? ?? const {};
    switch (call.method) {
      case 'isMaximized':
        return isMaximized();
      case 'isFullScreen':
        return isFullScreen();
      case 'isAlwaysOnTop':
        return isAlwaysOnTop();
      case 'getBounds':
        final value = await getBounds();
        return {
          'x': value.left,
          'y': value.top,
          'width': value.width,
          'height': value.height,
        };
      case 'setBounds':
        await setBounds(Rect.fromLTWH(
          (arguments['x'] as num?)?.toDouble() ?? bounds.left,
          (arguments['y'] as num?)?.toDouble() ?? bounds.top,
          (arguments['width'] as num?)?.toDouble() ?? bounds.width,
          (arguments['height'] as num?)?.toDouble() ?? bounds.height,
        ));
      case 'setMinimumSize':
        await setMinimumSize(Size((arguments['width'] as num).toDouble(),
            (arguments['height'] as num).toDouble()));
      case 'setAlwaysOnTop':
        await setAlwaysOnTop(arguments['isAlwaysOnTop'] as bool);
      case 'setFullScreen':
        await setFullScreen(arguments['isFullScreen'] as bool);
      case 'maximize':
        await maximize();
      case 'unmaximize':
        await unmaximize();
      default:
        throw StateError('Unexpected native window call: ${call.method}');
    }
    return null;
  }
}
