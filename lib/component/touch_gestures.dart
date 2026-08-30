import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Enables direct manipulation with touch/stylus while retaining desktop
/// wheel and trackpad behavior.
class DanPlayerScrollBehavior extends MaterialScrollBehavior {
  const DanPlayerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

/// Observes a left-edge touch swipe without entering Flutter's gesture arena,
/// so vertical lists and sliders keep their normal gestures.
class TouchEdgeSwipe extends StatefulWidget {
  const TouchEdgeSwipe({
    super.key,
    required this.child,
    required this.onSwipeRight,
  });

  final Widget child;
  final VoidCallback onSwipeRight;

  @override
  State<TouchEdgeSwipe> createState() => _TouchEdgeSwipeState();
}

class _TouchEdgeSwipeState extends State<TouchEdgeSwipe> {
  int? _pointer;
  Offset? _start;
  Offset? _last;
  bool? _horizontal;

  bool _isDirectTouch(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _down(PointerDownEvent event) {
    if (_pointer != null || !_isDirectTouch(event.kind)) return;
    if (event.localPosition.dx > 32.0) return;
    _pointer = event.pointer;
    _start = event.localPosition;
    _last = event.localPosition;
    _horizontal = null;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    if (start == null) return;
    final delta = event.localPosition - start;
    if (_horizontal == null && delta.distance >= 14.0) {
      _horizontal = delta.dx > 0 && delta.dx.abs() > delta.dy.abs() * 1.25;
    }
    if (_horizontal == true) _last = event.localPosition;
  }

  void _reset() {
    _pointer = null;
    _start = null;
    _last = null;
    _horizontal = null;
  }

  void _finish(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    final last = _last;
    final horizontal = _horizontal;
    _reset();
    if (start == null || last == null) return;
    final delta = last - start;
    if (horizontal == true &&
        delta.dx >= 88.0 &&
        delta.dx.abs() > delta.dy.abs() * 1.35) {
      widget.onSwipeRight();
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _finish,
        onPointerCancel: _cancel,
        child: widget.child,
      );
}

/// Horizontal direct-touch swipe for previous/next on the immersive player.
class TouchTrackSwipe extends StatefulWidget {
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
  State<TouchTrackSwipe> createState() => _TouchTrackSwipeState();
}

class _TouchTrackSwipeState extends State<TouchTrackSwipe> {
  int? _pointer;
  Offset? _start;
  Offset? _last;
  bool? _horizontal;

  bool _isDirectTouch(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _down(PointerDownEvent event) {
    if (_pointer != null || !_isDirectTouch(event.kind)) return;
    _pointer = event.pointer;
    _start = event.localPosition;
    _last = event.localPosition;
    _horizontal = null;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    if (start == null) return;
    final delta = event.localPosition - start;
    if (_horizontal == null && delta.distance >= 14.0) {
      _horizontal = delta.dx.abs() > delta.dy.abs() * 1.25;
    }
    if (_horizontal == true) _last = event.localPosition;
  }

  void _reset() {
    _pointer = null;
    _start = null;
    _last = null;
    _horizontal = null;
  }

  void _finish(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    final last = _last;
    final horizontal = _horizontal;
    _reset();
    if (horizontal != true || start == null || last == null) return;
    final delta = last - start;
    if (delta.dx.abs() <= delta.dy.abs() * 1.35) return;
    if (delta.dx <= -84.0) {
      widget.onNext();
    } else if (delta.dx >= 84.0) {
      widget.onPrevious();
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _finish,
        onPointerCancel: _cancel,
        child: widget.child,
      );
}
