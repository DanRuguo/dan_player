import 'dart:async';

import 'package:dan_player/desktop_integration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Automatically hides the mouse cursor after [delay] of pointer/keyboard
/// inactivity while [active] (or window fullscreen when [trackWindowFullscreen]
/// is true).
///
/// Outside the active state—or whenever the window is hidden/minimized,
/// unfocused, or covered by a modal route/dialog—no timer or keyboard handler
/// is kept alive and the cursor stays normal.
class AutoHideCursor extends StatefulWidget {
  const AutoHideCursor({
    super.key,
    required this.child,
    this.delay = const Duration(seconds: 3),
    this.active,
    this.hidden,
    this.trackWindowFullscreen = false,
  });

  final Widget child;
  final Duration delay;

  /// Explicit activation source (used by tests or callers that manage their
  /// own state). When omitted and [trackWindowFullscreen] is true, window
  /// fullscreen transitions control activation automatically.
  final ValueListenable<bool>? active;

  /// Window hidden/minimized state. Defaults to
  /// [DesktopIntegration.instance.isHidden].
  final ValueListenable<bool>? hidden;

  final bool trackWindowFullscreen;

  @override
  State<AutoHideCursor> createState() => _AutoHideCursorState();
}

class _AutoHideCursorState extends State<AutoHideCursor>
    with WidgetsBindingObserver, WindowListener {
  Timer? _idleTimer;
  bool _cursorHidden = false;
  bool _windowFullscreen = false;
  bool _listeningWindow = false;
  bool _keyboardAttached = false;
  bool _routeIsCurrent = true;
  bool _tickersEnabled = true;
  late AppLifecycleState _lifecycle =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  Offset? _lastHoverPosition;

  ValueListenable<bool> get _hiddenListenable =>
      widget.hidden ?? DesktopIntegration.instance.isHidden;

  bool get _activeValue =>
      widget.active != null ? widget.active!.value : _windowFullscreen;

  bool get _canAutoHide =>
      _activeValue &&
      !_hiddenListenable.value &&
      _routeIsCurrent &&
      _tickersEnabled &&
      _lifecycle == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.active?.addListener(_syncActivation);
    _hiddenListenable.addListener(_syncActivation);
    _syncWindowTracking();
    _syncActivation(allowSetState: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _syncActivation(allowSetState: false);
  }

  @override
  void didUpdateWidget(covariant AutoHideCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.active, widget.active)) {
      oldWidget.active?.removeListener(_syncActivation);
      widget.active?.addListener(_syncActivation);
    }
    final oldHidden = oldWidget.hidden ?? DesktopIntegration.instance.isHidden;
    final newHidden = _hiddenListenable;
    if (!identical(oldHidden, newHidden)) {
      oldHidden.removeListener(_syncActivation);
      newHidden.addListener(_syncActivation);
    }
    if (oldWidget.trackWindowFullscreen != widget.trackWindowFullscreen ||
        (oldWidget.active == null) != (widget.active == null)) {
      _syncWindowTracking();
    }
    if (oldWidget.delay != widget.delay && _idleTimer != null) {
      _armTimer();
    }
    _syncActivation(allowSetState: false);
  }

  void _syncWindowTracking() {
    final shouldListen = widget.active == null && widget.trackWindowFullscreen;
    if (shouldListen == _listeningWindow) return;
    _listeningWindow = shouldListen;
    if (shouldListen) {
      windowManager.addListener(this);
      unawaited(_readInitialFullscreen());
    } else {
      windowManager.removeListener(this);
      _windowFullscreen = false;
    }
  }

  Future<void> _readInitialFullscreen() async {
    try {
      final fullscreen = await windowManager.isFullScreen();
      if (!mounted || !_listeningWindow) return;
      if (_windowFullscreen != fullscreen) {
        _windowFullscreen = fullscreen;
        _syncActivation();
      }
    } catch (_) {
      // Headless tests or environments without window_manager stay inactive.
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted || !_listeningWindow) return;
    if (!_windowFullscreen) {
      _windowFullscreen = true;
      _syncActivation();
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted || !_listeningWindow) return;
    if (_windowFullscreen) {
      _windowFullscreen = false;
      _syncActivation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle == state) return;
    _lifecycle = state;
    _syncActivation();
  }

  void _attachKeyboard() {
    if (_keyboardAttached) return;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _keyboardAttached = true;
  }

  void _detachKeyboard() {
    if (!_keyboardAttached) return;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _keyboardAttached = false;
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!_canAutoHide) return false;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _recordActivity();
    }
    return false;
  }

  void _syncActivation({bool allowSetState = true}) {
    if (_canAutoHide) {
      _attachKeyboard();
      if (!_cursorHidden && _idleTimer == null) {
        _armTimer();
      }
    } else {
      _cancelTimer();
      _detachKeyboard();
      _lastHoverPosition = null;
      if (_cursorHidden && allowSetState && mounted) {
        setState(() => _cursorHidden = false);
      } else {
        _cursorHidden = false;
      }
    }
  }

  void _armTimer() {
    _idleTimer?.cancel();
    if (!_canAutoHide) {
      _idleTimer = null;
      return;
    }
    _idleTimer = Timer(widget.delay, () {
      _idleTimer = null;
      if (!mounted || !_canAutoHide || _cursorHidden) return;
      setState(() => _cursorHidden = true);
    });
  }

  void _cancelTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _recordActivity() {
    if (!_canAutoHide) return;
    if (_cursorHidden) {
      setState(() => _cursorHidden = false);
    }
    _armTimer();
  }

  void _onPointerMotion(PointerEvent event) {
    if (!_canAutoHide) return;
    // Windows may emit a synthetic WM_MOUSEMOVE at the unchanged coordinates
    // when cursor visibility toggles; ignore zero-delta repeats.
    if (event.delta == Offset.zero && event.position == _lastHoverPosition) {
      return;
    }
    _lastHoverPosition = event.position;
    _recordActivity();
  }

  void _onPointerExit(PointerExitEvent event) {
    _lastHoverPosition = null;
    _cancelTimer();
    if (_cursorHidden && mounted) {
      setState(() => _cursorHidden = false);
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    _detachKeyboard();
    if (_listeningWindow) {
      windowManager.removeListener(this);
      _listeningWindow = false;
    }
    widget.active?.removeListener(_syncActivation);
    _hiddenListenable.removeListener(_syncActivation);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _recordActivity(),
      onExit: _onPointerExit,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _onPointerMotion,
        onPointerMove: _onPointerMotion,
        onPointerDown: (_) => _recordActivity(),
        onPointerSignal: (_) => _recordActivity(),
        onPointerPanZoomUpdate: (_) => _recordActivity(),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_cursorHidden)
              const Positioned.fill(
                child: MouseRegion(
                  key: ValueKey('auto-hide-cursor-overlay'),
                  opaque: false,
                  hitTestBehavior: HitTestBehavior.translucent,
                  cursor: SystemMouseCursors.none,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
