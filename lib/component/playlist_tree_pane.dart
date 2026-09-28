import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'app_content_scrollbar.dart';
import 'app_motion.dart';
import 'app_toolbar_style.dart';
import 'now_playing_bar_metrics.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'adaptive_grid_drag.dart';
import 'playlist_cover_transition.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A flat view projection. Payloads and editing remain owned by PlaylistBrowser.
class PlaylistTreeNode<T> {
  const PlaylistTreeNode(
      {required this.id,
      required this.parentId,
      required this.depth,
      required this.branch,
      required this.searchText,
      required this.value});
  final String id;
  final String? parentId;
  final int depth;
  final bool branch;
  final String searchText;
  final T value;
}

class PlaylistTreePane<T> extends StatefulWidget {
  const PlaylistTreePane(
      {super.key,
      required this.nodes,
      required this.expanded,
      required this.onExpandedChanged,
      required this.itemBuilder,
      this.onActivate,
      this.revealId,
      this.onQueryChanged,
      this.initialQuery = ''});
  final List<PlaylistTreeNode<T>> nodes;
  final Set<String> expanded;
  final FutureOr<void> Function(Set<String>) onExpandedChanged;
  final Widget Function(BuildContext, PlaylistTreeNode<T>, VoidCallback)
      itemBuilder;
  final String? Function()? revealId;
  final ValueChanged<PlaylistTreeNode<T>>? onActivate;
  final String initialQuery;
  final ValueChanged<String>? onQueryChanged;
  @override
  State<PlaylistTreePane<T>> createState() => _PlaylistTreePaneState<T>();
}

