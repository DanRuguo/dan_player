import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_typography.dart';
import 'appearance_controller.dart';
import 'desktop_lyric_appearance.dart';
import 'desktop_lyric_controller.dart';
import 'desktop_lyric_window_layout.dart';
import 'message.dart';
import 'ui_language.dart';

/// The lyric engine owns persistence and the native palette session. Opening a
/// palette never changes the lyric HWND's bounds, minimum size or visibility.
class DesktopLyricPaletteHost {
  DesktopLyricPaletteHost({
    required this.controller,
    required this.layout,
    MethodChannel? channel,
    this.timeout = const Duration(seconds: 12),
  }) : channel =
            channel ?? const MethodChannel('dan_player/desktop_lyric_palette') {
    this.channel.setMethodCallHandler(_handle);
    for (final source in _sources) {
      source.addListener(_changed);
    }
  }

  static final instance = DesktopLyricPaletteHost(
      controller: DesktopLyricController.instance,
      layout: DesktopLyricWindowLayout.instance);
  final DesktopLyricController controller;
  final DesktopLyricWindowLayout layout;
  final MethodChannel channel;
  final Duration timeout;
  final isOpen = ValueNotifier(false);
  final isStarting = ValueNotifier(false);
  int _session = 0;
  int _revision = 0;
  int _editAck = 0;
  bool _disposed = false;
  bool _scheduled = false;
  bool _sending = false;
  bool _dirty = false;
  Future<void>? _opening;
  Completer<void>? _closed;

  List<Listenable> get _sources => [
        controller.appearance,
        controller.theme,
        controller.isDarkMode,
        controller.appearanceSaveError,
        layout.lastError,
        uiLanguage
      ];

  Map<String, Object?> _snapshot() {
    final theme = controller.theme.value;
    return {
      'session': _session,
      'revision': ++_revision,
      'editAck': _editAck,
      'appearance': controller.appearance.value.toJson(),
      'darkMode': controller.isDarkMode.value,
      'primary': theme.primary,
      'surfaceContainer': theme.surfaceContainer,
      'onSurface': theme.onSurface,
      'language': uiLanguage.value.code,
      'fontFamily': DesktopLyricTypography.fontFamily,
      'fontFamilyFallback': DesktopLyricTypography.fontFamilyFallback,
      'saveError': controller.appearanceSaveError.value,
      'layoutError': layout.lastError.value,
    };
  }

  Future<void> open() {
    if (_disposed) return Future.error(StateError('Palette owner is disposed'));
    return _opening ??= _open();
  }

  Future<void> _open() async {
    final session = ++_session;
    _editAck = 0;
    final closed = _closed = Completer<void>();
    isOpen.value = true;
    isStarting.value = true;
    layout.beginPalettePresentation(); // Hover latch only; no native geometry.
    try {
      await channel.invokeMethod<void>('open', _snapshot()).timeout(timeout);
      if (_disposed || session != _session) return;
      isStarting.value = false;
      _changed(); // Include changes received while the second engine started.
      await closed.future;
    } catch (_) {
      // Failed startup is explicit. Never fall back to resizing the owner.
      unawaited(channel
          .invokeMethod<void>('close', session)
          .catchError((Object _) {}));
      rethrow;
    } finally {
      if (session == _session) {
        _closed = null;
        _opening = null;
        _dirty = false;
        layout.endPalettePresentation();
        if (!_disposed) {
          isStarting.value = false;
          isOpen.value = false;
        }
      }
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    if (_disposed) return null;
    final args = call.arguments;
    if (args is! Map ||
        args['session'] != _session ||
        _closed == null ||
        _closed!.isCompleted) {
      return null;
    }
    if (call.method == 'closed') {
      final hover = args['ownerHover'];
      layout.endPalettePresentation(ownerHover: hover is bool ? hover : null);
      if (!_closed!.isCompleted) _closed!.complete();
      return null;
    }
    if (call.method == 'retry') {
      controller.retryAppearanceSave();
      return _snapshot();
    }
    if (call.method == 'edit') {
      final sequence = args['sequence'];
      final patch = args['patch'];
      if (sequence is! int || sequence <= _editAck || patch is! Map) {
        return _snapshot();
      }
      final current = controller.appearance.value.toJson();
      if (patch.keys
          .any((key) => key is! String || !current.containsKey(key))) {
        throw const FormatException('Invalid appearance field');
      }
      final next = DesktopLyricAppearance.tryFromJson({...current, ...patch});
      if (next == null) throw const FormatException('Invalid appearance edit');
      _editAck = sequence;
      controller.appearance.update(next);
      return _snapshot();
    }
    throw MissingPluginException('Unknown palette callback: ${call.method}');
  }

  void _changed() {
    if (_disposed || _closed == null) return;
    _dirty = true;
    if (_scheduled || _sending) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_publish());
    });
  }

  Future<void> _publish() async {
    if (_sending) return;
    _sending = true;
    var requestSession = _session;
    try {
      while (_dirty && !_disposed && _closed != null) {
        _dirty = false;
        requestSession = _session;
        await channel
            .invokeMethod<void>('update', _snapshot())
            .timeout(timeout);
      }
    } catch (error, stack) {
      final closed = _closed;
      if (requestSession == _session && closed != null && !closed.isCompleted) {
        closed.completeError(error, stack);
      }
    } finally {
      _sending = false;
      if (_dirty && !_disposed && _closed != null) _changed();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final source in _sources) {
      source.removeListener(_changed);
    }
    channel.setMethodCallHandler(null);
    final closed = _closed;
    if (closed != null && !closed.isCompleted) closed.complete();
    unawaited(channel
        .invokeMethod<void>('close', _session)
        .catchError((Object _) {}));
    layout.endPalettePresentation();
    isOpen.dispose();
    isStarting.dispose();
  }
}

