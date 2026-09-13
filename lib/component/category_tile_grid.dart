import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/adaptive_grid_drag.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/category_labels.dart';
import 'package:dan_player/component/category_tile_layout.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class CategoryTileGrid extends StatefulWidget {
  const CategoryTileGrid(
      {super.key,
      required this.groups,
      required this.presentation,
      required this.onChanged,
      required this.onOpen,
      required this.covers,
      required this.changing,
      required this.onChangeCover,
      required this.onRemoveCover,
      required this.icon,
      this.persistLayout = true});
  final List<MusicCategoryGroup> groups;
  final CategoryPresentation presentation;
  final ValueChanged<CategoryPresentation> onChanged;
  final ValueChanged<MusicCategoryGroup> onOpen, onChangeCover, onRemoveCover;
  final CategoryCoverStore covers;
  final Set<String> changing;
  final IconData icon;
  final bool persistLayout;
  @override
  State<CategoryTileGrid> createState() => _CategoryTileGridState();
}

class _CategoryTileGridState extends State<CategoryTileGrid> {
  List<CategoryTilePlacement> _placements = [];
  List<String> _ids = [];
  List<CategoryTileSize> _sizes = [];
  int _columns = 0;
  bool? _fill;
  CategoryCoverShape? _shape;
  String? _dragging;
  bool _linear = false;
  int _layoutRevision = 0;
  Object? _projectionKey;
  Widget? _cachedSliver;

  @override
  void didUpdateWidget(CategoryTileGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reuse during scrolling, but refresh callbacks, cover revisions and busy
    // state whenever the parent supplies new widget configuration.
    _cachedSliver = null;
  }

  void _reorder(String source, String target) {
    if (source == target) return;
    final groups = widget.groups;
    final visible = groups.map((g) => g.persistenceKey).toList();
    final visibleIds = visible.toSet();
    if (!visibleIds.contains(source) || !visibleIds.contains(target)) return;
    // Replace only visible slots in the saved order; filtered-out groups keep
    // their relative position when a search is active.
    final previous = widget.presentation.orders[groups.first.kind.name] ?? [];
    final previousIds = previous.toSet();
    final all = <String>[
      ...previous,
      ...visible.where((id) => !previousIds.contains(id))
    ];
    visible.remove(source);
    visible.insert(visible.indexOf(target), source);
    var index = 0;
    final next = [
      for (final id in all)
        if (visibleIds.contains(id)) visible[index++] else id
    ];
    widget.onChanged(widget.presentation.copyWith(
        sort: CategorySort.custom,
        orders: {...widget.presentation.orders, groups.first.kind.name: next}));
  }