class _PlaylistTreePaneState<T> extends State<PlaylistTreePane<T>>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _entryClock = AnimationController(
      vsync: this, duration: AppMotion.emphasized, value: 1);
  late final _entryOpacity =
      CurvedAnimation(parent: _entryClock, curve: AppMotion.standardCurve);
  late final _entryOffset = Tween(begin: const Offset(0, .10), end: Offset.zero)
      .animate(_entryOpacity);
  Set<String> _enteringIds = {};
  late final _search = TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  final _focus = <String, FocusNode>{};
  final _rowKeys = <String, GlobalKey>{};
  int _navigationEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted && appToolbarReduceMotion(context, kind: MotionKind.entrance)) {
      _entryClock.value = 1;
    }
  }

  @override
  void dispose() {
    _navigationEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _entryOpacity.dispose();
    _entryClock.dispose();
    _search.dispose();
    _scroll.dispose();
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.enabled(context, MotionKind.entrance) ||
        appToolbarReduceMotion(context, kind: MotionKind.entrance) ||
        !TickerMode.valuesOf(context).enabled) {
      _entryClock.value = 1;
    }
  }

  Widget _revealEntry(String id, Widget child) => FadeTransition(
      key: ValueKey('playlist-tree-entry-$id'),
      opacity: _enteringIds.contains(id)
          ? _entryOpacity
          : const AlwaysStoppedAnimation(1.0),
      child: SlideTransition(
          position: _enteringIds.contains(id)
              ? _entryOffset
              : const AlwaysStoppedAnimation(Offset.zero),
          child: child));

  @override
  void didUpdateWidget(covariant PlaylistTreePane<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text.trim().isEmpty &&
        !setEquals(widget.expanded, oldWidget.expanded)) {
      final oldVisible =
          visiblePlaylistTreeNodes(oldWidget.nodes, oldWidget.expanded, '')
              .map((n) => n.id)
              .toSet();
      _enteringIds = _visible()
          .map((n) => n.id)
          .where((id) => !oldVisible.contains(id))
          .toSet();
      if (_enteringIds.isNotEmpty &&
          AppMotion.enabled(context, MotionKind.entrance) &&
          !appToolbarReduceMotion(context, kind: MotionKind.entrance) &&
          TickerMode.valuesOf(context).enabled) {
        _entryClock.forward(from: 0);
      } else {
        _entryClock.value = 1;
      }
    }
    final ids = widget.nodes.map((n) => n.id).toSet();
    for (final id in _focus.keys.where((id) => !ids.contains(id)).toList()) {
      _focus.remove(id)?.dispose();
      _rowKeys.remove(id);
    }
  }

  Map<String, PlaylistTreeNode<T>> get _byId =>
      {for (final n in widget.nodes) n.id: n};

  List<PlaylistTreeNode<T>> _visible() =>
      visiblePlaylistTreeNodes(widget.nodes, widget.expanded, _search.text);

  void _toggle(PlaylistTreeNode<T> node) {
    if (!node.branch || _search.text.trim().isNotEmpty) return;
    final next = {...widget.expanded};
    if (!next.remove(node.id)) next.add(node.id);
    widget.onExpandedChanged(next);
  }

  // Only mounted rows own layout. Walk by viewport when a target is virtualized,
  // then use its actual geometry; never assume song and folder heights match.
  Future<void> _focusRow(String id) async {
    final epoch = ++_navigationEpoch;
    await WidgetsBinding.instance.endOfFrame;
    while (mounted && epoch == _navigationEpoch) {
      final visible = _visible();
      final target = visible.indexWhere((n) => n.id == id);
      if (target < 0) return;
      final rowContext = _rowKeys[id]?.currentContext;
      if (rowContext != null && rowContext.mounted) {
        await Scrollable.ensureVisible(rowContext,
            alignment: .4, duration: Duration.zero);
        if (mounted && epoch == _navigationEpoch) _focus[id]?.requestFocus();
        return;
      }
      if (!_scroll.hasClients) return;
      final mountedIndex =
          visible.indexWhere((n) => _rowKeys[n.id]?.currentContext != null);
      final direction = mountedIndex < 0 || target >= mountedIndex ? 1 : -1;
      final position = _scroll.position;
      final next =
          (_scroll.offset + direction * position.viewportDimension * .8)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if (next == _scroll.offset) return;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _reveal() async {
    final id = widget.revealId?.call();
    if (id == null) return;
    final byId = _byId;
    final next = {...widget.expanded};
    var parent = byId[id]?.parentId;
    while (parent != null && byId.containsKey(parent)) {
      next.add(parent);
      parent = byId[parent]?.parentId;
    }
    _search.clear();
    widget.onQueryChanged?.call('');
    await widget.onExpandedChanged(next);
    if (!mounted) return;
    _focusRow(id);
  }

  KeyEventResult _key(KeyEvent event, PlaylistTreeNode<T> node,
      List<PlaylistTreeNode<T>> visible) {
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final index = visible.indexOf(node);
    final key = event.logicalKey;
    final expanded =
        _search.text.trim().isNotEmpty || widget.expanded.contains(node.id);
    if (key == LogicalKeyboardKey.arrowRight && node.branch) {
      if (!expanded) {
        _toggle(node);
      } else if (index + 1 < visible.length &&
          visible[index + 1].depth > node.depth) {
        _focusRow(visible[index + 1].id);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (node.branch && expanded && _search.text.trim().isEmpty) {
        _toggle(node);
      } else if (node.parentId != null) {
        _focusRow(node.parentId!);
      }
    } else if (key == LogicalKeyboardKey.arrowDown &&
        index + 1 < visible.length) {
      _focusRow(visible[index + 1].id);
    } else if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      _focusRow(visible[index - 1].id);
    } else if (key == LogicalKeyboardKey.home) {
      _focusRow(visible.first.id);
    } else if (key == LogicalKeyboardKey.end) {
      _focusRow(visible.last.id);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (node.branch) {
        _toggle(node);
      } else {
        widget.onActivate?.call(node);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  List<int> _continuations(
      PlaylistTreeNode<T> node,
      Map<String, PlaylistTreeNode<T>> byId,
      Map<String?, String> lastByParent) {
    final result = <int>[];
    var parent = byId[node.parentId];
    while (parent != null) {
      if (parent.depth > 0 && lastByParent[parent.parentId] != parent.id) {
        result.add(parent.depth);
      }
      parent = byId[parent.parentId];
    }
    return result;
  }

  Widget _item(BuildContext context, PlaylistTreeNode<T> node,
      List<PlaylistTreeNode<T>> visible) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
        key: ValueKey('playlist-tree-focus-${node.id}'),
        focusNode: _focus.putIfAbsent(node.id, () => FocusNode()),
        onKeyEvent: (_, event) => _key(event, node, visible),
        child: Builder(
            builder: (context) => Semantics(
                expanded: node.branch
                    ? (_search.text.trim().isNotEmpty ||
                        widget.expanded.contains(node.id))
                    : null,
                child: Material(
                    key: _rowKeys.putIfAbsent(node.id, () => GlobalKey()),
                    color: node.branch
                        ? Colors.transparent
                        : scheme.surfaceContainerLow,
                    animationDuration: AppMotion.duration(
                        context, MotionKind.feedback, AppMotion.quick),
                    shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: Focus.of(context).hasPrimaryFocus
                                ? scheme.primary
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(12)),
                    child: widget.itemBuilder(
                        context, node, () => _toggle(node))))));
  }

  Widget _actions(BuildContext context, bool searching) {
    Widget button(
            String key, String label, IconData icon, VoidCallback? action) =>
        OutlinedButton.icon(
            key: ValueKey(key),
            style: appToolbarControlStyle(context),
            onPressed: action,
            icon: Icon(icon, size: 20),
            label: Text(ui(label)));
    return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          button(
              'playlist-tree-expand-all',
              '展开全部',
              Symbols.account_tree,
              searching
                  ? null
                  : () => widget.onExpandedChanged({
                        for (final n in widget.nodes)
                          if (n.branch) n.id
                      })),
          button('playlist-tree-collapse-all', '折叠全部', Symbols.folder,
              searching ? null : () => widget.onExpandedChanged({})),
          if (widget.revealId != null)
            button(
                'playlist-tree-reveal', '定位正在播放', Symbols.my_location, _reveal),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final searching = _search.text.trim().isNotEmpty;
    final lastByParent = {for (final node in visible) node.parentId: node.id};
    final byId = _byId;
    final maxDepth =
        visible.fold<int>(1, (depth, node) => math.max(depth, node.depth));
    final scheme = Theme.of(context).colorScheme;
    final search = Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: TextField(
            key: const ValueKey('playlist-tree-search'),
            controller: _search,
            decoration: InputDecoration(
                isDense: true,
                labelText: ui('搜索树状歌单'),
                prefixIcon: const Icon(Symbols.search),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: ui('清除搜索'),
                        onPressed: () {
                          _search.clear();
                          widget.onQueryChanged?.call('');
                          setState(() {});
                        },
                        icon: const Icon(Symbols.close))
                    : null),
            onChanged: (value) {
              widget.onQueryChanged?.call(value);
              setState(() {});
            }));
    return LayoutBuilder(builder: (context, bounds) {
      final step = math.min(20.0, bounds.maxWidth * .18 / maxDepth);
      final minimum = MediaQuery.textScalerOf(context).scale(300);
      final groups = <List<PlaylistTreeNode<T>>>[];
      for (final node in visible) {
        final columns = math.max(
            1,
            math.min(
                4,
                ((bounds.maxWidth - node.depth * step - 48) / minimum)
                    .floor()));
        if (!node.branch &&
            groups.isNotEmpty &&
            !groups.last.first.branch &&
            groups.last.first.parentId == node.parentId &&
            groups.last.length < columns) {
          groups.last.add(node);
        } else {
          groups.add([node]);
        }
      }
      final rowIndices = <Object, int>{
        for (var i = 0; i < groups.length; i++)
          for (final n in groups[i]) n.id: i
      };
      final groupIndices = {
        for (var i = 0; i < groups.length; i++) groups[i].first.id: i
      };
      return Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: bounds.maxWidth < MediaQuery.textScalerOf(context).scale(760)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        search,
                        const SizedBox(height: 8),
                        _actions(context, searching)
                      ])
                : Row(children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    _actions(context, searching)
                  ])),
        Expanded(
            child: visible.isEmpty
                ? Center(child: Text(ui('没有匹配的歌单或歌曲')))
                : PlaylistCoverLayoutIndices(
                    indices: rowIndices,
                    child: AppContentScrollbar(
                        controller: _scroll,
                        builder: (context, controller) =>
                            GridEdgeAutoScrollRegion(
                                controller: controller,
                                child: ListView.builder(
                                    key: const PageStorageKey(
                                        'playlist-tree-scroll'),
                                    controller: controller,
                                    padding: EdgeInsets.only(
                                        bottom:
                                            NowPlayingBarMetrics.reservedSpace(
                                                context)),
                                    itemCount: groups.length,
                                    findChildIndexCallback: (key) =>
                                        key is ValueKey<String>
                                            ? groupIndices[key.value]
                                            : null,
                                    itemBuilder: (context, index) {
                                      final group = groups[index];
                                      final first = group.first;
                                      final expanded = searching ||
                                          widget.expanded.contains(first.id);
                                      final columns = first.branch
                                          ? 1
                                          : math.max(
                                              1,
                                              math.min(
                                                  4,
                                                  ((bounds.maxWidth -
                                                              first.depth *
                                                                  step -
                                                              48) /
                                                          minimum)
                                                      .floor()));
                                      return KeyedSubtree(
                                          key: ValueKey(first.id),
                                          child: _revealEntry(
                                              first.id,
                                              CustomPaint(
                                                  painter: _TreeLines(
                                                      depth: first.depth,
                                                      step: step,
                                                      branch: first.branch,
                                                      last: lastByParent[first
                                                              .parentId] ==
                                                          group.last.id,
                                                      ancestors: _continuations(
                                                          first,
                                                          byId,
                                                          lastByParent),
                                                      color: scheme.primary
                                                          .withValues(
                                                              alpha: .38)),
                                                  child: Padding(
                                                      padding:
                                                          EdgeInsetsDirectional
                                                              .only(
                                                                  start: first
                                                                          .depth *
                                                                      step),
                                                      child: Row(children: [
                                                        SizedBox(
                                                            width: 40,
                                                            child: first.branch
                                                                ? IconButton(
                                                                    key: ValueKey(
                                                                        'playlist-tree-toggle-${first.id}'),
                                                                    tooltip: ui(expanded
                                                                        ? '折叠歌单'
                                                                        : '展开歌单'),
                                                                    onPressed: searching
                                                                        ? null
                                                                        : () => _toggle(
                                                                            first),
                                                                    icon: AnimatedRotation(
                                                                        turns: expanded
                                                                            ? .25
                                                                            : 0,
                                                                        duration: appToolbarReduceMotion(context)
                                                                            ? Duration
                                                                                .zero
                                                                            : AppMotion
                                                                                .quick,
                                                                        child: Icon(
                                                                            Symbols
                                                                                .chevron_right,
                                                                            color:
                                                                                scheme.primary)))
                                                                : null),
                                                        Expanded(
                                                            child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        right:
                                                                            8,
                                                                        top: 4,
                                                                        bottom:
                                                                            4),
                                                                child: Row(
                                                                    children: [
                                                                      for (var c =
                                                                              0;
                                                                          c < columns;
                                                                          c++) ...[
                                                                        if (c >
                                                                            0)
                                                                          const SizedBox(
                                                                              width: 8),
                                                                        Expanded(
                                                                            child: c < group.length
                                                                                ? _item(context, group[c], visible)
                                                                                : const SizedBox.shrink()),
                                                                      ]
                                                                    ]))),
                                                      ])))));
                                    }))))),
      ]);
    });
  }
}

