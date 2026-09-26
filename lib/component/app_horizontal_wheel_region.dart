import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_motion.dart';

/// A plain vertical mouse wheel navigates the horizontal rail under it.
/// Native horizontal/shift-wheel signals and touch gestures keep their owner.
/// At an edge, a surrounding page can keep its vertical wheel.
class AppHorizontalWheelRegion extends StatefulWidget {
  const AppHorizontalWheelRegion(
      {super.key, this.controller, required this.child});

  /// Explicit for ordinary rails; TabBar owns a private controller, captured
  /// from the nearest descendant's layout and scroll notifications.
  final ScrollController? controller;
  final Widget child;

  @override
  State<AppHorizontalWheelRegion> createState() =>
      _AppHorizontalWheelRegionState();
}

class _AppHorizontalWheelRegionState extends State<AppHorizontalWheelRegion>
    with WidgetsBindingObserver {
  ScrollPosition? _descendant;
  ScrollPosition? _targetPosition;
  double? _target;
  double _direction = 0;
  int _generation = 0;

  bool get _visible => TickerMode.valuesOf(context).enabled;
  bool get _animated {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return _visible &&
        AppMotion.enabled(context, MotionKind.feedback) &&
        !features.disableAnimations &&
        !features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finishDisabledMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => _finishDisabledMotion();

  void _finishDisabledMotion() {
    if (_animated || _target == null) return;
    final target = _target!;
    final position = _targetPosition;
    final visible = _visible;
    final generation = ++_generation;
    _target = null;
    _targetPosition = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          position?.context.notificationContext?.mounted != true) {
        return;
      }
      if (visible) {
        position!.jumpTo(
            target.clamp(position.minScrollExtent, position.maxScrollExtent));
      } else {
        position!.jumpTo(position.pixels);
      }
    });
  }

  void _cancelPending({bool stop = true}) {
    final position = _targetPosition;
    _generation++;
    _target = null;
    _targetPosition = null;
    _direction = 0;
    if (stop && position?.context.notificationContext?.mounted == true) {
      position!.jumpTo(position.pixels);
    }
  }

  void _capture(BuildContext? source, ScrollMetrics metrics) {
    if (source == null || metrics.axis != Axis.horizontal) return;
    final scrollable = Scrollable.maybeOf(source, axis: Axis.horizontal);
    if (scrollable != null) {
      final position = scrollable.position;
      if (!identical(_descendant, position)) {
        if (_targetPosition != null && !identical(_targetPosition, position)) {
          _cancelPending();
        }
        _descendant = position;
      }
    }
  }

  ScrollPosition? get _position {
    final controller = widget.controller;
    if (controller != null) {
      return controller.positions.length == 1
          ? controller.positions.single
          : null;
    }
    final position = _descendant;
    return position?.context.notificationContext?.mounted == true
        ? position
        : null;
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final behavior = ScrollConfiguration.of(context);
    final native = event.scrollDelta.dx != 0 ||
        (event.kind == PointerDeviceKind.mouse &&
            HardwareKeyboard.instance.logicalKeysPressed
                .any(behavior.pointerAxisModifiers.contains));
    if (native) {
      _cancelPending();
      return;
    }
    if (event.scrollDelta.dy == 0) return;
    final position = _position;
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions ||
        position.axis != Axis.horizontal ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final pending = identical(position, _targetPosition) ? _target : null;
    // Same-direction wheels accumulate. Reversal discards an unvisited target
    // so an opposite pulse at the old edge also cancels pending forward motion.
    final base =
        pending != null && _direction == delta.sign ? pending : position.pixels;
    final target = (base + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == (pending ?? position.pixels)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !identical(_position, position)) return;
      if (!_animated) {
        _cancelPending();
        position.pointerScroll(target - position.pixels);
      } else {
        _direction = delta.sign;
        final generation = ++_generation;
        _target = target;
        _targetPosition = position;
        unawaited(position
            .animateTo(target,
                duration: AppMotion.standard, curve: AppMotion.standardCurve)
            .whenComplete(() {
          if (mounted && generation == _generation) {
            _target = null;
            _targetPosition = null;
          }
        }));
      }
      event.respond(allowPlatformDefault: false);
    });
  }

  @override
  void didUpdateWidget(covariant AppHorizontalWheelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.child.runtimeType != widget.child.runtimeType ||
        oldWidget.child.key != widget.child.key) {
      _cancelPending();
      _descendant = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelPending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _capture(notification.context, notification.metrics);
            }
            return false;
          },
          child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  _capture(notification.context, notification.metrics);
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    // The drag already owns its new activity; clear only the
                    // old wheel destination without stopping that native drag.
                    _cancelPending(stop: false);
                  }
                }
                return false;
              },
              child: Listener(
                  onPointerDown: (_) => _cancelPending(),
                  onPointerPanZoomStart: (_) => _cancelPending(),
                  onPointerSignal: _wheel,
                  child: widget.child)));
}
