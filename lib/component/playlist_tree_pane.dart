import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'app_content_scrollbar.dart';
import 'app_horizontal_wheel_region.dart';
import 'app_scrollbar.dart';
import 'app_motion.dart';
import 'app_shape.dart';
import 'app_toolbar_style.dart';
import 'now_playing_bar_metrics.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'adaptive_grid_drag.dart';
import 'playlist_cover_transition.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Each generation shrinks, stopping above the former 40 px tree cover.
double playlistTreeCoverSize({required int nodeDepth}) =>
    math.max(48.0, 112.0 - nodeDepth * 24.0);

int playlistTreeSongRows({required int parentDepth}) =>
    playlistTreeCoverSize(nodeDepth: parentDepth) > 48 ? 2 : 1;

double playlistTreeSongCoverSize({required int parentDepth}) {
  final parent = playlistTreeCoverSize(nodeDepth: parentDepth);
  return playlistTreeSongRows(parentDepth: parentDepth) == 1
      ? 40
      : math.min(48.0, (parent + 12 - 4) / 2 - 6);
}

double playlistTreeSongPitch({required int parentDepth}) =>
    playlistTreeSongCoverSize(parentDepth: parentDepth) + 32;

class _TreeVisualGroup<T> {
  const _TreeVisualGroup(this.branch, this.songs);
  final PlaylistTreeNode<T>? branch;
  final List<PlaylistTreeNode<T>> songs;
  String get id => branch?.id ?? '\u0000root-songs';
  int get depth => branch?.depth ?? 0;
}

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
  late final _rootEntryOffset =
      Tween(begin: const Offset(0, .10), end: Offset.zero)
          .animate(_entryOpacity);
  late final _branchEntryOffset =
      Tween(begin: const Offset(0, -.10), end: Offset.zero)
          .animate(_entryOpacity);
  late final _songEntryOffset =
      Tween(begin: const Offset(-.16, 0), end: Offset.zero)
          .animate(_entryOpacity);
  Set<String> _enteringIds = {};
  bool _initialRevealStarted = false;
  Set<String>? _pendingExpansion;
  Set<String>? _requestedExpansion;
  Future<void> _commitTail = Future<void>.value();
  int _expansionEpoch = 0;
  late final _search = TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  final _songScroll = <String, ScrollController>{};
  final _focus = <String, FocusNode>{};
  final _rowKeys = <String, GlobalKey>{};
  final _groupKeys = <String, GlobalKey>{};
  int _navigationEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted && appToolbarReduceMotion(context, kind: MotionKind.entrance)) {
      _finishWithoutMotion();
    }
  }

  void _finishWithoutMotion() {
    _entryClock.value = 1;
    if (_pendingExpansion case final next?) {
      final epoch = ++_expansionEpoch;
      _pendingExpansion = null;
      _enteringIds = {};
      // Dependencies can change during build; commit the pending collapse
      // after that frame instead of leaving its reverse ticker cancelled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _expansionEpoch) {
          _requestedExpansion = next;
          unawaited(_enqueueExpansionCommit());
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void dispose() {
    _navigationEpoch++;
    _expansionEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _entryOpacity.dispose();
    _entryClock.dispose();
    _search.dispose();
    _scroll.dispose();
    for (final controller in _songScroll.values) {
      controller.dispose();
    }
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = AppMotion.enabled(context, MotionKind.entrance) &&
        !appToolbarReduceMotion(context, kind: MotionKind.entrance) &&
        TickerMode.valuesOf(context).enabled;
    if (!_initialRevealStarted) {
      _initialRevealStarted = true;
      if (enabled) {
        _enteringIds = {
          for (final node in _visible())
            if (node.depth == 0) node.id,
        };
        if (_enteringIds.isNotEmpty) _entryClock.forward(from: 0);
      }
    }
    if (!enabled) {
      _finishWithoutMotion();
    }
  }

  Widget _revealEntry(String id, Widget child,
          {required bool song, int depth = 0}) =>
      FadeTransition(
          key: ValueKey('playlist-tree-entry-$id'),
          opacity: _enteringIds.contains(id)
              ? _entryOpacity
              : const AlwaysStoppedAnimation(1.0),
          child: SlideTransition(
              position: _enteringIds.contains(id)
                  ? depth == 0
                      ? _rootEntryOffset
                      : song
                          ? _songEntryOffset
                          : _branchEntryOffset
                  : const AlwaysStoppedAnimation(Offset.zero),
              child: child));

  @override
  void didUpdateWidget(covariant PlaylistTreePane<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_requestedExpansion case final requested?) {
      if (setEquals(widget.expanded, requested)) _requestedExpansion = null;
    }
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
      final stale = _focus.remove(id);
      if (stale != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
      }
      _rowKeys.remove(id);
    }
    final groupIds = {
      for (final node in widget.nodes)
        if (node.branch) node.id,
      if (widget.nodes.any((node) => !node.branch && node.parentId == null))
        '\u0000root-songs',
    };
    final railIds = {
      for (final node in widget.nodes)
        if (!node.branch) node.parentId ?? '\u0000root-songs',
    };
    for (final id
        in _songScroll.keys.where((id) => !railIds.contains(id)).toList()) {
      final stale = _songScroll.remove(id)!;
      // The old rail is still mounted until this frame finishes rebuilding.
      WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
    }
    _groupKeys.removeWhere((id, _) => !groupIds.contains(id));
  }

  Map<String, PlaylistTreeNode<T>> get _byId =>
      {for (final n in widget.nodes) n.id: n};

  List<PlaylistTreeNode<T>> _visible() =>
      visiblePlaylistTreeNodes(widget.nodes, widget.expanded, _search.text);

  List<_TreeVisualGroup<T>> _groups(List<PlaylistTreeNode<T>> visible) {
    final songs = <String?, List<PlaylistTreeNode<T>>>{};
    for (final node in visible) {
      if (!node.branch) (songs[node.parentId] ??= []).add(node);
    }
    final result = <_TreeVisualGroup<T>>[];
    var addedRootSongs = false;
    for (final node in visible) {
      if (node.branch) {
        result.add(_TreeVisualGroup(node, songs[node.id] ?? const []));
      } else if (node.parentId == null && !addedRootSongs) {
        result.add(_TreeVisualGroup(null, songs[null] ?? const []));
        addedRootSongs = true;
      }
    }
    return result;
  }

  List<PlaylistTreeNode<T>> _visualOrder(List<_TreeVisualGroup<T>> groups) => [
        for (final group in groups) ...[
          if (group.branch case final branch?) branch,
          ...group.songs,
        ],
      ];

  // Cover tracking seeks a lazy destination before starting its flight. The
  // ordinary vertical row index is identical for every song in one rail, so
  // seek that row first and then its horizontal column without rebuilding all
  // songs or replacing the shared tracking animation.
  bool? _seekTreeSong(Object id, bool atStart) {
    if (id is! String || !_scroll.hasClients) return null;
    final groups = _groups(_visible());
    final groupIndex =
        groups.indexWhere((group) => group.songs.any((song) => song.id == id));
    if (groupIndex < 0) return null;
    final group = groups[groupIndex];
    final groupContext = _groupKeys[group.id]?.currentContext;
    if (groupContext == null || !groupContext.mounted) {
      final position = _scroll.position;
      final mountedIndex = groups
          .indexWhere((item) => _groupKeys[item.id]?.currentContext != null);
      final direction = mountedIndex < 0 || groupIndex >= mountedIndex ? 1 : -1;
      final next =
          (_scroll.offset + direction * position.viewportDimension * .8)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((next - _scroll.offset).abs() > 1) _scroll.jumpTo(next);
      return true;
    }
    final previous = _scroll.offset;
    Scrollable.ensureVisible(groupContext,
        duration: Duration.zero,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    if ((_scroll.offset - previous).abs() > 1) return true;
    final controller = _songScroll[group.id];
    if (controller == null || !controller.hasClients) return true;
    final position = controller.position;
    final songIndex = group.songs.indexWhere((song) => song.id == id);
    final rows = playlistTreeSongRows(parentDepth: group.depth);
    final destination = atStart
        ? position.minScrollExtent
        : (songIndex ~/ rows) * playlistTreeSongPitch(parentDepth: group.depth);
    final next = destination
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((controller.offset - next).abs() < 1) return false;
    controller.jumpTo(next);
    return true;
  }

  void _toggle(PlaylistTreeNode<T> node) {
    if (!node.branch || _search.text.trim().isNotEmpty) return;
    final next = {...(_requestedExpansion ?? widget.expanded)};
    if (!next.remove(node.id)) next.add(node.id);
    unawaited(_changeExpansion(next));
  }

  Future<void> _enqueueExpansionCommit() {
    final operation = _commitTail.then((_) async {
      if (!mounted || _requestedExpansion == null) return;
      final requested = {..._requestedExpansion!};
      if (setEquals(widget.expanded, requested)) {
        _requestedExpansion = null;
        return;
      }
      await widget.onExpandedChanged(requested);
    });
    _commitTail = operation;
    return operation;
  }

  Set<String> _rootedExpansion(Set<String> requested) {
    final byId = _byId;
    final result = <String>{};
    for (final node in widget.nodes) {
      if (!node.branch || !requested.contains(node.id)) continue;
      var parentId = node.parentId;
      var valid = true;
      var hops = 0;
      while (parentId != null) {
        final parent = byId[parentId];
        if (parent == null ||
            !requested.contains(parentId) ||
            ++hops > widget.nodes.length) {
          valid = false;
          break;
        }
        parentId = parent.parentId;
      }
      if (valid) result.add(node.id);
    }
    return result;
  }

  Future<void> _changeExpansion(Set<String> requested) async {
    // An expanded child cannot outlive a collapsed parent. Otherwise reopening
    // the parent would reveal every previously opened descendant at once.
    final next = _rootedExpansion(requested);
    final epoch = ++_expansionEpoch;
    _requestedExpansion = {...next};
    final visibleNow = _visible().map((node) => node.id).toSet();
    final visibleNext = visiblePlaylistTreeNodes(widget.nodes, next, '')
        .map((node) => node.id)
        .toSet();
    final leaving = visibleNow.difference(visibleNext);
    final animate = leaving.isNotEmpty &&
        AppMotion.enabled(context, MotionKind.entrance) &&
        !appToolbarReduceMotion(context, kind: MotionKind.entrance) &&
        TickerMode.valuesOf(context).enabled;
    if (!animate) {
      _pendingExpansion = null;
      _entryClock.value = 1;
      _enteringIds = {};
      setState(() {});
      await _enqueueExpansionCommit();
      return;
    }
    // Keep departing rows mounted until their reverse entrance finishes. The
    // parent still owns the persisted expansion state and receives it only
    // after the exit, so drag targets and keyboard focus stay intact.
    _pendingExpansion = next;
    setState(() => _enteringIds = leaving);
    try {
      await _entryClock.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || epoch != _expansionEpoch) return;
    _pendingExpansion = null;
    _enteringIds = {};
    await _enqueueExpansionCommit();
  }

  // Only mounted rows own layout. Walk by viewport when a target is virtualized,
  // then use its actual geometry; never assume song and folder heights match.
  Future<void> _focusRow(String id) async {
    final epoch = ++_navigationEpoch;
    await WidgetsBinding.instance.endOfFrame;
    for (var attempt = 0;
        attempt < 200 && mounted && epoch == _navigationEpoch;
        attempt++) {
      final visible = _visible();
      final groups = _groups(visible);
      final target = visible.where((n) => n.id == id).firstOrNull;
      if (target == null) return;
      final groupId =
          target.branch ? target.id : target.parentId ?? '\u0000root-songs';
      final targetGroup = groups.indexWhere((group) => group.id == groupId);
      if (targetGroup < 0) return;
      final groupContext = _groupKeys[groupId]?.currentContext;
      if (groupContext == null || !groupContext.mounted) {
        if (!_scroll.hasClients) return;
        final mountedIndex = groups.indexWhere(
            (group) => _groupKeys[group.id]?.currentContext != null);
        final direction =
            mountedIndex < 0 || targetGroup >= mountedIndex ? 1 : -1;
        final position = _scroll.position;
        final next =
            (_scroll.offset + direction * position.viewportDimension * .8)
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble();
        if (next == _scroll.offset) return;
        _scroll.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      await Scrollable.ensureVisible(groupContext,
          alignment: .4, duration: Duration.zero);
      if (!target.branch) {
        final group = groups[targetGroup];
        final controller = _songScroll[groupId];
        if (controller == null || !controller.hasClients) {
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        final index = group.songs.indexWhere((node) => node.id == id);
        final rows = playlistTreeSongRows(parentDepth: group.depth);
        final pitch = playlistTreeSongPitch(parentDepth: group.depth);
        final position = controller.position;
        final targetOffset = ((index ~/ rows) * pitch)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((controller.offset - targetOffset).abs() > 1) {
          controller.jumpTo(targetOffset);
          await WidgetsBinding.instance.endOfFrame;
        }
      }
      final rowContext = _rowKeys[id]?.currentContext;
      if (rowContext != null && rowContext.mounted) {
        await Scrollable.ensureVisible(rowContext,
            alignment: target.branch ? .4 : .05, duration: Duration.zero);
        if (mounted && epoch == _navigationEpoch) _focus[id]?.requestFocus();
        return;
      }
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
    await _changeExpansion(next);
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
                        (_requestedExpansion ?? widget.expanded)
                            .contains(node.id))
                    : null,
                child: Material(
                    key: _rowKeys.putIfAbsent(node.id, () => GlobalKey()),
                    color: Colors.transparent,
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
                  : () => unawaited(_changeExpansion({
                        for (final n in widget.nodes)
                          if (n.branch) n.id
                      }))),
          button('playlist-tree-collapse-all', '折叠全部', Symbols.folder,
              searching ? null : () => unawaited(_changeExpansion({}))),
          if (widget.revealId != null)
            button(
                'playlist-tree-reveal', '定位正在播放', Symbols.my_location, _reveal),
        ]);
  }

  Widget _songStrip(BuildContext context, _TreeVisualGroup<T> group,
      List<PlaylistTreeNode<T>> order) {
    final rows = playlistTreeSongRows(parentDepth: group.depth);
    final size = playlistTreeSongCoverSize(parentDepth: group.depth);
    final cell = size + 6;
    final pitch = playlistTreeSongPitch(parentDepth: group.depth);
    final controller =
        _songScroll.putIfAbsent(group.id, () => ScrollController());
    return AppHorizontalWheelRegion(
      controller: controller,
      child: AppScrollbar(
        controller: controller,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: ListView.builder(
          key: PageStorageKey('playlist-tree-songs-${group.id}'),
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemExtent: pitch,
          itemCount: (group.songs.length + rows - 1) ~/ rows,
          itemBuilder: (context, column) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: 4),
                SizedBox(
                  width: pitch,
                  height: cell,
                  child: column * rows + row < group.songs.length
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _revealEntry(
                            group.songs[column * rows + row].id,
                            _item(context, group.songs[column * rows + row],
                                order),
                            song: true,
                            depth: group.songs[column * rows + row].depth,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupWidget(
      BuildContext context,
      _TreeVisualGroup<T> group,
      List<PlaylistTreeNode<T>> order,
      double step,
      Map<String, PlaylistTreeNode<T>> byId,
      Map<String?, String> lastByParent,
      bool searching) {
    final branch = group.branch;
    final size = playlistTreeCoverSize(nodeDepth: group.depth);
    final expanded = branch != null &&
        (searching ||
            (_requestedExpansion ?? widget.expanded).contains(branch.id));
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: size + 12),
        child: Row(
          children: [
            if (branch != null) ...[
              SizedBox(
                width: 40,
                child: IconButton(
                  key: ValueKey('playlist-tree-toggle-${branch.id}'),
                  tooltip: ui(expanded ? '折叠歌单' : '展开歌单'),
                  onPressed: searching ? null : () => _toggle(branch),
                  isSelected: expanded,
                  constraints:
                      const BoxConstraints.tightFor(width: 40, height: 40),
                  padding: EdgeInsets.zero,
                  style: ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const WidgetStatePropertyAll(AppShape.control),
                    foregroundColor: WidgetStatePropertyAll(scheme.primary),
                    overlayColor: WidgetStatePropertyAll(
                        scheme.primary.withValues(alpha: .07)),
                    animationDuration: appToolbarReduceMotion(context)
                        ? Duration.zero
                        : AppMotion.quick,
                  ),
                  icon: AnimatedContainer(
                    key: ValueKey('playlist-tree-toggle-frame-${branch.id}'),
                    duration: appToolbarReduceMotion(context)
                        ? Duration.zero
                        : AppMotion.quick,
                    width: 22,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color.lerp(scheme.surfaceContainerHigh,
                          scheme.primaryContainer, expanded ? .4 : .2),
                      border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .55)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: AnimatedRotation(
                      turns: expanded ? .25 : 0,
                      duration: appToolbarReduceMotion(context)
                          ? Duration.zero
                          : AppMotion.quick,
                      child: const Icon(Symbols.chevron_right,
                          size: 19, weight: 600, opticalSize: 24),
                    ),
                  ),
                ),
              ),
              _revealEntry(
                branch.id,
                SizedBox(
                  width: size + 12,
                  child: _item(context, branch, order),
                ),
                song: false,
                depth: branch.depth,
              ),
              AnimatedContainer(
                duration: AppMotion.duration(
                    context, MotionKind.layout, AppMotion.standard),
                curve: AppMotion.standardCurve,
                width: group.songs.isEmpty ? 0 : 12,
                height: 3,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ] else
              const SizedBox(width: 40),
            if (group.songs.isNotEmpty)
              Expanded(
                child: SizedBox(
                  height: size + 12,
                  child: _songStrip(context, group, order),
                ),
              )
            else
              const Spacer(),
          ],
        ),
      ),
    );
    final indented = Padding(
      padding: EdgeInsetsDirectional.only(start: group.depth * step),
      child: content,
    );
    if (branch == null) return indented;
    return CustomPaint(
      painter: _TreeLines(
        depth: branch.depth,
        step: step,
        branch: true,
        last: lastByParent[branch.parentId] == branch.id,
        ancestors: _continuations(branch, byId, lastByParent),
        color: scheme.primary.withValues(alpha: .38),
      ),
      child: indented,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final searching = _search.text.trim().isNotEmpty;
    final lastByParent = {
      for (final node in visible)
        if (node.branch) node.parentId: node.id,
    };
    final byId = _byId;
    final maxDepth =
        visible.fold<int>(1, (depth, node) => math.max(depth, node.depth));
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
      final groups = _groups(visible);
      final order = _visualOrder(groups);
      final step = math.min(20.0, bounds.maxWidth * .18 / maxDepth);
      final rowIndices = <Object, int>{
        for (var i = 0; i < groups.length; i++) ...{
          if (groups[i].branch case final branch?) branch.id: i,
          for (final song in groups[i].songs) song.id: i,
        },
      };
      final groupIndices = {
        for (var i = 0; i < groups.length; i++) groups[i].id: i,
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
                    _actions(context, searching),
                  ],
                )
              : Row(children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  _actions(context, searching),
                ]),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(ui('没有匹配的歌单或歌曲')))
              : PlaylistCoverLayoutIndices(
                  indices: rowIndices,
                  seekTreeSong: _seekTreeSong,
                  child: AppContentScrollbar(
                    controller: _scroll,
                    builder: (context, controller) => GridEdgeAutoScrollRegion(
                      controller: controller,
                      child: ListView.builder(
                        key: const PageStorageKey('playlist-tree-scroll'),
                        controller: controller,
                        padding: EdgeInsets.only(
                          bottom: NowPlayingBarMetrics.reservedSpace(context),
                        ),
                        itemCount: groups.length,
                        findChildIndexCallback: (key) => key is ValueKey<String>
                            ? groupIndices[key.value]
                            : null,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return KeyedSubtree(
                            key: ValueKey(group.id),
                            child: KeyedSubtree(
                              key: _groupKeys.putIfAbsent(
                                  group.id, () => GlobalKey()),
                              child: _groupWidget(
                                context,
                                group,
                                order,
                                step,
                                byId,
                                lastByParent,
                                searching,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
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
