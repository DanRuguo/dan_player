import 'dart:ui';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef DetailContentBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  int index,
  List<T> visibleContent,
  MultiSelectController<T>? multiSelectController,
);

/// `ArtistDetailPage`, `AlbumDetailPage` 页面的主要组件。
///
/// `P`: 第一内容；`S`: 第二内容（主要）；`T`: 第三内容
///
/// 例如：对于 `ArtistDetailPage` 来说，
/// `P` 是 `Artist` 类，`S` 是 `Audio` 类，`T` 是 `Album` 类
///
/// `multiSelectController` 可以使页面进入多选状态。如果它不为空，则 `multiSelectViewActions` 也不可为空
class UniDetailPage<P, S, T> extends StatefulWidget {
  const UniDetailPage({
    super.key,
    required this.pref,
    required this.primaryContent,
    required this.primaryPic,
    required this.backgroundPic,
    required this.picShape,
    required this.title,
    required this.subtitle,
    required this.secondaryContent,
    required this.secondaryContentBuilder,
    required this.tertiaryContentTitle,
    required this.tertiaryContent,
    required this.tertiaryContentBuilder,
    this.enablePlayAll = false,
    required this.enableShufflePlay,
    this.enableAddAllToPlaylist = false,
    required this.enableSortMethod,
    required this.enableSortOrder,
    required this.enableSecondaryContentViewSwitch,
    this.sortMethods,
    this.secondaryContentSearchText,
    this.secondaryContentSearchHint,
    this.multiSelectController,
    this.multiSelectViewActions,
    this.enableMultiSelectAddToPlaylist = false,
  }) : assert(!enableMultiSelectAddToPlaylist || multiSelectController != null);

  final PagePreference pref;

  final P primaryContent;

  /// 用来展示内容图片，较高清
  final Future<ImageProvider?> primaryPic;

  /// 当作毛玻璃的背景，较模糊
  final Future<ImageProvider?> backgroundPic;

  final PicShape picShape;

  final String title;
  final String subtitle;

  final List<S> secondaryContent;
  final DetailContentBuilder<S> secondaryContentBuilder;

  /// Supplying this enables the in-page search field. The filtered list is
  /// also handed to [secondaryContentBuilder], keeping playback indices and
  /// the visible queue in sync.
  final String Function(S item)? secondaryContentSearchText;
  final String? secondaryContentSearchHint;

  final String tertiaryContentTitle;
  final List<T> tertiaryContent;
  final ContentBuilder<T> tertiaryContentBuilder;

  final bool enablePlayAll;
  final bool enableShufflePlay;
  final bool enableAddAllToPlaylist;
  final bool enableSortMethod;
  final bool enableSortOrder;
  final bool enableSecondaryContentViewSwitch;

  final List<SortMethodDesc<S>>? sortMethods;

  final MultiSelectController<S>? multiSelectController;
  final List<Widget>? multiSelectViewActions;
  final bool enableMultiSelectAddToPlaylist;

  @override
  State<UniDetailPage<P, S, T>> createState() => _UniDetailPageState<P, S, T>();
}

class _UniDetailPageState<P, S, T> extends State<UniDetailPage<P, S, T>> {
  late SortMethodDesc<S>? currSortMethod = _preferredSortMethod();
  late SortOrder currSortOrder = widget.pref.sortOrder;
  late ContentView currContentView = widget.pref.contentView;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  SortMethodDesc<S>? _preferredSortMethod() {
    final methods = widget.sortMethods;
    if (methods == null || methods.isEmpty) return null;
    final index = widget.pref.sortMethod;
    return methods[index >= 0 && index < methods.length ? index : 0];
  }

  @override
  void initState() {
    super.initState();
    currSortMethod?.method(widget.secondaryContent, currSortOrder);
    _scheduleSelectionReconcile();
  }

  @override
  void didUpdateWidget(covariant UniDetailPage<P, S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryContent != widget.primaryContent) {
      _query = '';
      _search.clear();
      _scheduleSelectionReconcile(clear: true);
    } else {
      _scheduleSelectionReconcile();
    }
    currSortMethod = _preferredSortMethod();
    currSortMethod?.method(widget.secondaryContent, currSortOrder);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<S> _visibleSecondaryContent() {
    final searchable = widget.secondaryContentSearchText;
    final query = _query.trim().toLowerCase();
    if (searchable == null || query.isEmpty) return widget.secondaryContent;
    return widget.secondaryContent
        .where((item) => searchable(item).toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _scheduleSelectionReconcile({bool clear = false}) {
    final expectedController = widget.multiSelectController;
    if (expectedController == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(expectedController, widget.multiSelectController)) {
        return;
      }
      final allowed = clear ? <S>{} : widget.secondaryContent.toSet();
      final retained = expectedController.selected
          .where(allowed.contains)
          .toList(growable: false);
      if (retained.length == expectedController.selected.length) return;
      expectedController.replaceSelection(retained);
    });
  }

