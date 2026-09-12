import 'dart:async';
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
  TapDownDetails? _secondary;
  void _release() {
    scheduleMicrotask(() {
      if (!mounted) return;
      _states.update(WidgetState.pressed, false);
      _states.update(WidgetState.hovered, false);
    });
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: InkWell(
          statesController: _states,
          borderRadius: widget.borderRadius,
          focusColor: widget.focusColor,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.pressed) &&
                !states.contains(WidgetState.hovered) &&
                !states.contains(WidgetState.focused))
              return Colors.transparent;
            return widget.overlayColor?.resolve(states) ??
                Theme.of(context).colorScheme.primary.withValues(
                    alpha: states.contains(WidgetState.pressed) ? .12 : .06);
          }),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTapDown:
              widget.onSecondaryTapDown == null && widget.onSecondaryTap == null
                  ? null
                  : (details) => _secondary = details,
          // Do not open an overlay on pointer-down: let InkWell finish the gesture
          // before moving focus/hit testing into a different overlay.
          onSecondaryTap:
              widget.onSecondaryTapDown == null && widget.onSecondaryTap == null
                  ? null
                  : () {
                      if (_secondary != null)
                        widget.onSecondaryTapDown?.call(_secondary!);
                      widget.onSecondaryTap?.call();
                    },
          child: widget.child));
}
