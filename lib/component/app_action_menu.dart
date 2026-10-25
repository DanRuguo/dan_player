import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'app_menu_anchor.dart';
import 'app_shape.dart';

/// An action in a lazily captured menu. A null entry is a separator; an entry
/// without a value is informational and never takes keyboard focus.
class AppActionMenuItem<T> {
  const AppActionMenuItem({
    required this.child,
    this.value,
    this.key,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Widget child;
  final T? value;
  final Key? key;
  final bool enabled;
  final EdgeInsetsGeometry padding;
}

/// Keeps action-menu snapshots and focus local to the trigger while delegating
/// layout, keyboard navigation, dismissal and the surface to AppMenuAnchor.
class AppActionMenu<T> extends StatefulWidget {
  const AppActionMenu({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    required this.builder,
    required this.semanticLabel,
    this.enabled = true,
    this.canOpen,
    this.width = 280,
    this.widthBuilder,
    this.maxHeight = double.infinity,
    this.alignment = AlignmentDirectional.bottomStart,
    this.alignmentOffset = const Offset(0, 6),
  });

  final List<AppActionMenuItem<T>?> Function(BuildContext) itemBuilder;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext, VoidCallback?, FocusNode, bool) builder;
  final String semanticLabel;
  final bool enabled;
  final bool Function()? canOpen;
  final double width, maxHeight;
  final double Function(BuildContext)? widthBuilder;
  final AlignmentGeometry alignment;
  final Offset alignmentOffset;

  @override
  State<AppActionMenu<T>> createState() => _AppActionMenuState<T>();
}

class _AppActionMenuState<T> extends State<AppActionMenu<T>> {
  final _focus = FocusNode();
  List<AppActionMenuItem<T>?> _items = const [];
  MenuController? _controller;
  bool _open = false;
  double? _requestedWidth;
  int _request = 0;

  bool get _available => widget.enabled && (widget.canOpen?.call() ?? true);

  void _show(MenuController controller) {
    if (_open || !_available) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final width = widget.widthBuilder?.call(context) ?? widget.width;
    final request = ++_request;
    setState(() {
      _items = items;
      _requestedWidth = width;
      _open = true;
    });
    // The new snapshot must be mounted before the framework opens its overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _request) return;
      if (!_available) {
        setState(() => _open = false);
        return;
      }
      try {
        controller.open();
      } catch (_) {
        if (mounted) setState(() => _open = false);
        rethrow;
      }
    });
  }

  @override
  void didUpdateWidget(AppActionMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open && !widget.enabled) {
      final request = ++_request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != _request) return;
        _controller?.close();
        if (_open) setState(() => _open = false);
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.max(
        44.0, math.min(_requestedWidth ?? widget.width, size.width - 32));
    final height = math.max(48.0, math.min(widget.maxHeight, size.height - 32));
    final scheme = Theme.of(context).colorScheme;
    final popupTheme = PopupMenuTheme.of(context);
    final request = _request;
    var focusAssigned = false;
    final children = <Widget>[];
    for (final item in _items) {
      if (item == null) {
        children.add(const Divider(height: 10));
        continue;
      }
      final value = item.value;
      final enabled = item.enabled && value != null;
      final autofocus = enabled && !focusAssigned;
      focusAssigned |= enabled;
      children.add(MenuItemButton(
        key: item.key,
        autofocus: autofocus,
        onPressed: enabled
            ? () {
                if (mounted && request == _request && _available) {
                  widget.onSelected(value);
                }
              }
            : null,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: WidgetStatePropertyAll(item.padding),
          textStyle: WidgetStateProperty.resolveWith((states) =>
              popupTheme.labelTextStyle?.resolve(states) ??
              popupTheme.textStyle ??
              Theme.of(context).textTheme.labelLarge),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: item.child,
      ));
    }
    return AppMenuAnchor(
      childFocusNode: _focus,
      consumeOutsideTap: true,
      reservedPadding: const EdgeInsets.all(16),
      alignmentOffset: widget.alignmentOffset,
      style: MenuStyle(
        alignment: widget.alignment,
        shape: const WidgetStatePropertyAll(AppShape.control),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor:
            WidgetStatePropertyAll(scheme.shadow.withValues(alpha: .18)),
        elevation: const WidgetStatePropertyAll(4),
        padding:
            const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, height)),
      ),
      menuChildren: _items.isEmpty
          ? const []
          : [
              SizedBox(
                width: width,
                child: Semantics(
                  role: SemanticsRole.menu,
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: widget.semanticLabel,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
      onClose: () {
        if (mounted && _open) setState(() => _open = false);
      },
      builder: (context, controller, _) {
        _controller = controller;
        // Trigger ink and its arrow animate independently of the menu. Keep
        // their paint invalidations local instead of repainting the page below
        // the live backdrop filter; the overlay remains outside this boundary.
        return RepaintBoundary(
          child: widget.builder(context,
              widget.enabled ? () => _show(controller) : null, _focus, _open),
        );
      },
    );
  }
}
