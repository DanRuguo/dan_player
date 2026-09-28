import 'package:flutter/material.dart';
import 'app_item_ink_well.dart';
import 'app_shape.dart';

/// Compact song cards and right-aligned folder summaries share the same cover.
class PlaylistTreeItem extends StatelessWidget {
  const PlaylistTreeItem(
      {super.key,
      required this.title,
      required this.metadata,
      required this.cover,
      required this.onTap,
      required this.onSecondaryTapDown,
      required this.onLongPress,
      this.time,
      this.shortMetadata,
      this.identityWrapper});
  final String title, metadata;
  final String? time;
  final String? shortMetadata;
  final Widget cover;
  final VoidCallback onTap, onLongPress;
  final GestureTapDownCallback onSecondaryTapDown;
  final Widget Function(Widget)? identityWrapper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    if (time != null) {
      return AppItemInkWell(
          borderRadius: AppShape.controlRadius,
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onLongPress: onLongPress,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                cover,
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Tooltip(
                          message: title,
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(color: color))),
                      const SizedBox(height: 4),
                      Tooltip(
                          message: metadata,
                          child: Text(metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: color))),
                    ])),
                const SizedBox(width: 8),
                Text(time!,
                    style: theme.textTheme.bodySmall?.copyWith(color: color)),
              ])));
    }
    return AppItemInkWell(
        borderRadius: AppShape.controlRadius,
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        onLongPress: onLongPress,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              Expanded(child: Builder(builder: (context) {
                final identity = Row(children: [
                  cover,
                  const SizedBox(width: 12),
                  Expanded(child: LayoutBuilder(builder: (context, bounds) {
                    final wide = bounds.maxWidth >=
                        MediaQuery.textScalerOf(context).scale(420);
                    final titleWidget = Tooltip(
                        message: title,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: color)));
                    final details = Tooltip(
                        message:
                            [metadata, if (time != null) time!].join(' · '),
                        child: Text(wide ? metadata : shortMetadata ?? metadata,
                            maxLines: wide ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: color)));
                    return wide
                        ? Row(children: [
                            Expanded(child: titleWidget),
                            const SizedBox(width: 16),
                            SizedBox(
                                width: bounds.maxWidth * .42, child: details),
                          ])
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                titleWidget,
                                const SizedBox(height: 4),
                                details,
                                if (time != null)
                                  Text(time!,
                                      textAlign: TextAlign.right,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: color)),
                              ]);
                  }))
                ]);
                return identityWrapper?.call(identity) ?? identity;
              })),
            ])));
  }
}
