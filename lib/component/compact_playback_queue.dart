import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef CompactQueueArtworkBuilder = Widget Function(
    BuildContext context, int index, double size);

/// Owns only presentation. The caller retains the actual queue and its indexed
/// playback operation, including separate occurrences of the same song.
class CompactPlaybackQueue extends StatefulWidget {
  const CompactPlaybackQueue({
    super.key,
    required this.enabled,
    required this.queueIdentity,
    required this.itemCount,
    required this.currentIndex,
    required this.itemLabel,
    required this.artworkBuilder,
    required this.anchorKey,
    required this.hidden,
    required this.onSelected,
    required this.onTraditionalQueue,
    required this.builder,
    this.canSelect = true,
    this.prepareSelection,
  });

  final bool enabled;
  final Object queueIdentity;
  final int itemCount;
  final int currentIndex;
  final String Function(int index) itemLabel;
  final CompactQueueArtworkBuilder artworkBuilder;
  final GlobalKey anchorKey;
  final ValueListenable<bool> hidden;
  final ValueChanged<int> onSelected;
  final VoidCallback onTraditionalQueue;
  final Widget Function(BuildContext context, VoidCallback onQueue, bool open)
      builder;
  final bool canSelect;
  final VoidCallback Function(int index)? prepareSelection;

  @override
  State<CompactPlaybackQueue> createState() => _CompactPlaybackQueueState();
}

