import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playlist_drag_data.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

export 'playlist_drag_data.dart';
import 'package:desktop_lyric/ui_language.dart';

enum PlaylistDropHoverState { idle, pending, ready, rejected }

typedef PlaylistDropZoneBuilder = Widget Function(
  BuildContext context,
  PlaylistDropHoverState state,
  Widget child,
);

/// Coordinates one pointer, native reorder animation, and deliberate folder drops.
///
/// Own this alongside the page state and dispose it with the page. The controller
/// never changes the playlist model or writes to disk. Drop callbacks must update
/// the model synchronously; callers may persist that change asynchronously.
class PlaylistReorderController extends ChangeNotifier {
  _PlaylistReorderSurfaceState? _surface;
  final _zones = <_PlaylistReorderDropZoneState>{};
  _PlaylistDragSession? _session;
  _PlaylistReorderDropZoneState? _hoveredZone;
  PlaylistDropHoverState _hoverState = PlaylistDropHoverState.idle;
  Timer? _dwellTimer;
  bool _notificationScheduled = false;
  bool _disposed = false;
  int _nextSession = 0;

  bool get isDragging =>
      _session?.started == true && _session?.cancelRequested == false;
  PlaylistDragData? get dragData => _session?.data;
  bool get _holdingFolderHover =>
      isDragging &&
      _session?.released == false &&
      _hoverState != PlaylistDropHoverState.idle;

  PlaylistDropHoverState hoverStateFor(Object id) =>
      _hoveredZone?.widget.id == id ? _hoverState : PlaylistDropHoverState.idle;

  /// Restores the native placeholder without saving either a reorder or a move.
  void cancel() => _cancel();

  void _attach(_PlaylistReorderSurfaceState surface) {
    assert(_surface == null || identical(_surface, surface),
        'A PlaylistReorderController may control only one active surface.');
    _surface = surface;
  }

  void _detach(_PlaylistReorderSurfaceState surface) {
    if (!identical(_surface, surface)) return;
    final session = _session;
    if (session != null) {
      session.cancelRequested = true;
      surface._cancelDetachedNative(session);
    }
    _clearSession(notify: false);
    _surface = null;
    _notifySoon();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _notifySoon() {
    if (_disposed || _notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  bool _preparePointer(int index, PointerDownEvent event, FocusNode focusNode) {
    final surface = _surface;
    if (_disposed ||
        _session != null ||
        surface == null ||
        !surface._canStartDrag ||
        event.buttons != kPrimaryButton ||
        index < 0 ||
        index >= surface._renderedItems.length) {
      return false;
    }
    _session = _PlaylistDragSession(
      id: ++_nextSession,
      pointer: event.pointer,
      data: surface._renderedItems[index],
      focusNode: focusNode,
      position: event.position,
    );
    // Register BEFORE SliverReorderableList adds its gesture recognizer route.
    // An armed folder drop can then cancel the native drag before PointerUp
    // starts its reorder callback/settling animation. No private SDK API needed.
    GestureBinding.instance.pointerRouter
        .addRoute(event.pointer, _routePointer);
    return true;
  }

  void _nativeStarted(int index) {
    final session = _session;
    if (session == null || _surface == null) return;
    session.started = true;
    session.focusNode.requestFocus();
    _updateHover();
    _notify();
  }

  void _routePointer(PointerEvent event) {
    final session = _session;
    if (session == null || event.pointer != session.pointer) return;
    if (session.cancelRequested) {
      _cancel();
      return;
    }
    session.position = event.position;
    if (event is PointerCancelEvent) {
      _cancel();
    } else if (event is PointerMoveEvent) {
      if (session.started) _updateHover();
    } else if (event is PointerUpEvent) {
      if (!session.started) {
        // A short click belongs to the supplied menu button, not to this bridge.
        _clearSession();
        return;
      }
      if (!session.proxyMounted) {
        // A complete sub-frame gesture has not displayed a native placeholder.
        // Cancel instead of reversing an unpainted, zero-progress SDK proxy and
        // racing its synchronous cleanup against onReorderEnd.
        _cancel();
        return;
      }
      _updateHover();
      final target = _hoveredZone;
      if (target != null && _hoverState == PlaylistDropHoverState.ready) {
        // Revalidate at release: a save, tree change, scroll, or disabled target
        // must not turn a stale hover into a move to the wrong parent.
        if (!target._canAccept(session.data)) {
          _cancel();
          return;
        }
        final onDrop = target.widget.onDrop;
        final data = session.data;
        _surface?._cancelNative(session);
        _clearSession();
        _restoreFocus(session);
        onDrop(data);
        return;
      }
      if (_hoverState == PlaylistDropHoverState.rejected ||
          _surface?._containsPoint(event.position) != true) {
        _cancel();
        return;
      }
      session.released = true;
      _removePointerRoute(session);
      _clearHover();
      // Leave the session alive until the native proxy settles. Its final index
      // already accounts for the removed source item in onReorderItem.
    }
  }

  void _nativeEnded(int _) {
    final session = _session;
    if (session == null) return;
    // If a down/move/up sequence completed before a paint, no proxy widget was
    // mounted to notify disposal. The next frame safely clears a no-op session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_session, session) &&
          session.released &&
          !session.proxyMounted) {
        _clearSession();
        _restoreFocus(session);
      }
    });
  }

