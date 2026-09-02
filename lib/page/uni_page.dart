import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/adaptive_grid_drag.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef ContentBuilder<T> = Widget Function(BuildContext context, T item,
    int index, MultiSelectController<T>? multiSelectController);

typedef SortMethod<T> = void Function(List<T> list, SortOrder order);
typedef ReorderCallback<T> = FutureOr<void> Function(List<T> list);

class SortMethodDesc<T> {
  IconData icon;
  String name;
  SortMethod<T> method;
  bool usesSortOrder;
  bool supportsReorder;
  ReorderCallback<T>? onReorder;

  SortMethodDesc({
    required this.icon,
    required this.name,
    required this.method,
    this.usesSortOrder = true,
    this.supportsReorder = false,
    this.onReorder,
  });
}

enum SortOrder {
  ascending,
  decending;

  static SortOrder? fromString(String sortOrder) {
    for (var value in SortOrder.values) {
      if (value.name == sortOrder) return value;
    }
    return null;
  }
}

enum ContentView {
  list,
  table;

  static ContentView? fromString(String contentView) {
    for (var value in ContentView.values) {
      if (value.name == contentView) return value;
    }
    return null;
  }
}

class MultiSelectController<T> extends ChangeNotifier {
  final Set<T> selected = {};
  bool enableMultiSelectView = false;

  void useMultiSelectView(bool multiSelectView) {
    enableMultiSelectView = multiSelectView;
    notifyListeners();
  }

  void select(T item) {
    selected.add(item);
    notifyListeners();
  }

  void unselect(T item) {
    selected.remove(item);
    notifyListeners();
  }

  void clear() {
    selected.clear();
    notifyListeners();
  }

  void selectAll(Iterable<T> items) {
    selected.addAll(items);
    notifyListeners();
  }

  void replaceSelection(Iterable<T> items) {
    final replacement = items.toSet();
    if (selected.length == replacement.length &&
        selected.containsAll(replacement)) {
      return;
    }
    selected
      ..clear()
      ..addAll(replacement);
    notifyListeners();
  }
}

/// `AudiosPage`, `ArtistsPage`, `AlbumsPage`, `FoldersPage`, `FolderDetailPage` 页面的主要组件，
/// 提供随机播放以及更改排序方式、排序顺序、内容视图的支持。
///
/// `enableShufflePlay` 只能在 `T` 是 `Audio` 时为 `ture`
///
/// `enableSortMethod` 为 `true` 时，`sortMethods` 不可为空且必须包含一个 `SortMethodDesc`
///
/// `defaultContentView` 表示默认的内容视图。如果设置为 `ContentView.list`，就以单行列表视图展示内容；
/// Compact grids share logical-pixel column geometry and grow their two-line
/// title budget with accessibility text scaling.
///
/// `multiSelectController` 可以使页面进入多选状态。如果它不为空，则 `multiSelectViewActions` 也不可为空
class UniPage<T> extends StatefulWidget {
  const UniPage({
    super.key,
    required this.pref,
    required this.title,
    this.subtitle,
    required this.contentList,
    required this.contentBuilder,
    this.primaryAction,
    required this.enableShufflePlay,
    required this.enableSortMethod,
    required this.enableSortOrder,
    required this.enableContentViewSwitch,
    this.sortMethods,
    this.locateTo,
    this.multiSelectController,
    this.multiSelectViewActions,
    this.enableAudioColumns = false,
    this.listItemExtent,
    this.gridDelegate,
  });

  final PagePreference pref;

  final String title;
  final String? subtitle;

  final List<T> contentList;
  final ContentBuilder<T> contentBuilder;

  final Widget? primaryAction;

  final bool enableShufflePlay;
  final bool enableSortMethod;
  final bool enableSortOrder;
  final bool enableContentViewSwitch;

  final List<SortMethodDesc<T>>? sortMethods;

  final T? locateTo;

  final MultiSelectController<T>? multiSelectController;
  final List<Widget>? multiSelectViewActions;
  final bool enableAudioColumns;
  final double? listItemExtent;
  final CompactMusicGridDelegate? gridDelegate;

  @override
  State<UniPage<T>> createState() => _UniPageState<T>();
}

