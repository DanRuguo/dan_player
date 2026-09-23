import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_scrollbar.dart';

/// Enables direct manipulation with touch/stylus while retaining desktop
/// wheel and trackpad behavior.
class DanPlayerScrollBehavior extends AppScrollBehavior {
  const DanPlayerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

/// Left-edge navigation competes with the child's gesture recognizers, so a
/// slider, selection, or accepted long press cannot also navigate on release.
class TouchEdgeSwipe extends StatelessWidget {
  const TouchEdgeSwipe({
    super.key,
    required this.child,
    required this.onSwipeRight,
  });

  final Widget child;
  final VoidCallback onSwipeRight;

  @override
  Widget build(BuildContext context) => _TouchSwipeSurface(
      edgeOnly: true, onSwipe: (_) => onSwipeRight(), child: child);
}

/// Horizontal direct-touch swipe for previous/next on the immersive player.
class TouchTrackSwipe extends StatelessWidget {
  const TouchTrackSwipe({
    super.key,
    required this.child,
    required this.onPrevious,
    required this.onNext,
  });

  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => _TouchSwipeSurface(
      edgeOnly: false,
      onSwipe: (distance) => distance < 0 ? onNext() : onPrevious(),
      child: child);
}

class _TouchSwipeSurface extends StatelessWidget {
  const _TouchSwipeSurface(
      {required this.edgeOnly, required this.onSwipe, required this.child});

  final bool edgeOnly;
  final ValueChanged<double> onSwipe;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _DirectTouchSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<_DirectTouchSwipeRecognizer>(
                  _DirectTouchSwipeRecognizer.new,
                  (recognizer) => recognizer
                    ..edgeOnly = edgeOnly
                    ..onSwipe = onSwipe),
        },
        child: child,
      );
}

class _DirectTouchSwipeRecognizer extends OneSequenceGestureRecognizer {
  _DirectTouchSwipeRecognizer()
      : super(
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
          allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
        );

  bool edgeOnly = false;
  ValueChanged<double>? onSwipe;
  final _pointers = <int>{};
  int? _primary;
  Offset? _start;
  Offset? _last;
  bool? _horizontal;
  bool _blocked = false;
  bool _won = false;

  bool _reachedAction(double distance) =>
      edgeOnly ? distance >= 88 : distance.abs() >= 84;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointers.add(event.pointer);
    if (_pointers.length > 1 || (edgeOnly && event.localPosition.dx > 32)) {
      // Once a second finger joins, keep the entire sequence inert until all
      // fingers lift. A pinch must not turn its first finger into a track swipe.
      _blocked = true;
      resolve(GestureDisposition.rejected);
      return;
    }
    _primary = event.pointer;
    _start = _last = event.localPosition;
  }

  // An unrelated mouse/stylus secondary button must not reject an ongoing
  // allowed touch. The base implementation rejects the whole active arena.
  @override
  void handleNonAllowedPointer(PointerDownEvent event) {}

  @override
  void handleEvent(PointerEvent event) {
    double? completed;
    if (event.pointer == _primary && !_blocked) {
      if (event is PointerMoveEvent && _start != null) {
        final delta = event.localPosition - _start!;
        if (_horizontal == null && delta.distance >= 14) {
          _horizontal = (!edgeOnly || delta.dx > 0) &&
              delta.dx.abs() > delta.dy.abs() * 1.25;
          if (!_horizontal!) {
            _blocked = true;
            resolve(GestureDisposition.rejected);
          }
        }
        if (_horizontal == true) {
          _last = event.localPosition;
          // Child controls get their normal drag slop first. Do not claim the
          // arena before this gesture has reached its actual action threshold.
          if (_reachedAction(delta.dx)) {
            resolve(GestureDisposition.accepted);
          }
        }
      } else if (event is PointerUpEvent && _won && _horizontal == true) {
        final delta = _last! - _start!;
        if (_reachedAction(delta.dx) &&
            delta.dx.abs() > delta.dy.abs() * 1.35) {
          completed = delta.dx;
        }
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
    if (completed != null) {
      invokeCallback<void>('onSwipe', () => onSwipe?.call(completed!));
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _primary && !_blocked) _won = true;
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _primary) _blocked = true;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    resolve(GestureDisposition.rejected);
    _primary = null;
    _start = _last = null;
    _horizontal = null;
    _blocked = _won = false;
  }

  @override
  String get debugDescription => 'direct touch swipe';
}
