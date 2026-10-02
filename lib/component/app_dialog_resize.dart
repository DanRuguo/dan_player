import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';

/// Place inside a dialog surface, around its content or minimal child column.
/// The surface then follows the measured content instead of jumping in size.
class AppDialogResize extends StatefulWidget {
  const AppDialogResize({super.key, required this.child});
  final Widget child;

  @override
  State<AppDialogResize> createState() => _AppDialogResizeState();
}

class _AppDialogResizeState extends State<AppDialogResize>
    with WidgetsBindingObserver {
  final _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduced = appToolbarReduceMotion(context, kind: MotionKind.layout);
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    // No clock in the static path. A zero-duration RenderAnimatedSize can
    // notify synchronously during layout; removing it also stops an ongoing
    // resize immediately while retaining form state/focus in this subtree.
    if (reduced) return content;
    return AnimatedSize(
      duration: AppMotion.standard,
      reverseDuration: AppMotion.standard,
      curve: AppMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