  void _nativeReordered(int oldIndex, int newIndex) {
    final surface = _surface;
    if (surface == null || !surface._canStartDrag) return;
    if (oldIndex < 0 ||
        oldIndex >= surface._renderedItems.length ||
        newIndex < 0 ||
        newIndex >= surface._renderedItems.length ||
        oldIndex == newIndex) {
      return;
    }
    final session = _session;
    final data = surface._renderedItems[oldIndex];
    if (session != null) {
      if (session.cancelRequested ||
          !session.released ||
          session.data.entryId != data.entryId) {
        return;
      }
      _clearSession();
      _restoreFocus(session);
    }
    // With no pointer session this is an SDK accessibility reorder action.
    // No second oldIndex/newIndex correction is permitted here.
    surface.widget.onReorder(data, newIndex);
  }

  void _proxyMounted(int sessionId) {
    final session = _session;
    if (session?.id == sessionId) session!.proxyMounted = true;
  }

  void _proxyRemoved(int sessionId) {
    final session = _session;
    if (session?.id != sessionId) return;
    session!.proxyMounted = false;
    if (session.released) {
      _clearSession();
      _restoreFocus(session);
    }
  }

  void _restoreFocus(_PlaylistDragSession session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _session != null || _surface?.mounted != true) return;
      final node = session.focusNode;
      final nodeContext = node.context;
      if (nodeContext != null &&
          nodeContext.mounted &&
          node.canRequestFocus &&
          (ModalRoute.of(nodeContext)?.isCurrent ?? true)) {
        node.requestFocus();
      }
    });
  }

  void _cancel({bool notify = true}) {
    final session = _session;
    if (session == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (session.cancelRequested) return;
      session.cancelRequested = true;
      _clearHover(notify: false);
      _notifySoon();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && identical(_session, session)) {
          _cancel(notify: notify);
        }
      });
      return;
    }
    _surface?._cancelNative(session);
    _clearSession(notify: notify);
    _restoreFocus(session);
    if (!notify) _notifySoon();
  }

  void _removePointerRoute(_PlaylistDragSession session) {
    if (!session.routeAttached) return;
    session.routeAttached = false;
    GestureBinding.instance.pointerRouter
        .removeRoute(session.pointer, _routePointer);
  }

  void _clearSession({bool notify = true}) {
    final session = _session;
    if (session != null) _removePointerRoute(session);
    _session = null;
    _clearHover(notify: false);
    if (notify) _notify();
  }

  void _registerZone(_PlaylistReorderDropZoneState zone) => _zones.add(zone);

  void _unregisterZone(_PlaylistReorderDropZoneState zone) {
    _zones.remove(zone);
    if (identical(_hoveredZone, zone)) {
      _clearHover(notify: false);
      _notifySoon();
    }
  }

  _PlaylistReorderDropZoneState? _zoneAt(Offset position) {
    _PlaylistReorderDropZoneState? best;
    var smallestArea = double.infinity;
    for (final zone in _zones) {
      final rect = zone._visibleRect;
      if (rect == null || !rect.contains(position)) continue;
      final area = rect.width * rect.height;
      // A name/cover target wins over a containing general-purpose target.
      if (area < smallestArea) {
        best = zone;
        smallestArea = area;
      }
    }
    return best;
  }

  void _updateHover() {
    final session = _session;
    if (session == null || !session.started || session.released) return;
    final zone = _zoneAt(session.position);
    final accepts = zone?._canAccept(session.data) ?? false;
    if (identical(zone, _hoveredZone) &&
        (zone == null ||
            accepts == (_hoverState != PlaylistDropHoverState.rejected))) {
      return;
    }
    _dwellTimer?.cancel();
    _dwellTimer = null;
    _hoveredZone = zone;
    _hoverState = zone == null
        ? PlaylistDropHoverState.idle
        : accepts
            ? PlaylistDropHoverState.pending
            : PlaylistDropHoverState.rejected;
    if (zone != null && accepts) {
      _dwellTimer = Timer(zone.widget.hoverDelay, () {
        _dwellTimer = null;
        if (!identical(_session, session) || session.released) return;
        if (!identical(_zoneAt(session.position), zone) ||
            !zone._canAccept(session.data)) {
          _updateHover();
          return;
        }
        _hoverState = PlaylistDropHoverState.ready;
        _notify();
      });
    }
    _notify();
  }

  void _refreshAfterScroll() {
    if (!isDragging) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _updateHover();
    });
  }

  void _clearHover({bool notify = true}) {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    final changed = _hoveredZone != null;
    _hoveredZone = null;
    _hoverState = PlaylistDropHoverState.idle;
    if (changed && notify) _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _clearSession(notify: false);
    _surface = null;
    _zones.clear();
    _disposed = true;
    super.dispose();
  }
}