  @override
  Widget build(BuildContext context) =>
      SliverLayoutBuilder(builder: (context, constraints) {
        final projectionKey = (
          widget.groups,
          widget.presentation,
          constraints.crossAxisExtent,
          MediaQuery.textScalerOf(context).scale(14),
          widget.persistLayout,
          _dragging
        );
        if (_projectionKey == projectionKey && _cachedSliver != null)
          return _cachedSliver!;
        _projectionKey = projectionKey;
        const gap = 4.0;
        final p = widget.presentation;
        final metadataLines = 1 +
            (widget.groups.any((g) => g.subtitle != null) ? 1 : 0) +
            (widget.groups.any((g) => g.evidenceSummary.isNotEmpty) ? 1 : 0);
        final minimum = math.max(
            116.0,
            (p.showTitle
                    ? MediaQuery.textScalerOf(context).scale(14) * 2.6
                    : 0) +
                (p.showDetails
                    ? MediaQuery.textScalerOf(context).scale(12) *
                        1.3 *
                        metadataLines
                    : 0) +
                26);
        final columns = math.max(
            1, ((constraints.crossAxisExtent + gap) / minimum).floor());
        final unit =
            (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
        final circle = widget.presentation.shape == CategoryCoverShape.circle;
        final ids = widget.groups.map((g) => g.persistenceKey).toList();
        final sizes = widget.groups
            .map((g) => circle
                ? CategoryTileSize.small
                : widget.presentation.sizes[g.persistenceKey] ??
                    CategoryTileSize.small)
            .toList();
        final sameIds = ids.length == _ids.length &&
            List.generate(ids.length, (i) => ids[i] == _ids[i]).every((v) => v);
        final changed = sizes.length == _sizes.length
            ? sizes.indexed
                .where((e) => e.$2 != _sizes[e.$1])
                .map((e) => e.$1)
                .firstOrNull
            : null;
        if (!sameIds ||
            columns != _columns ||
            _shape != widget.presentation.shape ||
            _fill != widget.presentation.autoFill ||
            changed != null) {
          _linear = _fill != null && _fill != widget.presentation.autoFill;
          List<CategoryTilePlacement>? previous;
          if (sameIds &&
              columns == _columns &&
              _shape == widget.presentation.shape) {
            previous = _placements;
          } else if (_ids.isEmpty && !circle && widget.persistLayout) {
            previous = [
              for (var i = 0; i < ids.length; i++)
                if (widget.presentation.layouts[ids[i]] case final saved?
                    when saved[0] == columns && saved[1] < columns)
                  CategoryTilePlacement(
                      i, saved[1], saved[2], sizes[i].columns, sizes[i].rows)
            ];
          }
          _placements = packCategoryTiles(sizes, columns,
              fillGaps: widget.presentation.autoFill,
              previous: previous,
              resizedIndex: changed);
          _ids = ids;
          _sizes = sizes;
          _columns = columns;
          _fill = widget.presentation.autoFill;
          _shape = widget.presentation.shape;
          if (!circle && widget.persistLayout) {
            final revision = ++_layoutRevision;
            final positions = {
              for (final tile in _placements)
                ids[tile.index]: [columns, tile.column, tile.row]
            };
            if (positions.entries.any((entry) {
              final old = widget.presentation.layouts[entry.key];
              return old == null ||
                  old.length != 3 ||
                  List.generate(3, (i) => old[i] != entry.value[i])
                      .any((v) => v);
            })) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || revision != _layoutRevision) return;
                widget.onChanged(widget.presentation.copyWith(
                    layouts: {...widget.presentation.layouts, ...positions}));
              });
            }
          }
        }
        final line = MediaQuery.textScalerOf(context).scale(14) * 1.3;
        final rowHeight = circle
            ? unit +
                (p.showTitle || p.showDetails ? 4 : 0) +
                (p.showTitle ? line * 2 : 0) +
                (p.showDetails ? line * metadataLines : 0)
            : unit;
        final indexByKey = <Key, int>{
          for (var i = 0; i < _placements.length; i++)
            ValueKey(
                ('category-group', widget.groups[_placements[i].index].id)): i
        };
        return _cachedSliver = SliverGrid.builder(
            gridDelegate: CategoryTileGridDelegate(_placements, unit, gap,
                rowHeight: rowHeight),
            itemCount: _placements.length,
            findChildIndexCallback: (key) => indexByKey[key],
            itemBuilder: (context, index) {
              final tile = _placements[index];
              final group = widget.groups[tile.index];
              final rect = Rect.fromLTWH(
                  tile.column * (unit + gap),
                  tile.row * (rowHeight + gap),
                  tile.columns * (unit + gap) - gap,
                  tile.rows * (rowHeight + gap) - gap);
              return CategoryTileMotion(
                  key: ValueKey(('category-group', group.id)),
                  rect: rect,
                  scaleSize: false,
                  linear: _linear,
                  child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          widget.presentation.sort == CategorySort.custom &&
                          details.data != group.persistenceKey,
                      onAcceptWithDetails: (details) =>
                          _reorder(details.data, group.persistenceKey),
                      builder: (context, candidates, rejected) => DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    width: 2,
                                    color: candidates.isEmpty
                                        ? Colors.transparent
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary)),
                            position: DecorationPosition.foreground,
                            child: _CategoryTile(
                                key: ValueKey(('category-tile', group.id)),
                                group: group,
                                covers: widget.covers,
                                presentation: widget.presentation,
                                icon: widget.icon,
                                dragging: _dragging == group.persistenceKey,
                                onOpen: () => widget.onOpen(group),
                                onDragStarted: () => setState(
                                    () => _dragging = group.persistenceKey),
                                onDragEnd: () {
                                  if (mounted) setState(() => _dragging = null);
                                },
                                onSize: (size) => widget.onChanged(
                                        widget.presentation.copyWith(sizes: {
                                      ...widget.presentation.sizes,
                                      group.persistenceKey: size
                                    })),
                                onChangeCover: widget.changing
                                        .contains(group.persistenceKey)
                                    ? null
                                    : () => widget.onChangeCover(group),
                                onRemoveCover: widget.changing
                                        .contains(group.persistenceKey)
                                    ? null
                                    : () => widget.onRemoveCover(group)),
                          )));
            });
      });
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile(
      {super.key,
      required this.group,
      required this.covers,
      required this.presentation,
      required this.icon,
      required this.dragging,
      required this.onOpen,
      required this.onDragStarted,
      required this.onDragEnd,
      required this.onSize,
      this.onChangeCover,
      this.onRemoveCover});
  final MusicCategoryGroup group;
  final CategoryCoverStore covers;
  final CategoryPresentation presentation;
  final IconData icon;
  final bool dragging;
  final VoidCallback onOpen, onDragStarted, onDragEnd;
  final VoidCallback? onChangeCover, onRemoveCover;
  final ValueChanged<CategoryTileSize> onSize;
  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  Offset? _menuPosition;
  Object? _request;
  Future<ImageProvider?>? _artwork;
  @override
  void initState() {
    super.initState();
    CoverCache.instance.changes.addListener(_coverChanged);
  }

  void _coverChanged() {
    if (mounted) setState(() => _request = null);
  }

  @override
  void dispose() {
    CoverCache.instance.changes.removeListener(_coverChanged);
    super.dispose();
  }

  Future<ImageProvider?> _load(
      MusicCategoryGroup group, ArtworkSize target) async {
    ImageProvider? provider = await widget.covers.imageFor(group);
    if (provider != null && mounted) {
      provider = ArtworkImageProvider(provider, target,
          revision: widget.covers.coverIdFor(group));
      var failed = false;
      await precacheImage(provider, context, onError: (_, __) => failed = true);
      if (failed) provider = null;
    }
    provider ??= await group.coverAudio?.artworkForSize(target);
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final group = widget.group, p = widget.presentation;
    final circle = p.shape == CategoryCoverShape.circle;
    final scheme = Theme.of(context).colorScheme;
    final duration =
        appToolbarReduceMotion(context) ? Duration.zero : AppMotion.standard;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth, height = constraints.maxHeight;
      final target = ArtworkSize.forDisplay(
          logicalWidth: width,
          logicalHeight: circle ? width : height,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
      final audio = group.coverAudio;
      final source = (
        group.persistenceKey,
        widget.covers.coverIdFor(group),
        widget.covers.revision,
        audio?.path,
        audio?.modified,
        audio?.coverFingerprint,
        audio?.artworkUrl,
        audio == null
            ? 0
            : CoverCache.instance.generationFor(audio.localFilePath)
      );
      final aspect = circle ? 1.0 : width / height;
      final request = (source as Object, target, aspect);
      if (request != _request) {
        _request = request;
        _artwork = _load(group, target);
      }
      final placeholder = ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
              child: Icon(widget.icon,
                  size: width * .4, color: scheme.onSurfaceVariant)));
      Widget caption(CoverCaptionColors colors) => AnimatedContainer(
          duration: duration,
          color: circle ? Colors.transparent : colors.background,
          padding:
              EdgeInsets.symmetric(horizontal: 4, vertical: circle ? 0 : 5),
          child: AnimatedDefaultTextStyle(
              duration: duration,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: circle ? scheme.onSurface : colors.foreground),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (p.showTitle)
                  Text(categoryDisplayTitle(group),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, height: 1.3)),
                if (p.showDetails && group.subtitle != null)
                  Text(group.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.3)),
                if (p.showDetails && group.evidenceSummary.isNotEmpty)
                  Text(categoryEvidenceSummary(group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.3)),
                if (p.showDetails)
                  Text(
                      ui('{0} 首 · {1}',
                          [group.audios.length, categorySourceSummary(group)]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.3)),
              ])));
      Widget visual(ImageProvider? image) =>
          Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
            AnimatedPositioned(
                duration: duration,
                curve: AppMotion.standardCurve,
                left: 0,
                width: width,
                top: 0,
                height: circle ? width : height,
                child: AnimatedContainer(
                    key: ValueKey(('category-cover', group.id)),
                    duration: duration,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(circle ? width / 2 : 0)),
                    child: ArtworkHandoff(
                      artworkKey: _request!,
                      loadArtwork: () => _artwork!,
                      placeholder: placeholder,
                      imageBuilder: (image) => Image(
                          image: image,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => placeholder),
                    ))),
            AnimatedPositioned(
                duration: duration,
                curve: AppMotion.standardCurve,
                left: 0,
                width: width,
                top: circle ? width + 4 : height,
                child: AnimatedSlide(
                    duration: duration,
                    curve: AppMotion.standardCurve,
                    offset: circle ? Offset.zero : const Offset(0, -1),
                    child: FutureBuilder<CoverCaptionColors>(
                        initialData: image == null
                            ? null
                            : CoverCaptionCache.cached(image, aspect),
                        future: circle ||
                                image == null ||
                                (!p.showTitle && !p.showDetails)
                            ? null
                            : CoverCaptionCache.resolve(image, aspect),
                        builder: (context, snapshot) => caption(
                            snapshot.data ?? CoverCaptionColors.fallback)))),
          ]);
      final cover = RepaintBoundary(
          child: FutureBuilder<ImageProvider?>(
        future: _artwork,
        builder: (_, snapshot) => visual(snapshot.data),
      ));
      return AppMenuAnchor(
          useRootOverlay: true,
          consumeOutsideTap: true,
          menuChildren: [
            if (!circle)
              SubmenuButton(
                  leadingIcon: const Icon(Icons.photo_size_select_large),
                  menuChildren: [
                    for (final size in CategoryTileSize.values)
                      MenuItemButton(
                          key: ValueKey(('category-size', group.id, size.name)),
                          trailingIcon: (p.sizes[group.persistenceKey] ??
                                      CategoryTileSize.small) ==
                                  size
                              ? const Icon(Icons.check)
                              : null,
                          onPressed: () => widget.onSize(size),
                          child: Text(ui(switch (size) {
                            CategoryTileSize.small => '小 · 1×1',
                            CategoryTileSize.wide => '中 · 2×1',
                            CategoryTileSize.tall => '中 · 1×2',
                            CategoryTileSize.large => '大 · 2×2'
                          })))
                  ],
                  child: Text(ui('封面尺寸'))),
            if (group.kind == MusicCategoryKind.album)
              MenuItemButton(
                  onPressed: () => showCoverRepairDialog(context, group.audios,
                      album: group, covers: widget.covers),
                  leadingIcon: const Icon(Icons.refresh),
                  child: Text(ui('重新读取封面'))),
            MenuItemButton(
                key: ValueKey(('category-change-cover', group.id)),
                onPressed: widget.onChangeCover,
                leadingIcon: const Icon(Icons.image_outlined),
                child: Text(ui('更改歌单封面'))),
            if (widget.covers.hasCover(group))
              MenuItemButton(
                  key: ValueKey(('category-remove-cover', group.id)),
                  onPressed: widget.onRemoveCover,
                  leadingIcon: const Icon(Icons.hide_image_outlined),
                  child: Text(ui('移除自定义封面'))),
          ],
          builder: (anchorContext, controller, _) {
            final interaction = Material(
                key: ValueKey(('category-cover-menu', group.id)),
                color: Colors.transparent,
                child: AppItemInkWell(
                    key: ValueKey(('category-card', group.id)),
                    onTap: widget.onOpen,
                    onSecondaryTapDown: (details) =>
                        _menuPosition = details.localPosition,
                    onSecondaryTap: () =>
                        controller.open(position: _menuPosition),
                    onLongPress:
                        p.sort == CategorySort.custom ? null : controller.open,
                    child: const SizedBox.expand()));
            final card = AppEntrance(
              identity: ('category-tile', group.persistenceKey),
              translate: false,
              initialScale: .9,
              child: Opacity(
                  opacity: widget.dragging ? .35 : 1,
                  child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        cover,
                        CategoryPointerGlow(circle: circle, child: interaction),
                      ])),
            );
            return Tooltip(
                message:
                    '${categoryDisplayTitle(group)} · ${categorySourceSummary(group)}',
                child: AdaptiveGridDragSource<String>(
                    dragKey: ValueKey(('category-drag', group.id)),
                    data: group.persistenceKey,
                    maxSimultaneousDrags: p.sort == CategorySort.custom ? 1 : 0,
                    mouseHoldDelay: const Duration(milliseconds: 250),
                    mouseBounds: () {
                      final box =
                          anchorContext.findRenderObject()! as RenderBox;
                      return box.localToGlobal(Offset.zero) & box.size;
                    },
                    onMouseClick: widget.onOpen,
                    onDragStarted: () {
                      controller.close();
                      widget.onDragStarted();
                    },
                    onDragEnd: (_) => widget.onDragEnd(),
                    feedback: Material(
                        elevation: 8,
                        color: scheme.surfaceContainerHigh,
                        child: SizedBox(
                            width: width, height: height, child: cover)),
                    child: card));
          });
    });
  }
}