  void setSortMethod(SortMethodDesc<S> sortMethod) {
    final index = widget.sortMethods?.indexOf(sortMethod) ?? -1;
    if (index < 0) return;
    setState(() {
      currSortMethod = sortMethod;
      widget.pref.sortMethod = index;
      currSortMethod?.method(widget.secondaryContent, currSortOrder);
    });
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      widget.pref.sortOrder = sortOrder;
      currSortMethod?.method(widget.secondaryContent, currSortOrder);
    });
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      widget.pref.contentView = contentView;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleSecondaryContent = _visibleSecondaryContent();

    final List<Widget> actions = [];
    if (widget.enablePlayAll) {
      actions.add(_PlayAll<S>(contentList: visibleSecondaryContent));
    }
    if (widget.enableShufflePlay) {
      actions.add(_ShuffleAll<S>(contentList: visibleSecondaryContent));
    }
    if (widget.enableAddAllToPlaylist) {
      actions.add(_AddAll<S>(contentList: visibleSecondaryContent));
    }
    if (widget.enableSortMethod && currSortMethod != null) {
      actions.add(SortMethodComboBox<S>(
        sortMethods: widget.sortMethods!,
        contentList: visibleSecondaryContent,
        currSortMethod: currSortMethod!,
        setSortMethod: setSortMethod,
        sortOrder: widget.enableSortOrder && currSortMethod!.usesSortOrder
            ? currSortOrder
            : null,
        setSortOrder: setSortOrder,
        scopeId: ('detail', widget.primaryContent),
      ));
    } else if (widget.enableSortOrder) {
      actions.add(SortOrderSwitch<S>(
        sortOrder: currSortOrder,
        setSortOrder: setSortOrder,
      ));
    }
    if (widget.enableSecondaryContentViewSwitch) {
      actions.add(ContentViewSwitch<S>(
        contentView: currContentView,
        setContentView: setContentView,
      ));
    }

    return widget.multiSelectController == null
        ? result(null, actions, scheme)
        : ListenableBuilder(
            listenable: widget.multiSelectController!,
            builder: (context, _) => result(
              widget.multiSelectController!,
              actions,
              scheme,
            ),
          );
  }

  Widget result(MultiSelectController<S>? multiSelectController,
      List<Widget> actions, ColorScheme scheme) {
    final visibleSecondaryContent = _visibleSecondaryContent();
    final multiSelectViewActions = multiSelectController == null
        ? null
        : widget.multiSelectViewActions ??
            [
              if (widget.enableMultiSelectAddToPlaylist)
                AudioMultiSelectionActions(
                  controller:
                      multiSelectController as MultiSelectController<Audio>,
                  contentList: visibleSecondaryContent.cast<Audio>(),
                ),
              if (!widget.enableMultiSelectAddToPlaylist) ...[
                _VisibleSelectOrClearAll<S>(
                  multiSelectController: multiSelectController,
                  visibleContent: visibleSecondaryContent,
                ),
                MultiSelectExit<S>(
                    multiSelectController: multiSelectController),
              ],
            ];
    final gridIndices = currContentView == ContentView.table
        ? <Key, int>{
            for (var i = 0; i < visibleSecondaryContent.length; i++)
              ValueKey(visibleSecondaryContent[i]): i,
          }
        : const <Key, int>{};
    final searchEnabled = widget.secondaryContentSearchText != null;
    return AppEntranceScope(
      child: ColoredBox(
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
              builder: (context, constraints) => Column(
                    children: [
                      // head
                      // The identity area may scroll independently, but can never
                      // consume the song viewport in a short/large-text window.
                      ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: (constraints.maxHeight -
                                          16 -
                                          (searchEnabled ? 72 : 0))
                                      .clamp(0.0, double.infinity) *
                                  .6),
                          child: SingleChildScrollView(
                              key: const ValueKey('uni-detail-header-scroll'),
                              primary: false,
                              child: _UniDetailPageHeader(
                                pic: widget.primaryPic,
                                backgroundPic: widget.backgroundPic,
                                picShape: widget.picShape,
                                title: widget.title,
                                subtitle: widget.subtitle,
                                actions: actions,
                                multiSelectController: multiSelectController,
                                multiSelectViewActions: multiSelectViewActions,
                              ))),
                      SizedBox(height: searchEnabled ? 12 : 16),
                      if (searchEnabled) ...[
                        TextField(
                          key: const ValueKey('uni-detail-search'),
                          controller: _search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: widget.secondaryContentSearchHint ??
                                ui("搜索标题、歌手或专辑"),
                            prefixIcon: const Icon(Icons.search),
                            border: AppShape.inputBorder,
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: ui("清除搜索"),
                                    onPressed: () => setState(() {
                                      _query = '';
                                      _search.clear();
                                    }),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: Material(
                          borderRadius: AppShape.surfaceRadius,
                          type: MaterialType.transparency,
                          child: AppContentScrollbar(
                            builder: (context, controller) => CustomScrollView(
                              key: const ValueKey('uni-detail-content-scroll'),
                              controller: controller,
                              slivers: [
                                // secondary content
                                switch (currContentView) {
                                  ContentView.list =>
                                    MediaQuery.textScalerOf(context).scale(14) >
                                            14
                                        ? SliverList.builder(
                                            itemCount:
                                                visibleSecondaryContent.length,
                                            itemBuilder: (context, i) =>
                                                _secondaryItem(
                                                    context,
                                                    i,
                                                    visibleSecondaryContent,
                                                    multiSelectController),
                                          )
                                        : SliverFixedExtentList.builder(
                                            itemExtent: 64,
                                            itemCount:
                                                visibleSecondaryContent.length,
                                            itemBuilder: (context, i) =>
                                                _secondaryItem(
                                                    context,
                                                    i,
                                                    visibleSecondaryContent,
                                                    multiSelectController),
                                          ),
                                  ContentView.table => MusicGridScope(
                                      child: SliverGrid.builder(
                                        gridDelegate:
                                            CompactMusicGridDelegate.of(
                                                context),
                                        itemCount:
                                            visibleSecondaryContent.length,
                                        findChildIndexCallback: (key) =>
                                            gridIndices[key],
                                        itemBuilder: (context, i) =>
                                            _secondaryItem(
                                                context,
                                                i,
                                                visibleSecondaryContent,
                                                multiSelectController),
                                      ),
                                    ),
                                },

                                if (visibleSecondaryContent.isEmpty &&
                                    _query.trim().isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        ui("未找到匹配的歌曲"),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),

                                // tertiary content
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: AppEntrance(
                                      identity: 'detail-tertiary-title',
                                      order: 2,
                                      child: Text(
                                        widget.tertiaryContentTitle,
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontSize: 18.0,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverList.builder(
                                  itemCount: widget.tertiaryContent.length,
                                  itemBuilder: (context, i) => AppEntrance(
                                    key: ValueKey(widget.tertiaryContent[i]),
                                    identity: (
                                      'detail-tertiary',
                                      widget.tertiaryContent[i]
                                    ),
                                    order: i,
                                    child: widget.tertiaryContentBuilder(
                                      context,
                                      widget.tertiaryContent[i],
                                      i,
                                      null,
                                    ),
                                  ),
                                ),
                                const SliverPadding(
                                    padding: EdgeInsets.only(bottom: 96.0)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )),
        ),
      ),
    );
  }

  Widget _secondaryItem(BuildContext context, int index, List<S> visibleContent,
      MultiSelectController<S>? controller) {
    final item = visibleContent[index];
    return AppEntrance(
      key: ValueKey(item),
      identity: ('detail-secondary', item),
      order: index,
      child: widget.secondaryContentBuilder(
          context, item, index, visibleContent, controller),
    );
  }
}

class _VisibleSelectOrClearAll<T> extends StatelessWidget {
  const _VisibleSelectOrClearAll({
    required this.multiSelectController,
    required this.visibleContent,
  });

  final MultiSelectController<T> multiSelectController;
  final List<T> visibleContent;

  @override
  Widget build(BuildContext context) {
    final allVisibleSelected = visibleContent.isNotEmpty &&
        visibleContent.every(multiSelectController.selected.contains);
    return IconButton.filledTonal(
      key: const ValueKey('detail-select-visible'),
      style: appToolbarControlStyle(context,
          primary: true, tonal: true, iconOnly: true),
      tooltip: allVisibleSelected ? ui("取消全选") : ui("全选"),
      onPressed: visibleContent.isEmpty
          ? null
          : () {
              if (allVisibleSelected) {
                final visible = visibleContent.toSet();
                multiSelectController.replaceSelection(
                  multiSelectController.selected.where(
                    (item) => !visible.contains(item),
                  ),
                );
              } else {
                multiSelectController.selectAll(visibleContent);
              }
            },
      icon: Icon(
        allVisibleSelected ? Symbols.clear_all : Symbols.select_all,
      ),
    );
  }
}

class _PlayAll<T> extends StatelessWidget {
  const _PlayAll({required this.contentList});

  final List<T> contentList;

  @override
  Widget build(BuildContext context) => FilledButton(
        key: const ValueKey('detail-play-all'),
        onPressed: contentList.isEmpty
            ? null
            : () => PlayService.instance.playbackService
                .play(0, contentList as List<Audio>),
        style: appToolbarControlStyle(context, primary: true),
        child: AppToolbarLabel(label: ui("播放全部"), icon: Symbols.play_arrow),
      );
}

class _ShuffleAll<T> extends StatelessWidget {
  const _ShuffleAll({required this.contentList});

  final List<T> contentList;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        key: const ValueKey('music-shuffle-action'),
        onPressed: contentList.isEmpty
            ? null
            : () => PlayService.instance.playbackService
                .shuffleAndPlay(contentList as List<Audio>),
        style: appToolbarControlStyle(context),
        child: AppToolbarLabel(label: ui("随机播放"), icon: Symbols.shuffle),
      );
}

class _AddAll<T> extends StatelessWidget {
  const _AddAll({required this.contentList});

  final List<T> contentList;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        key: const ValueKey('detail-add-all-to-playlist'),
        onPressed: contentList.isEmpty
            ? null
            : () => showAddAudiosToPlaylistDialog(
                  context,
                  contentList as List<Audio>,
                ),
        style: appToolbarControlStyle(context),
        child: AppToolbarLabel(label: ui("加入歌单…"), icon: Symbols.playlist_add),
      );
}

enum PicShape { oval, rrect }

class _UniDetailPageHeader extends StatelessWidget {
  const _UniDetailPageHeader({
    required this.pic,
    required this.backgroundPic,
    required this.picShape,
    required this.title,
    required this.subtitle,
    this.multiSelectController,
    required this.actions,
    this.multiSelectViewActions,
  });

  final Future<ImageProvider?> pic;
  final Future<ImageProvider?> backgroundPic;
  final PicShape picShape;

  final String title;
  final String subtitle;
  final MultiSelectController? multiSelectController;
  final List<Widget> actions;
  final List<Widget>? multiSelectViewActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(14) < 20;
      final coverSize = wide
          ? picShape == PicShape.oval
              ? 176.0
              : 200.0
          : constraints.maxWidth >= 400
              ? 96.0
              : 72.0;
      final controls = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: multiSelectController?.enableMultiSelectView == true
            ? multiSelectViewActions!
            : actions,
      );
      final text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: title,
            child: Text(
              title,
              key: const ValueKey('uni-detail-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 22,
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Tooltip(
            message: subtitle,
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
            ),
          ),
        ],
      );
      final cover = SizedBox.square(
        key: const ValueKey('uni-detail-cover'),
        dimension: coverSize,
        child: FutureBuilder<ImageProvider?>(
          future: pic,
          builder: (context, snapshot) {
            final placeholder = Icon(Symbols.broken_image,
                size: coverSize, color: scheme.onSurface);
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data == null) return placeholder;
            final image = Image(
                image: snapshot.data!,
                width: coverSize,
                height: coverSize,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => placeholder);
            return picShape == PicShape.oval
                ? ClipOval(child: image)
                : ClipRRect(borderRadius: AppShape.surfaceRadius, child: image);
          },
        ),
      );
      return ClipRRect(
        borderRadius: AppShape.surfaceRadius,
        child: Stack(
          children: [
            Positioned.fill(
                child: ColoredBox(color: scheme.surfaceContainerHighest)),
            Positioned.fill(
              child: FutureBuilder<ImageProvider?>(
                future: backgroundPic,
                builder: (context, snapshot) => snapshot.data == null
                    ? const SizedBox.shrink()
                    : Image(
                        image: snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
            Positioned.fill(
                child: ColoredBox(
                    color: theme.brightness == Brightness.dark
                        ? Colors.black38
                        : Colors.white30)),
            Positioned.fill(
                child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: const ColoredBox(color: Colors.transparent),
            )),
            AppEntrance(
              identity: 'detail-header',
              child: Padding(
                padding: EdgeInsets.all(wide ? 16 : 12),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                            cover,
                            const SizedBox(width: 16),
                            Expanded(
                                child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                text,
                                const SizedBox(height: 8),
                                controls
                              ],
                            )),
                          ])
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            cover,
                            const SizedBox(width: 12),
                            Expanded(child: text),
                          ]),
                          const SizedBox(height: 12),
                          controls,
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