class _PlaylistDragSession {
  _PlaylistDragSession({
    required this.id,
    required this.pointer,
    required this.data,
    required this.focusNode,
    required this.position,
  });

  final int id;
  final int pointer;
  final PlaylistDragData data;
  final FocusNode focusNode;
  Offset position;
  bool started = false;
  bool released = false;
  bool routeAttached = true;
  bool proxyMounted = false;
  bool cancelRequested = false;
}

/// A real Flutter reorderable list: animated placeholders and edge auto-scroll
/// stay in the SDK. Only the right-hand [PlaylistReorderHandle] starts a drag.
class PlaylistReorderSurface extends StatefulWidget {
  const PlaylistReorderSurface({
    super.key,
    required this.controller,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    this.enabled = true,
    this.scrollController,
    this.padding = const EdgeInsets.only(bottom: 96),
    this.itemExtent,
  });

  final PlaylistReorderController controller;
  final List<PlaylistDragData> items;
  final IndexedWidgetBuilder itemBuilder;
  final void Function(PlaylistDragData data, int correctedNewIndex) onReorder;
  final bool enabled;
  final ScrollController? scrollController;
  final EdgeInsets padding;
  final double? itemExtent;

  @override
  State<PlaylistReorderSurface> createState() => _PlaylistReorderSurfaceState();
}

class _PlaylistReorderSurfaceState extends State<PlaylistReorderSurface> {
  var _listKey = GlobalKey<SliverReorderableListState>();
  final _rowKeys = <String, GlobalKey>{};
  final _renderedRows = <String, Widget>{};
  final _scrollController = ScrollController();
  _PlaylistDragRecognizer? _recognizer;
  late List<PlaylistDragData> _renderedItems;
  late IndexedWidgetBuilder _renderedBuilder;
  bool _applyingExternalChange = false;
  bool _active = true;
  bool _detachedCancellationPending = false;
  _PlaylistDragSession? _detachedSession;
  String? _reparentSourceId;
  double _reparentSourceExtent = 0;

