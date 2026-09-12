import 'package:flutter/material.dart';

/// Convert the visible action into its row-wide menu's coordinate space.
/// Pointer menus can continue to supply their own local position.
void toggleMenuAtAction(MenuController controller, BuildContext anchorContext,
    BuildContext actionContext) {
  if (controller.isOpen) {
    controller.close();
    return;
  }
  final anchor = anchorContext.findRenderObject();
  final action = actionContext.findRenderObject();
  if (anchor is RenderBox &&
      action is RenderBox &&
      anchor.attached &&
      action.attached &&
      anchor.hasSize &&
      action.hasSize) {
    controller.open(
        position: anchor.globalToLocal(action
            .localToGlobal(Offset(action.size.width / 2, action.size.height))));
  } else {
    controller.open();
  }
}