class _UniPageState<T> extends State<UniPage<T>> {
  late SortMethodDesc<T>? currSortMethod = _preferredSortMethod();
  late SortOrder currSortOrder = widget.pref.sortOrder;
  late ContentView currContentView = widget.pref.contentView;
  late ScrollController scrollController = ScrollController();
  final _gridKey = GlobalKey();
  final _contentKey = GlobalKey();
  int _locateGeneration = 0;

  SortMethodDesc<T>? _preferredSortMethod() {
    final methods = widget.sortMethods;
    if (methods == null || methods.isEmpty) return null;
    final index = widget.pref.sortMethod;
    return methods[index >= 0 && index < methods.length ? index : 0];
  }

  @override
  void dispose() {
    _locateGeneration++;
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    currSortMethod?.method(widget.contentList, currSortOrder);
    if (widget.locateTo == null) return;
    _scheduleLocate(_locateGeneration);
  }

  // A large-text list can mix two/three-line classic rows, while columns use
  // one line. Only mounted sliver children can tell us their actual extents.
  // Seek using those measurements, then reveal the target's exact layout
  // offset. No offstage copy, artwork request or per-library height cache.
  void _scheduleLocate(int generation, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _locateGeneration ||
          !scrollController.hasClients ||
          widget.locateTo == null) {
        return;
      }
      final targetAt = widget.contentList.indexOf(widget.locateTo as T);
      if (targetAt < 0) return;
      if (currContentView == ContentView.table) {
        final grid = _gridKey.currentWidget;
        final box = _gridKey.currentContext?.findRenderObject();
        if (grid is GridView &&
            grid.gridDelegate is CompactMusicGridDelegate &&
            box is RenderBox) {
          _jumpTo((grid.gridDelegate as CompactMusicGridDelegate)
              .offsetForIndex(targetAt, box.size.width));
        }
        return;
      }

      final sliver = _contentSliver();
      if (sliver == null) return;
      RenderBox? nearest;
      var distance = double.infinity;
      var totalHeight = 0.0;
      var count = 0;
      for (var child = sliver.firstChild;
          child != null;
          child = sliver.childAfter(child)) {
        final index = sliver.indexOf(child);
        if (index == targetAt) {
          _jumpTo(RenderAbstractViewport.of(child)
              .getOffsetToReveal(child, 0)
              .offset);
          return;
        }
        if ((index - targetAt).abs() < distance) {
          nearest = child;
          distance = (index - targetAt).abs().toDouble();
        }
        totalHeight += child.size.height;
        count++;
      }
      if (nearest == null || count == 0 || totalHeight <= 0) return;
      final anchorOffset = RenderAbstractViewport.of(nearest)
          .getOffsetToReveal(nearest, 0)
          .offset;
      final offset = anchorOffset +
          (targetAt - sliver.indexOf(nearest)) * totalHeight / count;
      final previousOffset = scrollController.offset;
      _jumpTo(offset);
      // The next layout supplies new real indices, not just a pixel estimate.
      // A finite seek also prevents an unusual zero-height/custom child or an
      // external controller mutation from scheduling frames indefinitely.
      if (attempt < 31 && scrollController.offset != previousOffset) {
        _scheduleLocate(generation, attempt + 1);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _jumpTo(double offset) => scrollController.jumpTo(offset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent));

