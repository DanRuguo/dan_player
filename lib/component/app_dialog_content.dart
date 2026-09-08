import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A content-sized dialog viewport. The child uses a minimal Column and loose
/// Flexible / shrink-wrapped lists, so sparse content never reserves blank rows.
class AppDialogContent extends StatelessWidget {
  const AppDialogContent(
      {super.key,
      required this.width,
      this.maxHeight = 640,
      required this.child});
  final double width;
  final double maxHeight;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: math.min(maxHeight,
                  math.max(0, MediaQuery.sizeOf(context).height - 64))),
          child: child,
        ),
      );
}
