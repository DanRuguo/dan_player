import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A grid drag source that follows the input device instead of making touch
/// scrolling compete with an immediate drag recognizer.
///
/// Mouse/trackpad presses start after normal drag slop. Touch and pen input
/// must remain still for a long press first, so a regular vertical swipe keeps
/// scrolling the grid and never changes custom order.
class AdaptiveGridDragSource<T extends Object> extends StatelessWidget {
  const AdaptiveGridDragSource({
    super.key,
    required this.dragKey,
    required this.data,
    required this.child,
    required this.feedback,
    this.childWhenDragging,
    this.maxSimultaneousDrags = 1,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDraggableCanceled,
    this.onDragEnd,
    this.onDragCompleted,
    this.rootOverlay = true,
    this.mouseHoldDelay = Duration.zero,
    this.mouseBounds,
    this.onMouseClick,
  })  : assert(mouseHoldDelay == Duration.zero || mouseBounds != null),
        assert(onMouseClick == null || mouseBounds != null);

  /// Applied to the mouse [Draggable] to preserve stable finders and
  /// state while a virtualized grid rebuilds around the active drag.
  final Key dragKey;
  final T data;
  final Widget child;
  final Widget feedback;
  final Widget? childWhenDragging;
  final int? maxSimultaneousDrags;
  final VoidCallback? onDragStarted;
  final DragUpdateCallback? onDragUpdate;
  final DraggableCanceledCallback? onDraggableCanceled;
  final DragEndCallback? onDragEnd;
  final VoidCallback? onDragCompleted;
  final bool rootOverlay;

  /// Cards may drag on boundary exit or a still press; other sources drag
  /// immediately. Click and drag use the same full-card bounds.
  final Duration mouseHoldDelay;
  final Rect Function()? mouseBounds;
  final VoidCallback? onMouseClick;

  @override
  Widget build(BuildContext context) {
    final edgeScroll = _GridEdgeAutoScrollScope.maybeOf(context);

    void started() => onDragStarted?.call();
    void updated(DragUpdateDetails details) {
      edgeScroll?.update(details.globalPosition);
      onDragUpdate?.call(details);
    }

    void ended(DraggableDetails details) {
      edgeScroll?.stop();
      onDragEnd?.call(details);
    }

    void completed() {
      edgeScroll?.stop();
      onDragCompleted?.call();
    }

    void canceled(Velocity velocity, Offset offset) {
      edgeScroll?.stop();
      onDraggableCanceled?.call(velocity, offset);
    }

    final touchSource = _TouchLongPressDraggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      maxSimultaneousDrags: maxSimultaneousDrags,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      rootOverlay: rootOverlay,
      onDragStarted: started,
      onDragUpdate: updated,
      onDragEnd: ended,
      onDragCompleted: completed,
      onDraggableCanceled: canceled,
      child: onMouseClick == null
          ? child
          : RawGestureDetector(
              gestures: {
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(
                    supportedDevices: const {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad
                    },
                    allowedButtonsFilter: (buttons) =>
                        buttons == kPrimaryButton,
                    preAcceptSlopTolerance: double.infinity,
                    postAcceptSlopTolerance: double.infinity,
                  ),
                  (recognizer) => recognizer.onTapUp = (details) {
                    if (mouseBounds!().contains(details.globalPosition)) {
                      onMouseClick!();
                    }
                  },
                ),
              },
              child: child,
            ),
    );
    return _MouseDraggable<T>(
      holdDelay: mouseHoldDelay,
      bounds: mouseBounds,
      key: dragKey,
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      maxSimultaneousDrags: maxSimultaneousDrags,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      rootOverlay: rootOverlay,
      onDragStarted: started,
      onDragUpdate: updated,
      onDragEnd: ended,
      onDragCompleted: completed,
      onDraggableCanceled: canceled,
      child: touchSource,
    );
  }
}

class _MouseDraggable<T extends Object> extends Draggable<T> {
  const _MouseDraggable({
    required this.holdDelay,
    this.bounds,
    super.key,
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    super.rootOverlay,
  });

  final Duration holdDelay;
  final Rect Function()? bounds;

