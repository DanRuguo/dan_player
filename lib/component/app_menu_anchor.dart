import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keep a cascading menu attached to its button's bottom using the items that
/// have just been laid out, including wrapped labels and custom row heights.
/// Material still owns focus, hover, scrolling, animation and screen fitting.
class AppSubmenuButton extends StatefulWidget {
  const AppSubmenuButton({
    super.key,
    required this.menuChildren,
    required this.child,
    this.leadingIcon,
    this.trailingIcon,
    this.menuStyle,
    this.style,
    this.controller,
    this.focusNode,
    this.onOpen,
    this.onClose,
    this.useRootOverlay = false,
  });

  final List<Widget> menuChildren;
  final Widget child;
  final Widget? leadingIcon, trailingIcon;
  final MenuStyle? menuStyle;
  final ButtonStyle? style;
  final MenuController? controller;
  final FocusNode? focusNode;
  final VoidCallback? onOpen, onClose;
  final bool useRootOverlay;

  @override
  State<AppSubmenuButton> createState() => _AppSubmenuButtonState();
}

class _AppSubmenuButtonState extends State<AppSubmenuButton> {
  RenderBox? _panel;

  double _panelHeight() {
    if (_panel?.attached != true) {
      // OverlayPortal keeps its overlay in the anchor's element subtree.
      // Locate this menu's layout child once per opening; keep the original
      // items and keys intact for keyboard traversal and callers.
      void visit(Element element) {
        if (_panel != null && _panel!.attached) return;
        if (widget.menuChildren.isNotEmpty &&
            identical(element.widget, widget.menuChildren.first)) {
          RenderObject? object = element.findRenderObject();
          while (object != null) {
            final parent = object.parent;
            if (parent is RenderCustomSingleChildLayoutBox) {
              _panel = parent.child;
              return;
            }
            object = parent;
          }
        }
        element.visitChildren(visit);
      }

      _panel = null;
      context.visitChildElements(visit);
    }
    // The alignment callback runs inside this panel's immediate parent's
    // layout, which laid it out with parentUsesSize. Reading that direct child
    // is valid; reading individual descendant sizes here would not be.
    return _panel?.hasSize == true ? _panel!.size.height : 0;
  }

  @override
  Widget build(BuildContext context) {
    final menuStyle = widget.menuStyle ?? const MenuStyle();
    final padding = (menuStyle.padding?.resolve(const {}) ??
            MenuTheme.of(context).style?.padding?.resolve(const {}) ??
            const EdgeInsets.symmetric(vertical: 8))
        .resolve(Directionality.of(context));
    return SubmenuButton(
      leadingIcon: widget.leadingIcon,
      trailingIcon: widget.trailingIcon,
      style: widget.style,
      controller: widget.controller,
      focusNode: widget.focusNode,
      onOpen: widget.onOpen,
      onClose: widget.onClose,
      useRootOverlay: widget.useRootOverlay,
      // Preserve the application's existing instant cascading menus; the
      // containing MenuAnchor retains its own entrance/exit animation.
      menuStyle: menuStyle.copyWith(
        padding: WidgetStatePropertyAll(padding),
        alignment: _SubmenuBottomAlignment(_panelHeight, padding.top),
      ),
      menuChildren: widget.menuChildren,
      child: widget.child,
    );
  }
}

/// Menu alignment is resolved after its children are laid out. Reading their
/// sizes here corrects the first frame without a hidden measurement pass,
/// a post-frame rebuild or a second menu animation.
class _SubmenuBottomAlignment extends AlignmentDirectional {
  const _SubmenuBottomAlignment(this.height, this.topPadding) : super(1, 1);
  final double Function() height;
  final double topPadding;

  @override
  Alignment resolve(TextDirection? direction) => _SubmenuResolvedAlignment(
      direction == TextDirection.rtl ? -1 : 1, height, topPadding);

  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}

class _SubmenuResolvedAlignment extends Alignment {
  const _SubmenuResolvedAlignment(double x, this.height, this.topPadding)
      : super(x, 1);
  final double Function() height;
  final double topPadding;

  @override
  Offset withinRect(Rect rect) => Offset(
      x < 0 ? rect.left : rect.right, rect.bottom - height() + topPadding);
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
