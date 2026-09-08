import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';

/// Keep a readable text column when a row has several management actions.
/// Narrow windows and large text move those actions below the description.
class AppActionListTile extends StatelessWidget {
  const AppActionListTile(
      {super.key,
      required this.title,
      this.subtitle,
      this.leading,
      required this.actions,
      this.onTap});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final buttons = Wrap(spacing: 4, runSpacing: 4, children: actions);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: AppShape.control,
          leading: leading,
          title: Tooltip(
              message: title,
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
          subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Tooltip(
                          message: subtitle!,
                          child: Text(subtitle!,
                              maxLines: 3, overflow: TextOverflow.ellipsis))),
                if (stacked)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                          alignment: Alignment.centerRight, child: buttons)),
              ]),
          trailing: stacked ? null : buttons,
          onTap: onTap,
        );
      });
}
