import 'dart:math' as math;

import 'package:dan_player/component/music_grid.dart';
import 'package:flutter/material.dart';

/// Share two static line measurements across the current grid build. This is
/// a transient layout budget, not a per-song cache or per-card text layout.
class PlaylistCircleGeometry {
  PlaylistCircleGeometry.measure(BuildContext context)
      : titleHeight = musicGridLineHeight(context) * 2,
        detailsHeight = musicGridLineHeight(context, fontSize: 13) * 2;

  final double titleHeight;
  final double detailsHeight;
  double get extent =>
      16 +
      PlaylistCircleTile.coverSize +
      8 +
      titleHeight +
      4 +
      detailsHeight +
      8 +
      48;
}

/// Portrait presentation only. The browser still owns navigation, playback,
/// drag/drop, selection, focus and menus for the original playlist entry.
class PlaylistCircleTile extends StatelessWidget {
  const PlaylistCircleTile({
    super.key,
    this.showTooltip = true,
    required this.entryId,
    required this.title,
    required this.details,
    required this.artworkBuilder,
    required this.actions,
    required this.geometry,
    this.contentWrapper,
  });

  static const coverSize = 112.0;
  static const minimumWidth = 208.0;

  final String entryId;
  final bool showTooltip;
  final String title;
  final String details;
  final Widget Function(double size) artworkBuilder;
  final Widget actions;
  final PlaylistCircleGeometry geometry;
  final Widget Function(Widget child)? contentWrapper;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, constraints) {
        final size = math.min(coverSize, math.max(0.0, constraints.maxWidth));
        final identity = Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: coverSize,
            child: Center(
                child: ClipOval(
              key: ValueKey('playlist-circle-cover-$entryId'),
              child: artworkBuilder(size),
            )),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: geometry.titleHeight,
            child: Align(
                alignment: Alignment.topCenter,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: musicGridTitleStyle.copyWith(
                      color: scheme.onSurface, fontWeight: FontWeight.w600),
                )),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: geometry.detailsHeight,
            child: Text(
              details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.25, color: scheme.onSurfaceVariant),
            ),
          ),
        ]);
        return Column(children: [
          contentWrapper?.call(TooltipVisibility(
                  visible: showTooltip,
                  child: Tooltip(
                      message: '$title\n$details',
                      triggerMode: TooltipTriggerMode.manual,
                      child: identity))) ??
              TooltipVisibility(
                  visible: showTooltip,
                  child: Tooltip(
                      message: '$title\n$details',
                      triggerMode: TooltipTriggerMode.manual,
                      child: identity)),
          const SizedBox(height: 8),
          SizedBox(height: 48, child: actions),
        ]);
      }),
    );
  }
}