  RenderSliverMultiBoxAdaptor? _contentSliver() {
    RenderSliverMultiBoxAdaptor? result;
    void visit(RenderObject child) {
      if (child is RenderSliverMultiBoxAdaptor) {
        result = child;
      } else if (result == null) {
        child.visitChildren(visit);
      }
    }

    final root = _contentKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  @override
  void didUpdateWidget(covariant UniPage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    currSortMethod = _preferredSortMethod();
    currSortMethod?.method(widget.contentList, currSortOrder);
  }

  void setSortMethod(SortMethodDesc<T> sortMethod) {
    final index = widget.sortMethods?.indexOf(sortMethod) ?? -1;
    if (index < 0) return;
    _locateGeneration++;
    setState(() {
      currSortMethod = sortMethod;
      widget.pref.sortMethod = index;
      currSortMethod?.method(widget.contentList, currSortOrder);
    });
  }

  void setSortOrder(SortOrder sortOrder) {
    _locateGeneration++;
    setState(() {
      currSortOrder = sortOrder;
      widget.pref.sortOrder = sortOrder;
      currSortMethod?.method(widget.contentList, currSortOrder);
    });
  }

  void setContentView(ContentView contentView) {
    _locateGeneration++;
    setState(() {
      currContentView = contentView;
      widget.pref.contentView = contentView;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = [];
    if (widget.primaryAction != null) {
      actions.add(widget.primaryAction!);
    }
    if (widget.enableShufflePlay) {
      actions.add(ShufflePlay<T>(contentList: widget.contentList));
    }
    if (widget.enableSortMethod && currSortMethod != null) {
      actions.add(SortMethodComboBox<T>(
        sortMethods: widget.sortMethods!,
        contentList: widget.contentList,
        currSortMethod: currSortMethod!,
        setSortMethod: setSortMethod,
        sortOrder: widget.enableSortOrder && currSortMethod!.usesSortOrder
            ? currSortOrder
            : null,
        setSortOrder: setSortOrder,
        scopeId: ('uni', widget.title),
      ));
    } else if (widget.enableSortOrder) {
      actions.add(SortOrderSwitch<T>(
        sortOrder: currSortOrder,
        setSortOrder: setSortOrder,
      ));
    }
    if (widget.enableContentViewSwitch) {
      actions.add(ContentViewSwitch<T>(
        contentView: currContentView,
        setContentView: setContentView,
      ));
    }

    return widget.multiSelectController == null
        ? result(null, actions)
        : ListenableBuilder(
            listenable: widget.multiSelectController!,
            builder: (context, _) => result(
              widget.multiSelectController!,
              actions,
            ),
          );
  }

  Widget result(
      MultiSelectController<T>? multiSelectController, List<Widget> actions) {
    final enableReorder = currSortMethod?.supportsReorder == true &&
        multiSelectController?.enableMultiSelectView != true;
    final visibleActions = multiSelectController?.enableMultiSelectView == true
        ? widget.multiSelectViewActions!
        : actions;
    final gridIndices = currContentView == ContentView.table
        ? <Key, int>{
            for (var i = 0; i < widget.contentList.length; i++)
              ValueKey(widget.contentList[i]): i,
          }
        : const <Key, int>{};
    return PageScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: visibleActions,
      // Expanded two-choice selectors need the real toolbar width, not an
      // unbounded legacy Row. The common scaffold wraps without shrinking text.
      responsiveActions: visibleActions.isNotEmpty
          ? Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: visibleActions,
            )
          : null,
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction != ScrollDirection.idle) {
            _locateGeneration++;
          }
          return false;
        },
        child: Material(
          type: MaterialType.transparency,
          child: AppContentScrollbar(
            controller: scrollController,
            builder: (context, scrollController) => LayoutBuilder(
              builder: (context, constraints) {
                final columns = widget.enableAudioColumns &&
                    currContentView == ContentView.list &&
                    UiLayoutScope.of(context).libraryRowLayout ==
                        LibraryRowLayout.columns &&
                    AudioColumnsScope.fits(context,
                        constraints.maxWidth - (enableReorder ? 44 : 0));
                return AudioColumnsScope(
                    enabled: columns,
                    child: Column(children: [
                      if (columns) AudioColumnsHeader(reorder: enableReorder),
                      Expanded(
                          // List/reorder widgets own different ScrollPositions.
                          // A stable, page-local storage identity also preserves
                          // the offset when multi-selection replaces one with
                          // the other; the controller alone cannot do that.
                          child: KeyedSubtree(
                              key: PageStorageKey(scrollController),
                              child: KeyedSubtree(
                                  key: _contentKey,
                                  child: switch (currContentView) {
                                    ContentView.list => enableReorder
                                        ? ReorderableListView.builder(
                                            scrollController: scrollController,
                                            padding: EdgeInsets.only(
                                                bottom: NowPlayingBarMetrics
                                                    .reservedSpace(context)),
                                            itemCount:
                                                widget.contentList.length,
                                            itemExtent:
                                                _fixedRowExtent(context),
                                            buildDefaultDragHandles: true,
                                            onReorderItem:
                                                (oldIndex, newIndex) {
                                              setState(() {
                                                final item = widget.contentList
                                                    .removeAt(oldIndex);
                                                widget.contentList
                                                    .insert(newIndex, item);
                                              });
                                              currSortMethod?.onReorder
                                                  ?.call(widget.contentList);
                                            },
                                            itemBuilder: (context, i) =>
                                                KeyedSubtree(
                                              key: ValueKey(
                                                  widget.contentList[i]),
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 44.0),
                                                child: _content(context, i,
                                                    multiSelectController),
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            controller: scrollController,
                                            padding: EdgeInsets.only(
                                                bottom: NowPlayingBarMetrics
                                                    .reservedSpace(context)),
                                            itemCount:
                                                widget.contentList.length,
                                            itemExtent:
                                                _fixedRowExtent(context),
                                            itemBuilder: (context, i) =>
                                                _content(context, i,
                                                    multiSelectController),
                                          ),
                                    ContentView.table => MusicGridScope(
                                        child: MusicGridReorderScope(
                                          dragSourceBuilder:
                                              (context, item, label, child) =>
                                                  enableReorder
                                                      ? _gridDragSource(
                                                          context,
                                                          item as T,
                                                          label,
                                                          child,
                                                        )
                                                      : child,
                                          child: GridEdgeAutoScrollRegion(
                                            controller: scrollController,
                                            child: GridView.builder(
                                              key: _gridKey,
                                              controller: scrollController,
                                              padding: EdgeInsets.only(
                                                  bottom: NowPlayingBarMetrics
                                                      .reservedSpace(context)),
                                              gridDelegate: widget
                                                      .gridDelegate ??
                                                  CompactMusicGridDelegate.of(
                                                      context),
                                              itemCount:
                                                  widget.contentList.length,
                                              findChildIndexCallback: (key) =>
                                                  gridIndices[key],
                                              itemBuilder: (context, i) =>
                                                  enableReorder
                                                      ? _gridDropTarget(
                                                          widget.contentList[i],
                                                          _content(context, i,
                                                              multiSelectController),
                                                        )
                                                      : _content(context, i,
                                                          multiSelectController),
                                            ),
                                          ),
                                        ),
                                      ),
                                  }))),
                    ]));
              },
            ),
          ),
        ),
      ),
    );
  }

  // Large text can add a duration/status line on narrow song rows. Let the
  // actual child measure that layout rather than clipping it to two estimated
  // lines. Folder cards supply their own measured fixed extent.
  double? _fixedRowExtent(BuildContext context) =>
      widget.listItemExtent ??
      (MediaQuery.textScalerOf(context).scale(14) > 14 ? null : 64.0);

  int _identityIndex(T item) {
    final identity = widget.contentList
        .indexWhere((candidate) => identical(candidate, item));
    return identity >= 0 ? identity : widget.contentList.indexOf(item);
  }

  void _reorderGrid(_UniGridDrag<T> data, T target) {
    final oldIndex = _identityIndex(data.item);
    final targetIndex = _identityIndex(target);
    if (oldIndex < 0 || targetIndex < 0 || oldIndex == targetIndex) return;
    setState(() {
      final item = widget.contentList.removeAt(oldIndex);
      widget.contentList.insert(targetIndex, item);
    });
    currSortMethod?.onReorder?.call(widget.contentList);
  }

  Widget _gridDragSource(
      BuildContext context, T item, String label, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return AdaptiveGridDragSource<_UniGridDrag<T>>(
      dragKey: ValueKey(('uni-grid-drag', item)),
      data: _UniGridDrag(item),
      feedback: Material(
        elevation: 8,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.primary, width: 1.5),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.drag_indicator, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: child),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
  }

  Widget _gridDropTarget(T target, Widget child) => DragTarget<_UniGridDrag<T>>(
        key: ValueKey(target),
        onWillAcceptWithDetails: (details) =>
            _identityIndex(details.data.item) >= 0 &&
            !identical(details.data.item, target),
        onAcceptWithDetails: (details) => _reorderGrid(details.data, target),
        builder: (context, candidates, rejected) => Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (candidates.isNotEmpty || rejected.isNotEmpty)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: candidates.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _content(BuildContext context, int index,
      MultiSelectController<T>? multiSelectController) {
    final item = widget.contentList[index];
    return AppEntrance(
      key: ValueKey(item),
      identity: ('uni-item', item),
      order: index,
      child: widget.contentBuilder(context, item, index, multiSelectController),
    );
  }
}

class _UniGridDrag<T> {
  const _UniGridDrag(this.item);

  final T item;
}
