import 'package:flutter/material.dart';

import 'app_item_ink_well.dart';
import 'app_shape.dart';

const playlistTreeFolderArtworkGrowth = 4.0;

/// Cover-only tree tile. The title remains available on hover and to screen
/// readers without consuming the horizontal space reserved for direct songs.
class PlaylistTreeItem extends StatelessWidget {
  const PlaylistTreeItem({
    super.key,
    required this.title,
    required this.cover,
    required this.coverSize,
    required this.playlist,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onLongPress,
    this.selected = false,
    this.identityWrapper,
  });

  final String title;
  final Widget cover;
  final double coverSize;
  final bool playlist;
  final bool selected;
  final VoidCallback onTap, onLongPress;
  final GestureTapDownCallback onSecondaryTapDown;
  final Widget Function(Widget)? identityWrapper;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = playlist ? 4.0 : 3.0;
    final radius = playlist ? AppShape.controlRadius : AppShape.smallRadius;
    final identity = SizedBox.square(
      dimension: coverSize + (playlist ? playlistTreeFolderArtworkGrowth : 0),
      child: cover,
    );
    return SizedBox.square(
      dimension: coverSize + (playlist ? 12 : inset * 2),
      child: Semantics(
        label: title,
        button: true,
        selected: selected,
        child: Tooltip(
          message: title,
          child: Material(
            color: playlist
                ? Color.lerp(
                    scheme.surfaceContainerHigh, scheme.primaryContainer, .3)
                : scheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: selected ? 2 : 0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppItemInkWell(
              borderRadius: radius,
              onTap: onTap,
              onSecondaryTapDown: onSecondaryTapDown,
              onLongPress: onLongPress,
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: identityWrapper?.call(identity) ?? identity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
