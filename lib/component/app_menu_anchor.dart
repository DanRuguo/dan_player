import 'dart:async';
import 'package:flutter/material.dart';

/// Serialize reopen requests through the existing closing animation. Starting
/// forward while reverse().whenComplete(hideOverlay) is pending strands the
/// framework menu in an open-but-invisible state after rapid context clicks.
class AppMenuAnchor extends StatefulWidget {
  const AppMenuAnchor(
      {super.key,
      required this.menuChildren,
      required this.builder,
      this.useRootOverlay = false,
      this.consumeOutsideTap = false,
      this.crossAxisUnconstrained = true,
      this.alignmentOffset = Offset.zero,
      this.reservedPadding = EdgeInsets.zero,
      this.style});
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final bool useRootOverlay, consumeOutsideTap, crossAxisUnconstrained;
  final Offset alignmentOffset;
  final EdgeInsetsGeometry reservedPadding;
  final MenuStyle? style;
  @override
  State<AppMenuAnchor> createState() => _AppMenuAnchorState();
}

class _AppMenuAnchorState extends State<AppMenuAnchor> {
  final _controller = _SerialMenuController();
  @override
  void dispose() {
    _controller.disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
      controller: _controller,
      useRootOverlay: widget.useRootOverlay,
      consumeOutsideTap: widget.consumeOutsideTap,
      crossAxisUnconstrained: widget.crossAxisUnconstrained,
      alignmentOffset: widget.alignmentOffset,
      reservedPadding: widget.reservedPadding,
      style: widget.style,
      menuChildren: widget.menuChildren,
      builder: widget.builder,
      onAnimationStatusChanged: (status) =>
          _controller.closing = status == AnimationStatus.reverse,
      onClose: _controller.closed);
}

class _SerialMenuController extends MenuController {
  bool disposed = false, closing = false, pending = false;
  Offset? position;
  @override
  void open({Offset? position}) {
    if (disposed) return;
    if (isOpen || closing) {
      pending = true;
      this.position = position;
      if (!closing) super.close();
      return;
    }
    super.open(position: position);
  }

  @override
  void close() {
    pending = false;
    super.close();
  }

  void closed() {
    closing = false;
    if (!pending) return;
    pending = false;
    final requested = position;
    scheduleMicrotask(() {
      if (!disposed) open(position: requested);
    });
  }
}
