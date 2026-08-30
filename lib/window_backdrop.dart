import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Only the native compositor can sample windows behind this application.
/// A Flutter BackdropFilter cannot cross the native window boundary.
@immutable
class WindowBackdropStatus {
  const WindowBackdropStatus({
    this.available = false,
    this.effect = 'solid',
    this.reason,
    this.fallbackColor,
  });

  factory WindowBackdropStatus.fromMessage(Object? message) {
    if (message is! Map || message['available'] is! bool) {
      return const WindowBackdropStatus(reason: 'invalid_response');
    }
    final effect = message['effect'];
    final available = message['available'] == true;
    // Mica and a plain transparent gradient are not live desktop blur.
    if ((available && effect != 'acrylic' && effect != 'blur') ||
        (!available && effect != 'solid')) {
      return const WindowBackdropStatus(reason: 'invalid_response');
    }
    final color = message['fallbackColor'];
    return WindowBackdropStatus(
      available: available,
      effect: effect as String,
      reason: message['reason'] is String ? message['reason'] as String : null,
      fallbackColor: color is int && color >= 0 && color <= 0xFFFFFFFF
          ? Color(color).withValues(alpha: 1)
          : null,
    );
  }

  final bool available;
  final String effect;
  final String? reason;
  final Color? fallbackColor;

  String get description => available
      ? 'Windows 实时窗后毛玻璃可用'
      : switch (reason) {
          'disabled' => '未选择窗后背景，原生毛玻璃已停用',
          'transparency_disabled' => '系统透明效果已关闭，主界面使用实色背景',
          'high_contrast' => '高对比度模式，主界面使用系统背景色',
          'energy_saver' || 'battery_saver' => '节电模式，主界面暂时使用实色背景',
          'initializing' => '正在初始化 Windows 窗后毛玻璃',
          _ => '窗后毛玻璃暂不可用，主界面使用实色背景',
        };

  @override
  bool operator ==(Object other) =>
      other is WindowBackdropStatus &&
      available == other.available &&
      effect == other.effect &&
      reason == other.reason &&
      fallbackColor == other.fallbackColor;

  @override
  int get hashCode => Object.hash(available, effect, reason, fallbackColor);
}

class WindowBackdropService extends ValueNotifier<WindowBackdropStatus> {
  WindowBackdropService._({
    required MethodChannel channel,
    required bool supportedPlatform,
    Duration timeout = const Duration(seconds: 4),
  })  : _channel = channel,
        _supportedPlatform = supportedPlatform,
        _timeout = timeout,
        super(const WindowBackdropStatus(reason: 'initializing'));

  @visibleForTesting
  factory WindowBackdropService.forTesting({
    required MethodChannel channel,
    bool supportedPlatform = true,
    Duration timeout = const Duration(seconds: 4),
  }) =>
      WindowBackdropService._(
        channel: channel,
        supportedPlatform: supportedPlatform,
        timeout: timeout,
      );

  static final instance = WindowBackdropService._(
    channel: const MethodChannel('dan_player/window_backdrop'),
    supportedPlatform: Platform.isWindows,
  );

  final MethodChannel _channel;
  final bool _supportedPlatform;
  final Duration _timeout;
  bool _dark = false;
  bool _enabled = true;
  bool _initialized = false;
  bool _disposed = false;
  int _eventRevision = 0;
  int _requestRevision = 0;
  Future<void> _pending = Future<void>.value();

  /// Call only after window_manager finishes applying its transparent window
  /// options: setBackgroundColor also writes the Windows accent policy.
  Future<void> initialize({required Brightness brightness, bool? enabled}) {
    if (_disposed) return Future.value();
    _dark = brightness == Brightness.dark;
    if (enabled != null) _enabled = enabled;
    if (!_supportedPlatform) {
      value = const WindowBackdropStatus(reason: 'unsupported_platform');
      return Future.value();
    }
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_onMethodCall);
    }
    return _schedule();
  }

  Future<void> setBrightness(Brightness brightness) {
    return configure(brightness: brightness, enabled: _enabled);
  }

  Future<void> configure(
      {required Brightness brightness, required bool enabled}) {
    if (_disposed) return Future.value();
    final dark = brightness == Brightness.dark;
    if (_dark == dark && _enabled == enabled) return _pending;
    _dark = dark;
    _enabled = enabled;
    return _initialized ? _schedule() : Future.value();
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (_disposed || call.method != 'stateChanged') return;
    final message = call.arguments;
    if (message is Map && message['dark'] is bool && message['dark'] != _dark) {
      return;
    }
    if (message is Map &&
        message['enabled'] is bool &&
        message['enabled'] != _enabled) {
      return;
    }
    ++_eventRevision;
    value = WindowBackdropStatus.fromMessage(message);
  }

  Future<void> _schedule() {
    final requestRevision = ++_requestRevision;
    final dark = _dark;
    final enabled = _enabled;
    // A serial chain avoids overlapping native policies. Queued requests that
    // have already been superseded do not reconfigure the compositor at all.
    return _pending = _pending.then((_) async {
      if (_disposed || requestRevision != _requestRevision) return;
      final eventRevision = _eventRevision;
      WindowBackdropStatus result;
      try {
        final message = await _channel.invokeMethod<Object?>(
          'configure',
          {'dark': dark, 'enabled': enabled},
        ).timeout(_timeout);
        result = message is Map &&
                ((message['dark'] is bool && message['dark'] != dark) ||
                    (message['enabled'] is bool &&
                        message['enabled'] != enabled))
            ? const WindowBackdropStatus(reason: 'invalid_response')
            : WindowBackdropStatus.fromMessage(message);
      } on MissingPluginException {
        result = const WindowBackdropStatus(reason: 'unsupported_platform');
      } on TimeoutException {
        result = const WindowBackdropStatus(reason: 'backend_timeout');
      } on PlatformException {
        result = const WindowBackdropStatus(reason: 'backend_error');
      } catch (_) {
        result = const WindowBackdropStatus(reason: 'invalid_response');
      }
      if (!_disposed &&
          requestRevision == _requestRevision &&
          dark == _dark &&
          enabled == _enabled &&
          eventRevision == _eventRevision) {
        value = result;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    if (_initialized) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Only brightness and actual use of native glass configure the compositor.
/// Cover, opacity and blur-radius updates are Flutter-only; navigating pages,
/// mini transitions and window dragging do not cycle native effects.
class WindowBackdropThemeSync extends StatefulWidget {
  const WindowBackdropThemeSync({super.key, required this.child});

  final Widget child;

  @override
  State<WindowBackdropThemeSync> createState() =>
      _WindowBackdropThemeSyncState();
}

class _WindowBackdropThemeSyncState extends State<WindowBackdropThemeSync> {
  Brightness? _brightness;
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.backgrounds.addListener(_sync);
  }

  @override
  void dispose() {
    AppSettings.instance.backgrounds.removeListener(_sync);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final brightness = Theme.of(context).brightness;
    final enabled = AppSettings.instance.backgrounds.value.needsNativeGlass;
    if (brightness == _brightness && enabled == _enabled) return;
    _brightness = brightness;
    _enabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _brightness == brightness && _enabled == enabled) {
        unawaited(WindowBackdropService.instance
            .configure(brightness: brightness, enabled: enabled));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
