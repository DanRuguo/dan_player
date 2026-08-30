import 'package:flutter/material.dart';

/// Centers only a dialog's heading; form/list alignment remains independent.
/// Optional actions occupy balanced slots so a close button or switch does not
/// pull the title away from the dialog center. No fixed text height or color.
class AppDialogTitle extends StatelessWidget {
  const AppDialogTitle(
    this.title, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.leading,
    this.trailing,
    this.subtitle,
    this.sideExtent = 48,
  });

  final String title;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Widget? leading;
  final Widget? trailing;
  final Widget? subtitle;
  final double sideExtent;

  @override
  Widget build(BuildContext context) {
    final text = Text(title,
        textAlign: TextAlign.center,
        style: style,
        maxLines: maxLines,
        overflow: overflow);
    final content = subtitle == null
        ? text
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [text, subtitle!],
          );
    if (leading == null && trailing == null) {
      return Align(alignment: Alignment.center, child: content);
    }
    return Row(
      children: [
        SizedBox(width: sideExtent, child: Center(child: leading)),
        Expanded(child: content),
        SizedBox(width: sideExtent, child: Center(child: trailing)),
      ],
    );
  }
}