class _CompactPlaybackQueueState extends State<CompactPlaybackQueue>
    with WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  final _tapGroup = Object();
  final _fanKey = GlobalKey<_QueueFanState>();
  FocusNode? _openerFocus;
  bool _closingOwnedFocus = false;
  bool _open = false;
  Listenable? _geometry;
  int _closeGeneration = 0;
  VoidCallback? _pendingSelection;
  AppLifecycleState? _lifecycle;

  bool get _lifecycleVisible =>
      _lifecycle != AppLifecycleState.hidden &&
      _lifecycle != AppLifecycleState.paused &&
      _lifecycle != AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden.addListener(_visibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final geometry = AppContentRegion.geometryChangesOf(context);
    if (!identical(geometry, _geometry)) {
      _geometry?.removeListener(_geometryChanged);
      _geometry = geometry;
      _geometry?.addListener(_geometryChanged);
    }
    if (!_lifecycleVisible || !TickerMode.valuesOf(context).enabled) {
      _scheduleImmediateClose();
    }
  }

  @override
  void didUpdateWidget(covariant CompactPlaybackQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.hidden, oldWidget.hidden)) {
      oldWidget.hidden.removeListener(_visibilityChanged);
      widget.hidden.addListener(_visibilityChanged);
    }
    if (!widget.enabled || widget.hidden.value) _scheduleImmediateClose();
  }

  void _geometryChanged() {
    if (mounted && _portal.isShowing) setState(() {});
  }

  void _visibilityChanged() {
    if (widget.hidden.value) _closeImmediately();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!_lifecycleVisible) _closeImmediately();
  }

  void _scheduleImmediateClose() {
    if (!_portal.isShowing) return;
    final generation = ++_closeGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _closeGeneration) _closeImmediately();
    });
  }

  void _closeImmediately() {
    _closeGeneration++;
    _fanKey.currentState?.stopMotion();
    final selection = _takeSelection();
    if (!_portal.isShowing && !_open) {
      selection?.call();
      return;
    }
    _portal.hide();
    if (mounted) setState(() => _open = false);
    selection?.call();
  }

  VoidCallback? _takeSelection() {
    final selection = _pendingSelection;
    _pendingSelection = null;
    return selection;
  }

  void _select(int index) {
    if (!_open || !widget.canSelect || _pendingSelection != null) return;
    // Playback can replace the queue's artwork and do synchronous source work.
    // Keep the selected occurrence and its owner's guard until the visible
    // reverse animation has reached its endpoint.
    final onSelected = widget.onSelected;
    _pendingSelection =
        widget.prepareSelection?.call(index) ?? () => onSelected(index);
    _dismiss();
  }

  void _toggle() {
    if (!widget.enabled) {
      widget.onTraditionalQueue();
      return;
    }
    if (!_lifecycleVisible ||
        widget.hidden.value ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    if (!_open) _takeSelection()?.call();
    _closeGeneration++;
    if (!_open && !_portal.isShowing) {
      _openerFocus = FocusManager.instance.primaryFocus;
    }
    _closingOwnedFocus = _open && (_fanKey.currentState?.ownsFocus ?? false);
    setState(() => _open = !_open);
    if (_open) _portal.show();
  }

  void _dismiss() {
    if (_open && mounted) {
      _closingOwnedFocus = _fanKey.currentState?.ownsFocus ?? false;
      setState(() => _open = false);
    }
  }

  void _finishedClosing() {
    if (_open || !mounted) return;
    final opener = _openerFocus;
    final restore = _closingOwnedFocus &&
        (_fanKey.currentState?.ownsFocus ?? false) &&
        _lifecycleVisible &&
        !widget.hidden.value &&
        TickerMode.valuesOf(context).enabled &&
        opener?.context?.mounted == true &&
        opener!.canRequestFocus;
    _closingOwnedFocus = false;
    _portal.hide();
    if (restore) opener.requestFocus();
    _takeSelection()?.call();
  }

  bool _canOwnFocus() =>
      mounted &&
      _open &&
      _portal.isShowing &&
      _lifecycleVisible &&
      widget.enabled &&
      !widget.hidden.value &&
      TickerMode.valuesOf(context).enabled;

  @override
  void dispose() {
    _closeGeneration++;
    _pendingSelection = null;
    WidgetsBinding.instance.removeObserver(this);
    widget.hidden.removeListener(_visibilityChanged);
    _geometry?.removeListener(_geometryChanged);
    super.dispose();
  }

  Widget _overlay(BuildContext overlayContext, OverlayChildLayoutInfo info) {
    final overlayBox = Overlay.of(context).context.findRenderObject();
    final anchorBox = widget.anchorKey.currentContext?.findRenderObject();
    final viewport = Offset.zero & info.overlaySize;
    Rect bounds = viewport;
    final bar = MatrixUtils.transformRect(
        info.childPaintTransform, Offset.zero & info.childSize);
    Rect anchor = bar;
    if (overlayBox is RenderBox) {
      final panel = AppContentRegion.globalBoundsOf(context);
      if (panel != null) {
        bounds = Rect.fromPoints(overlayBox.globalToLocal(panel.topLeft),
                overlayBox.globalToLocal(panel.bottomRight))
            .intersect(viewport);
      }
      if (anchorBox is RenderBox && anchorBox.hasSize) {
        anchor = Rect.fromPoints(
            overlayBox.globalToLocal(anchorBox.localToGlobal(Offset.zero)),
            overlayBox.globalToLocal(anchorBox
                .localToGlobal(anchorBox.size.bottomRight(Offset.zero))));
      }
    }
    // A tall text-scaled bar centers its icon lower than the bar's top edge.
    // Reserve the whole bar so the bottom song never covers its title/actions.
    anchor = Rect.fromLTRB(anchor.left, math.min(anchor.top, bar.top),
        anchor.right, anchor.bottom);
    if (bounds.isEmpty) return const SizedBox.shrink();
    // Clip the entire fan, including its animated origin, to the actual body.
    return Positioned.fromRect(
      rect: bounds,
      child: ClipRect(
        key: const ValueKey('compact-queue-body-clip'),
        child: LayoutBuilder(builder: (context, constraints) {
          final localAnchor = anchor.shift(-bounds.topLeft);
          final layout = _QueueLayout.measure(
              context,
              constraints.biggest,
              localAnchor,
              _open
                  ? widget.itemCount
                  : _fanKey.currentState?.presentationItemCount ??
                      widget.itemCount);
          return _QueueFan(
            key: _fanKey,
            canOwnFocus: _canOwnFocus,
            tapGroup: _tapGroup,
            barRect: bar.shift(-bounds.topLeft),
            open: _open,
            queueIdentity: widget.queueIdentity,
            itemCount: widget.itemCount,
            currentIndex: widget.currentIndex,
            itemLabel: widget.itemLabel,
            artworkBuilder: widget.artworkBuilder,
            layout: layout,
            canSelect: widget.canSelect,
            onSelected: _select,
            onDismiss: _dismiss,
            onClosed: _finishedClosing,
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _overlay,
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _dismiss(),
          child: widget.builder(context, _toggle, _open),
        ),
      );
}

class _QueueLayout {
  const _QueueLayout(this.rect, this.stride, this.visibleCount, this.curveWidth,
      this.origin, this.leansLeft);
  final Rect rect;
  final double stride;
  final int visibleCount;
  final double curveWidth;
  final Alignment origin;
  final bool leansLeft;

  static _QueueLayout measure(
      BuildContext context, Size size, Rect anchor, int itemCount) {
    final direction = Directionality.of(context);
    double lineHeight = 0;
    for (final weight in [FontWeight.w500, FontWeight.w700]) {
      final text = TextPainter(
        text: TextSpan(
            text: 'Ag 日本語文件名',
            style: _itemStyle(context).copyWith(fontWeight: weight)),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      lineHeight = math.max(lineHeight, text.height.ceilToDouble());
      text.dispose();
    }
    final stride = math.max(64.0, lineHeight + 28);
    final inset = math.min(8.0, math.min(size.width, size.height) / 4);
    final availableHeight = math.max(0.0, anchor.top - inset - 10);
    final count = math.max(1,
        math.min(math.min(itemCount, 7), (availableHeight / stride).floor()));
    final height =
        math.min(stride * count, math.max(0.0, size.height - inset * 2));
    final width = math.min(400.0, math.max(0.0, size.width - inset * 2));
    final bottom = (anchor.top - 10).clamp(inset + height, size.height - inset);
    final leftRoom = math.max(0.0, anchor.center.dx - inset);
    final rightRoom = math.max(0.0, size.width - inset - anchor.center.dx);
    final leansLeft = leftRoom >= rightRoom;
    final left = leansLeft
        ? (anchor.right - width).clamp(inset, size.width - inset - width)
        : anchor.left.clamp(inset, size.width - inset - width);
    final minimumRowWidth = math.max(
        224.0,
        MediaQuery.textScalerOf(context)
                    .scale(_itemStyle(context).fontSize ?? 14) *
                6 +
            76);
    final imbalance = (leftRoom - rightRoom).abs() / math.max(1.0, size.width);
    final curveWidth = math.min(
        width * .3 * (.35 + .65 * imbalance.clamp(0.0, 1.0)),
        math.max(0.0, width - minimumRowWidth));
    final originX = ((anchor.center.dx - left) / math.max(1.0, width) * 2 - 1)
        .clamp(-1.0, 1.0);
    return _QueueLayout(Rect.fromLTWH(left, bottom - height, width, height),
        stride, count, curveWidth, Alignment(originX, 1), leansLeft);
  }
}

TextStyle _itemStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 14);

class _QueueFan extends StatefulWidget {
  const _QueueFan({
    super.key,
    required this.open,
    required this.queueIdentity,
    required this.itemCount,
    required this.currentIndex,
    required this.itemLabel,
    required this.artworkBuilder,
    required this.layout,
    required this.canSelect,
    required this.onSelected,
    required this.onDismiss,
    required this.onClosed,
    required this.tapGroup,
    required this.barRect,
    required this.canOwnFocus,
  });
  final bool open;
  final Object queueIdentity;
  final int itemCount;
  final int currentIndex;
  final String Function(int) itemLabel;
  final CompactQueueArtworkBuilder artworkBuilder;
  final _QueueLayout layout;
  final bool canSelect;
  final ValueChanged<int> onSelected;
  final VoidCallback onDismiss;
  final VoidCallback onClosed;
  final Object tapGroup;
  final Rect barRect;
  final bool Function() canOwnFocus;

  @override
  State<_QueueFan> createState() => _QueueFanState();
}

class _QueueFanState extends State<_QueueFan>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _reveal = AnimationController(
      vsync: this,
      duration: AppMotion.emphasized,
      reverseDuration: AppMotion.standard)
    ..addStatusListener(_revealStatus);
  late final _scroll = AnimationController.unbounded(vsync: this)
    ..value = _centeredOffset
    ..addListener(_scrollWindowChanged)
    ..addStatusListener(_scrollStatus);
  late final _rowMotion = Listenable.merge([_reveal, _scroll]);
  final _focus = FocusNode(debugLabel: 'compact-queue');
  final _itemFocus = <int, FocusNode>{};
  final _stylePaused = ValueNotifier(false);
  late int _itemCount = widget.itemCount;
  late int _currentIndex = widget.currentIndex;
  late String Function(int) _itemLabel = widget.itemLabel;
  late CompactQueueArtworkBuilder _artworkBuilder = widget.artworkBuilder;
  double _target = 0;
  double _direction = 0;
  int _keyboardIndex = 0;
  bool _closingQueued = false;
  Timer? _settleTimer;
  bool _settling = false;
  bool _directScrolling = false;
  final _contacts = <int>{};
  int _windowFirst = -1;
  int _windowLast = -1;
  AppLifecycleState? _lifecycle;
  int get presentationItemCount => _itemCount;
  bool get ownsFocus => _focus.hasFocus;
  bool get _canOwnFocus =>
      mounted &&
      _lifecycleVisible &&
      widget.open &&
      widget.canOwnFocus() &&
      TickerMode.valuesOf(context).enabled;

  void _focusWhenOpened() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canOwnFocus) {
        _focus.requestFocus();
      }
    });
  }

  double get _maxOffset =>
      math.max(0, _itemCount - widget.layout.visibleCount).toDouble();
  double get _centeredOffset =>
      (_currentIndex - (widget.layout.visibleCount - 1) / 2)
          .roundToDouble()
          .clamp(0.0, _maxOffset);
  bool get _reduceTransitions =>
      appToolbarReduceMotion(context, kind: MotionKind.transitions);
  bool get _reduceScroll =>
      appToolbarReduceMotion(context, kind: MotionKind.layout);
  bool get _lifecycleVisible =>
      _lifecycle != AppLifecycleState.hidden &&
      _lifecycle != AppLifecycleState.paused &&
      _lifecycle != AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _target = _scroll.value;
    _rememberWindow();
    _keyboardIndex =
        widget.currentIndex.clamp(0, math.max(0, widget.itemCount - 1));
    _focusWhenOpened();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (!_lifecycleVisible) {
      stopMotion();
      return;
    }
    _stylePaused.value = !widget.open;
    if (_reduceScroll) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _settling = false;
      _target = _target.roundToDouble().clamp(0.0, _maxOffset);
      _scroll.value = _target;
    }
    if (_reduceTransitions) {
      _reveal.value = widget.open ? 1 : 0;
      if (!widget.open) _queueClosed();
    } else if (widget.open) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
  }

  void _queueClosed() {
    if (_closingQueued) return;
    _closingQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closingQueued = false;
      if (mounted && !widget.open && _reveal.value == 0) widget.onClosed();
    });
  }

  void _revealStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _queueClosed();
  }

  void _scrollStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _settling = false;
  }

  @override
  void didChangeAccessibilityFeatures() => _syncMotion();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!_lifecycleVisible) stopMotion();
  }

  @override
  void didUpdateWidget(covariant _QueueFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.open && oldWidget.open) {
      _cancelScroll();
      _stylePaused.value = true;
    }
    if (widget.open) {
      if (_lifecycleVisible) _stylePaused.value = false;
      _itemCount = widget.itemCount;
      _currentIndex = widget.currentIndex;
      _itemLabel = widget.itemLabel;
      _artworkBuilder = widget.artworkBuilder;
    }
    if (widget.open &&
        (widget.currentIndex != oldWidget.currentIndex ||
            !identical(widget.queueIdentity, oldWidget.queueIdentity))) {
      _keyboardIndex =
          widget.currentIndex.clamp(0, math.max(0, widget.itemCount - 1));
      _moveTo(_centeredOffset);
    } else if (widget.layout.visibleCount != oldWidget.layout.visibleCount ||
        (widget.open && widget.itemCount != oldWidget.itemCount)) {
      _moveTo(
          _scroll.value +
              (oldWidget.layout.visibleCount - widget.layout.visibleCount) / 2,
          animate: false);
      if (widget.open) _scheduleSettle();
    }
    if (widget.open != oldWidget.open) {
      _syncMotion();
      if (widget.open) {
        _focusWhenOpened();
        _scheduleSettle();
      }
    }
  }

  void _moveTo(double value, {bool animate = true}) {
    if (!_lifecycleVisible) {
      _scroll.stop();
      return;
    }
    _target = value.clamp(0.0, _maxOffset);
    if ((_target - _scroll.value).abs() < .000001) {
      _scroll.stop();
      _scroll.value = _target;
      return;
    }
    if (!animate || _reduceScroll) {
      _scroll.value = _target;
    } else {
      _scroll.animateTo(_target,
          duration: AppMotion.standard, curve: AppMotion.standardCurve);
    }
  }

  void _moveBy(double delta, {bool animate = true}) {
    if (delta == 0 || !_lifecycleVisible || !widget.open || _maxOffset == 0) {
      return;
    }
    final base = animate && delta.sign == _direction ? _target : _scroll.value;
    _direction = delta.sign;
    _moveTo(base + delta, animate: animate);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !widget.open ||
        _maxOffset == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_settling) _cancelScroll();
      _moveBy(event.scrollDelta.dy / widget.layout.stride);
      _scheduleSettle();
      event.respond(allowPlatformDefault: false);
    });
  }

  void _cancelScroll() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _settling = false;
    _scroll.stop();
    _target = _scroll.value;
    _direction = 0;
  }

  void stopMotion() {
    _stylePaused.value = true;
    _cancelScroll();
    _reveal.stop();
    _directScrolling = false;
    _contacts.clear();
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
    if (!_lifecycleVisible ||
        !widget.open ||
        _directScrolling ||
        _contacts.isNotEmpty) {
      return;
    }
    if (_reduceScroll) {
      _settle();
    } else {
      _settleTimer = Timer(AppMotion.quick, _settle);
    }
  }

  void _settle() {
    _settleTimer?.cancel();
    _settleTimer = null;
    if (!mounted ||
        !_lifecycleVisible ||
        !widget.open ||
        _directScrolling ||
        _contacts.isNotEmpty) {
      return;
    }
    // Whole rows are the only resting positions. Keep the intended wheel
    // destination, rather than rounding a partly completed animation frame.
    final destination = _target.roundToDouble().clamp(0.0, _maxOffset);
    if (_scroll.isAnimating && destination == _target) return;
    _settling =
        !_reduceScroll && (destination - _scroll.value).abs() >= .000001;
    _direction = 0;
    _moveTo(destination);
  }

  void _contactStarted(PointerDownEvent event) {
    _contacts.add(event.pointer);
    _cancelScroll();
  }

  void _contactEnded(PointerEvent event) {
    _contacts.remove(event.pointer);
    if (_contacts.isEmpty && !_directScrolling) _settle();
  }

  void _directStarted() {
    _directScrolling = true;
    _cancelScroll();
  }

  void _directEnded() {
    _directScrolling = false;
    _settle();
  }

  void _semanticScroll(double delta) {
    if (_settling) _cancelScroll();
    _moveBy(delta);
    _scheduleSettle();
  }

  (int, int) get _visibleWindow {
    final offset = _scroll.value.clamp(0.0, _maxOffset);
    return (
      math.max(0, offset.floor() - 1),
      math.min(_itemCount - 1, (offset + widget.layout.visibleCount).ceil())
    );
  }

  void _rememberWindow() {
    final (first, last) = _visibleWindow;
    _windowFirst = first;
    _windowLast = last;
  }

  void _scrollWindowChanged() {
    if (!mounted) return;
    final (first, last) = _visibleWindow;
    if (first == _windowFirst && last == _windowLast) return;
    // Only mount/retire rows when an index enters/leaves the bounded window.
    // Transform ticks keep the laid-out text and decoded artwork as children.
    setState(_rememberWindow);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!_canOwnFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (widget.canSelect && widget.itemCount > 0) {
        widget.onSelected(_keyboardIndex);
      }
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.home &&
        key != LogicalKeyboardKey.end &&
        key != LogicalKeyboardKey.pageUp &&
        key != LogicalKeyboardKey.pageDown) {
      return KeyEventResult.ignored;
    }
    if (widget.itemCount == 0) {
      return KeyEventResult.handled;
    }
    final step =
        key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown
            ? widget.layout.visibleCount
            : 1;
    _keyboardIndex = key == LogicalKeyboardKey.home
        ? 0
        : key == LogicalKeyboardKey.end
            ? widget.itemCount - 1
            : (_keyboardIndex +
                    (key == LogicalKeyboardKey.arrowUp ||
                            key == LogicalKeyboardKey.pageUp
                        ? -step
                        : step))
                .clamp(0, widget.itemCount - 1);
    if (_keyboardIndex < _scroll.value) {
      _moveTo(_keyboardIndex.toDouble(), animate: false);
    } else if (_keyboardIndex >
        _scroll.value + widget.layout.visibleCount - 1) {
      _moveTo((_keyboardIndex - widget.layout.visibleCount + 1).toDouble(),
          animate: false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canOwnFocus) _itemFocus[_keyboardIndex]?.requestFocus();
    });
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    _reveal.dispose();
    _scroll.dispose();
    _stylePaused.dispose();
    _focus.dispose();
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _card(int index, FocusNode focusNode) {
    final layout = widget.layout;
    return _QueueItemStyle(
      index: index,
      current: index == _currentIndex,
      open: widget.open,
      paused: _stylePaused,
      label: _itemLabel(index),
      focusNode: focusNode,
      rowWidth: layout.rect.width - layout.curveWidth,
      artworkGap: math.min(12.0, layout.rect.width * .05),
      onFocusChange: (focused) {
        if (focused) _keyboardIndex = index;
      },
      onSelected: widget.canSelect ? () => widget.onSelected(index) : null,
      artwork: SizedBox(
        key: ValueKey('compact-queue-artwork-$index'),
        child: ClipRRect(
          borderRadius: AppShape.smallRadius,
          child: _artworkBuilder(
              context,
              index,
              math.min(
                  math.min(48.0, layout.stride - 16),
                  math.max(0.0,
                      (layout.rect.width - layout.curveWidth - 16) * .38))),
        ),
      ),
    );
  }

  Widget _rows() {
    final layout = widget.layout;
    final (first, last) = _visibleWindow;
    _rememberWindow();
    final retired = [
      for (final entry in _itemFocus.entries)
        if (entry.key < first || entry.key > last) entry.key,
    ];
    if (retired.isNotEmpty) {
      final nodes = [for (final index in retired) _itemFocus.remove(index)!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in nodes) {
          node.dispose();
        }
      });
    }
    return Stack(clipBehavior: Clip.hardEdge, children: [
      if (_itemCount == 0)
        Center(child: Text(ui('播放列表为空'), style: _itemStyle(context))),
      for (int index = first; index <= last; index++)
        AnimatedBuilder(
          key: ValueKey('compact-queue-entry-$index'),
          animation: _rowMotion,
          child: _card(
              index,
              _itemFocus.putIfAbsent(
                  index, () => FocusNode(debugLabel: 'compact-queue-$index'))),
          builder: (context, card) {
            final offset = _scroll.value.clamp(0.0, _maxOffset);
            final y = (index - offset) * layout.stride;
            final edge = math
                .min(1 + y / layout.stride,
                    (layout.rect.height - y) / layout.stride)
                .clamp(0.0, 1.0);
            final phase = AppMotion.standardCurve.transform(_reveal.value);
            final scale = (_reduceScroll ? 1.0 : edge) * phase;
            final curve = layout.curveWidth *
                math.sin(((y + layout.stride / 2) /
                            math.max(1.0, layout.rect.height))
                        .clamp(0.0, 1.0) *
                    math.pi /
                    2);
            final visible = edge > .05;
            return Positioned(
              key: ValueKey('compact-queue-position-$index'),
              top: layout.rect.height * (1 - phase) + y * phase,
              left: layout.leansLeft ? curve : layout.curveWidth - curve,
              width: layout.rect.width - layout.curveWidth,
              height: layout.stride,
              child: ExcludeSemantics(
                excluding: !visible || !widget.open,
                child: IgnorePointer(
                  ignoring: !visible || !widget.open,
                  child: ExcludeFocus(
                    excluding: !visible || !widget.open,
                    child: Transform.scale(
                      key: ValueKey('compact-queue-scale-$index'),
                      scale: scale,
                      alignment: layout.leansLeft
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: card,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final fan = FocusTraversalGroup(
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: Semantics(
          container: true,
          label: ui('播放列表'),
          onScrollUp: _maxOffset > 0 ? () => _semanticScroll(-1) : null,
          onScrollDown: _maxOffset > 0 ? () => _semanticScroll(1) : null,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _wheel,
            onPointerDown: _contactStarted,
            onPointerUp: _contactEnded,
            onPointerCancel: _contactEnded,
            onPointerPanZoomStart: (_) => _directStarted(),
            onPointerPanZoomUpdate: (event) => _moveBy(
                -event.panDelta.dy / widget.layout.stride,
                animate: false),
            onPointerPanZoomEnd: (_) => _directEnded(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _directStarted(),
              onVerticalDragUpdate: (event) => _moveBy(
                  -event.delta.dy / widget.layout.stride,
                  animate: false),
              onVerticalDragEnd: (_) => _directEnded(),
              onVerticalDragCancel: _directEnded,
              child: AnimatedBuilder(
                animation: _reveal,
                child: _rows(),
                builder: (context, rows) => Transform.scale(
                  scale: .8 +
                      .2 * AppMotion.standardCurve.transform(_reveal.value),
                  alignment: widget.layout.origin,
                  child: Opacity(opacity: _reveal.value, child: rows),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final surface = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: _reveal,
      child: Positioned.fromRect(
        rect: widget.layout.rect,
        child: TapRegion(
          groupId: widget.tapGroup,
          child: SizedBox(
            key: const ValueKey('compact-queue-fan'),
            child: fan,
          ),
        ),
      ),
      builder: (context, fan) => Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ClipPath(
                clipper: _QueueVeilClipper(widget.barRect),
                child: ColoredBox(
                  key: const ValueKey('compact-queue-body-veil'),
                  color: surface.withValues(
                      alpha: .72 *
                          AppMotion.standardCurve.transform(_reveal.value)),
                ),
              ),
            ),
          ),
        ),
        fan!,
      ]),
    );
  }
}

/// Fade the entire content background, including the floating bar's margins,
/// while preserving the actual bar surface rather than a whole footer strip.
class _QueueVeilClipper extends CustomClipper<Path> {
  const _QueueVeilClipper(this.bar);
  final Rect bar;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRRect(AppShape.surfaceRadius.toRRect(Offset.zero & size))
    ..addRRect(AppShape.surfaceRadius.toRRect(bar));

  @override
  bool shouldReclip(_QueueVeilClipper oldClipper) => bar != oldClipper.bar;
}

/// One retained row trades its two backgrounds without overlapping them or
/// creating an outgoing copy of its title, focus node, or decoded artwork.
class _QueueItemStyle extends StatefulWidget {
  const _QueueItemStyle({
    required this.index,
    required this.current,
    required this.open,
    required this.paused,
    required this.label,
    required this.focusNode,
    required this.rowWidth,
    required this.artworkGap,
    required this.onFocusChange,
    required this.onSelected,
    required this.artwork,
  });

  final int index;
  final bool current;
  final bool open;
  final ValueListenable<bool> paused;
  final String label;
  final FocusNode focusNode;
  final double rowWidth;
  final double artworkGap;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onSelected;
  final Widget artwork;

  @override
  State<_QueueItemStyle> createState() => _QueueItemStyleState();
}

class _QueueItemStyleState extends State<_QueueItemStyle>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _progress = AnimationController(
      vsync: this, duration: AppMotion.quick, value: widget.current ? 1 : 0);
  late double _target = widget.current ? 1 : 0;
  AppLifecycleState? _lifecycle;

  bool get _lifecycleVisible =>
      _lifecycle != AppLifecycleState.hidden &&
      _lifecycle != AppLifecycleState.paused &&
      _lifecycle != AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.paused.addListener(_syncProgress);
  }

  void _syncProgress() {
    final target = widget.current ? 1.0 : 0.0;
    if (appToolbarReduceMotion(context, kind: MotionKind.layout)) {
      _target = target;
      _progress.value = target;
      return;
    }
    if (!_lifecycleVisible || !widget.open || widget.paused.value) {
      _progress.stop();
      return;
    }
    if (_progress.value == target ||
        (_progress.isAnimating && _target == target)) {
      return;
    }
    _target = target;
    // Shortening a reversal to the remaining distance keeps this phase in one
    // quick interval and takes over exactly where the previous frame stopped.
    final micros =
        (AppMotion.quick.inMicroseconds * (target - _progress.value).abs())
            .round();
    _progress.animateTo(target,
        duration: Duration(microseconds: math.max(1, micros)),
        curve: AppMotion.standardCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncProgress();
  }

  @override
  void didUpdateWidget(covariant _QueueItemStyle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.paused, oldWidget.paused)) {
      oldWidget.paused.removeListener(_syncProgress);
      widget.paused.addListener(_syncProgress);
    }
    if (widget.current != oldWidget.current ||
        widget.open != oldWidget.open ||
        !identical(widget.paused, oldWidget.paused)) {
      _syncProgress();
    }
  }

  @override
  void didChangeAccessibilityFeatures() => _syncProgress();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncProgress();
  }

  @override
  void dispose() {
    widget.paused.removeListener(_syncProgress);
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  Widget _label(BuildContext context, ColorScheme scheme, double phase) {
    final index = widget.index;
    final alpha = (1 - 2 * phase).clamp(0.0, 1.0);
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Opacity(
            key: ValueKey('compact-queue-label-fade-$index'),
            opacity: alpha,
            child: alpha == 0
                ? KeyedSubtree(
                    key: ValueKey('compact-queue-label-$index'),
                    child: const SizedBox.expand())
                : FrostedSurface(
                    key: ValueKey('compact-queue-label-$index'),
                    borderRadius: AppShape.smallRadius,
                    blur: 8,
                    tintColor: (Theme.of(context).brightness == Brightness.dark
                            ? scheme.surfaceContainerHighest
                            : scheme.surface)
                        .withValues(alpha: .58),
                    borderColor: scheme.outlineVariant.withValues(alpha: .4),
                    boxShadow: const [],
                    child: const SizedBox.expand(),
                  ),
          ),
        ),
      ),
      // The text always paints once above the two mutually exclusive fills.
      // Padding and weight follow the same phase, preserving natural widths
      // and avoiding a geometry jump when the current song changes again.
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 6 * (1 - phase), vertical: 3 * (1 - phase)),
        child: Text(
          widget.label,
          key: ValueKey('compact-queue-title-$index'),
          textWidthBasis: TextWidthBasis.longestLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: _itemStyle(context).copyWith(
            color: Color.lerp(scheme.primary, scheme.onPrimaryContainer, phase),
            fontWeight:
                FontWeight.lerp(FontWeight.w500, FontWeight.w700, phase),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        child: widget.artwork,
        builder: (context, artwork) {
          final scheme = Theme.of(context).colorScheme;
          final phase = _progress.value;
          final emphasis = (2 * phase - 1).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Align(
              alignment: Directionality.of(context) == TextDirection.rtl
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minWidth: math.min(44.0, widget.rowWidth)),
                child: Semantics(
                  selected: widget.current,
                  child: Material(
                    key: ValueKey('compact-queue-card-${widget.index}'),
                    // This controller owns the fill phase. A second implicit
                    // Material tween would make the painted fills overlap.
                    animationDuration: Duration.zero,
                    color: emphasis == 0
                        ? Colors.transparent
                        : scheme.primaryContainer
                            .withValues(alpha: .92 * emphasis),
                    shape: AppShape.control,
                    child: InkWell(
                      key: ValueKey('compact-queue-item-${widget.index}'),
                      focusNode: widget.focusNode,
                      canRequestFocus: widget.open,
                      borderRadius: AppShape.controlRadius,
                      onFocusChange: widget.onFocusChange,
                      onTap: widget.onSelected,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: math.min(8.0, widget.rowWidth * .08),
                            vertical: 5),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Tooltip(
                              message: widget.label,
                              child: _label(context, scheme, phase),
                            ),
                          ),
                          SizedBox(width: widget.artworkGap),
                          artwork!,
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