List<PlaylistTreeNode<T>> visiblePlaylistTreeNodes<T>(
    List<PlaylistTreeNode<T>> nodes, Set<String> expanded, String search) {
  final query = search.trim().toLowerCase();
  if (query.isNotEmpty) {
    final byId = {for (final n in nodes) n.id: n};
    final included = <String>{};
    final matchingBranches = <String>{};
    for (final node in nodes) {
      if (node.searchText.toLowerCase().contains(query) ||
          matchingBranches.contains(node.parentId)) {
        if (node.branch) matchingBranches.add(node.id);
        PlaylistTreeNode<T>? ancestor = node;
        while (ancestor != null && included.add(ancestor.id)) {
          ancestor = byId[ancestor.parentId];
        }
      }
    }
    return nodes.where((n) => included.contains(n.id)).toList();
  }
  final visibleBranches = <String>{};
  final result = <PlaylistTreeNode<T>>[];
  for (final node in nodes) {
    if (node.depth == 0 || visibleBranches.contains(node.parentId)) {
      result.add(node);
      if (node.branch && expanded.contains(node.id)) {
        visibleBranches.add(node.id);
      }
    }
  }
  return result;
}

class _TreeLines extends CustomPainter {
  const _TreeLines(
      {required this.depth,
      required this.step,
      required this.branch,
      required this.last,
      required this.ancestors,
      required this.color});
  final int depth;
  final double step;
  final bool branch, last;
  final List<int> ancestors;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final level in ancestors) {
      final x = (level - 1) * step + 20;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    if (depth == 0) return;
    final x = (depth - 1) * step + 20;
    canvas.drawLine(
        Offset(x, 0), Offset(x, last ? size.height / 2 : size.height), pen);
    canvas.drawLine(Offset(x, size.height / 2),
        Offset(depth * step + (branch ? 8 : 36), size.height / 2), pen);
  }

  @override
  bool shouldRepaint(covariant _TreeLines old) =>
      old.depth != depth ||
      old.step != step ||
      old.branch != branch ||
      old.last != last ||
      old.color != color ||
      old.ancestors.join(',') != ancestors.join(',');
}