class DesktopLyricPaletteScope extends InheritedWidget {
  const DesktopLyricPaletteScope(
      {super.key, required this.host, required super.child});
  final DesktopLyricPaletteHost host;
  static DesktopLyricPaletteHost? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopLyricPaletteScope>()
      ?.host;
  @override
  bool updateShouldNotify(DesktopLyricPaletteScope oldWidget) =>
      oldWidget.host != host;
}

/// A second engine has no stdin reader, playback clock, native layout binding,
/// settings or persistence. Its edits are bounded, coalesced field patches.
class DesktopLyricPaletteClient extends ChangeNotifier {
  DesktopLyricPaletteClient(
      {MethodChannel? channel,
      this.flushInterval = const Duration(milliseconds: 33),
      this.timeout = const Duration(seconds: 5)})
      : channel = channel ??
            const MethodChannel('dan_player/desktop_lyric_palette_child') {
    appearance = TextDisplayController(onChanged: _edit);
    this.channel.setMethodCallHandler((call) async {
      if (!_disposed &&
          (call.method == 'present' || call.method == 'refresh')) {
        if (!applySnapshot(call.arguments,
            beginSession: call.method == 'present')) {
          throw const FormatException('Invalid new palette session');
        }
        if (call.method == 'refresh') {
          _presentationEpoch++;
          notifyListeners();
        }
        // Native waits for this layout before requesting a fresh raster/show.
        final frame = WidgetsBinding.instance.endOfFrame;
        // This engine's HWND is still hidden. Request exactly one layout frame
        // even if its lifecycle currently suppresses normal scheduled frames.
        WidgetsBinding.instance.scheduleForcedFrame();
        await frame;
        return null;
      }
      if (!_disposed &&
          call.method == 'suspend' &&
          call.arguments == _session) {
        suspend();
      }
      if (!_disposed && call.method == 'snapshot') {
        applySnapshot(call.arguments);
      }
      if (!_disposed && call.method == 'requestClose') unawaited(close());
    });
  }
  final MethodChannel channel;
  final Duration flushInterval;
  final Duration timeout;
  late final TextDisplayController appearance;
  final theme = ValueNotifier(
      const ThemeChangedMessage(0xff2196f3, 0xffffffff, 0xff000000));
  final isDarkMode = ValueNotifier(false);
  final saveError = ValueNotifier<String?>(null);
  final layoutError = ValueNotifier<String?>(null);
  String fontFamily = DesktopLyricTypography.fontFamily;
  List<String> fontFamilyFallback = DesktopLyricTypography.fontFamilyFallback;
  DesktopLyricAppearance _base = DesktopLyricAppearance.defaults;
  DesktopLyricAppearance _displayed = DesktopLyricAppearance.defaults;
  Map<String, Object?> _pending = {};
  Map<String, Object?> _inflight = {};
  int _session = 0;
  int _revision = -1;
  int _sequence = 0;
  int _inflightSequence = 0;
  Timer? _timer;
  Future<void>? _flushFuture;
  bool _disposed = false;
  bool _closing = false;
  bool _active = true;
  bool get active => _active;
  int _presentationEpoch = 0;
  int get presentationId => _presentationEpoch;

  /// The production native entry passes a StandardMessageCodec snapshot as
  /// hex, avoiding a platform round trip before the first frame. The optional
  /// ready path remains for embedders/tests; malformed arguments fail closed.
  static Object? decodeStartupSnapshot(List<String> arguments) {
    if (arguments.length != 1 ||
        arguments.single.length > 65536 ||
        arguments.single.length.isOdd ||
        arguments.single.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(arguments.single)) {
      throw const FormatException('Invalid palette startup payload');
    }
    final hex = arguments.single;
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return const StandardMessageCodec()
        .decodeMessage(ByteData.sublistView(bytes));
  }

  Future<void> initialize({Object? initialSnapshot}) async {
    final snapshot = initialSnapshot ??
        await channel.invokeMethod<Object?>('ready').timeout(timeout);
    if (!_disposed && !applySnapshot(snapshot)) {
      throw const FormatException('Invalid initial palette snapshot');
    }
  }

