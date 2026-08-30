import 'dart:ui';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    required this.enableShufflePlay,
    required this.enableSortMethod,
    required this.enableSortOrder,
    required this.enableSecondaryContentViewSwitch,
    this.sortMethods,
    this.multiSelectController,
    this.multiSelectViewActions,
  });

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
  final ContentBuilder<S> secondaryContentBuilder;

  final String tertiaryContentTitle;
  final List<T> tertiaryContent;
  final ContentBuilder<T> tertiaryContentBuilder;

  final bool enableShufflePlay;
  final bool enableSortMethod;
  final bool enableSortOrder;
  final bool enableSecondaryContentViewSwitch;

  final List<SortMethodDesc<S>>? sortMethods;

  final MultiSelectController<S>? multiSelectController;
  final List<Widget>? multiSelectViewActions;

  @override
  State<UniDetailPage<P, S, T>> createState() => _UniDetailPageState<P, S, T>();
}

class _UniDetailPageState<P, S, T> extends State<UniDetailPage<P, S, T>> {
  late SortMethodDesc<S>? currSortMethod = _preferredSortMethod();
  late SortOrder currSortOrder = widget.pref.sortOrder;
  late ContentView currContentView = widget.pref.contentView;

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
  }

  @override
  void didUpdateWidget(covariant UniDetailPage<P, S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    currSortMethod = _preferredSortMethod();
    currSortMethod?.method(widget.secondaryContent, currSortOrder);
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

    final List<Widget> actions = [];
    if (widget.enableShufflePlay) {
      actions.add(ShufflePlay<S>(contentList: widget.secondaryContent));
    }
    if (widget.enableSortMethod && currSortMethod != null) {
      actions.add(SortMethodComboBox<S>(
        sortMethods: widget.sortMethods!,
        contentList: widget.secondaryContent,
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
    final gridIndices = currContentView == ContentView.table
        ? <Key, int>{
            for (var i = 0; i < widget.secondaryContent.length; i++)
              ValueKey(widget.secondaryContent[i]): i,
          }
        : const <Key, int>{};
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
                              maxHeight: (constraints.maxHeight - 16)
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
                                multiSelectViewActions:
                                    widget.multiSelectViewActions,
                              ))),
                      const SizedBox(height: 16.0),
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
                                                widget.secondaryContent.length,
                                            itemBuilder: (context, i) =>
                                                _secondaryItem(context, i,
                                                    multiSelectController),
                                          )
                                        : SliverFixedExtentList.builder(
                                            itemExtent: 64,
                                            itemCount:
                                                widget.secondaryContent.length,
                                            itemBuilder: (context, i) =>
                                                _secondaryItem(context, i,
                                                    multiSelectController),
                                          ),
                                  ContentView.table => MusicGridScope(
                                      child: SliverGrid.builder(
                                        gridDelegate:
                                            CompactMusicGridDelegate.of(
                                                context),
                                        itemCount:
                                            widget.secondaryContent.length,
                                        findChildIndexCallback: (key) =>
                                            gridIndices[key],
                                        itemBuilder: (context, i) =>
                                            _secondaryItem(context, i,
                                                multiSelectController),
                                      ),
                                    ),
                                },

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

  Widget _secondaryItem(
      BuildContext context, int index, MultiSelectController<S>? controller) {
    final item = widget.secondaryContent[index];
    return AppEntrance(
      key: ValueKey(item),
      identity: ('detail-secondary', item),
      order: index,
      child: widget.secondaryContentBuilder(context, item, index, controller),
    );
  }
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
          ? 200.0
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
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      cover,
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [text, const SizedBox(height: 8), controls],
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
          ],
        ),
      );
    });
  }
}