  bool get _ownsController =>
      _active &&
      !widget.controller._disposed &&
      identical(widget.controller._surface, this);

  bool get _canStartDrag =>
      _ownsController &&
      widget.enabled &&
      !_applyingExternalChange &&
      !_detachedCancellationPending;

  @override
  void initState() {
    super.initState();
    _renderedItems = List.of(widget.items);
    _renderedBuilder = widget.itemBuilder;
    widget.controller._attach(this);
  }

  @override
  void deactivate() {
    // A new PageStorageKey can mount the next playlist before this State is
    // disposed. Release ownership now, while preserving the one-active-surface
    // invariant. Detaching also invalidates the old pointer and dwell timer.
    _active = false;
    widget.controller._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    widget.controller._attach(this);
    final session = _detachedSession;
    if (_detachedCancellationPending && session?.started == true) {
      // Flutter's dragged _ReorderableItem unregisters on deactivate, but its
      // dragging build does not register again on activate. Cancelling the old
      // Sliver now would leave that item dragging after _dragInfo is cleared.
      // Recreate only SDK wrappers, retaining every real row's GlobalKey. Keep
      // the existing source proxy/placeholder until the old overlay is removed
      // at the frame boundary, then migrate its SAME row State back to the list.
      _reparentSourceId = session!.data.entryId;
      final source =
          _rowKeys[_reparentSourceId]?.currentContext?.findRenderObject();
      _reparentSourceExtent = source is RenderBox && source.hasSize
          ? source.size.height
          : widget.itemExtent ?? 72;
      _listKey = GlobalKey<SliverReorderableListState>();
    }
  }

