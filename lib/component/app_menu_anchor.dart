import 'dart:async';
import 'package:flutter/material.dart';

/// Align a standard vertical submenu's bottom with its trigger. Material's
/// overflow fallback otherwise places its bottom at the trigger's top.
/// Desktop visual density shrinks the default 48 px menu rows to 40 px; use
/// the effective theme density for both panels instead of assuming 48 px.
Offset appSubmenuBottomOffset(BuildContext context, int itemCount,
    {int dividerCount = 0}) {
  final itemHeight =
      48.0 + Theme.of(context).visualDensity.baseSizeAdjustment.dy;
  final triggerHeight = itemHeight;
  const dividerHeight = 16.0;
  const panelPadding = 8.0;
  final panelHeight =
      itemCount * itemHeight + dividerCount * dividerHeight + panelPadding * 2;
  // SubmenuButton also subtracts its top padding from alignmentOffset.
  return Offset(0, triggerHeight + panelPadding - panelHeight);
}

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
      this.style,
      this.onClose});
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final bool useRootOverlay, consumeOutsideTap, crossAxisUnconstrained;
  final Offset alignmentOffset;
  final EdgeInsetsGeometry reservedPadding;
  final MenuStyle? style;
  final VoidCallback? onClose;
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
      onClose: () {
        _controller.closed();
        widget.onClose?.call();
      });
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
