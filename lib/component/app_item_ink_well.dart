import 'dart:async';
import 'app_motion.dart';
import 'package:flutter/material.dart';

/// Item ink must end with the pointer sequence, including a long press won by
/// a drag recognizer or a popup that temporarily takes the pointer's hit test.
/// Keep real keyboard focus and explicit list selection independent of ink.
class AppItemInkWell extends StatefulWidget {
  const AppItemInkWell(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.onSecondaryTapDown,
      this.onSecondaryTap,
      this.borderRadius,
      this.focusColor,
      this.overlayColor});
  final Widget child;
  final VoidCallback? onTap, onLongPress, onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final BorderRadius? borderRadius;
  final Color? focusColor;
  final WidgetStateProperty<Color?>? overlayColor;
  @override
  State<AppItemInkWell> createState() => _AppItemInkWellState();
}

class _AppItemInkWellState extends State<AppItemInkWell> {
  final _states = WidgetStatesController();
  final _focus = FocusNode(debugLabel: 'item ink');
  TapDownDetails? _secondary;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _release() {
    scheduleMicrotask(() {
      if (!mounted) return;
      _states.update(WidgetState.pressed, false);
      _states.update(WidgetState.hovered, false);
    });
  }

  Color _stateColor(BuildContext context, Set<WidgetState> states) {
    final active = Set<WidgetState>.of(states);
    if (!_focus.hasPrimaryFocus) active.remove(WidgetState.focused);
    if (!active.contains(WidgetState.pressed) &&
        !active.contains(WidgetState.hovered) &&
        !active.contains(WidgetState.focused)) {
      return Colors.transparent;
    }
    return widget.overlayColor?.resolve(active) ??
        (active.contains(WidgetState.focused) ? widget.focusColor : null) ??
        Theme.of(context).colorScheme.primary.withValues(
            alpha: active.contains(WidgetState.pressed) ? .12 : .06);
  }

  @override
  void dispose() {
    _focus.dispose();
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: ListenableBuilder(
          listenable: _states,
          // Flutter's InkHighlight keeps its creation-time opacity independently
          // of WidgetStatesController. Reparenting into a drag overlay can leave
          // that highlight alive after a missing mouse-exit event. Own the state
          // layer explicitly; keep InkWell's gestures, keyboard and splash ink.
          builder: (context, child) => TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: _stateColor(context, _states.value)),
                duration: AppMotion.duration(context, MotionKind.feedback,
                    const Duration(milliseconds: 50)),
                builder: (_, color, child) => Ink(
                  decoration: BoxDecoration(
                      color: color, borderRadius: widget.borderRadius),
                  child: child,
                ),
                child: child,
              ),
          child: InkWell(
              splashFactory: AppMotion.enabled(context, MotionKind.feedback)
                  ? null
                  : NoSplash.splashFactory,
              statesController: _states,
              focusNode: _focus,
              borderRadius: widget.borderRadius,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              // The visible state layer above owns the original 50 ms hover
              // fade; do not run another invisible hover/focus ticker here.
              hoverDuration: Duration.zero,
              focusColor: Colors.transparent,
              splashColor: _stateColor(context, {WidgetState.pressed}),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onSecondaryTapDown: widget.onSecondaryTapDown == null &&
                      widget.onSecondaryTap == null
                  ? null
                  : (details) => _secondary = details,
              // Do not open an overlay on pointer-down: let InkWell finish the gesture
              // before moving focus/hit testing into a different overlay.
              onSecondaryTap: widget.onSecondaryTapDown == null &&
                      widget.onSecondaryTap == null
                  ? null
                  : () {
                      if (_secondary != null) {
                        widget.onSecondaryTapDown?.call(_secondary!);
                      }
                      widget.onSecondaryTap?.call();
                    },
              child: widget.child)));
}
