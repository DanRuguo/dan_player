import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';

/// Remembers appearances within a page/chrome region, without painting a layer.
///
/// Use stable [AppEntrance.identity] values for virtualized/reordered content.
/// Saturation skips subsequent motion instead of evicting old identities and
/// replaying their animations when a long list is scrolled back into view.
class AppEntranceScope extends StatefulWidget {
  const AppEntranceScope({
    super.key,
    required this.child,
    this.ready = true,
    this.maxRememberedIdentities = 2048,
    this.maxConcurrentAnimations = 24,
  })  : assert(maxRememberedIdentities > 0),
        assert(maxConcurrentAnimations > 0);

  final Widget child;

  /// Delay initial entrances while an opaque startup overlay hides the UI.
  /// Children still mount/preload; no ticker or appearance identity is consumed.
  final bool ready;
  final int maxRememberedIdentities;
  final int maxConcurrentAnimations;

  @override
  State<AppEntranceScope> createState() => _AppEntranceScopeState();
}

class _AppEntranceScopeState extends State<AppEntranceScope> {
  final Set<Object> _seen = {};
  int _active = 0;

  bool remember(Object identity) {
    if (_seen.contains(identity) ||
        _seen.length >= widget.maxRememberedIdentities) {
      return false;
    }
    _seen.add(identity);
    return true;
  }

  bool acquire() {
    if (_active >= widget.maxConcurrentAnimations) return false;
    _active++;
    return true;
  }

  void release() {
    if (_active > 0) _active--;
  }

  @override
  Widget build(BuildContext context) {
    final parent =
        context.dependOnInheritedWidgetOfExactType<_EntranceScopeData>();
    return _EntranceScopeData(
      owner: this,
      ready: widget.ready && (parent?.ready ?? true),
      child: widget.child,
    );
  }
}

class _EntranceScopeData extends InheritedWidget {
  const _EntranceScopeData({
    required this.owner,
    required this.ready,
    required super.child,
  });

  final _AppEntranceScopeState owner;
  final bool ready;

  @override
  bool updateShouldNotify(_EntranceScopeData oldWidget) =>
      owner != oldWidget.owner || ready != oldWidget.ready;
}

/// A first-appearance fade and eight-pixel rise for one meaningful UI group.
///
/// Wrap content, never a window/page's opaque backing colour or a native drag
/// region. [order] adds a bounded stagger; it is deliberately not a replay key.
/// Rebuilds, changed text/progress, and changed order never restart the effect.
/// Nested entrances are suppressed so text/icons inside a revealed card are
/// not faded or translated twice. Interaction, semantics and layout stay live.
class AppEntrance extends StatefulWidget {
  const AppEntrance({
    super.key,
    required this.child,
    this.identity,
    this.order = 0,
    this.translate = true,
  });

  static const duration = AppMotion.standard;
  static const staggerStep = Duration(milliseconds: 24);
  static const maximumStagger = Duration(milliseconds: 144);
  static const double distance = 8;

  final Widget child;
  final Object? identity;
  final int order;

  /// Whether the first appearance also rises by [distance].
  ///
  /// Icons that must remain concentric with a fixed circular control can keep
  /// the fade while disabling translation. This avoids a visibly off-centre
  /// hit target during responsive layout changes.
  final bool translate;

  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Object _anonymousIdentity = Object();
  AnimationController? _controller;
  Animation<double> _progress = const AlwaysStoppedAnimation(1);
  _AppEntranceScopeState? _scope;
  bool _decided = false;
  bool _holdsSlot = false;

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopeData =
        context.dependOnInheritedWidgetOfExactType<_EntranceScopeData>();
    final scope = scopeData?.owner;
    final nested =
        context.dependOnInheritedWidgetOfExactType<_EntranceBoundary>() != null;
    final reduced = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        _platformReducesMotion;
    final enabled = TickerMode.valuesOf(context).enabled;

    if (_decided) {
      if (reduced || !enabled || nested) _finish();
      return;
    }
    if (scopeData?.ready == false) {
      _progress = AlwaysStoppedAnimation(reduced || !enabled || nested ? 1 : 0);
      return;
    }
    _decided = true;
    _scope = scope;
    _progress = const AlwaysStoppedAnimation(1);
    if (nested) return;

    final identity = widget.identity ?? widget.key ?? _anonymousIdentity;
    final firstAppearance = scope?.remember(identity) ?? true;
    if (!firstAppearance || reduced || !enabled) return;
    if (scope != null) {
      if (!scope.acquire()) return;
      _holdsSlot = true;
    }

    final delay = Duration(
      milliseconds:
          widget.order.clamp(0, 6) * AppEntrance.staggerStep.inMilliseconds,
    );
    final total = AppEntrance.duration + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = controller.drive(CurveTween(
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.standardCurve,
      ),
    ));
    controller.addStatusListener(_onStatus);
    // Stagger uses the finite controller timeline, never a delayed Timer.
    controller.forward();
  }

  @override
  void didUpdateWidget(covariant AppEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity && widget.identity != null) {
      // An unkeyed parent may reuse this state for another list item. Keep its
      // already-visible state and remember the new identity without replaying.
      _scope?.remember(widget.identity!);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _releaseSlot();
  }

  void _releaseSlot() {
    if (!_holdsSlot) return;
    _holdsSlot = false;
    _scope?.release();
  }

  void _finish() {
    final controller = _controller;
    if (controller == null) {
      _progress = const AlwaysStoppedAnimation(1);
    } else if (controller.value != 1) {
      controller.value = 1;
    }
    _releaseSlot();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducesMotion) setState(_finish);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseSlot();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EntranceBoundary(
        child: AnimatedBuilder(
          animation: _progress,
          // The child is built once per normal parent update, not every frame.
          // Keep the same wrapper tree after settling to preserve child state.
          child: widget.child,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              widget.translate
                  ? AppEntrance.distance * (1 - _progress.value)
                  : 0,
            ),
            child: Opacity(
              opacity: _progress.value,
              alwaysIncludeSemantics: true,
              child: child,
            ),
          ),
        ),
      );
}

class _EntranceBoundary extends InheritedWidget {
  const _EntranceBoundary({required super.child});

  @override
  bool updateShouldNotify(_EntranceBoundary oldWidget) => false;
}