  bool applySnapshot(Object? raw, {bool beginSession = false}) {
    if (_disposed || raw is! Map) return false;
    final session = raw['session'];
    final revision = raw['revision'];
    final value = DesktopLyricAppearance.tryFromJson(raw['appearance']);
    bool color(Object? value) =>
        value is int && value >= 0 && value <= 0xffffffff;
    final fallback = raw['fontFamilyFallback'];
    if (session is! int ||
        session <= 0 ||
        revision is! int ||
        revision < 0 ||
        value == null ||
        raw['editAck'] is! int ||
        (raw['editAck'] as int) < 0 ||
        raw['darkMode'] is! bool ||
        !color(raw['primary']) ||
        !color(raw['surfaceContainer']) ||
        !color(raw['onSurface']) ||
        (raw['saveError'] != null && raw['saveError'] is! String) ||
        (raw['layoutError'] != null && raw['layoutError'] is! String) ||
        (raw['language'] != null && raw['language'] is! String) ||
        (raw['fontFamily'] != null && raw['fontFamily'] is! String) ||
        (fallback != null &&
            (fallback is! List || fallback.any((e) => e is! String))) ||
        (beginSession
            ? session <= _session
            : (_session != 0 && session != _session))) {
      return false;
    }
    if (beginSession) {
      _presentationEpoch++;
      _timer?.cancel();
      _timer = null;
      _flushFuture = null;
      _pending = {};
      _inflight = {};
      _revision = -1;
      _sequence = 0;
      _inflightSequence = 0;
      _closing = false;
      _active = true;
    }
    _session = session;
    if (revision > _revision) {
      _revision = revision;
      _base = value;
      isDarkMode.value = raw['darkMode'] == true;
      theme.value = ThemeChangedMessage(raw['primary'] as int,
          raw['surfaceContainer'] as int, raw['onSurface'] as int);
      saveError.value = raw['saveError'] as String?;
      layoutError.value = raw['layoutError'] as String?;
      uiLanguage.value = UiLanguage.parse(raw['language']);
      fontFamily =
          raw['fontFamily'] as String? ?? DesktopLyricTypography.fontFamily;
      fontFamilyFallback =
          (raw['fontFamilyFallback'] as List?)?.cast<String>() ??
              DesktopLyricTypography.fontFamilyFallback;
    }
    final ack = raw['editAck'];
    if (ack is int && ack >= _inflightSequence) _inflight = {};
    _displayed = DesktopLyricAppearance.fromJson(
        {..._base.toJson(), ..._inflight, ..._pending});
    appearance.value =
        _displayed; // Snapshot application must never echo edits.
    notifyListeners();
    return true;
  }

  void _edit(DesktopLyricAppearance next) {
    if (_disposed || !_active || _closing || _session == 0) return;
    final old = _displayed.toJson();
    next.toJson().forEach((key, value) {
      if (old[key] != value) _pending[key] = value;
    });
    _displayed = next;
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    final session = _session;
    return _flushFuture ??= _flush(session).whenComplete(() {
      if (session == _session) _flushFuture = null;
    });
  }

  Future<void> _flush(int session) async {
    _timer?.cancel();
    _timer = null;
    try {
      while (
          _pending.isNotEmpty && !_disposed && session == _session && _active) {
        _inflight = _pending;
        _pending = {};
        _inflightSequence = ++_sequence;
        final snapshot = await channel.invokeMethod<Object?>('edit', {
          'session': session,
          'sequence': _sequence,
          'patch': _inflight,
        }).timeout(timeout);
        if (_disposed || session != _session || !_active) return;
        if (!applySnapshot(snapshot) ||
            (snapshot as Map)['editAck'] < _inflightSequence) {
          throw const FormatException('Missing palette edit acknowledgement');
        }
      }
    } catch (error) {
      if (!_disposed && session == _session && _active) {
        _pending = {..._inflight, ..._pending};
        _inflight = {};
        saveError.value = ui('保存桌面歌词外观失败，请重试');
      }
    }
  }

  Future<void> retrySave() async {
    final session = _session;
    await flush();
    if (_disposed || !_active || session != _session || _pending.isNotEmpty) {
      return;
    }
    try {
      applySnapshot(await channel.invokeMethod<Object?>(
          'retry', {'session': session}).timeout(timeout));
    } catch (_) {
      if (!_disposed && session == _session && _active) {
        saveError.value = ui('保存桌面歌词外观失败，请重试');
      }
    }
  }

  Future<void> close() async {
    if (_disposed || _closing || !_active) return;
    final session = _session;
    _closing = true;
    await flush();
    if (_disposed || session != _session) return;
    // Keep an unsent edit visible and retryable instead of silently losing it.
    if (_pending.isNotEmpty) {
      _closing = false;
      return;
    }
    try {
      await channel
          .invokeMethod<void>('close', {'session': session}).timeout(timeout);
      if (!_disposed && session == _session) suspend();
    } catch (_) {
      if (!_disposed && session == _session) {
        _closing = false;
        layoutError.value = ui('无法关闭歌词外观窗口');
      }
    }
  }

  void suspend() {
    if (_disposed || !_active) return;
    _timer?.cancel();
    _timer = null;
    _active = false;
    _closing = true;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    channel.setMethodCallHandler(null);
    appearance.dispose();
    theme.dispose();
    isDarkMode.dispose();
    saveError.dispose();
    layoutError.dispose();
    super.dispose();
  }
}
