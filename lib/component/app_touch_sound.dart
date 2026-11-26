import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Determines whether the deepest interactive render target in [result]
/// represents a clickable control rather than empty space or a text input.
///
/// Handles both explicit `SystemMouseCursors.click` regions and standard
/// Flutter Material 3 desktop controls on Windows (whose default mouse cursor
/// is `SystemMouseCursors.basic` while exposing semantic tap/button/toggle
/// annotations):
/// - Enabled buttons, IconButtons, InkWells, ListTiles, Switches, Chips,
///   MenuItemButtons, and timed lyric lines -> returns `true`.
/// - Empty background areas, route `ModalBarrier`s, disabled controls, sliders,
///   text fields (`RenderEditable` / `SystemMouseCursors.text`), and resize
///   dividers -> returns `false`.
bool isInteractiveClickTarget(HitTestResult result) {
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderEditable || target is RenderBlockSemantics) {
      return false;
    }
    if (target is RenderMouseRegion) {
      final cursor = target.cursor;
      if (cursor == MouseCursor.defer) continue;
      if (cursor == SystemMouseCursors.click) return true;
      if (cursor != SystemMouseCursors.basic) return false;
      break;
    }
  }

  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderEditable || target is RenderBlockSemantics) {
      return false;
    }
    if (target is RenderMouseRegion) {
      final cursor = target.cursor;
      if (cursor != MouseCursor.defer &&
          cursor != SystemMouseCursors.basic &&
          cursor != SystemMouseCursors.click) {
        return false;
      }
    }
    if (target is RenderSemanticsAnnotations) {
      final props = target.properties;
      if (props.enabled == false || props.textField == true) {
        return false;
      }
      if (props.button == true ||
          props.toggled != null ||
          props.checked != null ||
          props.link == true ||
          props.onTap != null) {
        return true;
      }
    }
    if (target is RenderSemanticsGestureHandler) {
      final allowsTap = target.validActions == null ||
          target.validActions!.contains(SemanticsAction.tap);
      if (target.onTap != null && allowsTap) {
        return true;
      }
    }
  }
  return false;
}

/// Dispatches the Android Material `Effect_Tick` touch/click sound to the
/// native XAudio2 voice pool when enabled and not in WASAPI exclusive mode.
class TouchSoundService {
  TouchSoundService._();

  static final TouchSoundService instance = TouchSoundService._();

  static const MethodChannel _channel = MethodChannel('dan_player/touch_sound');
  static const Duration minInterval = Duration(milliseconds: 28);

  DateTime? _lastPlayedAt;
  Duration? _lastEventTimeStamp;

  @visibleForTesting
  Future<void> Function(double gain)? overridePlayForTesting;

  @visibleForTesting
  void resetForTesting() {
    _lastPlayedAt = null;
    _lastEventTimeStamp = null;
    overridePlayForTesting = null;
  }

  bool get _shouldPlay {
    final experience = AppSettings.instance.experience.value;
    if (!experience.touchSound) return false;
    // Keep WASAPI exclusive hardware streams 100% pure and undisturbed.
    if (experience.exclusiveOutput) return false;
    if (PlayService.playbackReady.value &&
        PlayService.instance.playbackService.wasapiExclusive.value) {
      return false;
    }
    return true;
  }

  void playTick({double gain = 1.0, Duration? eventTimeStamp}) {
    if (!_shouldPlay || !gain.isFinite || gain <= 0) return;
    if (eventTimeStamp != null) {
      if (eventTimeStamp > Duration.zero) {
        final previousStamp = _lastEventTimeStamp;
        if (previousStamp != null &&
            eventTimeStamp >= previousStamp &&
            (eventTimeStamp - previousStamp) < minInterval) {
          return;
        }
        _lastEventTimeStamp = eventTimeStamp;
      }
    } else {
      final timestamp = DateTime.now();
      final previous = _lastPlayedAt;
      if (previous != null && timestamp.difference(previous) < minInterval) {
        return;
      }
      _lastPlayedAt = timestamp;
    }
    final override = overridePlayForTesting;
    if (override != null) {
      unawaited(override(gain));
      return;
    }
    unawaited(
      _channel
          .invokeMethod<bool>('playTick', {'gain': gain})
          .catchError((Object _) => false),
    );
  }
}

typedef _PendingTap = ({Offset downPosition, Duration downTimeStamp});

/// Observes pointer gestures across main routes, overlays, menus, dialogs, and
/// mini-player without claiming the gesture arena. Plays [TouchSoundService]
/// only when a tap begins on an interactive control and completes within
/// [kTouchSlop] and [maxTapDuration].
class AppTouchSoundScope extends StatefulWidget {
  const AppTouchSoundScope({super.key, required this.child});

  final Widget child;

  static const Duration maxTapDuration = Duration(milliseconds: 500);

  @override
  State<AppTouchSoundScope> createState() => _AppTouchSoundScopeState();
}

class _AppTouchSoundScopeState extends State<AppTouchSoundScope> {
  final Map<int, _PendingTap> _pending = <int, _PendingTap>{};

  bool _isPrimaryPress(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return event.buttons == kPrimaryButton;
    }
    return event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_isPrimaryPress(event)) {
      _pending.remove(event.pointer);
      return;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    if (!isInteractiveClickTarget(hit)) {
      _pending.remove(event.pointer);
      return;
    }
    _pending[event.pointer] = (
      downPosition: event.position,
      downTimeStamp: event.timeStamp,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final tracked = _pending[event.pointer];
    if (tracked == null) return;
    if ((event.position - tracked.downPosition).distance > kTouchSlop) {
      _pending.remove(event.pointer);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final tracked = _pending.remove(event.pointer);
    if (tracked == null) return;
    if ((event.position - tracked.downPosition).distance > kTouchSlop) return;
    final elapsed = event.timeStamp - tracked.downTimeStamp;
    if (elapsed > AppTouchSoundScope.maxTapDuration) return;
    TouchSoundService.instance.playTick(eventTimeStamp: event.timeStamp);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pending.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
