import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

abstract class WindowLayoutAdapter {
  Future<Size> getSize();
  Future<void> setResizable(bool value);
  Future<void> setAspectRatio(double value);
}

class WindowManagerLayoutAdapter implements WindowLayoutAdapter {
  const WindowManagerLayoutAdapter();

  @override
  Future<Size> getSize() => windowManager.getSize();

  @override
  Future<void> setResizable(bool value) => windowManager.setResizable(value);

  @override
  Future<void> setAspectRatio(double value) =>
      windowManager.setAspectRatio(value);
}

/// Applies normal-window resize preferences to the existing native window.
///
/// Calls are serialized because toggling two switches quickly must not let an
/// older platform response overwrite the latest preference. Programmatic
/// bounds changes (including mini-player enter/exit) remain available when the
/// user resize affordance is locked.
class WindowLayoutController extends ChangeNotifier {
  WindowLayoutController({
    WindowLayoutAdapter? adapter,
    ValueNotifier<PlayerExperiencePreferences>? preferences,
    Future<void> Function()? persistCapturedRatio,
  })  : _adapter = adapter ?? const WindowManagerLayoutAdapter(),
        _preferences = preferences ?? AppSettings.instance.experience,
        _persistCapturedRatio = persistCapturedRatio ??
            (() => AppSettings.instance.saveSettings(throwOnError: true));

  static final WindowLayoutController instance = WindowLayoutController();

  final WindowLayoutAdapter _adapter;
  final ValueNotifier<PlayerExperiencePreferences> _preferences;
  final Future<void> Function() _persistCapturedRatio;

  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  bool _applying = false;
  Object? _lastError;

  bool get isApplying => _applying;
  Object? get lastError => _lastError;

  Future<void> initialize() {
    if (_disposed) return Future.error(StateError('controller is disposed'));
    if (!_initialized) {
      _initialized = true;
      _preferences.addListener(_onPreferenceChanged);
    }
    return apply();
  }

  void _onPreferenceChanged() {
    unawaited(apply().catchError((Object _, StackTrace __) {}));
  }

  Future<void> apply() {
    if (_disposed) return Future.error(StateError('controller is disposed'));
    final requested = _preferences.value;
    final task = _tail.then((_) => _apply(requested));
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _apply(PlayerExperiencePreferences requested) async {
    _applying = true;
    _lastError = null;
    notifyListeners();
    try {
      // Fixed size is the authoritative fallback for malformed/legacy state
      // that contains both constraints. Valid settings are already normalized
      // while loading, but native application must remain safe on its own.
      final aspectRatioLocked =
          requested.windowAspectRatioLocked && !requested.windowSizeLocked;
      var ratio = requested.windowAspectRatio;
      if (aspectRatioLocked && ratio == 0) {
        final size = await _adapter.getSize();
        if (!size.width.isFinite ||
            !size.height.isFinite ||
            size.width <= 0 ||
            size.height <= 0) {
          throw StateError('无法从当前窗口取得有效纵横比');
        }
        ratio = PlayerExperiencePreferences.safeWindowAspectRatio(
          size.width / size.height,
        );
        if (ratio == 0) throw StateError('当前窗口纵横比超出支持范围');
      }

      await _adapter.setAspectRatio(
        aspectRatioLocked ? ratio : 0,
      );
      await _adapter.setResizable(!requested.windowSizeLocked);

      if (aspectRatioLocked &&
          requested.windowAspectRatio == 0 &&
          _preferences.value.windowAspectRatioLocked &&
          !_preferences.value.windowSizeLocked) {
        _preferences.value = _preferences.value.copyWith(
          windowAspectRatio: ratio,
        );
        await _persistCapturedRatio();
      }
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _applying = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_initialized) _preferences.removeListener(_onPreferenceChanged);
    _disposed = true;
    super.dispose();
  }
}
