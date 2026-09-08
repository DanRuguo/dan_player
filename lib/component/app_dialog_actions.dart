import 'package:flutter/material.dart';

/// Dialog footers share right alignment, including wrapped button rows.
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children,
        ),
      );
}
