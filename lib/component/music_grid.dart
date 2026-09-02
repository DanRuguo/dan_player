import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:desktop_lyric/ui_language.dart';

/// All song grids use the same compact presentation. List rows deliberately
/// keep their metadata and do not inherit this mode from another route.
class MusicGridScope extends InheritedWidget {
  const MusicGridScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MusicGridScope>() != null;

  @override
  bool updateShouldNotify(MusicGridScope oldWidget) => false;
}

typedef MusicGridDragSourceBuilder = Widget Function(
  BuildContext context,
  Object item,
  String label,
  Widget child,
);

/// Lets the page that owns a custom order turn only a grid card's identity
/// area into a drag source. The card keeps ownership of playback, selection,
/// right-click and its action button, so enabling reorder never replaces those
/// interactions with a second full-card gesture surface.
class MusicGridReorderScope extends InheritedWidget {
  const MusicGridReorderScope({
    super.key,
    required this.dragSourceBuilder,
    required super.child,
  });

  final MusicGridDragSourceBuilder dragSourceBuilder;

  static Widget wrap(
    BuildContext context, {
    required Object item,
    required String label,
    required Widget child,
  }) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MusicGridReorderScope>();
    return scope?.dragSourceBuilder(context, item, label, child) ?? child;
  }

  @override
  bool updateShouldNotify(MusicGridReorderScope oldWidget) =>
      dragSourceBuilder != oldWidget.dragSourceBuilder;
}

/// Logical-pixel grid geometry shared by library, detail and playlist views.
/// Width is never multiplied by DPR; only artwork decode targets use DPR.
class CompactMusicGridDelegate extends SliverGridDelegate {
  const CompactMusicGridDelegate({
    required this.mainAxisExtent,
    this.minimumTileWidth = 256,
    this.spacing = 8,
  })  : assert(mainAxisExtent > 0),
        assert(minimumTileWidth > 0),
        assert(spacing >= 0);

  factory CompactMusicGridDelegate.of(BuildContext context) =>
      CompactMusicGridDelegate(
        mainAxisExtent: math.max(64, musicGridLineHeight(context) * 2 + 16),
      );

  final double mainAxisExtent;
  final double minimumTileWidth;
  final double spacing;

  int columnCount(double width) =>
      math.max(1, ((width + spacing) / (minimumTileWidth + spacing)).floor());

  double offsetForIndex(int index, double width) =>
      (math.max(0, index) ~/ columnCount(width)) * (mainAxisExtent + spacing);

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final count = columnCount(constraints.crossAxisExtent);
    final width = math.max(
        0.0, (constraints.crossAxisExtent - spacing * (count - 1)) / count);
    return SliverGridRegularTileLayout(
      crossAxisCount: count,
      mainAxisStride: mainAxisExtent + spacing,
      crossAxisStride: width + spacing,
      childMainAxisExtent: mainAxisExtent,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CompactMusicGridDelegate oldDelegate) =>
      mainAxisExtent != oldDelegate.mainAxisExtent ||
      minimumTileWidth != oldDelegate.minimumTileWidth ||
      spacing != oldDelegate.spacing;
}

const musicGridTitleStyle = TextStyle(fontSize: 16, height: 1.25);

/// Measure a single shared line once per grid build, never each song/title.
/// Explicit height keeps the tile's two-line budget and its text in agreement
/// at accessibility scales, with the actual active font and text scaler.
double musicGridLineHeight(BuildContext context, {double fontSize = 16}) {
  final painter = TextPainter(
    text: TextSpan(
      text: ui("Ag国"),
      style: DefaultTextStyle.of(context).style.merge(
            TextStyle(fontSize: fontSize, height: 1.25),
          ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

/// Presentation only. The parent owns playback/navigation, selection, focus,
/// ink and menus, so compact grids cannot accidentally create a second player
/// or a competing drag recognizer. The 44px menu remains visible on touch.
class MusicGridTileBody extends StatelessWidget {
  const MusicGridTileBody({
    super.key,
    required this.artwork,
    required this.title,
    this.tooltip,
    this.color,
    this.leading,
    this.action,
    this.contentWrapper,
    this.padding = const EdgeInsets.all(8),
  });

  final Widget artwork;
  final String title;
  final String? tooltip;
  final Color? color;
  final Widget? leading;
  final Widget? action;
  final Widget Function(Widget child)? contentWrapper;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final content = Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: 8)],
      SizedBox.square(dimension: 48, child: artwork),
      const SizedBox(width: 12),
      Expanded(
        child: Tooltip(
          message: tooltip ?? title,
          // Keep mouse hover hints without entering the touch gesture arena;
          // the song card owns long-press context menus.
          triggerMode: TooltipTriggerMode.manual,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: musicGridTitleStyle.copyWith(color: color),
          ),
        ),
      ),
    ]);
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: contentWrapper?.call(content) ?? content),
        if (action != null) ...[const SizedBox(width: 4), action!],
      ]),
    );
  }
}