  bool _sameRelationships(List<PlaylistDragData> a, List<PlaylistDragData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].entryId != b[i].entryId ||
          a[i].sourceParent?.id != b[i].sourceParent?.id) {
        return false;
      }
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant PlaylistReorderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadNativeDrag = oldWidget.controller._session?.started ?? false;
    final changedRelationships =
        !_sameRelationships(_renderedItems, widget.items);
    final changedController = oldWidget.controller != widget.controller;
    if (changedController) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    if (((changedRelationships || changedController || !widget.enabled) &&
            hadNativeDrag) ||
        _applyingExternalChange) {
      // Removing/reindexing rows in the SAME build as cancelling the overlay
      // makes the SDK reuse its global-keyed source before its old parent has
      // rebuilt. Restore the unchanged list for one frame, then show the latest
      // projection. Normal completed drops never take this deferred path.
      if (!_applyingExternalChange) {
        _applyingExternalChange = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Cancel outside build, so Overlay and sliver both rebuild together
          // on the next frame, just as they do for an ordinary pointer cancel.
          widget.controller._cancel(notify: false);
          setState(() {
            _applyingExternalChange = false;
            _applyProjection();
          });
        });
      }
    } else if (!_applyingExternalChange) {
      if (changedRelationships || !widget.enabled) {
        widget.controller._cancel(notify: false);
      }
      _applyProjection();
    }
  }

  void _applyProjection() {
    _renderedItems = List.of(widget.items);
    _renderedBuilder = widget.itemBuilder;
    final ids = widget.items.map((item) => item.entryId).toSet();
    _rowKeys.removeWhere((id, _) => !ids.contains(id));
    _renderedRows.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      widget.controller._cancel(notify: false);
    }
  }

  bool _containsPoint(Offset position) {
    final box = context.findRenderObject();
    return box is RenderBox &&
        box.attached &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  void _startPointer(int index, PointerDownEvent event, FocusNode focusNode) {
    final list = _listKey.currentState;
    if (list == null ||
        !widget.controller._preparePointer(index, event, focusNode)) {
      return;
    }
    final recognizer = _PlaylistDragRecognizer(widget.controller)
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    _recognizer = recognizer;
    try {
      list.startItemDragReorder(
          index: index, event: event, recognizer: recognizer);
    } catch (_) {
      widget.controller._cancel();
      rethrow;
    }
  }

  void _cancelNative(_PlaylistDragSession session) {
    if (!mounted) return;
    if (session.started) {
      _listKey.currentState?.cancelReorder();
    } else {
      // cancelReorder() has no active _DragInfo before the slop threshold.
      // Reject just this pointer; the SDK still owns/disposes the recognizer.
      final recognizer = _recognizer;
      if (recognizer != null && !recognizer.wasDisposed) {
        recognizer.rejectGesture(session.pointer);
      }
    }
  }

  void _cancelDetachedNative(_PlaylistDragSession session) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _cancelNative(session);
      return;
    }
    final list = _listKey.currentState;
    final recognizer = _recognizer;
    _detachedSession = session;
    _detachedCancellationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Removed/replaced Slivers dispose their own overlay and auto-scroller.
      // Controller replacement or an unrecognized pointer can retain this
      // Sliver; cancel that captured gesture outside build. Never resolve the
      // controller here: it may already own a different page.
      if (list?.mounted == true && identical(_recognizer, recognizer)) {
        if (session.started) {
          list!.cancelReorder();
        } else if (recognizer != null && !recognizer.wasDisposed) {
          recognizer.rejectGesture(session.pointer);
        }
      }
      _detachedCancellationPending = false;
      _detachedSession = null;
      if (_reparentSourceId != null) {
        setState(() => _reparentSourceId = null);
      }
    });
  }

  void _nativeStarted(int index) {
    if (_canStartDrag) widget.controller._nativeStarted(index);
  }

  void _nativeEnded(int index) {
    if (_ownsController && !_detachedCancellationPending) {
      widget.controller._nativeEnded(index);
    }
  }

  void _nativeReordered(int oldIndex, int newIndex) {
    if (_canStartDrag) {
      widget.controller._nativeReordered(oldIndex, newIndex);
    }
  }

  Widget _proxy(Widget child, int _, Animation<double> animation) {
    final sessionId = widget.controller._session?.id;
    final scheme = Theme.of(context).colorScheme;
    return _PlaylistReorderProxyMarker(
      child: _PlaylistProxyLifetime(
        controller: widget.controller,
        sessionId: sessionId,
        child: AnimatedBuilder(
          animation: animation,
          child: IgnorePointer(
            child: TickerMode(
              enabled: false,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child,
              ),
            ),
          ),
          builder: (context, child) => Material(
            color: scheme.surfaceContainerHigh,
            shape: AppShape.control,
            elevation:
                lerpDouble(0, 6, Curves.easeInOut.transform(animation.value))!,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    assert(
        widget.items.map((item) => item.entryId).toSet().length ==
            widget.items.length,
        'Each playlist relationship needs a unique ID.');
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        widget.controller._refreshAfterScroll();
        return false;
      },
      child: AppContentScrollbar(
        controller: widget.scrollController ?? _scrollController,
        builder: (context, controller) => CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: SliverReorderableList(
                key: _listKey,
                itemCount: _renderedItems.length,
                itemExtent: widget.itemExtent,
                itemBuilder: (context, index) {
                  final id = _renderedItems[index].entryId;
                  if (id == _reparentSourceId) {
                    return SizedBox(
                      key: ValueKey(('playlist-reparent-placeholder', id)),
                      height: _reparentSourceExtent,
                    );
                  }
                  final row = _applyingExternalChange
                      ? _renderedRows[id] ??
                          SizedBox(height: widget.itemExtent ?? 72)
                      : _renderedRows[id] = _renderedBuilder(context, index);
                  // Like Material ReorderableListView, keep the actual row under
                  // an identity-only GlobalKey. The SDK sliver's own wrapper key
                  // includes its index and alone cannot preserve row/cover/focus
                  // state across a reorder or a transfer into the proxy Overlay.
                  return KeyedSubtree(
                    key: _rowKeys.putIfAbsent(id, GlobalKey.new),
                    child: row,
                  );
                },
                onReorderStart: _nativeStarted,
                onReorderEnd: _nativeEnded,
                onReorderItem: _nativeReordered,
                proxyDecorator: _proxy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _scrollController.dispose();
    super.dispose();
  }
}

class _PlaylistDragRecognizer extends ImmediateMultiDragGestureRecognizer {
  _PlaylistDragRecognizer(this.controller);

  final PlaylistReorderController controller;
  bool wasDisposed = false;

  @override
  set onStart(GestureMultiDragStartCallback? callback) {
    super.onStart = callback == null
        ? null
        : (position) {
            final drag = callback(position);
            return drag == null ? null : _PlaylistNativeDrag(drag, controller);
          };
  }

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

/// A folder's name region is a deliberate alternative to a reorder gap. Hold
/// the native gap in place while hovering it; otherwise that gap pushes the
/// target row out from underneath the pointer before the dwell can complete.
/// The one native recognizer still owns the gesture. Leaving the region flushes
/// all withheld movement, so the proxy never loses distance or jumps backwards.
class _PlaylistNativeDrag implements Drag {
  _PlaylistNativeDrag(this.native, this.controller);

  final Drag native;
  final PlaylistReorderController controller;
  Offset _pendingDelta = Offset.zero;
  DragUpdateDetails? _latest;

  void _flush() {
    final latest = _latest;
    if (latest == null || _pendingDelta == Offset.zero) return;
    final delta = _pendingDelta;
    _pendingDelta = Offset.zero;
    native.update(DragUpdateDetails(
      sourceTimeStamp: latest.sourceTimeStamp,
      delta: delta,
      globalPosition: latest.globalPosition,
      localPosition: latest.localPosition,
    ));
  }

  @override
  void update(DragUpdateDetails details) {
    _latest = details;
    _pendingDelta += details.delta;
    if (!controller._holdingFolderHover) _flush();
  }

  @override
  void end(DragEndDetails details) {
    _flush();
    native.end(details);
  }

  @override
  void cancel() {
    native.cancel();
    controller._clearSession();
  }
}

/// Wrap the one trailing menu button, not the entire row. A click still belongs
/// to that button; dragging with the primary mouse button/touch moves the row.
class PlaylistReorderHandle extends StatefulWidget {
  const PlaylistReorderHandle({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  final PlaylistReorderController controller;
  final int index;
  final Widget child;
  final bool enabled;

  @override
  State<PlaylistReorderHandle> createState() => _PlaylistReorderHandleState();
}

class _PlaylistReorderHandleState extends State<PlaylistReorderHandle> {
  final _focusNode = FocusNode(debugLabel: 'playlist reorder handle');

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Focus(
      focusNode: _focusNode,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            widget.controller.isDragging) {
          widget.controller.cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: widget.enabled
            ? (event) => widget.controller._surface
                ?._startPointer(widget.index, event, _focusNode)
            : null,
        child: MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.grab : MouseCursor.defer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}

/// A name/cover or breadcrumb target for native reorder gestures. This widget
/// does not install a pointer recognizer and never eats clicks or touch scrolls.
/// Keep the trailing handle OUTSIDE its bounds, so vertical sorting is safe.
class PlaylistReorderDropZone extends StatefulWidget {
  const PlaylistReorderDropZone({
    super.key,
    required this.controller,
    required this.id,
    required this.canDrop,
    required this.onDrop,
    required this.child,
    this.rejectionReason,
    this.builder,
    this.enabled = true,
    this.hoverDelay = const Duration(milliseconds: 500),
  });

  final PlaylistReorderController controller;
  final Object id;
  final bool Function(PlaylistDragData data) canDrop;
  final void Function(PlaylistDragData data) onDrop;
  final String? Function(PlaylistDragData data)? rejectionReason;
  final Widget child;
  final PlaylistDropZoneBuilder? builder;
  final bool enabled;
  final Duration hoverDelay;

  @override
  State<PlaylistReorderDropZone> createState() =>
      _PlaylistReorderDropZoneState();
}

class _PlaylistReorderDropZoneState extends State<PlaylistReorderDropZone> {
  bool _proxy = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.controller._registerZone(this);
  }

  @override
  void deactivate() {
    _active = false;
    widget.controller._unregisterZone(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    widget.controller._registerZone(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _proxy = context.dependOnInheritedWidgetOfExactType<
            _PlaylistReorderProxyMarker>() !=
        null;
  }

  @override
  void didUpdateWidget(covariant PlaylistReorderDropZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._unregisterZone(this);
      widget.controller._registerZone(this);
    }
  }

  bool _canAccept(PlaylistDragData data) =>
      mounted && _active && !_proxy && widget.enabled && widget.canDrop(data);

  Rect? get _visibleRect {
    if (!mounted || !_active || _proxy || !widget.enabled) return null;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    var rect = box.localToGlobal(Offset.zero) & box.size;
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      rect =
          rect.intersect(viewport.localToGlobal(Offset.zero) & viewport.size);
    }
    return rect.isEmpty ? null : rect;
  }

  Widget _defaultFeedback(
      BuildContext context, PlaylistDropHoverState state, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    final rejected = state == PlaylistDropHoverState.rejected;
    final data = widget.controller.dragData;
    final message = switch (state) {
      PlaylistDropHoverState.idle => '',
      PlaylistDropHoverState.pending => ui("稍作停留移入"),
      PlaylistDropHoverState.ready => ui("松开移入"),
      PlaylistDropHoverState.rejected =>
        (data == null ? null : widget.rejectionReason?.call(data)) ??
            ui("不能移入"),
    };
    final color = state == PlaylistDropHoverState.idle
        ? Colors.transparent
        : rejected
            ? scheme.error
            : scheme.primary;
    return Stack(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: color.withValues(
                alpha: state == PlaylistDropHoverState.idle
                    ? 0
                    : state == PlaylistDropHoverState.ready
                        ? .15
                        : .07),
            border: Border.all(color: color, width: 1.5),
            borderRadius: AppShape.controlRadius,
          ),
          child: child,
        ),
        Positioned(
          left: 4,
          right: 4,
          bottom: 0,
          child: IgnorePointer(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    backgroundColor: scheme.surface),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => (widget.builder ?? _defaultFeedback)(
        context,
        _proxy
            ? PlaylistDropHoverState.idle
            : widget.controller.hoverStateFor(widget.id),
        widget.child,
      ),
    );
  }

  @override
  void dispose() {
    widget.controller._unregisterZone(this);
    super.dispose();
  }
}

class _PlaylistReorderProxyMarker extends InheritedWidget {
  const _PlaylistReorderProxyMarker({required super.child});

  @override
  bool updateShouldNotify(_PlaylistReorderProxyMarker oldWidget) => false;
}

class _PlaylistProxyLifetime extends StatefulWidget {
  const _PlaylistProxyLifetime({
    required this.controller,
    required this.sessionId,
    required this.child,
  });

  final PlaylistReorderController controller;
  final int? sessionId;
  final Widget child;

  @override
  State<_PlaylistProxyLifetime> createState() => _PlaylistProxyLifetimeState();
}

class _PlaylistProxyLifetimeState extends State<_PlaylistProxyLifetime> {
  @override
  void initState() {
    super.initState();
    final id = widget.sessionId;
    if (id != null) widget.controller._proxyMounted(id);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return widget.child;
  }

  @override
  void dispose() {
    final id = widget.sessionId;
    final controller = widget.controller;
    if (id != null) scheduleMicrotask(() => controller._proxyRemoved(id));
    super.dispose();
  }
}