  @override
  MultiDragGestureRecognizer createRecognizer(
      GestureMultiDragStartCallback onStart) {
    final recognizer = holdDelay == Duration.zero
        ? ImmediateMultiDragGestureRecognizer(
            supportedDevices: const {
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
            allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
          )
        : _HeldMouseDragRecognizer(holdDelay, bounds!);
    return recognizer..onStart = onStart;
  }
}

class _HeldMouseDragRecognizer extends MultiDragGestureRecognizer {
  _HeldMouseDragRecognizer(this.delay, this.bounds)
      : super(
            debugOwner: null,
            supportedDevices: const {
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
            allowedButtonsFilter: (buttons) => buttons == kPrimaryButton);
  final Duration delay;
  final Rect Function() bounds;
  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _HeldMouseDragState(
          event.position, event.kind, gestureSettings, delay, bounds());
  @override
  String get debugDescription => 'held mouse drag';
}

/// Remain a click inside the original card; exiting it always starts a drag.
/// A still press may also lift the card. Movement only cancels that timer,
/// never the exit-to-drag gesture, so a continuous drag cannot get stranded.
class _HeldMouseDragState extends MultiDragPointerState {
  _HeldMouseDragState(super.initialPosition, super.kind, super.gestureSettings,
      Duration delay, this.bounds) {
    _timer = Timer(delay, _activate);
  }
  final Rect bounds;
  Timer? _timer;
  GestureMultiDragStartCallback? _starter;
  bool _ready = false;
  void _activate() {
    _timer?.cancel();
    _timer = null;
    _ready = true;
    final starter = _starter;
    _starter = null;
    if (starter != null) {
      starter(initialPosition);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_ready) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    final delta = pendingDelta!;
    if (!bounds.contains(initialPosition + delta)) {
      _activate();
    } else if (delta.distance > kTouchSlop) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _TouchLongPressDraggable<T extends Object> extends LongPressDraggable<T> {
  const _TouchLongPressDraggable({
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    super.rootOverlay,
  });

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
      GestureMultiDragStartCallback onStart) {
    return DelayedMultiDragGestureRecognizer(
      delay: delay,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
    )..onStart = (position) {
        final drag = onStart(position);
        if (drag != null && hapticFeedbackOnStart) {
          HapticFeedback.selectionClick();
        }
        return drag;
      };
  }
}

/// Supplies continuous vertical edge scrolling to adaptive drag sources below
/// it. One timer belongs to the viewport rather than to every virtualized card.
class GridEdgeAutoScrollRegion extends StatefulWidget {
  const GridEdgeAutoScrollRegion({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<GridEdgeAutoScrollRegion> createState() =>
      _GridEdgeAutoScrollRegionState();
}

class _GridEdgeAutoScrollRegionState extends State<GridEdgeAutoScrollRegion> {
  static const _interval = Duration(milliseconds: 16);
  static const _maxStep = 18.0;
  final _regionKey = GlobalKey();
  Timer? _timer;
  double _step = 0;

  void _update(Offset globalPosition) {
    final box = _regionKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height <= 0) {
      _stop();
      return;
    }
    final y = box.globalToLocal(globalPosition).dy;
    final edge = math.min(72.0, math.max(32.0, box.size.height * .18));
    final double proximity;
    if (y < edge) {
      proximity = -((edge - y) / edge).clamp(0.0, 1.0);
    } else if (y > box.size.height - edge) {
      proximity = ((y - (box.size.height - edge)) / edge).clamp(0.0, 1.0);
    } else {
      proximity = 0;
    }
    if (proximity == 0) {
      _stop();
      return;
    }
    _step = proximity.sign * (2 + (_maxStep - 2) * proximity.abs());
    _timer ??= Timer.periodic(_interval, (_) => _tick());
  }

  void _tick() {
    if (!mounted || !widget.controller.hasClients) {
      _stop();
      return;
    }
    final position = widget.controller.position;
    final next = (position.pixels + _step)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next != position.pixels) widget.controller.jumpTo(next);
  }

  void _stop() {
    _step = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GridEdgeAutoScrollScope(
        update: _update,
        stop: _stop,
        child: Listener(
          key: _regionKey,
          behavior: HitTestBehavior.translucent,
          onPointerUp: (_) => _stop(),
          onPointerCancel: (_) => _stop(),
          child: widget.child,
        ),
      );
}

class _GridEdgeAutoScrollScope extends InheritedWidget {
  const _GridEdgeAutoScrollScope({
    required this.update,
    required this.stop,
    required super.child,
  });

  final ValueChanged<Offset> update;
  final VoidCallback stop;

  static _GridEdgeAutoScrollScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GridEdgeAutoScrollScope>();

  @override
  bool updateShouldNotify(_GridEdgeAutoScrollScope oldWidget) =>
      update != oldWidget.update || stop != oldWidget.stop;
}
